`include "adv7513/adv7513.v"
`include "camera/camera.v"
`include "difference/difference.v"

// Top-level module.
// IP cores (pll_25, pll_5, bram_2port) are added via their .qip files.
//
// Hierarchy:
//   TopModule
//   ├── pll_25      — 50 MHz → 25.175 MHz pixel clock (Quartus IP)
//   ├── pll_5       — 50 MHz → 25 MHz OV7670 XCLK     (Quartus IP)
//   ├── camera      — OV7670 camera subsystem (SCCB init + YUV422 capture)
//   ├── bram_2port  — dual-port RAM 8-bit × 307200     (Quartus IP)
//   │     port A: write ← camera   (CAM_PCLK 12.5 MHz)
//   │     port B: read  → adv7513  (clock25 25.175 MHz)
//   └── adv7513     — HDMI output + I2C config
module TopModule (
    input  wire        clock50,
    input  wire        reset_n,
    input  wire        switchR, switchG, switchB,

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
    output wire        CAM_PCLK_ACT   // PCLK 受信中に点灯
);

wire [18:0] diff_addr;
wire [7:0]  diff_data;
wire        diff_we;

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

    .current_addr (bram_addr_a),
    .current_data (bram_wdata_a),
    .current_we   (bram_we_a),

    .diff_addr    (diff_addr),
    .diff_data    (diff_data),
    .diff_we      (diff_we)
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

endmodule
