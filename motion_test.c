#include <linux/device.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/semaphore.h>

/* motion_avalon_slave レジスタマップ(ワードアドレス相当のバイトオフセット) */
#define MOTION_REG_STATUS 0x00 /* [0] new_data (sticky, ACK書き込みでクリア) */
#define MOTION_REG_COUNT  0x04 /* [16:0] */
#define MOTION_REG_SUM_X  0x08 /* [24:0] */
#define MOTION_REG_SUM_Y  0x0C /* [24:0] */
#define MOTION_REG_ACK    0x10 /* write-only, 任意の値でSTATUS[0]をクリア */

static struct semaphore g_dev_probe_sem;
static int g_platform_probe_flag;
static unsigned long g_motion_base_addr;
static unsigned long g_motion_size;
static int g_motion_irq;
static void __iomem *g_ioremap_addr;

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

static irqreturn_t
motion_interrupt(int irq, void *dev_id)
{
	uint32_t status, count, sum_x, sum_y;

	if (irq != g_motion_irq)
		return IRQ_NONE;

	status = ioread32(g_ioremap_addr + MOTION_REG_STATUS);
	if ((status & 0x1) == 0)
		return IRQ_NONE;

	count = ioread32(g_ioremap_addr + MOTION_REG_COUNT);
	sum_x = ioread32(g_ioremap_addr + MOTION_REG_SUM_X);
	sum_y = ioread32(g_ioremap_addr + MOTION_REG_SUM_Y);

	pr_info("motion_driver: irq=%d count=%u sum_x=%u sum_y=%u\n",
		irq, count, sum_x, sum_y);

	/* ACKレジスタへの書き込みでSTATUS[0]をクリアし、irqをdeassertする */
	iowrite32(0x1, g_ioremap_addr + MOTION_REG_ACK);

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
