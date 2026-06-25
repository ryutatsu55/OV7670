module difference(
  input  clock,   // 50 MHz
  input  reset,   // active-high until PLL locks

  input wire [18:0] current_addr,
  input wire [7:0]  current_data,

  input wire [18:0] prev_addr,
  input wire [7:0]  prev_data,

  output reg [18:0]  diff_addr,
  output reg [7:0]  diff_data,
  output reg  dest
  
);

localparam PICT1 = 1'd0;
localparam PICT2 = 1'd1;


always @(posedge clock) begin
    if (reset) begin
        dest <= PICT1;
        diff_addr <= 19'd0;
        diff_data <= 8'd0;
    end else begin
    
    if(current_data>prev_data)begin
        diff_data <= current_data - prev_data;
    end else begin
        diff_data <= prev_data - current_data;
    end
        diff_addr <= current_addr;
    
    if(current_addr == 19'd76799)begin
        dest <= ~dest;
    end
    end
end

endmodule
