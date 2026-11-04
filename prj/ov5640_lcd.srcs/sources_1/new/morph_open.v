`timescale 1ns / 1ps

module morph_open(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [2:0] line0,
    input  wire [2:0] line1,
    input  wire [2:0] line2,

    input  wire       vsync_in,
    input  wire       href_in,

    output reg        bin_out,
    output reg        vsync_out,
    output reg        href_out
);

// 9个窗口像素
wire [8:0] window_9;
assign window_9 = {line0, line1, line2};

// 每项明确扩展为4位，避免求和位宽歧义
wire [3:0] cnt_white;

assign cnt_white =
    {3'b000, window_9[0]} +
    {3'b000, window_9[1]} +
    {3'b000, window_9[2]} +
    {3'b000, window_9[3]} +
    {3'b000, window_9[4]} +
    {3'b000, window_9[5]} +
    {3'b000, window_9[6]} +
    {3'b000, window_9[7]} +
    {3'b000, window_9[8]};

// 数据、帧同步、有效信号均延迟一级
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bin_out   <= 1'b0;
        vsync_out <= 1'b0;
        href_out  <= 1'b0;
    end
    else begin
        vsync_out <= vsync_in;
        href_out  <= href_in;

        if (href_in)
            bin_out <= (cnt_white >= 4'd5);
        else
            bin_out <= 1'b0;
    end
end

endmodule