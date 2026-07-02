`include "difference_calc.v"
`include "prev_data_ram.v"

module frame_difference(

    input  wire        clock,
    input  wire        reset,

    input wire mode,

    input  wire [18:0] current_addr,
    input  wire [7:0]  current_data,
    input  wire        current_we,

    output wire [18:0] diff_addr,
    output wire [7:0]  diff_data,
    output wire        diff_we,

    output wire [31:0] center_x, 
    output wire [31:0] center_y,

    output wire f_dist, // 0: frame0 , 1: frame1

    input wire write_phase

);

wire [18:0] prev_rd_addr;
wire [7:0]  prev_rd_data;

wire [18:0] prev_wr_addr;
wire [7:0]  prev_wr_data;
wire        prev_wr_we;

//wire f_dist; // 0: frame0 , 1: frame1


difference_calc u_diff(

    .clock(clock),
    .reset(reset),

    .current_addr(current_addr),
    .current_data(current_data),
    .current_we(current_we),

    .prev_rd_addr(prev_rd_addr),
    .prev_rd_data(prev_rd_data),

    .prev_wr_addr(prev_wr_addr),
    .prev_wr_data(prev_wr_data),
    .prev_wr_we(prev_wr_we),

    .diff_addr(diff_addr),
    .diff_data(diff_data),
    .diff_we(diff_we),

    .center_x(center_x),
    .center_y(center_y),
    
    .f_dist(f_dist),
    
    .write_phase(write_phase),

    .mode(mode)

);


prev_data_ram u_prev (
    .data      (prev_wr_data),
    .rdaddress (prev_rd_addr[16:0]),
    .rdclock   (clock),
    .wraddress (prev_wr_addr[16:0]),
    .wrclock   (clock),
    .wren      (prev_wr_we),
    .q         (prev_rd_data)
);

endmodule