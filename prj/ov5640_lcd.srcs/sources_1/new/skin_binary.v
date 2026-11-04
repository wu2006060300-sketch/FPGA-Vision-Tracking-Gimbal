`timescale 1ns / 1ps

module skin_binary(
    input        clk,
    input        rst_n,
    
    input [7:0]  Y,      // 亮度分量
    input [7:0]  Cb,     // 蓝色色度
    input [7:0]  Cr,     // 红色色度
    input        vsync_in,
    input        href_in,
    
    output reg       bin_out,  // 1=肤色，0=背景
    output reg       vsync_out,
    output reg       href_out
);

// ========== 阈值参数，可根据现场微调 ==========
// 色度阈值（黄种人标准）
parameter Cb_MIN = 8'd77;
parameter Cb_MAX = 8'd127;
parameter Cr_MIN = 8'd133;
parameter Cr_MAX = 8'd173;
// 亮度阈值（过滤过黑、过曝区域）
parameter Y_MIN  = 8'd20;
parameter Y_MAX  = 8'd240;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        bin_out <= 1'b0;
        vsync_out <= 1'b0;
        href_out  <= 1'b0;
    end else begin
        // 色度+亮度 三个条件同时满足才判定为肤色
        if((Cb >= Cb_MIN && Cb <= Cb_MAX) && 
           (Cr >= Cr_MIN && Cr <= Cr_MAX) &&
           (Y  >= Y_MIN  && Y  <= Y_MAX ))
            bin_out <= 1'b1;
        else
            bin_out <= 1'b0;
        
        // 同步信号打1拍
        vsync_out <= vsync_in;
        href_out  <= href_in;
    end
end

endmodule
