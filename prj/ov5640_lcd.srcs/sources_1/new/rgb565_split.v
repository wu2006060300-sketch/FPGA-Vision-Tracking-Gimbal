`timescale 1ns / 1ps

module rgb565_split(
    input        clk,
    input        rst_n,
    
    input [15:0] rgb565_in,
    input        vsync_in,
    input        href_in,
    
    output reg [7:0] R,
    output reg [7:0] G,
    output reg [7:0] B,
    output reg       vsync_out,
    output reg       href_out
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        R <= 8'd0;
        G <= 8'd0;
        B <= 8'd0;
        vsync_out <= 1'b0;
        href_out  <= 1'b0;
    end else begin
        // RGB565 5-6-5 扩展为8位
        R <= {rgb565_in[15:11], rgb565_in[15:13]};
        G <= {rgb565_in[10:5],  rgb565_in[10:9]};
        B <= {rgb565_in[4:0],   rgb565_in[4:2]};
        
        // 同步信号打1拍，和数据对齐
        vsync_out <= vsync_in;
        href_out  <= href_in;
    end
end

endmodule
