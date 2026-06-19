module capture_gray
(
    input  wire        rst_n, //アクティブLowのリセット信号

    // OV7670からもらう情報
    input  wire        pclk,  //画素クロック
    input  wire        vsync, //新しい画像データの始まりに 1 になる
    input  wire        href,  //有効画素のときに 1　になる
    input  wire [7:0]  c_data, //OV7670からくる8bitのデータ

    // BRAMへの書き込み
    output reg  [18:0] bram_addr, //BRAMのアドレス　19bit（TopModuleのBRAMと幅を合わせる）
                                   //BRAMの1アドレス=8 bit
    output reg  [7:0]  data_to_bram, //BRAMへのデータ
    output reg         bram_we  //BRAMに書き込むかどうか
                                 // Weite Enable
);


    // YUV422 Y0 U Y1 V　を繰り返す
    // これら4状態ごとに処理を行う

    localparam ST_Y0 = 2'd0; //保存する
    localparam ST_U  = 2'd1; //捨てる
    localparam ST_Y1 = 2'd2; //保存する
    localparam ST_V  = 2'd3; //捨てる

    reg [1:0] state;  //状態を格納する 2 bit


    // キャプチャ

    always @(posedge pclk or negedge rst_n)
    begin
        if(rst_n == 0)
        begin
            //初期化
            state        <= ST_Y0;
            bram_addr    <= 19'd0;
            data_to_bram <= 8'd0;
            bram_we      <= 1'b0;
        end
        else
        begin
            bram_we <= 1'b0;

            // 新しい画像データの始まりの時
            if(vsync)
            begin
                state     <= ST_Y0;
                bram_addr <= 19'd0;
            end

            // 水平ブランキング中: 次ラインの先頭バイト(Y0)に備えて常にリセット
            // HREF の PCLK カウントが4の倍数でない場合のずれを毎ライン補正する
            else if(!href)
            begin
                state <= ST_Y0;
            end

            // 有効画像のとき (送られてきたものが画像データの時)
            else if(href)
            begin

                case(state) //状態に応じた処理

                    // Y0: データをラッチして書き込み。アドレスは次サイクル(ST_U)で進める
                    ST_Y0:
                    begin
                        data_to_bram <= c_data;
                        bram_we      <= 1'b1;
                        state        <= ST_U;
                    end


                    // U: Y0 の BRAM 書き込みが確定した後にアドレスを進める
                    ST_U:
                    begin
                        if(bram_addr < 19'd76799) // 320 × 240 = 76800画素
                            bram_addr <= bram_addr + 1'b1;
                        state <= ST_Y1;
                    end


                    // Y1: データをラッチして書き込み。アドレスは次サイクル(ST_V)で進める
                    ST_Y1:
                    begin
                        data_to_bram <= c_data;
                        bram_we      <= 1'b1;
                        state        <= ST_V;
                    end


                    // V: Y1 の BRAM 書き込みが確定した後にアドレスを進める
                    ST_V:
                    begin
                        if(bram_addr < 19'd76799)
                            bram_addr <= bram_addr + 1'b1;
                        state <= ST_Y0;
                    end

                    default:
                    begin
                        state <= ST_Y0;
                    end

                endcase

            end

        end

    end

endmodule
