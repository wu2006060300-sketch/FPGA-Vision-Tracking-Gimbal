//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�http://www.openedv.com/forum.php
//�Ա����̣�https://zhengdianyuanzi.tmall.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���?
//Copyright(C) ����ԭ�� 2023-2033
//All rights reserved         
//----------------------------------------------------------------------------------------
// File name:           ov5640_lcd
// Created by:          ����ԭ��
// Created date:        2025��11��010��14:20:02
// Version:             V1.0
// Descriptions:        OV5640����ͷLCD��ʾ
//                      
//----------------------------------------------------------------------------------------
//****************************************************************************************//
module ov5640_lcd(    
    input                 sys_clk      ,  //ϵͳʱ��
    input                 sys_rst_n    ,  //ϵͳ��λ���͵�ƽ��Ч
    //����ͷ�ӿ�                       
    input                 cam_pclk     ,  //CMOS ��������ʱ��
    input                 cam_vsync    ,  //CMOS ��ͬ���ź�
    input                 cam_href     ,  //CMOS ��ͬ���ź�
    input   [7:0]         cam_data     ,  //CMOS ����
    output                cam_rst_n    ,  //CMOS ��λ�źţ��͵�ƽ��Ч
    output                cam_pwdn     ,  //��Դ����ģʽѡ�� 0������ģʽ 1����Դ����ģʽ
    output                cam_scl      ,  //CMOS SCCB_SCL��
    inout                 cam_sda      ,  //CMOS SCCB_SDA��       
    // DDR3                            
    inout   [31:0]        ddr3_dq      ,  //DDR3 ����
    inout   [3:0]         ddr3_dqs_n   ,  //DDR3 dqs��
    inout   [3:0]         ddr3_dqs_p   ,  //DDR3 dqs��  
    output  [13:0]        ddr3_addr    ,  //DDR3 ��ַ   
    output  [2:0]         ddr3_ba      ,  //DDR3 bank ѡ��
    output                ddr3_ras_n   ,  //DDR3 ��ѡ��
    output                ddr3_cas_n   ,  //DDR3 ��ѡ��
    output                ddr3_we_n    ,  //DDR3 ��дѡ��
    output                ddr3_reset_n ,  //DDR3 ��λ
    output  [0:0]         ddr3_ck_p    ,  //DDR3 ʱ����
    output  [0:0]         ddr3_ck_n    ,  //DDR3 ʱ�Ӹ�
    output  [0:0]         ddr3_cke     ,  //DDR3 ʱ��ʹ��
    output  [0:0]         ddr3_cs_n    ,  //DDR3 Ƭѡ
    output  [3:0]         ddr3_dm      ,  
    output  [0:0]         ddr3_odt     ,                                         
    //lcd�ӿ�                           
    output                lcd_hs       ,  //LCD ��ͬ���ź�
    output                lcd_vs       ,  //LCD ��ͬ���ź�
    output                lcd_de       ,  //LCD ��������ʹ��
    inout       [23:0]    lcd_rgb      ,  //LCD ��ɫ����
    output                lcd_bl       ,  //LCD ��������ź�?
    output                lcd_rst      ,  //LCD ��λ�ź�
    output                lcd_pclk     ,  //LCD ����ʱ��
    // ========== ������1�������������������̨��? ==========
    output [9:0]          face_x       ,  //��������X����
    output [8:0]          face_y       ,  //��������Y����
    output                face_valid   ,  //������Ч����
    // ========== ���̨��? PWM ���? ==========
    output wire           pwm_pan      ,  //ˮƽ��̨�����PWM
    output wire           pwm_tilt        //��ֱ��̨�����PWM
    );                                 
                                                                   
//wire define                          
wire         clk_50m                   ;  //50MHzʱ��,�ṩ��lcd����ʱ��
wire         locked                    ;  //ʱ�������ź�
wire         rst_n                     ;  //ȫ�ָ�λ                                                                            
wire  [15:0] wrdata                    ;  //DDR3������ģ��д����
wire         rdata_req                 ;  //DDR3������ģ�������?
wire  [15:0] rddata                    ;  //DDR3������ģ�������?
wire         cmos_frame_valid          ;  //������Чʹ���ź�
wire         init_calib_complete       ;  //DDR3��ʼ������ź�?
wire         sys_init_done             ;  //ϵͳ��ʼ�����?
wire         clk_200m                  ;  //DDR3�ο�ʱ��
wire         cmos_frame_vsync          ;  //���֡��Ч��ͬ���ź�?
wire         lcd_clk                   ;  //��Ƶ������LCD ����ʱ��
wire  [12:0] h_disp                    ;  //LCD��ˮƽ�ֱ���
wire  [12:0] v_disp                    ;  //LCD����ֱ�ֱ���           
wire  [12:0] y_addr_st                 ; 
wire  [12:0] y_addr_end                ;
wire  [15:0] lcd_id                    ;  //LCD����ID��
wire  [27:0] ddr3_addr_max             ;  //����DDR3������д��ַ               
wire  [12:0] total_h_pixel             ;  //ˮƽ�����ش�С 
wire  [12:0] total_v_pixel             ;  //��ֱ�����ش�С
wire         rd_vsync                  ;  //LCD����Ķ���ͬ��?
// ========== ��������ֵ����ͼ���ź� ==========
wire [15:0] binary_rddata;
wire        binary_rd_vsync;

