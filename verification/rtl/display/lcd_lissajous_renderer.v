// Full-resolution 4-bit persistence canvas, double buffered. A frame copies
// and fades 130560 pixels, then stamps 4096 parametric samples with a halo.
// No external DDR or CPU is needed. Bank swaps only occur in frame blanking.
module lcd_lissajous_renderer #(
    parameter integer AUTO_MODE_FRAMES = 512
) (
    input wire clk,
    input wire rst_n,
    input wire frame_start,
    input wire [1:0] mode_request,
    input wire pause_request,
    input wire [8:0] pixel_x,
    input wire [8:0] pixel_y,
    input wire pixel_active,
    output reg initialized,
    output wire [3:0] intensity,
    output reg [15:0] display_phase,
    output reg [1:0] display_mode,
    output reg display_paused
);
    localparam CLEAR=0, WAIT_FRAME=1, COPY=2, DRAIN=3,
               SINE_READ=4, SINE_WAIT=5, COORD=6,
               STAMP_ADDR=7, STAMP_WAIT=8, STAMP_WRITE=9, NEXT_POINT=10;
    reg [3:0] state;
    reg front_bank;
    reg ready;
    reg [16:0] copy_count;
    reg copy_valid;
    reg [16:0] copy_addr;
    reg [15:0] animation_phase;
    reg [15:0] pending_phase;
    reg [1:0] pending_mode;
    reg [15:0] mode_frames;
    reg [1:0] auto_mode;
    reg [11:0] point_index;
    reg signed [10:0] point_x, point_y;
    reg [4:0] stamp_index;
    reg [16:0] stamp_addr;
    reg signed [3:0] dx,dy;
    reg [3:0] stamp_level;
    reg [11:0] x_turn,y_turn;
    wire [9:0] angle_x = x_turn[11:2] + pending_phase[9:0] * 10'd3;
    wire [9:0] angle_y = y_turn[11:2] + pending_phase[9:0] * 10'd5;
    wire signed [9:0] sine_x,sine_y;
    wire signed [19:0] scaled_x = sine_x * 10'sd208;
    wire signed [19:0] scaled_y = sine_y * 10'sd112;
    wire signed [11:0] brush_x = point_x + dx;
    wire signed [11:0] brush_y = point_y + dy;
    wire [16:0] video_addr = pixel_active ?
                   ({8'd0,pixel_y} << 9) - ({8'd0,pixel_y} << 5) + pixel_x : 17'd0;
    wire [3:0] video_0,video_1,read_0,read_1;
    wire [3:0] front_read = front_bank ? read_1 : read_0;
    wire [3:0] back_read = front_bank ? read_0 : read_1;
    wire [3:0] core_level = point_index[11:6] == pending_phase[5:0] ? 4'd15 : 4'd12;
    reg [16:0] front_addr,back_addr;
    reg back_we;
    reg [3:0] back_data;
    wire clear_we = rst_n && state == CLEAR;
    wire [16:0] addr_0 = state == CLEAR ? copy_count :
                                  front_bank ? back_addr : front_addr;
    wire [16:0] addr_1 = state == CLEAR ? copy_count :
                                  front_bank ? front_addr : back_addr;
    wire we_0 = clear_we || (rst_n && front_bank && back_we);
    wire we_1 = clear_we || (rst_n && !front_bank && back_we);
    assign intensity = front_bank ? video_1 : video_0;

    lcd_lissajous_ram u_bank0(.clk(clk),.video_addr(video_addr),.video_q(video_0),
        .render_addr(addr_0),.render_we(we_0),
        .render_data(state == CLEAR ? 4'd0 : back_data),.render_q(read_0));
    lcd_lissajous_ram u_bank1(.clk(clk),.video_addr(video_addr),.video_q(video_1),
        .render_addr(addr_1),.render_we(we_1),
        .render_data(state == CLEAR ? 4'd0 : back_data),.render_q(read_1));
    lcd_lissajous_sine u_sine(.clk(clk),.angle_x(angle_x),.angle_y(angle_y),
                             .sine_x(sine_x),.sine_y(sine_y));

    always @* begin
        case (pending_mode)
            0: begin x_turn=(point_index<<1)+point_index; y_turn=point_index<<1; end
            1: begin x_turn=(point_index<<2)+point_index; y_turn=point_index<<2; end
            2: begin x_turn=(point_index<<3)-point_index; y_turn=(point_index<<2)+point_index; end
            default: begin x_turn=(point_index<<3)+point_index; y_turn=point_index<<3; end
        endcase
        dx=0; dy=0; stamp_level=core_level;
        case(stamp_index)
            1: begin dx=-1; stamp_level=core_level-4'd2; end
            2: begin dx= 1; stamp_level=core_level-4'd2; end
            3: begin dy=-1; stamp_level=core_level-4'd2; end
            4: begin dy= 1; stamp_level=core_level-4'd2; end
            5: begin dx=-2; stamp_level=6; end
            6: begin dx= 2; stamp_level=6; end
            7: begin dy=-2; stamp_level=6; end
            8: begin dy= 2; stamp_level=6; end
            9: begin dx=-1; dy=-1; stamp_level=8; end
            10: begin dx=1; dy=-1; stamp_level=8; end
            11: begin dx=-1; dy=1; stamp_level=8; end
            12: begin dx=1; dy=1; stamp_level=8; end
            13: begin dx=-3; stamp_level=2; end
            14: begin dx=3; stamp_level=2; end
            15: begin dy=-3; stamp_level=2; end
            16: begin dy=3; stamp_level=2; end
            default: begin end
        endcase
        front_addr=copy_count;
        back_addr=stamp_addr;
        back_we=0;
        back_data=0;
        if ((state == COPY || state == DRAIN) && copy_valid) begin
            back_addr=copy_addr;
            back_we=1;
            // Fade every other animated frame, about a 0.45 s persistence.
            back_data=(!pending_phase[0] && front_read != 0) ? front_read-1'b1 : front_read;
        end else if(state == STAMP_WRITE) begin
            back_we=1;
            back_data=back_read > stamp_level ? back_read : stamp_level;
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=CLEAR; initialized<=0; front_bank<=0; ready<=0;
            copy_count<=0; copy_valid<=0; copy_addr<=0;
            animation_phase<=0; pending_phase<=0; pending_mode<=0;
            mode_frames<=0; auto_mode<=0;
            point_index<=0; point_x<=240; point_y<=136;
            stamp_index<=0; stamp_addr<=0;
            display_phase<=0; display_mode<=0; display_paused<=0;
        end else begin
            copy_valid<=state == COPY;
            copy_addr<=copy_count;
            case(state)
                CLEAR: if(copy_count == 130559) begin
                    copy_count<=0; initialized<=1; state<=WAIT_FRAME;
                end else copy_count<=copy_count+1'b1;
                WAIT_FRAME: if(frame_start) begin
                    display_paused<=pause_request;
                    if(ready) begin
                        front_bank<=~front_bank;
                        display_phase<=pending_phase;
                        display_mode<=pending_mode;
                        ready<=0;
                    end
                    if(!pause_request) begin
                        pending_phase<=animation_phase;
                        pending_mode<=auto_mode+mode_request;
                        animation_phase<=animation_phase+1'b1;
                        if(mode_frames == AUTO_MODE_FRAMES-1) begin
                            mode_frames<=0; auto_mode<=auto_mode+1'b1;
                        end else mode_frames<=mode_frames+1'b1;
                        copy_count<=0; state<=COPY;
                    end
                end
                COPY: if(copy_count == 130559) state<=DRAIN;
                      else copy_count<=copy_count+1'b1;
                DRAIN: begin point_index<=0; state<=SINE_READ; end
                SINE_READ: state<=SINE_WAIT;
                SINE_WAIT: state<=COORD;
                COORD: begin
                    point_x<=11'sd240+$signed(scaled_x[19:9]);
                    point_y<=11'sd136+$signed(scaled_y[19:9]);
                    stamp_index<=0; state<=STAMP_ADDR;
                end
                STAMP_ADDR: begin
                    // 480*y+x, with signed brush offsets and ample margins.
                    stamp_addr<=(brush_y<<<9)-(brush_y<<<5)+brush_x;
                    state<=STAMP_WAIT;
                end
                STAMP_WAIT: state<=STAMP_WRITE;
                STAMP_WRITE: if(stamp_index == 16) state<=NEXT_POINT;
                    else begin stamp_index<=stamp_index+1'b1; state<=STAMP_ADDR; end
                NEXT_POINT: if(point_index == 4095) begin ready<=1; state<=WAIT_FRAME; end
                    else begin point_index<=point_index+1'b1; state<=SINE_READ; end
                default: state<=CLEAR;
            endcase
        end
    end
endmodule
