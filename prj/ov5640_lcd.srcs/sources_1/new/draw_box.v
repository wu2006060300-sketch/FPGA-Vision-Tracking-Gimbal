`timescale 1ns / 1ps

module draw_box(
    input               clk,
    input               rst_n,

    input [15:0]        rgb_in,
    input               vsync_in,
    input               href_in,

    // Retained for compatibility; not used by the cross overlay.
    input [9:0]         box_xmin,
    input [9:0]         box_xmax,
    input [8:0]         box_ymin,
    input [8:0]         box_ymax,
    input               box_valid,

    input [9:0]         center_x,
    input [8:0]         center_y,

    output reg [15:0]   rgb_out,
    output reg          vsync_out,
    output reg          href_out
);

reg [9:0] col_cnt;
reg [8:0] row_cnt;
reg       vsync_d1;

wire frame_start;
wire [9:0] distance_x;
wire [8:0] distance_y;

wire center_in_range;
wire cross_red;
wire cross_outline;

assign frame_start = vsync_in && !vsync_d1;

assign distance_x = (col_cnt >= center_x) ?
                    (col_cnt - center_x) :
                    (center_x - col_cnt);

assign distance_y = (row_cnt >= center_y) ?
                    (row_cnt - center_y) :
                    (center_y - row_cnt);

assign center_in_range =
    (center_x < 10'd800) &&
    (center_y < 9'd480);

// Red cross: 41 pixels long, 3 pixels thick.
assign cross_red = box_valid && center_in_range &&
    (
        ((distance_x <= 10'd1) && (distance_y <= 9'd20))
        ||
        ((distance_y <= 9'd1) && (distance_x <= 10'd20))
    );

// One-pixel black outline around the cross.
assign cross_outline = box_valid && center_in_range &&
    (
        ((distance_x <= 10'd2) && (distance_y <= 9'd21))
        ||
        ((distance_y <= 9'd2) && (distance_x <= 10'd21))
    );

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_cnt   <= 10'd0;
        row_cnt   <= 9'd0;
        vsync_d1  <= 1'b0;

        rgb_out   <= 16'h0000;
        vsync_out <= 1'b0;
        href_out  <= 1'b0;
    end
    else begin
        vsync_d1  <= vsync_in;
        vsync_out <= vsync_in;
        href_out  <= href_in && !frame_start;

        if (frame_start) begin
            col_cnt <= 10'd0;
            row_cnt <= 9'd0;
            rgb_out <= 16'h0000;
        end
        else if (href_in) begin
            col_cnt <= col_cnt + 1'b1;

            if (cross_red)
                rgb_out <= 16'hF800;
            else if (cross_outline)
                rgb_out <= 16'h0000;
            else
                rgb_out <= rgb_in;
        end
        else begin
            rgb_out <= 16'h0000;

            if (col_cnt != 10'd0) begin
                col_cnt <= 10'd0;
                row_cnt <= row_cnt + 1'b1;
            end
        end
    end
end

endmodule