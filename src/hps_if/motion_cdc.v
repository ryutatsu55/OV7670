// motion_cdc — CAM_PCLK ドメイン(モーション集計モジュール)から
// clock50 ドメイン(motion_avalon_slave)へのクロックドメイン交差。
//
// motion_count/motion_sum_x/motion_sum_y はフレームにつき1回(motion_frame_done)しか
// 更新されない低速バスのため、トグルビット + 2段フリップフロップ同期 + エッジ検出という
// 標準的な CDC パターンで十分（Gray コードや非同期 FIFO は不要）。
//
//   src (CAM_PCLK): motion_frame_done_src のたびに req_toggle を反転
//   dst (clock50) : req_toggle を2段同期し、トグルエッジで捕捉して new_data_pulse_dst を発行

module motion_cdc (

    // ---- src ドメイン（CAM_PCLK）----
    input  wire        clock_src,
    input  wire        reset_src,

    input  wire [16:0] motion_count_src,
    input  wire [24:0] motion_sum_x_src,
    input  wire [24:0] motion_sum_y_src,
    input  wire        motion_frame_done_src,

    // ---- dst ドメイン（clock50）----
    input  wire        clock_dst,
    input  wire        reset_dst,

    output reg  [16:0] motion_count_dst,
    output reg  [24:0] motion_sum_x_dst,
    output reg  [24:0] motion_sum_y_dst,
    output reg         new_data_pulse_dst
);

// ---- src ドメイン: トグルビット ----
reg req_toggle;

always @(posedge clock_src) begin
    if (reset_src)
        req_toggle <= 1'b0;
    else if (motion_frame_done_src)
        req_toggle <= ~req_toggle;
end

// ---- dst ドメイン: 2段同期 + エッジ検出 ----
reg sync0, sync1, sync1_d;

always @(posedge clock_dst) begin
    if (reset_dst) begin
        sync0   <= 1'b0;
        sync1   <= 1'b0;
        sync1_d <= 1'b0;
    end else begin
        sync0   <= req_toggle;
        sync1   <= sync0;
        sync1_d <= sync1;
    end
end

wire toggle_edge = sync1 ^ sync1_d;

always @(posedge clock_dst) begin
    if (reset_dst) begin
        motion_count_dst   <= 17'd0;
        motion_sum_x_dst   <= 25'd0;
        motion_sum_y_dst   <= 25'd0;
        new_data_pulse_dst <= 1'b0;
    end else begin
        new_data_pulse_dst <= 1'b0;

        if (toggle_edge) begin
            // req_toggle が反転してから複数 clock_dst サイクルが経過しており、
            // src 側のデータバスはすでに安定している。
            motion_count_dst   <= motion_count_src;
            motion_sum_x_dst   <= motion_sum_x_src;
            motion_sum_y_dst   <= motion_sum_y_src;
            new_data_pulse_dst <= 1'b1;
        end
    end
end

endmodule
