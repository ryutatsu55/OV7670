#include <linux/device.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/jiffies.h>
#include <linux/kernel.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/semaphore.h>
#include <linux/timer.h>

/* motion_avalon_slave レジスタマップ(ワードアドレス相当のバイトオフセット) */
#define MOTION_REG_STATUS 0x00 /* [0] new_data (sticky, ACK書き込みでクリア) */
#define MOTION_REG_COUNT  0x04 /* [16:0] */
#define MOTION_REG_SUM_X  0x08 /* [24:0] */
#define MOTION_REG_SUM_Y  0x0C /* [24:0] */
#define MOTION_REG_ACK    0x10 /* write-only, 任意の値でSTATUS[0]をクリア */

/* この時間(ms)割り込みが来なければ、速度計算用の直前座標をリセットする */
#define MOTION_TIMEOUT_MS 1000

static struct semaphore g_dev_probe_sem;
static int g_platform_probe_flag;
static unsigned long g_motion_base_addr;
static unsigned long g_motion_size;
static int g_motion_irq;
static void __iomem *g_ioremap_addr;

/* 速度計算・タイムアウト用の状態 */
static bool          g_have_last_pos;
static s32           g_last_center_x;
static s32           g_last_center_y;
static unsigned long g_last_irq_jiffies;
static struct timer_list g_timeout_timer;

static int motion_probe(struct platform_device *pdev);
static void motion_remove(struct platform_device *pdev);

static struct of_device_id motion_driver_dt_ids[] = {
	{
		.compatible = "ov7670,motion-avalon-slave-1.0"
	},
	{ /* end of table */ }
};

static struct platform_driver motion_driver = {
	.probe = motion_probe,
	.remove = motion_remove,
	.driver = {
		.name = "motion_driver",
		.owner = THIS_MODULE,
		.of_match_table = motion_driver_dt_ids,
	},
};

/* MOTION_TIMEOUT_MS の間割り込みが来なかった場合に呼ばれる。速度計算の基準点を
 * 失効させる（次の割り込みでは速度を計算せず、新しい基準点として記録するだけにする）。
 */
static void
motion_timeout_callback(struct timer_list *t)
{
	pr_info("motion_driver: %ums 間割り込みなし、速度計算用の座標をリセットします\n",
		MOTION_TIMEOUT_MS);
	g_have_last_pos = false;
}

static irqreturn_t
motion_interrupt(int irq, void *dev_id)
{
	uint32_t status, count, sum_x, sum_y;
	s32 center_x, center_y;
	unsigned long now;
	unsigned int dt_ms;

	if (irq != g_motion_irq)
		return IRQ_NONE;

	status = ioread32(g_ioremap_addr + MOTION_REG_STATUS);
	if ((status & 0x1) == 0)
		return IRQ_NONE;

	count = ioread32(g_ioremap_addr + MOTION_REG_COUNT);
	sum_x = ioread32(g_ioremap_addr + MOTION_REG_SUM_X);
	sum_y = ioread32(g_ioremap_addr + MOTION_REG_SUM_Y);

	/* ACKレジスタへの書き込みでSTATUS[0]をクリアし、irqをdeassertする */
	iowrite32(0x1, g_ioremap_addr + MOTION_REG_ACK);

	if (count == 0) {
		/* ゼロ割り防止。しきい値判定を通っていれば通常発生しないはずだが念のため */
		pr_info("motion_driver: irq=%d count=0 (重心計算スキップ)\n", irq);
		return IRQ_HANDLED;
	}

	/* 重心座標 = 座標総和 / しきい値超過画素数 */
	center_x = (s32)(sum_x / count);
	center_y = (s32)(sum_y / count);

	now = jiffies;

	if (g_have_last_pos) {
		dt_ms = jiffies_to_msecs(now - g_last_irq_jiffies);
		if (dt_ms == 0)
			dt_ms = 1; /* ゼロ割り防止 */

		/* 単位: pixel/sec（前回座標との差分を経過時間で正規化） */
		s32 velocity_x = ((center_x - g_last_center_x) * 1000) / (s32)dt_ms;
		s32 velocity_y = ((center_y - g_last_center_y) * 1000) / (s32)dt_ms;

		pr_info("motion_driver: irq=%d count=%u center=(%d,%d) dt=%ums velocity=(%d,%d)px/s\n",
			irq, count, center_x, center_y, dt_ms, velocity_x, velocity_y);
	} else {
		pr_info("motion_driver: irq=%d count=%u center=(%d,%d) velocity=基準点なし(スキップ)\n",
			irq, count, center_x, center_y);
	}

	g_last_center_x = center_x;
	g_last_center_y = center_y;
	g_last_irq_jiffies = now;
	g_have_last_pos = true;

	/* タイムアウト監視タイマーを再アーム */
	mod_timer(&g_timeout_timer, jiffies + msecs_to_jiffies(MOTION_TIMEOUT_MS));

	return IRQ_HANDLED;
}

