// servo_face_track.v  (simplified, fixed-constant, ASCII-only)
// Face-tracking pan/tilt servo controller with two-clock-domain CDC handshake.
// All timing values are fixed constants to avoid any parameter elaboration issues.

module servo_face_track (
    input  wire        image_clk,
    input  wire        ctrl_clk,
    input  wire        rst_n,

    input  wire [12:0] face_x,
    input  wire [12:0] face_y,
    input  wire        face_update,

    input  wire [12:0] image_width,
    input  wire [12:0] image_height,

    output wire        pwm_pan,
    output wire        pwm_tilt,

    output reg  [31:0] pan_width,
    output reg  [31:0] tilt_width
);

    // ---- fixed constants ----
    // PWM period count for 20ms @ 50MHz = 1_000_000
    localparam [31:0] PERIOD_COUNT = 32'd1000000;

    localparam [31:0] PAN_MIN  = 32'd55000; // 1.1 ms
    localparam [31:0] PAN_MID  = 32'd75000; // 保留初始位置
    localparam [31:0] PAN_MAX  = 32'd95000; // 1.9 ms
    
    localparam [31:0] TILT_MIN = 32'd55000; // 1.1 ms
    localparam [31:0] TILT_MID = 32'd78000; // 保留已调好的初始位置
    localparam [31:0] TILT_MAX = 32'd95000; // 1.9 ms

    // 50 MHz: 150 counts = 3 us pulse-width adjustment
    localparam [31:0] STEP_COUNT = 32'd300;
    
    // Pixel dead zone around image center
    localparam signed [31:0] DEAD_X = 32'sd32;
    localparam signed [31:0] DEAD_Y = 32'sd32;
    
    // First test pan only
    localparam PAN_ENABLE  = 1'b1;
    localparam TILT_ENABLE = 1'b1;
    
    // Change the corresponding bit if tracking direction is reversed
    localparam PAN_REVERSE  = 1'b0;
    localparam TILT_REVERSE = 1'b1;

    // ---- reset synchronizers ----
    (* ASYNC_REG = "TRUE" *) reg [1:0] image_reset;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ctrl_reset;

    always @(posedge image_clk or negedge rst_n) begin
        if (!rst_n)
            image_reset <= 2'b00;
        else
            image_reset <= {image_reset[0], 1'b1};
    end

    always @(posedge ctrl_clk or negedge rst_n) begin
        if (!rst_n)
            ctrl_reset <= 2'b00;
        else
            ctrl_reset <= {ctrl_reset[0], 1'b1};
    end

    wire image_rst_n = image_reset[1];
    wire ctrl_rst_n  = ctrl_reset[1];

    // ---- CDC handshake: image domain -> ctrl domain ----
    reg [51:0] source_data;
    reg        request_toggle;
    reg        acknowledge_toggle;

    (* ASYNC_REG = "TRUE" *) reg ack_meta;
    (* ASYNC_REG = "TRUE" *) reg ack_sync;

    always @(posedge image_clk or negedge image_rst_n) begin
        if (!image_rst_n) begin
            ack_meta <= 1'b0;
            ack_sync <= 1'b0;
        end
        else begin
            ack_meta <= acknowledge_toggle;
            ack_sync <= ack_meta;
        end
    end

    wire source_ready = (request_toggle == ack_sync);

    always @(posedge image_clk or negedge image_rst_n) begin
        if (!image_rst_n) begin
            source_data    <= 52'd0;
            request_toggle <= 1'b0;
        end
        else if (face_update && source_ready) begin
            source_data    <= {image_width, image_height, face_x, face_y};
            request_toggle <= ~request_toggle;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg request_meta;
    (* ASYNC_REG = "TRUE" *) reg request_sync;

    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) begin
            request_meta <= 1'b0;
            request_sync <= 1'b0;
        end
        else begin
            request_meta <= request_toggle;
            request_sync <= request_meta;
        end
    end

    // ---- coordinate capture in ctrl domain ----
    reg [12:0] received_x;
    reg [12:0] received_y;
    reg [12:0] received_width;
    reg [12:0] received_height;

    reg        coordinate_pending;
    reg [31:0] pwm_counter;

    wire period_end = (pwm_counter == (PERIOD_COUNT - 32'd1));
    
        // 100 ms @ 50 MHz
    localparam [31:0] COORD_TIMEOUT = 32'd5000000;
    
    reg [31:0] coordinate_age;
    
    wire new_coordinate =
        (request_sync != acknowledge_toggle);
    
    wire coordinate_fresh =
        (coordinate_age < COORD_TIMEOUT);
    
    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n)
            coordinate_age <= COORD_TIMEOUT;
        else if (new_coordinate)
            coordinate_age <= 32'd0;
        else if (coordinate_age < COORD_TIMEOUT)
            coordinate_age <= coordinate_age + 1'b1;
    end

    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) begin
            received_x         <= 13'd0;
            received_y         <= 13'd0;
            received_width     <= 13'd0;
            received_height    <= 13'd0;
            acknowledge_toggle <= 1'b0;
            coordinate_pending <= 1'b0;
        end
        else begin
            if (period_end)
                coordinate_pending <= 1'b0;

            if (request_sync != acknowledge_toggle) begin
                received_width     <= source_data[51:39];
                received_height    <= source_data[38:26];
                received_x         <= source_data[25:13];
                received_y         <= source_data[12:0];
                acknowledge_toggle <= request_sync;
                coordinate_pending <= 1'b1;
            end
        end
    end

    // ---- error computation (signed) ----
    wire [13:0] center_x = {1'b0, received_width[12:1]};
    wire [13:0] center_y = {1'b0, received_height[12:1]};

    wire signed [14:0] error_x = $signed({1'b0, received_x}) - $signed({1'b0, center_x});
    wire signed [14:0] error_y = $signed({1'b0, received_y}) - $signed({1'b0, center_y});
    wire signed [14:0] control_error_x =
        PAN_REVERSE ? -error_x : error_x;

    wire signed [14:0] control_error_y =
        TILT_REVERSE ? -error_y : error_y;

    wire coordinate_in_range =
        (received_width  != 13'd0) &&
        (received_height != 13'd0) &&
        (received_x < received_width) &&
        (received_y < received_height);

    // Incremental PID, Q8 coefficients.
    // KI_T includes the fixed 20 ms sample period.
    // KD_OVER_T includes division by the sample period.
    //
    // Start with PI only. These are initial tuning values,
    // not validated gains for the actual mechanism.
    localparam signed [31:0] KP_Q8        = 32'sd256;
    localparam signed [31:0] KI_T_Q8      = 32'sd512;
    localparam signed [31:0] KD_OVER_T_Q8 = 32'sd0;
    
    // Maximum pulse-width change per 20 ms: 300 counts = 6 us
    localparam signed [31:0] MAX_CHANGE = 32'sd600;
    
    reg signed [31:0] pan_e1, pan_e2;
    reg signed [31:0] tilt_e1, tilt_e2;
    
    wire signed [31:0] pan_error =
        {{17{control_error_x[14]}}, control_error_x};
    
    wire signed [31:0] tilt_error =
        {{17{control_error_y[14]}}, control_error_y};
    
    function signed [31:0] pid_delta;
        input signed [31:0] e;
        input signed [31:0] e1;
        input signed [31:0] e2;
    
        reg signed [63:0] p_term;
        reg signed [63:0] i_term;
        reg signed [63:0] d_term;
        reg signed [63:0] result;
        begin
            p_term = KP_Q8 * (e - e1);
            i_term = KI_T_Q8 * e;
            d_term = KD_OVER_T_Q8 * (e - (e1 <<< 1) + e2);
    
            result = (p_term + i_term + d_term) >>> 8;
    
            if (result > MAX_CHANGE)
                pid_delta = MAX_CHANGE;
            else if (result < -MAX_CHANGE)
                pid_delta = -MAX_CHANGE;
            else
                pid_delta = result;
        end
    endfunction
    
    // Signed addition prevents unsigned subtraction underflow.
    // Clamp each new command to the existing mechanical limits.
    function [31:0] bounded_width;
        input [31:0] current_width;
        input signed [31:0] change;
        input [31:0] minimum_width;
        input [31:0] maximum_width;
    
        reg signed [63:0] next_width;
        begin
            next_width =
                $signed({1'b0, current_width}) + change;
    
            if (next_width < $signed({1'b0, minimum_width}))
                bounded_width = minimum_width;
            else if (next_width > $signed({1'b0, maximum_width}))
                bounded_width = maximum_width;
            else
                bounded_width = next_width[31:0];
        end
    endfunction

    // ---- PWM / position control ----
    // ---- PWM / incremental PID control ----
    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) begin
            pwm_counter <= 32'd0;
    
            pan_width  <= PAN_MID;
            tilt_width <= TILT_MID;
    
            pan_e1  <= 32'sd0;
            pan_e2  <= 32'sd0;
            tilt_e1 <= 32'sd0;
            tilt_e2 <= 32'sd0;
        end
        else if (period_end) begin
            pwm_counter <= 32'd0;
    
            if (coordinate_fresh && coordinate_in_range) begin
    
                // Horizontal axis
                if (PAN_ENABLE &&
                    ((pan_error > DEAD_X) ||
                     (pan_error < -DEAD_X))) begin
    
                    pan_width <= bounded_width(
                        pan_width,
                        pid_delta(pan_error, pan_e1, pan_e2),
                        PAN_MIN,
                        PAN_MAX
                    );
    
                    pan_e2 <= pan_e1;
                    pan_e1 <= pan_error;
                end
                else begin
                    // Hold position inside dead zone.
                    pan_e1 <= 32'sd0;
                    pan_e2 <= 32'sd0;
                end
    
                // Vertical axis
                if (TILT_ENABLE &&
                    ((tilt_error > DEAD_Y) ||
                     (tilt_error < -DEAD_Y))) begin
    
                    tilt_width <= bounded_width(
                        tilt_width,
                        pid_delta(tilt_error, tilt_e1, tilt_e2),
                        TILT_MIN,
                        TILT_MAX
                    );
    
                    tilt_e2 <= tilt_e1;
                    tilt_e1 <= tilt_error;
                end
                else begin
                    tilt_e1 <= 32'sd0;
                    tilt_e2 <= 32'sd0;
                end
            end
            else begin
                // Stale/invalid coordinates: hold position.
                // Reset history before the next acquisition.
                pan_e1  <= 32'sd0;
                pan_e2  <= 32'sd0;
                tilt_e1 <= 32'sd0;
                tilt_e2 <= 32'sd0;
            end
        end
        else begin
            pwm_counter <= pwm_counter + 1'b1;
        end
    end
        assign pwm_pan  = ctrl_rst_n && (pwm_counter < pan_width);
        assign pwm_tilt = ctrl_rst_n && (pwm_counter < tilt_width);
    
endmodule
