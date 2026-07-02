// motion_stats_stub — 相方ブランチの motion_stats がマージされるまでの暫定代役。
// CAM_VSYNC の立ち上がり（新フレーム開始）ごとに、フレーム番号から作った
// ダミー値を motion_count/sum_x/sum_y として確定させ、motion_frame_done を
// 1 サイクル発行する。HPS までの割り込み経路（motion_cdc → motion_avalon_slave
// → soc_system → デバイスドライバ）が正しく動作するかを、実際のモーション検出
// ロジックを待たずに確認するためのテスト専用モジュール。
// 相方の motion_stats がマージされたら、TopModule.v での接続をそちらに置き換えて
// このモジュールの instantiate を削除する。

module motion_stats_stub (
    input  wire        clock,        // CAM_PCLK
    input  wire        reset,        // active-high
    input  wire        CAM_VSYNC,

    output reg  [16:0] motion_count,
    output reg  [24:0] motion_sum_x,
    output reg  [24:0] motion_sum_y,
    output reg         motion_frame_done
);

reg        vsync_d;
reg [23:0] frame_counter;

always @(posedge clock) begin
    if (reset) begin
        vsync_d           <= 1'b0;
        frame_counter     <= 24'd0;
        motion_count      <= 17'd0;
        motion_sum_x      <= 25'd0;
        motion_sum_y      <= 25'd0;
        motion_frame_done <= 1'b0;
    end else begin
        vsync_d           <= CAM_VSYNC;
        motion_frame_done <= 1'b0;

        // 新フレーム開始エッジ = 直前フレーム分の値が確定するタイミング
        if (CAM_VSYNC && !vsync_d) begin
            frame_counter <= frame_counter + 1'b1;
            motion_count      <= frame_counter[16:0];
            motion_sum_x      <= {frame_counter, 1'b0};
            motion_sum_y      <= {1'b0, frame_counter};
            motion_frame_done <= 1'b1;
        end
    end
end

endmodule
