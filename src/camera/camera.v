`include "capture_gray.v"
`include "sccb/OV7670_init.v"
`include "sccb/OV7670_sccb_write.v"

// OV7670 camera subsystem.
// pll_5 (XCLK 25 MHz) is instantiated by the parent TopModule; clock5 is passed in.
// BRAM port A signals (bram_addr/bram_wdata/bram_we) are routed through to capture_gray.
//
// Hierarchy:
//   camera
//   ├── capture_gray            — PCLK-domain YUV422→Y capture → BRAM port A
//   └── sccb/
//         ├── OV7670_init       — SCCB initialization sequencer (ROM 10 entries)
//         └── OV7670_sccb_write — SCCB write driver (3-byte: DEV_ADDR + REG + DATA)
module camera (
    // システムクロック・リセット
    input  wire        clock50,  // 50 MHz (SCCB 用)
    input  wire        clock5,   // 25 MHz (OV7670 XCLK、TopModule の pll_5 出力)
    input  wire        reset_n,  // アクティブ Low リセット

    // OV7670 物理ピン
    input  wire        CAM_PCLK,
    input  wire        CAM_VSYNC,
    input  wire        CAM_HREF,
    input  wire [7:0]  CAM_D,
    output wire        CAM_XCLK,
    inout  wire        CAM_SIOD,
    output wire        CAM_SIOC,
    output wire        CAM_RESET,
    output wire        CAM_PWDN,

    // BRAM ポート A（書き込み側 — capture_gray が駆動）
    output wire [18:0] bram_addr,
    output wire [7:0]  bram_wdata,
    output wire        bram_we,

    // 状態インジケータ（LED アサイン用）
    output wire        init_done,   // SCCB 初期化完了で HIGH（全レジスタ書き込み済み）
    output wire        pclk_active  // PCLK 受信中に点灯（トグル出力 ~2.5 MHz）
);

// ---- 固定制御 -------------------------------------------------------
assign CAM_XCLK  = clock5;
assign CAM_RESET = 1'b1;  // active-low: High = 通常動作
assign CAM_PWDN  = 1'b0;  // active-high: Low  = 通常動作

// ---- 内部ワイヤー ---------------------------------------------------
wire sccb_start, sccb_busy, sccb_done;
wire [7:0] sccb_reg_addr, sccb_reg_data;
wire cam_init_done;
wire bram_we_raw;

// ---- 状態インジケータ -----------------------------------------------
assign init_done = cam_init_done;

// PCLK トグル: PCLK が来ていれば ~2.5 MHz で反転 → LED 点灯
reg pclk_toggle;
always @(posedge CAM_PCLK or negedge reset_n) begin
    if (!reset_n) pclk_toggle <= 1'b0;
    else          pclk_toggle <= ~pclk_toggle;
end
assign pclk_active = pclk_toggle;

// BRAM 書き込みゲート: 初期化完了後のみ有効
assign bram_we = bram_we_raw & cam_init_done;

// ---- サブモジュール -------------------------------------------------

// SCCB ライタ（50 MHz 動作、100 kHz SCCB）
ov7670_sccb_write #(
    .CLK_FREQ (50000000),
    .SCCB_FREQ(100000)
) u_sccb (
    .clk      (clock50),
    .reset_n  (reset_n),
    .start    (sccb_start),
    .reg_addr (sccb_reg_addr),
    .reg_data (sccb_reg_data),
    .busy     (sccb_busy),
    .done     (sccb_done),
    .sioc     (CAM_SIOC),
    .siod     (CAM_SIOD)
);

// 初期化シーケンサ（YUV422 / QVGA レジスタを順次 SCCB 書き込み）
ov7670_init u_init (
    .clk          (clock50),
    .reset_n      (reset_n),
    .i2c_start    (sccb_start),
    .i2c_reg_addr (sccb_reg_addr),
    .i2c_reg_data (sccb_reg_data),
    .i2c_busy     (sccb_busy),
    .i2c_done     (sccb_done),
    .init_done    (cam_init_done)
);

// グレースケールキャプチャ（YUV422 の Y 成分のみ BRAM 書き込み）
capture_gray u_capture (
    .rst_n        (reset_n),
    .pclk         (CAM_PCLK),
    .vsync        (CAM_VSYNC),
    .href         (CAM_HREF),
    .c_data       (CAM_D),
    .bram_addr    (bram_addr),
    .data_to_bram (bram_wdata),
    .bram_we      (bram_we_raw)
);

endmodule
