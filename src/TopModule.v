`include "adv7513/adv7513.v"
`include "camera/camera.v"
`include "difference/difference.v"
`include "hps_if/motion_cdc.v"

// Top-level module.
// IP cores (pll_25, pll_5, bram_2port, soc_system) are added via their .qip files。
// motion_avalon_slave.v は soc_system.qip 経由でコンパイルされる（soc_system 内部に
// Platform Designer コンポーネントとして組み込み済みのため、TopModule からは
// `include も直接インスタンス化もしない）。
//
// Hierarchy:
//   TopModule
//   ├── pll_25             — 50 MHz → 25.175 MHz pixel clock (Quartus IP)
//   ├── pll_5              — 50 MHz → 25 MHz OV7670 XCLK     (Quartus IP)
//   ├── camera             — OV7670 camera subsystem (SCCB init + YUV422 capture)
//   ├── frame_difference   — 前フレームとの絶対差分計算 + しきい値判定・画素数/
//   │                        x,y座標総和集計 (count/sum_x/sum_y、CAM_PCLK ドメイン)
//   ├── motion_cdc         — CAM_PCLK → clock50 クロックドメイン交差
//   ├── bram_2port         — dual-port RAM 8-bit × 307200     (Quartus IP)
//   │     port A: write ← frame_difference (CAM_PCLK)
//   │     port B: read  → adv7513           (clock25 25.175 MHz)
//   ├── adv7513            — HDMI output + I2C config
//   └── soc_system         — HPS + Lightweight HPS-to-FPGA ブリッジ (Platform Designer 生成、.qip)
//         内部に motion_avalon_slave（Avalon-MM スレーブ + 割り込み）を含む。
//         DE10-Nano GHRD (soc_system.qsys) をベースに、motion_avalon_slave を追加したもの。
module TopModule (
    input  wire        clock50,
    input  wire        reset_n,
    input  wire        switchR, switchG, switchB,

    input  wire        mode, // 0:黒地 1:白地
    input  wire     mode2,

    // AUDIO (unused)
    output wire        HDMI_I2S0,
    output wire        HDMI_MCLK,
    output wire        HDMI_LRCLK,
    output wire        HDMI_SCLK,

    // VIDEO
    output wire [23:0] HDMI_TX_D,
    output wire        HDMI_TX_VS,
    output wire        HDMI_TX_HS,
    output wire        HDMI_TX_DE,
    output wire        HDMI_TX_CLK,

    // HDMI config
    input  wire        HDMI_TX_INT,
    inout  wire        HDMI_I2C_SDA,
    output wire        HDMI_I2C_SCL,
    output wire        READY,
    output wire        locked,

    // OV7670 カメラ
    input  wire        CAM_PCLK,
    input  wire        CAM_VSYNC,
    input  wire        CAM_HREF,
    input  wire [7:0]  CAM_D,
    output wire        CAM_XCLK,
    inout  wire        CAM_SIOD,
    output wire        CAM_SIOC,
    output wire        CAM_RESET,
    output wire        CAM_PWDN,

    // カメラ状態インジケータ（LED アサイン用）
    output wire        CAM_INIT_DONE,  // SCCB 初期化完了で HIGH
    output wire        CAM_PCLK_ACT,   // PCLK 受信中に点灯

    // ---- HPS ハードIO -----------------------------------------------
    // soc_system.qsys の hps_io エクスポート由来。ポート名は DE10-Nano GHRD
    // (DE10_NANO_SoC_GHRD.v) と完全に一致させてあり、Pin Planner で GHRD の
    // .qsf からピン割り当てをそのままインポートできるようにしている。

    // HPS DDR3
    output wire [14:0] HPS_DDR3_ADDR,
    output wire [2:0]  HPS_DDR3_BA,
    output wire        HPS_DDR3_CAS_N,
    output wire        HPS_DDR3_CK_N,
    output wire        HPS_DDR3_CK_P,
    output wire        HPS_DDR3_CKE,
    output wire        HPS_DDR3_CS_N,
    output wire [3:0]  HPS_DDR3_DM,
    inout  wire [31:0] HPS_DDR3_DQ,
    inout  wire [3:0]  HPS_DDR3_DQS_N,
    inout  wire [3:0]  HPS_DDR3_DQS_P,
    output wire        HPS_DDR3_ODT,
    output wire        HPS_DDR3_RAS_N,
    output wire        HPS_DDR3_RESET_N,
    input  wire        HPS_DDR3_RZQ,
    output wire        HPS_DDR3_WE_N,

    // HPS Ethernet (EMAC1)
    output wire        HPS_ENET_GTX_CLK,
    inout  wire        HPS_ENET_INT_N,
    output wire        HPS_ENET_MDC,
    inout  wire        HPS_ENET_MDIO,
    input  wire        HPS_ENET_RX_CLK,
    input  wire [3:0]  HPS_ENET_RX_DATA,
    input  wire        HPS_ENET_RX_DV,
    output wire [3:0]  HPS_ENET_TX_DATA,
    output wire        HPS_ENET_TX_EN,

    // HPS I2C
    inout  wire        HPS_I2C0_SCLK,
    inout  wire        HPS_I2C0_SDAT,
    inout  wire        HPS_I2C1_SCLK,
    inout  wire        HPS_I2C1_SDAT,

    // HPS 共有 GPIO（ボード上で LED0 / KEY0 と FPGA ファブリックが共有するピン）
    inout  wire        HPS_KEY,
    inout  wire        HPS_LED,

    // HPS SD/MMC（ブートデバイス）
    output wire        HPS_SD_CLK,
    inout  wire        HPS_SD_CMD,
    inout  wire [3:0]  HPS_SD_DATA,

    // HPS SPI Master
    output wire        HPS_SPIM_CLK,
    input  wire        HPS_SPIM_MISO,
    output wire        HPS_SPIM_MOSI,
    inout  wire        HPS_SPIM_SS,

    // HPS UART（コンソール）
    input  wire        HPS_UART_RX,
    output wire        HPS_UART_TX,

    // HPS USB
    input  wire        HPS_USB_CLKOUT,
    inout  wire [7:0]  HPS_USB_DATA,
    input  wire        HPS_USB_DIR,
    input  wire        HPS_USB_NXT,
    output wire        HPS_USB_STP,

    // HPS 個別 GPIO（loan I/O、ボード固有配線: USB PHYリセット/LTC電源監視/Gセンサ割り込み）
    inout  wire        HPS_CONV_USB_N,
    inout  wire        HPS_LTC_GPIO,
    inout  wire        HPS_GSENSOR_INT
);

