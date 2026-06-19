`include "PVI.v"
`include "i2c/I2C_HDMI_Config.v"

// ADV7513 HDMI output block.
// PLL is instantiated by the parent TopModule and clock25/locked are passed in.
// BRAM port B signals (bram_addr / bram_rdata) are routed through to vgaHdmi.
module adv7513(
  input  clock50, reset_n,
  input  clock25,
  input  locked,
  input  switchR, switchG, switchB,

  // AUDIO (unused)
  output HDMI_I2S0,
  output HDMI_MCLK,
  output HDMI_LRCLK,
  output HDMI_SCLK,

  // VIDEO
  output [23:0] HDMI_TX_D,
  output HDMI_TX_VS,
  output HDMI_TX_HS,
  output HDMI_TX_DE,
  output HDMI_TX_CLK,

  // HDMI config
  input  HDMI_TX_INT,
  inout  HDMI_I2C_SDA,
  output HDMI_I2C_SCL,
  output READY,

  // BRAM port B (read side — driven by PVI pixel counters)
  output [18:0] bram_addr,
  input  [7:0]  bram_rdata
);

assign HDMI_I2S0  = 1'bz;
assign HDMI_MCLK  = 1'bz;
assign HDMI_LRCLK = 1'bz;
assign HDMI_SCLK  = 1'bz;

PVI PVI (
  .clock      (clock25),
  .clock50    (clock50),
  .reset      (~locked),
  .switchR    (switchR),
  .switchG    (switchG),
  .switchB    (switchB),
  .hsync      (HDMI_TX_HS),
  .vsync      (HDMI_TX_VS),
  .dataEnable (HDMI_TX_DE),
  .vgaClock   (HDMI_TX_CLK),
  .RGBchannel (HDMI_TX_D),
  .bram_addr  (bram_addr),
  .bram_rdata (bram_rdata)
);

I2C_HDMI_Config #(
  .CLK_Freq (50000000),
  .I2C_Freq (20000)
) I2C_HDMI_Config (
  .iCLK        (clock50),
  .iRST_N      (reset_n),
  .I2C_SCLK    (HDMI_I2C_SCL),
  .I2C_SDAT    (HDMI_I2C_SDA),
  .HDMI_TX_INT (HDMI_TX_INT),
  .READY       (READY)
);

endmodule
