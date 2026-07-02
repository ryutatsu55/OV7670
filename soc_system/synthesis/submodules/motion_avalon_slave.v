// motion_avalon_slave — モーション検出結果（画素数・x座標総和・y座標総和）を
// HPS へ引き渡すための常時レディな Avalon-MM スレーブ（clock50 ドメイン）。
// Platform Designer の Component Editor でこのファイルをコンポーネント化し、
// HPS の Lightweight HPS-to-FPGA ブリッジ配下に接続する（IP 生成物ではなく手書きファイル）。
//
// レジスタマップ（ワードアドレス avs_address[2:0]、Address units = WORDS）
//   0 STATUS  R   [0]=new_data（sticky, new_data_pulse_in でセット / ACK 書き込みでクリア）
//   1 COUNT   R   [16:0]=motion_count
//   2 SUM_X   R   [24:0]=motion_sum_x
//   3 SUM_Y   R   [24:0]=motion_sum_y
//   4 ACK     W   任意の値を書き込むと STATUS[0] をクリアし irq を deassert
//
// COUNT/SUM_X/SUM_Y は二重化・FIFO を持たない単純なレジスタ。HPS が前フレームを
// ACK する前に次フレームが到着した場合は値が上書きされる（~30fps に対し割り込み
// レイテンシは十分小さいため許容する設計上の割り切り）。

module motion_avalon_slave (
    input  wire        clock,
    input  wire        reset,

    // motion_cdc（clock50 ドメイン側出力）から
    input  wire [16:0] motion_count_in,
    input  wire [24:0] motion_sum_x_in,
    input  wire [24:0] motion_sum_y_in,
    input  wire        new_data_pulse_in,

    // Avalon-MM スレーブ
    input  wire [2:0]  avs_address,
    input  wire        avs_read,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    output reg  [31:0] avs_readdata,
    output wire        avs_waitrequest,

    // HPS f2h_irq0 へ
    output wire         irq
);

localparam ADDR_STATUS = 3'd0;
localparam ADDR_COUNT  = 3'd1;
localparam ADDR_SUM_X  = 3'd2;
localparam ADDR_SUM_Y  = 3'd3;
localparam ADDR_ACK    = 3'd4;

assign avs_waitrequest = 1'b0; // 常時レディ

// ---- ラッチされたモーションデータ ----
reg [16:0] motion_count_reg;
reg [24:0] motion_sum_x_reg;
reg [24:0] motion_sum_y_reg;

// ---- sticky STATUS フラグ ----
reg status_new_data;

wire ack_write = avs_write && (avs_address == ADDR_ACK);

always @(posedge clock) begin
    if (reset) begin
        motion_count_reg <= 17'd0;
        motion_sum_x_reg <= 25'd0;
        motion_sum_y_reg <= 25'd0;
        status_new_data  <= 1'b0;
    end else begin
        if (new_data_pulse_in) begin
            motion_count_reg <= motion_count_in;
            motion_sum_x_reg <= motion_sum_x_in;
            motion_sum_y_reg <= motion_sum_y_in;
        end

        // new_data_pulse_in によるセットを ack_write によるクリアより優先する
        // （同一サイクルで両方発生しても新フレームの通知を取りこぼさない）
        if (new_data_pulse_in)
            status_new_data <= 1'b1;
        else if (ack_write)
            status_new_data <= 1'b0;
    end
end

assign irq = status_new_data;

// ---- 読み出し ----
always @(posedge clock) begin
    if (reset) begin
        avs_readdata <= 32'd0;
    end else if (avs_read) begin
        case (avs_address)
            ADDR_STATUS: avs_readdata <= {31'd0, status_new_data};
            ADDR_COUNT:  avs_readdata <= {15'd0, motion_count_reg};
            ADDR_SUM_X:  avs_readdata <= {7'd0,  motion_sum_x_reg};
            ADDR_SUM_Y:  avs_readdata <= {7'd0,  motion_sum_y_reg};
            default:     avs_readdata <= 32'd0;
        endcase
    end
end

endmodule
