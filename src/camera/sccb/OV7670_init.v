module ov7670_init (
    input  wire       clk,
    input  wire       reset_n,

    output reg        i2c_start,
    output reg [7:0]  i2c_reg_addr,
    output reg [7:0]  i2c_reg_data,
    input  wire       i2c_busy,
    input  wire       i2c_done,

    output reg        init_done
);

    localparam S_WAIT  = 3'd0;
    localparam S_LOAD  = 3'd1;
    localparam S_START = 3'd2;
    localparam S_BUSY  = 3'd3;
    localparam S_NEXT  = 3'd4;
    localparam S_DONE  = 3'd5;
    localparam S_DELAY = 3'd6; // FFF0 マーカー用 10ms ウェイト

    // wait_cnt: S_WAIT（起動ウェイト）と S_DELAY（リセット後ウェイト）で兼用
    localparam WAIT_10MS = 20'd500000; // 50MHz × 10ms

    reg [2:0]  state;
    reg [7:0]  rom_index;
    reg [15:0] rom_data;
    reg [19:0] wait_cnt;

    // 初期化ROM（YUV422 / QVGA 設定）
    // FFF0 = 10ms ウェイトマーカー（COM7 リセット完了待ちに使用）
    // FFFF = 終端マーカー
    //
    // QVGA には COM7 だけでなく、DCW スケーリングレジスタとウィンドウタイミングの設定が必要。
    // これらが欠けると VGA（640×480）のまま出力される。
    always @(*) begin
        case (rom_index)
            // ---- ソフトウェアリセット ----------------------------------------
            8'd0:  rom_data = 16'h1280; // COM7: ソフトウェアリセット
            8'd1:  rom_data = 16'hFFF0; // 10ms ウェイト（内部リセット完了待ち）

            // ---- 基本設定 ----------------------------------------------------
            8'd2:  rom_data = 16'h0900; // COM2: 出力ドライブ強度 1x（最小）
            8'd3:  rom_data = 16'h1101; // CLKRC: 内部プレスケーラを「2分周」に設定
            8'd4:  rom_data = 16'h1210; // COM7: QVGA(bit4=1) + YUV出力
            8'd5:  rom_data = 16'h0C04; // COM3: DCW（デシメーション）有効
            8'd6:  rom_data = 16'h3E19; // COM14: 【重要】元の2分周（0x19）に絶対に戻す！

            // ---- QVGAスケーリング（VGA→QVGA 2×2 サブサンプリング）----------
            8'd7:  rom_data = 16'h703A; // SCALING_XSC: 水平スケーリング係数
            8'd8:  rom_data = 16'h7135; // SCALING_YSC: 垂直スケーリング係数
            8'd9:  rom_data = 16'h7211; // SCALING_DCWCTR: 水平 2x + 垂直 2x 間引き
            8'd10: rom_data = 16'h73F1; // SCALING_PCLK_DIV: 2分周のまま維持  (データシートの「COM14[2:0]と連動させること」という指示に従う)
            8'd11: rom_data = 16'hA202; // SCALING_PCLK_DELAY: スケーリング後遅延補正

            // ---- ウィンドウタイミング（QVGA 用標準値）-----------------------
            8'd12: rom_data = 16'h1716; // HSTART: 水平開始位置
            8'd13: rom_data = 16'h1804; // HSTOP:  水平終了位置
            8'd14: rom_data = 16'h3280; // HREF:   水平タイミング補正
            8'd15: rom_data = 16'h1902; // VSTART: 垂直開始位置
            8'd16: rom_data = 16'h1A7A; // VSTOP:  垂直終了位置
            8'd17: rom_data = 16'h030A; // VREF:   垂直タイミング補正

            // ---- YUV出力設定 ------------------------------------------------
            8'd18: rom_data = 16'h40C0; // COM15: 出力レンジ全域 [0-255]（YUV用）
            8'd19: rom_data = 16'h3A04; // TSLB:  YUYV バイト順（Y0,Cb,Y1,Cr）
            8'd20: rom_data = 16'h1408; // COM9:  AGC/AEC ゲイン上限 2x（白飛び抑制）
            8'd21: rom_data = 16'h8C00; // RGB444: 無効
            8'd22: rom_data = 16'h6B4A; // DBLV: 内部PLLを「4倍」に設定（10MHz × 4 ＝ 40MHz）

            default: rom_data = 16'hFFFF; // 終端マーカー
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_WAIT;
            rom_index    <= 8'd0;
            wait_cnt     <= 20'd0;
            i2c_start    <= 1'b0;
            i2c_reg_addr <= 8'd0;
            i2c_reg_data <= 8'd0;
            init_done    <= 1'b0;
        end else begin
            case (state)

                S_WAIT: begin
                    i2c_start <= 1'b0;
                    // 電源投入・XCLK 安定待ち（50MHz × 10ms）
                    if (wait_cnt < WAIT_10MS)
                        wait_cnt <= wait_cnt + 20'd1;
                    else
                        state <= S_LOAD;
                end

                S_LOAD: begin
                    i2c_start <= 1'b0;
                    if (rom_data == 16'hFFFF) begin
                        // 全レジスタ書き込み完了
                        state <= S_DONE;
                    end else if (rom_data == 16'hFFF0) begin
                        // 10ms ウェイトマーカー: wait_cnt をリセットして S_DELAY へ
                        wait_cnt <= 20'd0;
                        state    <= S_DELAY;
                    end else begin
                        i2c_reg_addr <= rom_data[15:8];
                        i2c_reg_data <= rom_data[7:0];
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (!i2c_busy) begin
                        // SCCB が受理するまでアサートし続ける
                        // （tick は 125 サイクルに 1 回のため 1 パルスでは届かない）
                        i2c_start <= 1'b1;
                    end else begin
                        // busy=1 → SCCB が受理確認 → デアサートして次へ
                        i2c_start <= 1'b0;
                        state     <= S_BUSY;
                    end
                end

                S_BUSY: begin
                    i2c_start <= 1'b0;
                    if (i2c_done)
                        state <= S_NEXT;
                end

                S_NEXT: begin
                    i2c_start <= 1'b0;
                    rom_index <= rom_index + 8'd1;
                    state     <= S_LOAD;
                end

                S_DELAY: begin
                    i2c_start <= 1'b0;
                    // 10ms カウント後に S_NEXT へ進み rom_index をインクリメント
                    if (wait_cnt < WAIT_10MS)
                        wait_cnt <= wait_cnt + 20'd1;
                    else
                        state <= S_NEXT;
                end

                S_DONE: begin
                    i2c_start <= 1'b0;
                    init_done <= 1'b1;
                    state     <= S_DONE;
                end

                default: begin
                    i2c_start <= 1'b0;
                    state     <= S_WAIT;
                end

            endcase
        end
    end

endmodule