wire [18:0] diff_addr;
wire [7:0]  diff_data;
wire        diff_we;

// モーション統計（frame_difference が算出する画素数/座標総和、CAM_PCLK ドメイン）
// frame_difference は f_dist（ダブルバッファのフェーズ、1フレームごとにトグル）と
// 同じタイミングで count/sum_x/sum_y を確定させるので、f_dist のトグルエッジを
// 検出して motion_frame_done パルスを作る。frame_difference 側は count/sum_x/sum_y
// とも32bit幅で出力するため、ここで motion_count/sum_x/sum_y の実幅
// （17bit/25bit/25bit、motion_avalon_slave のレジスタ幅に合わせたもの）へ切り詰める。
wire [31:0] diff_count;
wire [31:0] diff_sum_x;
wire [31:0] diff_sum_y;
wire        f_dist_w; // frame_difference の書き込み先バンク（0/1）、自己フィードバック

wire [16:0] motion_count = diff_count[16:0];
wire [24:0] motion_sum_x = diff_sum_x[24:0];
wire [24:0] motion_sum_y = diff_sum_y[24:0];

reg  f_dist_d;
always @(posedge CAM_PCLK) begin
    if (reset)
        f_dist_d <= 1'b0;
    else
        f_dist_d <= f_dist_w;
end
wire f_dist_edge = (f_dist_w != f_dist_d);

// count がこのしきい値を超えたフレームだけ HPS に通知する（ノイズ的な微小変化を除外）。
// 必要に応じてこの値を調整すること。
localparam [16:0] MOTION_COUNT_THRESHOLD = 17'd5000;
wire motion_frame_done = f_dist_edge && (motion_count > MOTION_COUNT_THRESHOLD);

// motion_cdc 出力（clock50 ドメイン）
wire [16:0] motion_count_50;
wire [24:0] motion_sum_x_50;
wire [24:0] motion_sum_y_50;
wire        motion_new_data_50;

// soc_system のファブリック側リセット。soc_system 自身の hps_0_h2f_reset_reset_n
// 出力（HPS がリセット解除の準備を終えたことを示す）を、そのまま soc_system の
// reset_reset_n 入力へフィードバックする。DE10-Nano GHRD と同じ配線パターンで、
// HPS 本体の準備が整うまで h2f_lw 配下（motion_avalon_slave 含む）を確実にリセット
// 状態に保つための設計。
wire hps_fpga_reset_n;

