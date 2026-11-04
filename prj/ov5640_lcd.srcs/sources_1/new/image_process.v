`timescale 1ns / 1ps

module image_process(
    input        clk,
    input        rst_n,
    
    input [15:0] rgb565_in,
    input        vsync_in,
    input        href_in,
    
    output [15:0] rgb565_out,  // 输出：带红框的二值化画面
    output        vsync_out,   // 输出：场同步
    // 人脸坐标输出，给顶层连到云台
    output [9:0]  face_x,
    output [8:0]  face_y,
    output        face_valid
);

// ========== 内部连线（全部加调试标记，防止优化�?�方便ILA观测�? ==========
// �?1级：分量拆分
wire [7:0] R, G, B;
(* mark_debug = "true" *) wire vsync1;
(* mark_debug = "true" *) wire href1;

// �?2级：YCbCr转换
wire [7:0] Y, Cb, Cr;
(* mark_debug = "true" *) wire vsync2;
(* mark_debug = "true" *) wire href2;

// �?3级：带亮度约束的肤色二�?�化
(* mark_debug = "true" *) wire bin_skin;
(* mark_debug = "true" *) wire vsync3;
(* mark_debug = "true" *) wire href3;

// �?4级：3×3窗口生成
wire [2:0] line0, line1, line2;
(* mark_debug = "true" *) wire vsync4;
(* mark_debug = "true" *) wire href4;

// �?5级：形�?�学�?运算（弱腐蚀5票�?�过制）
(* mark_debug = "true" *) wire bin_final;
(* mark_debug = "true" *) wire vsync5;
(* mark_debug = "true" *) wire href5;

// �?6级：人脸�?测定�?
(* mark_debug = "true" *) wire [9:0] tar_x;
(* mark_debug = "true" *) wire [8:0] tar_y;
(* mark_debug = "true" *) wire tar_valid;

// 锁存的边界框坐标（给画框用）
reg [9:0] reg_xmin, reg_xmax;
reg [8:0] reg_ymin, reg_ymax;
reg reg_box_valid;
wire target_active;
// RGB delay matching the existing detection pipeline:
// split(1) + YCbCr(2) + skin(1) + window(1) + morph(1) = 6 clocks
reg [15:0] color_delay [0:5];
integer color_i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (color_i = 0; color_i < 6; color_i = color_i + 1)
            color_delay[color_i] <= 16'h0000;
    end
    else begin
        color_delay[0] <= rgb565_in;

        for (color_i = 1; color_i < 6; color_i = color_i + 1)
            color_delay[color_i] <= color_delay[color_i-1];
    end
end

// ========== �?1级：RGB565分量拆分 ==========
rgb565_split u_split(
    .clk(clk), .rst_n(rst_n),
    .rgb565_in(rgb565_in), .vsync_in(vsync_in), .href_in(href_in),
    .R(R), .G(G), .B(B), .vsync_out(vsync1), .href_out(href1)
);

// ========== �?2级：RGB转YCbCr ==========
rgb2ycbcr u_ycbcr(
    .clk(clk), .rst_n(rst_n),
    .R(R), .G(G), .B(B), .vsync_in(vsync1), .href_in(href1),
    .Y(Y), .Cb(Cb), .Cr(Cr), .vsync_out(vsync2), .href_out(href2)
);

// ========== �?3级：肤色二�?�化（带亮度约束�? ==========
skin_binary u_skin(
    .clk(clk), .rst_n(rst_n),
    .Y(Y), .Cb(Cb), .Cr(Cr), .vsync_in(vsync2), .href_in(href2),
    .bin_out(bin_skin), .vsync_out(vsync3), .href_out(href3)
);

// ========== �?4级：3×3窗口生成 ==========
window_3x3 #(
    .H_DISP(800)
) u_window(
    .clk(clk), .rst_n(rst_n),
    .din(bin_skin), .vsync_in(vsync3), .href_in(href3),
    .line0(line0), .line1(line1), .line2(line2),
    .vsync_out(vsync4), .href_out(href4)
);

// ========== �?5级：形�?�学�?运算（弱腐蚀5票�?�过制） ==========
morph_open u_morph(
    .clk(clk), .rst_n(rst_n),
    .line0(line0), .line1(line1), .line2(line2),
    .vsync_in(vsync4), .href_in(href4),
    .bin_out(bin_final), .vsync_out(vsync5), .href_out(href5)
);

// ========== �?6级：人脸边界�?�? + 中心坐标 ==========
face_detect u_face(
    .clk(clk), .rst_n(rst_n),
    .bin_in(bin_final), .vsync_in(vsync5), .href_in(href5),
    .target_x(tar_x), .target_y(tar_y), .target_valid(tar_valid),
    .target_active(target_active)
);

// ========== 坐标转边界框，锁存给画框 ==========
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        reg_xmin <= 10'd0;
        reg_xmax <= 10'd0;
        reg_ymin <= 9'd0;
        reg_ymax <= 9'd0;
        reg_box_valid <= 1'b0;
    end
    else if(tar_valid) begin
        // 以中心坐标为基准，左右各�?50像素，上下各�?40像素，可微调
        reg_xmin <= tar_x - 10'd50;
        reg_xmax <= tar_x + 10'd50;
        reg_ymin <= tar_y - 9'd40;
        reg_ymax <= tar_y + 9'd40;
        reg_box_valid <= 1'b1;
    end
end

// ========== �?7级：画红色检测框 ==========
draw_box u_draw_box(
    .clk        (clk),
    .rst_n      (rst_n),

    .rgb_in     (color_delay[5]),
    .vsync_in   (vsync5),
    .href_in    (href5),

    .box_xmin   (reg_xmin),
    .box_xmax   (reg_xmax),
    .box_ymin   (reg_ymin),
    .box_ymax   (reg_ymax),
    
    .box_valid (target_active),
    .center_x  (tar_x),
    .center_y  (tar_y),

    .rgb_out    (rgb565_out),
    .vsync_out  (vsync_out),
    .href_out   ()
);

// ========== 坐标输出到模块端�? ==========
assign face_x = tar_x;
assign face_y = tar_y;
assign face_valid = tar_valid;

endmodule
