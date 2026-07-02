module difference_calc(
  input  wire        clock,
  input  wire        reset,
  
  input wire mode,
  input wire mode2,

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
  output reg         diff_we,

  output reg [31:0] center_x, 
  output reg [31:0] center_y, // 重心座標

  output reg f_dist, // 0: frame0 , 1: frame1
  input write_phase
);



localparam [18:0] BASE = 19'd76800; //320*240 = 76800
localparam [7:0] THRESHOLD = 8'd20; // 差分の閾値

reg [18:0] current_addr_d1, current_addr_d2;
reg [7:0]  current_data_d1, current_data_d2;
reg        current_we_d1, current_we_d2;

//reg [18:0] addr_x;

reg [31:0] Sx, Sy, S; // 重心計算用の変数

wire [7:0] abs_diff =
  (current_data_d2 >= prev_rd_data) ?
  (current_data_d2 - prev_rd_data) :
  (prev_rd_data - current_data_d2);

wire [1:0] output_switch = {mode2, mode}; //mode2が2bit目　mode が1bit目

wire [7:0] diff_pixel =
    (output_switch == 2'b00) ? (8'd255 - abs_diff) : // 黒地
    (output_switch == 2'b01) ? abs_diff :            // 白地
                               current_data_d2;       // output_switch==2'b10：何も加工しない



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

    f_dist   <= 1'b0;
    //addr_x   <= 19'd0;
    Sx       <= 32'd0;
    Sy       <= 32'd0;
    S        <= 32'd0;
    center_x <= 32'd0;
    center_y <= 32'd0;
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
    if(write_phase ==1'b1)begin
      diff_addr <= current_addr_d2 + BASE;
    end else begin
      diff_addr <= current_addr_d2;
    end

    if (current_we_d2 && current_addr_d2 == 19'd76799) begin
      f_dist <= ~f_dist;
    end

    diff_we   <= current_we_d2;

    /*if (current_data_d2 >= prev_rd_data && mode == 1'b1) begin
      diff_data <= (current_data_d2 - prev_rd_data);
    end else if (current_data_d2 < prev_rd_data && mode == 1'b1) begin
      diff_data <= (prev_rd_data - current_data_d2);
    end else if (current_data_d2 >= prev_rd_data && mode == 1'b0) begin
      diff_data <= 10'd255-(current_data_d2 - prev_rd_data);
    end else if (current_data_d2 < prev_rd_data && mode == 1'b0) begin
      diff_data <= 10'd255-(prev_rd_data - current_data_d2);
    end*/

    diff_data <= diff_pixel;

    //Sx Sy Sの計算
    if(current_we_d2 && diff_pixel > THRESHOLD)begin
      // 差分が閾値を超えた場合の処理
      //addr_x <= current_addr_d2[18:0] % 19'd320;
      Sx <= Sx + (current_addr_d2 % 19'd320);
      Sy <= Sy + (current_addr_d2 / 19'd320);
      S <= S + 1;

    end
    else begin
      // 差分が閾値以下の場合の処理
      // 特に何もしない

    end

    //変更テスト

    //重心の算出
    if (current_we_d2 && current_addr_d2 == 19'd76799) begin
      if (S != 0) begin
        center_x <= Sx / S;
        center_y <= Sy / S;
      end else begin
        center_x <= 0;
        center_y <= 0;
      end

      Sx <= 0;
      Sy <= 0;
      S  <= 0;
    end

    // 現在フレームを次回用に保存
    prev_wr_addr <= current_addr_d2;
    prev_wr_data <= current_data_d2;
    prev_wr_we   <= current_we_d2;
  end
end

endmodule