wire clock25;
wire clock5;
wire reset;
assign reset = ~reset_n;

// BRAM ポート A（camera → BRAM 書き込み、CAM_PCLK ドメイン）
wire [18:0] bram_addr_a;
wire [7:0]  bram_wdata_a;
wire        bram_we_a;

// BRAM ポート B（adv7513 → BRAM 読み出し、clock25 ドメイン）
wire [18:0] bram_addr_b;
wire [7:0]  bram_rdata_b;

// ---- クロック生成 ---------------------------------------------------

// 50 MHz → 25.175 MHz（VGA ピクセルクロック）
pll_25 pll_25 (
    .refclk   (clock50),
    .rst      (reset),
    .outclk_0 (clock25),
    .locked   (locked)
);

// 50 MHz → 25 MHz（OV7670 XCLK）
pll_5 pll_5 (
    .refclk   (clock50),
    .rst      (reset),
    .outclk_0 (clock5),
    .locked   ()
);

// ---- カメラサブシステム --------------------------------------------

camera u_camera (
    .clock50     (clock50),
    .clock5      (clock5),
    .reset_n     (reset_n),
    .CAM_PCLK    (CAM_PCLK),
    .CAM_VSYNC   (CAM_VSYNC),
    .CAM_HREF    (CAM_HREF),
    .CAM_D       (CAM_D),
    .CAM_XCLK    (CAM_XCLK),
    .CAM_SIOD    (CAM_SIOD),
    .CAM_SIOC    (CAM_SIOC),
    .CAM_RESET   (CAM_RESET),
    .CAM_PWDN    (CAM_PWDN),
    .bram_addr   (bram_addr_a),
    .bram_wdata  (bram_wdata_a),
    .bram_we     (bram_we_a),
    .init_done   (CAM_INIT_DONE),
    .pclk_active (CAM_PCLK_ACT)
);

frame_difference u_frame_difference (
    .clock        (CAM_PCLK),
    .reset        (reset),
    .mode         (mode),
    .mode2        (mode2),
    .current_addr (bram_addr_a),
    .current_data (bram_wdata_a),
    .current_we   (bram_we_a),

    .diff_addr    (diff_addr),
    .diff_data    (diff_data),
    .diff_we      (diff_we),

    .count        (diff_count),
    .sum_x        (diff_sum_x),
    .sum_y        (diff_sum_y),

    .f_dist       (f_dist_w),
    .write_phase  (f_dist_w) // ダブルバッファのフェーズを自己フィードバック
);

