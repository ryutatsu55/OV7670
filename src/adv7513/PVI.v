// VGA/HDMI timing controller — 640x480 @ 60 Hz, 25 MHz pixel clock.
// Pixel data is stored in BRAM at QVGA resolution (320x240).
// Each QVGA pixel maps to a 2x2 VGA block (nearest-neighbor upscale).
// BRAM has 1-cycle registered output latency, so hsync/vsync/dataEnable use
// a 1-stage pipeline to keep them aligned with the BRAM read data.

module PVI(
  input  clock, clock50, reset,

  input  display_phase,

  output reg  hsync, vsync,
  output reg  dataEnable,
  output reg  vgaClock,
  output [23:0] RGBchannel,

  // BRAM port B interface
  output [18:0] bram_addr,  // read address presented to BRAM each cycle
  input  [7:0]  bram_rdata,  // 8-bit grayscale pixel data from BRAM (unregistered output)

  output frame_done,

);

assign frame_done = (pixelH == H_TOTAL - 1) && (pixelV == V_TOTAL - 1);

reg [9:0] pixelH, pixelV;
//reg [18:0] offset; // 0 or 76800, depending on which frame is being read

//localparam BASE = 18'd76800; // 320*240 = 76800
reg phase; // 0: frame0 , 1: frame1
wire [18:0] offset = display_phase ? 19'd76800 : 19'd0;

parameter H_ACTIVE = 640;
parameter H_FP     = 16;
parameter H_SYNC   = 96;
parameter H_TOTAL  = 800;

parameter V_ACTIVE = 480;
parameter V_FP     = 10;
parameter V_SYNC   = 2;
parameter V_TOTAL  = 525;

// 1. Pixel / line counters
always @(posedge clock or posedge reset) begin
  if (reset) begin
    pixelH <= 0;
    pixelV <= 0;
  phase  <= 0;
  //offset <= 19'd0;
  end 
  else begin
    if (pixelH == H_TOTAL - 1) begin
      pixelH <= 0;

      if (pixelV == V_TOTAL - 1 ) begin
        pixelV <= 0;
        if(framedone == 1'b1)begin
          phase  <= ~phase;
        end

        //offset = display_phase ? 19'd76800 : 19'd0;
      end else begin
        pixelV <= pixelV + 1;
      end
    end else begin
      pixelH <= pixelH + 1;
    end
  end
end

// 2. BRAM read address — combinational QVGA upscale from VGA counters.
//    Each QVGA pixel maps to a 2x2 VGA block: qvga_h = pixelH/2, qvga_v = pixelV/2.
//    addr = qvga_v * 320 + qvga_h = (qvga_v << 8) + (qvga_v << 6) + qvga_h
wire [8:0] qvga_h = pixelH[9:1];   // pixelH / 2 → 0..319
wire [7:0] qvga_v = pixelV[8:1];   // pixelV / 2 → 0..239

//TODO: offsetは0だったり76800だったりする
assign bram_addr = offset + ({11'b0, qvga_v} << 8) + ({11'b0, qvga_v} << 6) + {10'b0, qvga_h};


//assign bram_addr = BASE + ({11'b0, qvga_v} << 8) + ({11'b0, qvga_v} << 6) + {10'b0, qvga_h};

// 3. Sync / DE pipeline — 1 stage.
//    BRAM output is UNREGISTERED (combinational after address register), so it
//    updates at the same time as these registered signals — both reflect the
//    counter value from before the current clock edge.  1 stage is sufficient.
always @(posedge clock or posedge reset) begin
  if (reset) begin
    hsync      <= 1;
    vsync      <= 1;
    dataEnable <= 0;
  end 
  else begin
    hsync      <= ((pixelH >= H_ACTIVE + H_FP) && (pixelH < H_ACTIVE + H_FP + H_SYNC)) ? 1'b0 : 1'b1;
    vsync      <= ((pixelV >= V_ACTIVE + V_FP) && (pixelV < V_ACTIVE + V_FP + V_SYNC)) ? 1'b0 : 1'b1;
    dataEnable <= (pixelH < H_ACTIVE) && (pixelV < V_ACTIVE);
  end
end

// 4. Pixel clock
always @(*) vgaClock = ~clock;

// 5. Expand 8-bit grayscale to 24-bit RGB (R=G=B)
assign RGBchannel = {bram_rdata, bram_rdata, bram_rdata};

endmodule