static int
motion_probe(struct platform_device *pdev)
{
	int ret;
	struct resource *r;
	struct resource *motion_mem_region;
	int irq;
	uint32_t io_result;

	pr_info("motion_probe\n");

	ret = -EBUSY;
	if (down_interruptible(&g_dev_probe_sem))
		return -ERESTARTSYS;
	if (g_platform_probe_flag != 0)
		goto bad_exit_return;

	ret = -EINVAL;

	r = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (r != NULL) {
		pr_info("r->start = 0x%08lx\n", (long unsigned int)r->start);
		pr_info("r->end = 0x%08lx\n", (long unsigned int)r->end);
		pr_info("r->name = %s\n", r->name);
	} else {
		pr_err("IORESOURCE_MEM, 0 does not exist\n");
		goto bad_exit_return;
	}
	g_motion_base_addr = r->start;
	g_motion_size = resource_size(r);

	irq = platform_get_irq(pdev, 0);
	g_motion_irq = irq;
	if (irq < 0) {
		pr_err("get_irq failed\n");
		goto bad_exit_return;
	}
	pr_info("irq = %d\n", irq);

	motion_mem_region = request_mem_region(g_motion_base_addr, g_motion_size,
						"motion_hw_region");
	if (motion_mem_region == NULL) {
		pr_err("request_mem_region failed: motion_driver\n");
		goto bad_exit_return;
	}

	g_ioremap_addr = ioremap(g_motion_base_addr, g_motion_size);
	if (g_ioremap_addr == NULL) {
		pr_err("ioremap failed: motion_driver\n");
		goto bad_exit_release_mem_region;
	}

	pr_info("probe registers\n");
	io_result = ioread32(g_ioremap_addr + MOTION_REG_STATUS);
	pr_info("STATUS: %x\n", io_result);
	io_result = ioread32(g_ioremap_addr + MOTION_REG_COUNT);
	pr_info("COUNT : %x\n", io_result);
	io_result = ioread32(g_ioremap_addr + MOTION_REG_SUM_X);
	pr_info("SUM_X : %x\n", io_result);
	io_result = ioread32(g_ioremap_addr + MOTION_REG_SUM_Y);
	pr_info("SUM_Y : %x\n", io_result);

	ret = request_irq(irq, motion_interrupt, 0,
			   motion_driver.driver.name, &motion_driver);
	if (ret) {
		pr_err("request_irq_failed\n");
		goto bad_exit_iounmap;
	}

	g_have_last_pos = false;
	timer_setup(&g_timeout_timer, motion_timeout_callback, 0);

	g_platform_probe_flag = 1;
	up(&g_dev_probe_sem);
	pr_info("motion_probe exit!!\n");
	return 0;

bad_exit_iounmap:
	iounmap(g_ioremap_addr);
bad_exit_release_mem_region:
	release_mem_region(g_motion_base_addr, g_motion_size);
bad_exit_return:
	up(&g_dev_probe_sem);
	pr_info("motion_probe bad_exit\n");
	return ret;
}

static void
motion_remove(struct platform_device *pdev)
{
	pr_info("motion_remove\n");
	del_timer_sync(&g_timeout_timer);
	free_irq(g_motion_irq, &motion_driver);
	iounmap(g_ioremap_addr);
	release_mem_region(g_motion_base_addr, g_motion_size);

	down(&g_dev_probe_sem);
	g_platform_probe_flag = 0;
	up(&g_dev_probe_sem);
	return;
}

MODULE_DEVICE_TABLE(of, motion_driver_dt_ids);

MODULE_LICENSE("GPL");

static int __init
motion_init(void)
{
	int ret;

	pr_info("motion_init_enter\n");
	sema_init(&g_dev_probe_sem, 1);
	ret = platform_driver_register(&motion_driver);
	if (ret != 0) {
		pr_err("platform_driver_register returned %d\n", ret);
		return ret;
	}
	pr_info("motion_driver registered\n");

	return 0;
}

static void
motion_exit(void)
{
	pr_info("do exit for motion_driver\n");
	platform_driver_unregister(&motion_driver);
	pr_info("exit from motion_driver\n");
}
module_init(motion_init);
module_exit(motion_exit);
