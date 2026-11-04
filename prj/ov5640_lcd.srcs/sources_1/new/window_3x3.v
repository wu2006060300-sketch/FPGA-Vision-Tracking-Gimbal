`timescale 1ns / 1ps

module window_3x3 #(
    parameter integer H_DISP = 800
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       din,
    input  wire       vsync_in,
    input  wire       href_in,

    output reg [2:0]  line0,
    output reg [2:0]  line1,
    output reg [2:0]  line2,

    output reg        vsync_out,
    output reg        href_out
);

// 保存上一行、上上行
reg line_buf0 [0:H_DISP-1];
reg line_buf1 [0:H_DISP-1];

reg [12:0] col_cnt;

// 只需区分第0行、第1行和第2行以后
reg [1:0] rows_ready;

reg vsync_d1;
reg href_d1;

wire frame_start;
wire line_end;

assign frame_start = vsync_in && !vsync_d1;
assign line_end    = !href_in && href_d1;

// 每一行窗口中的前两个像素
reg top_prev1;
reg top_prev2;

reg mid_prev1;
reg mid_prev2;

reg bot_prev1;
reg bot_prev2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_cnt    <= 13'd0;
        rows_ready <= 2'd0;

        vsync_d1 <= 1'b0;
        href_d1  <= 1'b0;

        vsync_out <= 1'b0;
        href_out  <= 1'b0;

        line0 <= 3'b000;
        line1 <= 3'b000;
        line2 <= 3'b000;

        top_prev1 <= 1'b0;
        top_prev2 <= 1'b0;
        mid_prev1 <= 1'b0;
        mid_prev2 <= 1'b0;
        bot_prev1 <= 1'b0;
        bot_prev2 <= 1'b0;
    end
    else begin
        vsync_d1 <= vsync_in;
        href_d1  <= href_in;

        // 数据和有效信号均在本级寄存一次
        vsync_out <= vsync_in;
        href_out  <= href_in && !frame_start;

        if (frame_start) begin
            col_cnt    <= 13'd0;
            rows_ready <= 2'd0;

            line0 <= 3'b000;
            line1 <= 3'b000;
            line2 <= 3'b000;

            top_prev1 <= 1'b0;
            top_prev2 <= 1'b0;
            mid_prev1 <= 1'b0;
            mid_prev2 <= 1'b0;
            bot_prev1 <= 1'b0;
            bot_prev2 <= 1'b0;
        end
        else if (href_in) begin
            if (col_cnt < H_DISP) begin

                // 非阻塞赋值读取的是更新前的缓存：
                // line_buf0 = 上一行
                // line_buf1 = 上上行
                line_buf0[col_cnt] <= din;
                line_buf1[col_cnt] <= line_buf0[col_cnt];

                // 更新横向移位寄存器
                top_prev2 <= top_prev1;
                top_prev1 <= line_buf1[col_cnt];

                mid_prev2 <= mid_prev1;
                mid_prev1 <= line_buf0[col_cnt];

                bot_prev2 <= bot_prev1;
                bot_prev1 <= din;

                // 前两行、前两列没有完整窗口，输出0。
                // 保留href节拍，避免改变后续行列计数。
                if ((rows_ready == 2'd2) &&
                    (col_cnt >= 13'd2)) begin
                    line0 <= {
                        top_prev2,
                        top_prev1,
                        line_buf1[col_cnt]
                    };

                    line1 <= {
                        mid_prev2,
                        mid_prev1,
                        line_buf0[col_cnt]
                    };

                    line2 <= {
                        bot_prev2,
                        bot_prev1,
                        din
                    };
                end
                else begin
                    line0 <= 3'b000;
                    line1 <= 3'b000;
                    line2 <= 3'b000;
                end

                col_cnt <= col_cnt + 1'b1;
            end
            else begin
                // 防止输入异常时访问缓存边界以外
                line0 <= 3'b000;
                line1 <= 3'b000;
                line2 <= 3'b000;
            end
        end
        else begin
            col_cnt <= 13'd0;

            line0 <= 3'b000;
            line1 <= 3'b000;
            line2 <= 3'b000;

            // 每行结束后清除横向历史，避免串行
            top_prev1 <= 1'b0;
            top_prev2 <= 1'b0;
            mid_prev1 <= 1'b0;
            mid_prev2 <= 1'b0;
            bot_prev1 <= 1'b0;
            bot_prev2 <= 1'b0;

            if (line_end && rows_ready < 2'd2)
                rows_ready <= rows_ready + 1'b1;
        end
    end
end

endmodule