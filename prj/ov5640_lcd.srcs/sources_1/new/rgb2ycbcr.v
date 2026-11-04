`timescale 1ns / 1ps

module rgb2ycbcr(
    input        clk,
    input        rst_n,
    
    input [7:0]  R,
    input [7:0]  G,
    input [7:0]  B,
    input        vsync_in,
    input        href_in,
    
    output reg [7:0] Y,
    output reg [7:0] Cb,
    output reg [7:0] Cr,
    output reg       vsync_out,
    output reg       href_out
);

reg [15:0] Y_tmp;
reg [15:0] Cb_tmp;
reg [15:0] Cr_tmp;
//新增
reg vsync_d1;
reg href_d1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        Y_tmp  <= 16'd0;
        Cb_tmp <= 16'd0;
        Cr_tmp <= 16'd0;
        Y      <= 8'd0;
        Cb     <= 8'd0;
        Cr     <= 8'd0;
        vsync_out <= 1'b0;
        href_out  <= 1'b0;
        vsync_d1 <= 1'b0;
        href_d1  <= 1'b0;
    end else begin
        // 第一拍：定点数乘法（系数放大256倍）
        Y_tmp  <=  77*R + 150*G +  29*B;
        Cb_tmp <= (-43)*R + (-85)*G + 128*B + 16'd32768;
        Cr_tmp <=  128*R + (-107)*G + (-21)*B + 16'd32768;
        
        // 第二拍：右移8位，得到8位结果
        Y  <= Y_tmp[15:8];
        Cb <= Cb_tmp[15:8];
        Cr <= Cr_tmp[15:8];
        
        // 同步信号打2拍
// 颜色计算经过两级寄存器，同步信号也经过两级
        vsync_d1  <= vsync_in;
        href_d1   <= href_in;
        
        vsync_out <= vsync_d1;
        href_out  <= href_d1;
    end
end

endmodule
