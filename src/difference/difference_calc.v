module difference_calc(
  input  wire        clock,
  input  wire        reset,

  input  wire [18:0] current_addr,
  input  wire [7:0]  current_data,
  input  wire        current_we,

  output reg  [18:0] prev_rd_addr,
  input  wire [7:0]  prev_rd_data,

  output reg  [18:0] prev_wr_addr,
  output reg  [7:0]  prev_wr_data,
  output reg         prev_wr_we,

  output reg  [18:0] diff_addr,
  output reg  [7:0]  diff_data,
  output reg         diff_we
);

reg [18:0] current_addr_d1;
reg [7:0]  current_data_d1;
reg        current_we_d1;

always @(posedge clock) begin
  if (reset) begin
    prev_rd_addr    <= 19'd0;
    prev_wr_addr    <= 19'd0;
    prev_wr_data    <= 8'd0;
    prev_wr_we      <= 1'b0;

    current_addr_d1 <= 19'd0;
    current_data_d1 <= 8'd0;
    current_we_d1   <= 1'b0;

    diff_addr       <= 19'd0;
    diff_data       <= 8'd0;
    diff_we         <= 1'b0;
  end else begin
    // 前フレームBRAMへ読み出しアドレスを出す
    prev_rd_addr    <= current_addr;

    // BRAM読み出し1クロック遅延に合わせてcameraデータも遅延
    current_addr_d1 <= current_addr;
    current_data_d1 <= current_data;
    current_we_d1   <= current_we;

    // 前フレームBRAMを現在フレームで更新
    prev_wr_addr <= current_addr_d1;
    prev_wr_data <= current_data_d1;
    prev_wr_we   <= current_we_d1;

    // 差分結果を差分BRAMへ出力
    diff_addr <= current_addr_d1;
    diff_we   <= current_we_d1;

    if (current_data_d1 > prev_rd_data)
      diff_data <= current_data_d1 - prev_rd_data;
    else
      diff_data <= prev_rd_data - current_data_d1;
  end
end

endmodule