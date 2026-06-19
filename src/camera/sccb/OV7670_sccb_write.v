module ov7670_sccb_write (
    input  wire       clk,
    input  wire       reset_n,

    input  wire       start,
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,

    output reg        busy,
    output reg        done,

    output reg        sioc,
    inout  wire       siod
);

    parameter CLK_FREQ = 50000000;
    parameter SCCB_FREQ = 100000;
    localparam DIV = CLK_FREQ / (SCCB_FREQ * 4);

    localparam DEV_ADDR = 8'h42;

    reg [15:0] div_cnt;
    reg tick;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_cnt <= 0;
            tick <= 0;
        end else begin
            if (div_cnt == DIV-1) begin
                div_cnt <= 0;
                tick <= 1;
            end else begin
                div_cnt <= div_cnt + 1;
                tick <= 0;
            end
        end
    end

    reg siod_out;
    reg siod_oe;

    assign siod = siod_oe ? siod_out : 1'bz;

    localparam S_IDLE      = 5'd0;
    localparam S_START_A   = 5'd1;
    localparam S_START_B   = 5'd2;
    localparam S_LOAD      = 5'd3;
    localparam S_BIT_LOW   = 5'd4;
    localparam S_BIT_HIGH  = 5'd5;
    localparam S_ACK_LOW   = 5'd6;
    localparam S_ACK_HIGH  = 5'd7;
    localparam S_NEXT      = 5'd8;
    localparam S_STOP_A    = 5'd9;
    localparam S_STOP_B    = 5'd10;
    localparam S_STOP_C    = 5'd11;
    localparam S_DONE      = 5'd12;

    reg [4:0] state;
    reg [7:0] tx_byte;
    reg [2:0] bit_cnt;
    reg [1:0] byte_cnt;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state    <= S_IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            sioc     <= 1'b1;
            siod_out <= 1'b1;
            siod_oe  <= 1'b1;
            tx_byte  <= 8'd0;
            bit_cnt  <= 3'd0;
            byte_cnt <= 2'd0;
        end else begin
            done <= 1'b0;

            if (tick) begin
                case (state)

                    S_IDLE: begin
                        sioc     <= 1'b1;
                        siod_out <= 1'b1;
                        siod_oe  <= 1'b1;
                        busy     <= 1'b0;

                        if (start) begin
                            busy     <= 1'b1;
                            byte_cnt <= 2'd0;
                            state    <= S_START_A;
                        end
                    end

                    // START: SIOC=1 のまま SIOD を 1→0
                    S_START_A: begin
                        sioc     <= 1'b1;
                        siod_out <= 1'b1;
                        siod_oe  <= 1'b1;
                        state    <= S_START_B;
                    end

                    S_START_B: begin
                        siod_out <= 1'b0;
                        state    <= S_LOAD;
                    end

                    S_LOAD: begin
                        sioc    <= 1'b0;
                        bit_cnt <= 3'd7;

                        case (byte_cnt)
                            2'd0: tx_byte <= DEV_ADDR;
                            2'd1: tx_byte <= reg_addr;
                            2'd2: tx_byte <= reg_data;
                            default: tx_byte <= 8'h00;
                        endcase

                        siod_oe <= 1'b1;
                        state   <= S_BIT_LOW;
                    end

                    // SIOC=0 中にデータを出す
                    S_BIT_LOW: begin
                        sioc     <= 1'b0;
                        siod_oe  <= 1'b1;
                        siod_out <= tx_byte[bit_cnt];
                        state    <= S_BIT_HIGH;
                    end

                    // SIOC=1 でスレーブが読む
                    S_BIT_HIGH: begin
                        sioc <= 1'b1;

                        if (bit_cnt == 3'd0) begin
                            state <= S_ACK_LOW;
                        end else begin
                            bit_cnt <= bit_cnt - 3'd1;
                            state   <= S_BIT_LOW;
                        end
                    end

                    // ACK 期間: SIOD を解放（Hi-Z）
                    S_ACK_LOW: begin
                        sioc    <= 1'b0;
                        siod_oe <= 1'b0;
                        state   <= S_ACK_HIGH;
                    end

                    S_ACK_HIGH: begin
                        sioc  <= 1'b1;
                        state <= S_NEXT;
                    end

                    S_NEXT: begin
                        sioc    <= 1'b0;
                        siod_oe <= 1'b1;

                        if (byte_cnt == 2'd2) begin
                            state <= S_STOP_A;
                        end else begin
                            byte_cnt <= byte_cnt + 2'd1;
                            state    <= S_LOAD;
                        end
                    end

                    // STOP: SIOC=1 中に SIOD を 0→1
                    S_STOP_A: begin
                        sioc     <= 1'b0;
                        siod_oe  <= 1'b1;
                        siod_out <= 1'b0;
                        state    <= S_STOP_B;
                    end

                    S_STOP_B: begin
                        sioc  <= 1'b1;
                        state <= S_STOP_C;
                    end

                    S_STOP_C: begin
                        siod_out <= 1'b1;
                        state    <= S_DONE;
                    end

                    S_DONE: begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end

                    default: begin
                        state <= S_IDLE;
                    end

                endcase
            end
        end
    end

endmodule
