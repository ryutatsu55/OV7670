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

  output reg  [18:0] diff_addr, //19bit
  output reg  [7:0]  diff_data,
  output reg         diff_we
);

reg f_dist; // 0: frame0 , 1: frame1

localparam BASE = 18'd76800; //320*240 = 76800
localparam THRESHOLD = 8'd20; // 差分の閾値

reg [18:0] current_addr_d1, current_addr_d2;
reg [7:0]  current_data_d1, current_data_d2;
reg        current_we_d1, current_we_d2;

reg [31:0] Sx, Sy, S; // 重心計算用の変数

always @(posedge clock) begin
  if (reset) begin
    prev_rd_addr <= 19'd0;

    current_addr_d1 <= 19'd0;
    current_addr_d2 <= 19'd0;
    current_data_d1 <= 8'd0;
    current_data_d2 <= 8'd0;
    current_we_d1   <= 1'b0;
    current_we_d2   <= 1'b0;

    prev_wr_addr <= 19'd0;
    prev_wr_data <= 8'd0;
    prev_wr_we   <= 1'b0;

    diff_addr <= 19'd0;
    diff_data <= 8'd0;
    diff_we   <= 1'b0;
  end else begin
    // 前フレームRAMへ読み出し要求
    prev_rd_addr <= current_addr;

    // RAM読み出し2クロック遅延に合わせる
    current_addr_d1 <= current_addr;
    current_data_d1 <= current_data;
    current_we_d1   <= current_we;

    current_addr_d2 <= current_addr_d1;
    current_data_d2 <= current_data_d1;
    current_we_d2   <= current_we_d1;


    // 差分出力
    if(f_dist ==1'b1)begin
      diff_addr <= current_addr_d2 + BASE;
    end else begin
      diff_addr <= current_addr_d2;
    end

    if(current_addr_d2 == 19'd76799)begin
      f_dist <= ~f_dist;
    end

    diff_we   <= current_we_d2;

    if (current_data_d2 > prev_rd_data)
      diff_data <= current_data_d2 - prev_rd_data;
    else
      diff_data <= prev_rd_data - current_data_d2;

    //TODO: Sx Sy Sの計算
    if(diff_data > THRESHOLD)begin
      // 差分が閾値を超えた場合の処理
      Sx <= Sx + current_addr_d2[18:0];
      Sy <= Sy + 19'd239 - current_addr_d2[18:0];
      S <= S + 1;

    end
    else begin
      // 差分が閾値以下の場合の処理


    end
    //TODO: 重心の算出

    // 現在フレームを次回用に保存
    prev_wr_addr <= current_addr_d2;
    prev_wr_data <= current_data_d2;
    prev_wr_we   <= current_we_d2;
  end
end

endmodule