// ---- BRAM（デュアルポート）-----------------------------------------
// Port A: 書き込み（CAM_PCLK ~5 MHz） — camera/capture_gray
// Port B: 読み出し（clock25）         — adv7513/PVI
bram_2port bram_2port (
    .clock_a   (CAM_PCLK),
    .address_a (diff_addr),
    .data_a    (diff_data),
    .wren_a    (diff_we),
    .q_a       (),

    .clock_b   (clock25),
    .address_b (bram_addr_b),
    .data_b    (8'h00),
    .wren_b    (1'b0),
    .q_b       (bram_rdata_b)
);

// ---- HDMI 出力 ------------------------------------------------------
adv7513 adv7513 (
    .clock50      (clock50),
    .reset_n      (reset_n),
    .clock25      (clock25),
    .locked       (locked),
    .switchR      (switchR),
    .switchG      (switchG),
    .switchB      (switchB),
    .HDMI_I2S0    (HDMI_I2S0),
    .HDMI_MCLK    (HDMI_MCLK),
    .HDMI_LRCLK   (HDMI_LRCLK),
    .HDMI_SCLK    (HDMI_SCLK),
    .HDMI_TX_D    (HDMI_TX_D),
    .HDMI_TX_VS   (HDMI_TX_VS),
    .HDMI_TX_HS   (HDMI_TX_HS),
    .HDMI_TX_DE   (HDMI_TX_DE),
    .HDMI_TX_CLK  (HDMI_TX_CLK),
    .HDMI_TX_INT  (HDMI_TX_INT),
    .HDMI_I2C_SDA (HDMI_I2C_SDA),
    .HDMI_I2C_SCL (HDMI_I2C_SCL),
    .READY        (READY),
    .bram_addr    (bram_addr_b),
    .bram_rdata   (bram_rdata_b)
);

// ---- モーション検出 → HPS 送信 --------------------------------------
// CAM_PCLK ドメインの motion_count/sum_x/sum_y/frame_done（frame_difference が算出）を
// clock50 ドメインへ CDC し、HPS 向け Avalon-MM スレーブとして公開する。

motion_cdc u_motion_cdc (
    .clock_src              (CAM_PCLK),
    .reset_src              (reset),

    .motion_count_src       (motion_count),
    .motion_sum_x_src       (motion_sum_x),
    .motion_sum_y_src       (motion_sum_y),
    .motion_frame_done_src  (motion_frame_done),

    .clock_dst              (clock50),
    .reset_dst              (reset),

    .motion_count_dst       (motion_count_50),
    .motion_sum_x_dst       (motion_sum_x_50),
    .motion_sum_y_dst       (motion_sum_y_50),
    .new_data_pulse_dst     (motion_new_data_50)
);

// ---- HPS サブシステム（Platform Designer 生成、soc_system.qip）------
// motion_avalon_slave はこの内部に含まれている。button_pio/dipsw_pio/led_pio は
// DE10-Nano GHRD 由来のデモ用ペリフェラルで、今回は実ピンに接続せず無効値に固定。
// f2h_cold/warm/debug_reset_req・stm_hw_events も同様に未使用のため無効値に固定。
soc_system u_soc_system (
    .clk_clk                                (clock50),
    .reset_reset_n                          (hps_fpga_reset_n),

    // モーションデータ（motion_cdc → soc_system 内部の motion_avalon_slave）
    .motion_data_export                     (motion_count_50),
    .motion_data_motion_sum_x_in            (motion_sum_x_50),
    .motion_data_motion_sum_y_in            (motion_sum_y_50),
    .motion_data_new_data_pulse_in          (motion_new_data_50),

    // HPS リセット関連（GHRD と同じ自己フィードバック構成。詳細は上の
    // hps_fpga_reset_n の宣言コメントを参照）
    .hps_0_h2f_reset_reset_n                (hps_fpga_reset_n),
    .hps_0_f2h_cold_reset_req_reset_n       (1'b1),
    .hps_0_f2h_debug_reset_req_reset_n      (1'b1),
    .hps_0_f2h_warm_reset_req_reset_n       (1'b1),
    .hps_0_f2h_stm_hw_events_stm_hwevents   (28'd0),

    // GHRD 由来のデモ周辺回路（未使用、無効値に固定）
    .button_pio_external_connection_export  (2'b00),
    .dipsw_pio_external_connection_export   (4'b0000),
    .led_pio_external_connection_export     (),

    // HPS DDR3
    .memory_mem_a                           (HPS_DDR3_ADDR),
    .memory_mem_ba                          (HPS_DDR3_BA),
    .memory_mem_ck                          (HPS_DDR3_CK_P),
    .memory_mem_ck_n                        (HPS_DDR3_CK_N),
    .memory_mem_cke                         (HPS_DDR3_CKE),
    .memory_mem_cs_n                        (HPS_DDR3_CS_N),
    .memory_mem_ras_n                       (HPS_DDR3_RAS_N),
    .memory_mem_cas_n                       (HPS_DDR3_CAS_N),
    .memory_mem_we_n                        (HPS_DDR3_WE_N),
    .memory_mem_reset_n                     (HPS_DDR3_RESET_N),
    .memory_mem_dq                          (HPS_DDR3_DQ),
    .memory_mem_dqs                         (HPS_DDR3_DQS_P),
    .memory_mem_dqs_n                       (HPS_DDR3_DQS_N),
    .memory_mem_odt                         (HPS_DDR3_ODT),
    .memory_mem_dm                          (HPS_DDR3_DM),
    .memory_oct_rzqin                       (HPS_DDR3_RZQ),

    // HPS Ethernet (EMAC1)
    .hps_0_hps_io_hps_io_emac1_inst_TX_CLK  (HPS_ENET_GTX_CLK),
    .hps_0_hps_io_hps_io_emac1_inst_TXD0    (HPS_ENET_TX_DATA[0]),
    .hps_0_hps_io_hps_io_emac1_inst_TXD1    (HPS_ENET_TX_DATA[1]),
    .hps_0_hps_io_hps_io_emac1_inst_TXD2    (HPS_ENET_TX_DATA[2]),
    .hps_0_hps_io_hps_io_emac1_inst_TXD3    (HPS_ENET_TX_DATA[3]),
    .hps_0_hps_io_hps_io_emac1_inst_RXD0    (HPS_ENET_RX_DATA[0]),
    .hps_0_hps_io_hps_io_emac1_inst_MDIO    (HPS_ENET_MDIO),
    .hps_0_hps_io_hps_io_emac1_inst_MDC     (HPS_ENET_MDC),
    .hps_0_hps_io_hps_io_emac1_inst_RX_CTL  (HPS_ENET_RX_DV),
    .hps_0_hps_io_hps_io_emac1_inst_TX_CTL  (HPS_ENET_TX_EN),
    .hps_0_hps_io_hps_io_emac1_inst_RX_CLK  (HPS_ENET_RX_CLK),
    .hps_0_hps_io_hps_io_emac1_inst_RXD1    (HPS_ENET_RX_DATA[1]),
    .hps_0_hps_io_hps_io_emac1_inst_RXD2    (HPS_ENET_RX_DATA[2]),
    .hps_0_hps_io_hps_io_emac1_inst_RXD3    (HPS_ENET_RX_DATA[3]),

    // HPS SD/MMC
    .hps_0_hps_io_hps_io_sdio_inst_CMD      (HPS_SD_CMD),
    .hps_0_hps_io_hps_io_sdio_inst_D0       (HPS_SD_DATA[0]),
    .hps_0_hps_io_hps_io_sdio_inst_D1       (HPS_SD_DATA[1]),
    .hps_0_hps_io_hps_io_sdio_inst_CLK      (HPS_SD_CLK),
    .hps_0_hps_io_hps_io_sdio_inst_D2       (HPS_SD_DATA[2]),
    .hps_0_hps_io_hps_io_sdio_inst_D3       (HPS_SD_DATA[3]),

    // HPS USB
    .hps_0_hps_io_hps_io_usb1_inst_D0       (HPS_USB_DATA[0]),
    .hps_0_hps_io_hps_io_usb1_inst_D1       (HPS_USB_DATA[1]),
    .hps_0_hps_io_hps_io_usb1_inst_D2       (HPS_USB_DATA[2]),
    .hps_0_hps_io_hps_io_usb1_inst_D3       (HPS_USB_DATA[3]),
    .hps_0_hps_io_hps_io_usb1_inst_D4       (HPS_USB_DATA[4]),
    .hps_0_hps_io_hps_io_usb1_inst_D5       (HPS_USB_DATA[5]),
    .hps_0_hps_io_hps_io_usb1_inst_D6       (HPS_USB_DATA[6]),
    .hps_0_hps_io_hps_io_usb1_inst_D7       (HPS_USB_DATA[7]),
    .hps_0_hps_io_hps_io_usb1_inst_CLK      (HPS_USB_CLKOUT),
    .hps_0_hps_io_hps_io_usb1_inst_STP      (HPS_USB_STP),
    .hps_0_hps_io_hps_io_usb1_inst_DIR      (HPS_USB_DIR),
    .hps_0_hps_io_hps_io_usb1_inst_NXT      (HPS_USB_NXT),

    // HPS SPI Master
    .hps_0_hps_io_hps_io_spim1_inst_CLK     (HPS_SPIM_CLK),
    .hps_0_hps_io_hps_io_spim1_inst_MOSI    (HPS_SPIM_MOSI),
    .hps_0_hps_io_hps_io_spim1_inst_MISO    (HPS_SPIM_MISO),
    .hps_0_hps_io_hps_io_spim1_inst_SS0     (HPS_SPIM_SS),

    // HPS UART
    .hps_0_hps_io_hps_io_uart0_inst_RX      (HPS_UART_RX),
    .hps_0_hps_io_hps_io_uart0_inst_TX      (HPS_UART_TX),

    // HPS I2C
    .hps_0_hps_io_hps_io_i2c0_inst_SDA      (HPS_I2C0_SDAT),
    .hps_0_hps_io_hps_io_i2c0_inst_SCL      (HPS_I2C0_SCLK),
    .hps_0_hps_io_hps_io_i2c1_inst_SDA      (HPS_I2C1_SDAT),
    .hps_0_hps_io_hps_io_i2c1_inst_SCL      (HPS_I2C1_SCLK),

    // HPS 個別 GPIO（loan I/O、ボード固有配線）
    .hps_0_hps_io_hps_io_gpio_inst_GPIO09   (HPS_CONV_USB_N),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO35   (HPS_ENET_INT_N),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO40   (HPS_LTC_GPIO),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO53   (HPS_LED),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO54   (HPS_KEY),
    .hps_0_hps_io_hps_io_gpio_inst_GPIO61   (HPS_GSENSOR_INT)
);

endmodule