//*****************************************************
//**                    main code
//*****************************************************
//��ʱ�������������λ�����ź�?
assign  rst_n = sys_rst_n & locked;
//ϵͳ��ʼ����ɣ�DDR3��ʼ�����?
assign  sys_init_done = init_calib_complete;
//����ͷͼ��ֱ�������ģ��?
picture_size u_picture_size (
    .rst_n                 (rst_n              ),
    .clk                   (clk_50m            ),    
    .lcd_id                (lcd_id             ),  //LCD������ID
                        
    .cmos_h_pixel          (h_disp             ),  //����ͷˮƽ�ֱ���
    .cmos_v_pixel          (v_disp             ),  //����ͷ��ֱ�ֱ���  
    .total_h_pixel         (total_h_pixel      ),  //ˮƽ�����ش�С
    .total_v_pixel         (total_v_pixel      ),  //��ֱ�����ش�С
    .y_addr_st             (y_addr_st          ), 
    .y_addr_end            (y_addr_end         ),
    .ddr3_addr_max         (ddr3_addr_max      )   //DDR3����д��ַ
    );
//ov5640 ����
ov5640_dri u_ov5640_dri(
    .clk                   (clk_50m            ),
    .rst_n                 (rst_n              ),
    .cam_pclk              (cam_pclk           ),
    .cam_vsync             (cam_vsync          ),
    .cam_href              (cam_href           ),
    .cam_data              (cam_data           ),
    .cam_rst_n             (cam_rst_n          ),
    .cam_pwdn              (cam_pwdn           ),
    .cam_scl               (cam_scl            ),
    .cam_sda               (cam_sda            ),
    
    .capture_start         (init_calib_complete),
    .cmos_h_pixel          (h_disp             ),
    .cmos_v_pixel          (v_disp             ),
    .total_h_pixel         (total_h_pixel      ),
    .total_v_pixel         (total_v_pixel      ),
    .y_addr_st             (y_addr_st          ), 
    .y_addr_end            (y_addr_end         ),
    .cmos_frame_vsync      (cmos_frame_vsync   ),
    .cmos_frame_href       (                   ),
    .cmos_frame_valid      (cmos_frame_valid   ),
    .cmos_frame_data       (wrdata             )
    );   
