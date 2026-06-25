`include "difference_calc.v"
`include "prev_data_ram.v"

module frame_difference(

    input  wire        clock,
    input  wire        reset,

    input  wire [18:0] current_addr,
    input  wire [7:0]  current_data,
    input  wire        current_we,

    output wire [18:0] diff_addr,
    output wire [7:0]  diff_data,
    output wire        diff_we

);

wire [18:0] prev_addr;
wire [7:0]  prev_data;


difference_calc u_diff(

    .clock(clock),
    .reset(reset),

    .current_addr(current_addr),
    .current_data(current_data),

    .prev_addr(prev_addr),
    .prev_data(prev_data),

    .diff_addr(diff_addr),
    .diff_data(diff_data),
    .diff_we(diff_we)

);


prev_data_ram u_prev(

    .clock(clock),

    // cameraから現在画像を書き込む
    .wr_addr(current_addr),
    .wr_data(current_data),
    .wr_en(current_we),

    // difference_calcが前画像を読む
    .rd_addr(prev_addr),
    .rd_data(prev_data)

);

endmodule