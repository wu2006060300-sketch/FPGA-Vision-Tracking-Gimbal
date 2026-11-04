`timescale 1ns/1ps
// Fixed 800x480 prototype. 25x15 tiles, four-connected component search.
// Analysis runs in vertical blank; no original video buffering is changed.
module face_detect #(
    parameter H_DISP=800, V_DISP=480,
    parameter AREA_MIN=1800,
    parameter CELL_MIN=128,
    parameter CONFIRM_FRAMES=3,
    parameter LOST_FRAMES=8
)(
    input clk, rst_n, bin_in, vsync_in, href_in,
    output reg [9:0] target_x,
    output reg [8:0] target_y,
    output reg target_valid,
    output reg target_active
);
localparam INIT=0, WAIT_FRAME=1, CAPTURE=2, SCAN=3,
           POP=4, NEIGHBOR=5, EVALUATE=6, FINISH=7, CLEAR=8;
reg [3:0] state;
reg [10:0] cells[0:374];
reg seen[0:374];
reg [8:0] queue[0:374];
reg [9:0] x;
reg [8:0] y;
reg vs_d;
wire frame_start=vsync_in & ~vs_d;
wire [8:0] tile_index=(y >> 5)*25+(x >> 5);
integer idx, scan_index, head, tail, node, direction;
integer nx, ny, neighbor_index, neighbor_ok;
integer xmin, xmax, ymin, ymax, area;
integer bx, by, bw, bh, box_pixels, distance;
integer best_x, best_y, best_area, best_distance;
integer pending_x, pending_y, confirmations, misses;
integer dx, dy;
reg locked;
// Combinational candidate measurements. Integers keep arithmetic widened.
always @* begin
    bw=(xmax-xmin+1)*32;
    bh=(ymax-ymin+1)*32;
    bx=(xmin+xmax+1)*16;
    by=(ymin+ymax+1)*16;
    box_pixels=bw*bh;
    dx=bx-target_x; if(dx<0) dx=-dx;
    dy=by-target_y; if(dy<0) dy=-dy;
    distance=dx+dy;
    nx=node%25; ny=node/25;
    neighbor_index=0; neighbor_ok=0;
    case(direction)
      0: begin neighbor_index=node-1;  neighbor_ok=(nx>0);  end
      1: begin neighbor_index=node+1;  neighbor_ok=(nx<24); end
      2: begin neighbor_index=node-25; neighbor_ok=(ny>0);  end
      3: begin neighbor_index=node+25; neighbor_ok=(ny<14); end
    endcase
end
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
    state<=INIT; idx<=0; scan_index<=0;
    x<=0; y<=0; vs_d<=0;
    target_x<=0; target_y<=0; target_valid<=0; target_active<=0;
    head<=0; tail<=0; node<=0; direction<=0;
    xmin<=0; xmax<=0; ymin<=0; ymax<=0; area<=0;
    best_x<=0; best_y<=0; best_area<=0; best_distance<=2048;
    pending_x<=0; pending_y<=0; confirmations<=0; misses<=0; locked<=0;
 end else begin
    vs_d<=vsync_in;
    target_valid<=0;
    if(frame_start) begin x<=0; y<=0; end
    else if(href_in) begin
      if(x<800) x<=x+1'b1;
    end else if(x!=0) begin x<=0; if(y<480) y<=y+1'b1; end
    case(state)
      INIT: begin
        cells[idx]<=0; seen[idx]<=0;
        if(idx==374) begin idx<=0; state<=WAIT_FRAME; end
        else idx<=idx+1;
      end
      WAIT_FRAME: if(frame_start) state<=CAPTURE;
      CAPTURE: begin
        if(frame_start) begin
          scan_index<=0; best_area<=0; best_distance<=2048;
          state<=SCAN;
        end else if(href_in && bin_in && x<800 && y<480)
          cells[tile_index]<=cells[tile_index]+1'b1;
      end
      SCAN: begin
        if(scan_index==375) state<=FINISH;
        else if(!seen[scan_index] && cells[scan_index]>=CELL_MIN) begin
          seen[scan_index]<=1;
          queue[0]<=scan_index; head<=0; tail<=1;
          xmin<=24; xmax<=0; ymin<=14; ymax<=0; area<=0;
          state<=POP;
        end else scan_index<=scan_index+1;
      end
      POP: begin
        if(head==tail) state<=EVALUATE;
        else begin
          node<=queue[head]; head<=head+1;
          if(queue[head]%25<xmin) xmin<=queue[head]%25;
          if(queue[head]%25>xmax) xmax<=queue[head]%25;
          if(queue[head]/25<ymin) ymin<=queue[head]/25;
          if(queue[head]/25>ymax) ymax<=queue[head]/25;
          area<=area+cells[queue[head]];
          direction<=0; state<=NEIGHBOR;
        end
      end
      NEIGHBOR: begin
        // Separate range guard prevents out-of-range array reads.
        if(neighbor_ok) begin
          if(!seen[neighbor_index] && cells[neighbor_index]>=CELL_MIN) begin
            seen[neighbor_index]<=1;
            queue[tail]<=neighbor_index; tail<=tail+1;
          end
        end
        if(direction==3) state<=POP; else direction<=direction+1;
      end
      EVALUATE: begin
        // Broad portrait-shape limits, minimum density 25 percent.
        // These are heuristics, not a trained face classifier.
        if(area>=AREA_MIN && bw>=32 && bh>=64 &&
           bw*5>=bh*2 && bw*2<=bh*3 && area*4>=box_pixels) begin
          if((!locked && area>best_area) ||
             (locked && dx<=128 && dy<=96 &&
              (distance<best_distance ||
               (distance==best_distance && area>best_area)))) begin
            best_x<=bx; best_y<=by; best_area<=area;
            best_distance<=distance;
          end
        end
        scan_index<=scan_index+1; state<=SCAN;
      end
      FINISH: begin
        if(best_area!=0) begin
          if(locked) begin
            // Integer low-pass; freeze movements of four pixels or less.
            if(best_x>target_x+4 || best_x+4<target_x)
              target_x<=(3*target_x+best_x+2)/4;
            if(best_y>target_y+4 || best_y+4<target_y)
              target_y<=(3*target_y+best_y+2)/4;
            misses<=0; target_valid<=1;
          end else begin
            if(confirmations!=0 &&
               best_x<=pending_x+64 && pending_x<=best_x+64 &&
               best_y<=pending_y+64 && pending_y<=best_y+64) begin
              if(confirmations>=CONFIRM_FRAMES-1) begin
                locked<=1; target_active<=1; target_valid<=1;
                target_x<=best_x; target_y<=best_y;
                confirmations<=0; misses<=0;
              end else confirmations<=confirmations+1;
            end else confirmations<=1;
            pending_x<=best_x; pending_y<=best_y;
          end
        end else begin
          confirmations<=0;
          if(locked) begin
            if(misses>=LOST_FRAMES-1) begin
              locked<=0; target_active<=0; misses<=0;
            end else misses<=misses+1;
          end
        end
        idx<=0; state<=CLEAR;
      end
      CLEAR: begin
        cells[idx]<=0; seen[idx]<=0;
        if(idx==374) begin idx<=0; state<=CAPTURE; end
        else idx<=idx+1;
      end
      default: state<=INIT;
    endcase
 end
end
endmodule