ddr3_top u_ddr3_top(
    .rst_n                 (rst_n              ),  //��λ,����Ч
    .init_calib_complete   (init_calib_complete),  //DDR3��ʼ������ź�?    
    //ddr3�ӿ��ź�         
    .app_addr_rd_min       (28'd0              ),  //��DDR3����ʼ��ַ
    .app_addr_rd_max       (ddr3_addr_max[27:1]),  //��DDR3�Ľ�����ַ
    .rd_bust_len           (h_disp[10:4]       ),  //��DDR3�ж�����ʱ��ͻ������
    .app_addr_wr_min       (28'd0              ),  //дDDR3����ʼ��ַ
    .app_addr_wr_max       (ddr3_addr_max[27:1]),  //дDDR3�Ľ�����ַ
    .wr_bust_len           (h_disp[10:4]       ),  //��DDR3��д����ʱ��ͻ������
    // DDR3 IO�ӿ�                
    .ddr3_dq               (ddr3_dq            ),  //DDR3 ����
    .ddr3_dqs_n            (ddr3_dqs_n         ),  //DDR3 dqs��
    .ddr3_dqs_p            (ddr3_dqs_p         ),  //DDR3 dqs��  
    .ddr3_addr             (ddr3_addr          ),  //DDR3 ��ַ   
    .ddr3_ba               (ddr3_ba            ),  //DDR3 bank ѡ��
    .ddr3_ras_n            (ddr3_ras_n         ),  //DDR3 ��ѡ��
    .ddr3_cas_n            (ddr3_cas_n         ),  //DDR3 ��ѡ��
    .ddr3_we_n             (ddr3_we_n          ),  //DDR3 ��дѡ��
    .ddr3_reset_n          (ddr3_reset_n       ),  //DDR3 ��λ
    .ddr3_ck_p             (ddr3_ck_p          ),  //DDR3 ʱ����
    .ddr3_ck_n             (ddr3_ck_n          ),  //DDR3 ʱ�Ӹ�  
    .ddr3_cke              (ddr3_cke           ),  //DDR3 ʱ��ʹ��
    .ddr3_cs_n             (ddr3_cs_n          ),  //DDR3 Ƭѡ
    .ddr3_dm               (ddr3_dm            ),  //DDR3_dm
    .ddr3_odt              (ddr3_odt           ),  //DDR3_odt
    // System Clock Ports                            
    .sys_clk_i             (clk_200m           ),   
    // Reference Clock Ports                         
    .clk_ref_i             (clk_200m           ),    
    //�û�
    .ddr3_read_valid       (1'b1               ),  //DDR3 ��ʹ��
    .ddr3_pingpang_en      (1'b1               ),  //DDR3 ƹ�Ҳ���ʹ��
    .wr_clk                (cam_pclk           ),  //дʱ��
    .wr_load               (cmos_frame_vsync   ),  //����Դ�����ź�   
    .wr_en                 (cmos_frame_valid   ),  //������Чʹ���ź�
    .wrdata                (wrdata             ),  //д��Ч���� 
    .rd_clk                (lcd_clk            ),  //��ʱ�� 
    .rd_load               (rd_vsync           ),  //���Դ�����ź�?    
    .rddata                (rddata             ),  //rfifo�������?
    .rdata_req             (rdata_req          )   //������������     
     );                
 clk_wiz_0 u_clk_wiz_0
   (
    // Clock out ports
    .clk_out1              (clk_200m           ),     
    .clk_out2              (clk_50m            ),
    // Status and control signals
    .reset                 (~sys_rst_n         ), 
    .locked                (locked             ),       
   // Clock in ports
    .clk_in1               (sys_clk            )
    );     

// ========== ��ɫ��ֵ�� + ������⴦��ģ��? ==========
image_process u_image_process(
    .clk        (lcd_clk     ),  // ����ʱ�ӣ���LCD��ʱ��һ��
    .rst_n      (rst_n       ),  // ϵͳ��λ���͵�ƽ��Ч
    
    .rgb565_in  (rddata      ),  // ���룺DDR3������ԭʼͼ��
    .vsync_in   (rd_vsync    ),  // ���룺��ͬ��
    .href_in    (rdata_req   ),  // ���룺������Ч/�����ź�
    
    .rgb565_out (binary_rddata ), // �������ֵ��?+������ͼ��
    .vsync_out  (binary_rd_vsync),
    // ========== ������2�������ź����ߡ� ==========
    .face_x     (face_x     ),
    .face_y     (face_y     ),
    .face_valid (face_valid )
);

//LCD������ʾģ��
lcd_rgb_top  u_lcd_rgb_top(
    .sys_clk               (clk_50m            ),
    .sys_rst_n             (rst_n              ),
    .sys_init_done         (sys_init_done      ),     
                           
    //lcd�ӿ�                            
    .lcd_id                (lcd_id             ),  //LCD����ID�� 
    .lcd_hs                (lcd_hs             ),  //LCD ��ͬ���ź�
    .lcd_vs                (lcd_vs             ),  //LCD ��ͬ���ź�
    .lcd_de                (lcd_de             ),  //LCD ��������ʹ��
    .lcd_rgb               (lcd_rgb            ),  //LCD ��ɫ����
    .lcd_bl                (lcd_bl             ),  //LCD ��������ź�?
    .lcd_rst               (lcd_rst            ),  //LCD ��λ�ź�
    .lcd_pclk              (lcd_pclk           ),  //LCD ����ʱ��
    .lcd_clk               (lcd_clk            ),  //LCD ����ʱ��
    //�û��ӿ�                     
    .out_vsync             (rd_vsync           ),  // ��ͬ���Ӵ�������ź�?
    .h_disp                (                   ),  //�зֱ���  
    .v_disp                (                   ),  //���ֱ���  
    .pixel_xpos            (                   ),
    .pixel_ypos            (                   ),       
    .data_in               (binary_rddata      ),  // ͼ�����ݽӴ�����Ķ�ֵ�?
    .data_req              (rdata_req          )   // rdata_reqֱ��ֱͨ���������㷨
    );   

// ========== ���̨��������ģ��? ==========
servo_face_track u_servo_face_track (
    .image_clk    (lcd_clk    ),
    .ctrl_clk     (clk_50m    ),
    .rst_n        (rst_n      ),

    .face_x       ({3'b000, face_x}  ),
    .face_y       ({4'b0000, face_y} ),
    .face_update  (face_valid        ),

    .image_width  (h_disp     ),
    .image_height (v_disp     ),

    .pwm_pan      (pwm_pan    ),
    .pwm_tilt     (pwm_tilt   ),

    .pan_width    (),
    .tilt_width   ()
);
    
endmodule
