// Native-pixel, antialiased XY scan conversion, centered (343.5,135.5), radius 74.5.
// Solve the reference sine for each row, evaluate actual voice DDS at those
// times, connect successive crossings, and add a faint older-phase ghost.
// Two scanline buffers replace a framebuffer. Arithmetic is shared by voices.
module guitar_radial_curve_renderer(input wire clk,rst_n,frame_start,
    input wire [399:0] snapshot,input wire [8:0] pixel_x,pixel_y,
    input wire pixel_active,output reg initialized,output wire [11:0] mask,
    output reg [43:0] display_hz,output reg [15:0] display_fret,display_level,
    output reg [3:0] display_active,display_flash,output reg deadline_miss,
    output wire [31:0] display_strikes,output reg visual_update);
    localparam INIT=0,WAIT=1,SETTLE=2,DIVIDE=3,CLEAR=4,BRANCH=5,
        PRODUCT=6,ANGLE=7,SINE_WAIT=8,POSITION=9,LIMITS=10,PLOT=11,DRAIN=12,NEXT=13,BOUNDS=14;
    localparam [31:0] REF_INCREMENT=32'd19685267;
    localparam [19:0] WINDOW=20'd307582; // 1024/48000 seconds, ref cycles Q16
    reg [3:0] state;
    reg front_bank,ready;
    reg [8:0] clear_addr,row_y,plot_x,plot_end;
    reg [5:0] settle_count;
    reg [399:0] pending,history;
    assign display_strikes=pending[399:368];
    reg [31:0] previous_strikes;
    reg [3:0] flash_count [0:3];
    reg [17:0] ratios [0:3],old_ratios [0:3];
    reg [47:0] dividend,quotient;
    reg [31:0] remainder;
    reg [5:0] division_bit;
    wire [32:0] trial={remainder,dividend[47]};
    wire subtract=trial>={1'b0,REF_INCREMENT};
    wire [47:0] next_quotient={quotient[46:0],subtract};
    reg [1:0] voice;
    reg [3:0] branch;
    reg ghost;
    reg signed [15:0] previous_x [0:47];
    reg [47:0] previous_valid;
    wire [5:0] crossing_index={voice,2'b00}+{voice,3'b000}+branch;
    wire signed [17:0] theta;
    guitar_radial_arcsine u_arcsine(.clk(clk),.y(row_y[7:0]),.theta(theta));
    wire [31:0] ref_phase=ghost ? history[287:256] : pending[287:256];
    wire [15:0] voice_phase=ghost ? history[voice*32+16+:16] : pending[voice*32+16+:16];
    wire [17:0] ratio=ghost ? old_ratios[voice] : ratios[voice];
    wire signed [20:0] base_phase=$signed({1'b0,branch[3:1],16'd0});
    wire signed [20:0] solution=base_phase+(branch[0] ? 21'sd32768-$signed(theta) : $signed(theta));
    wire signed [20:0] delta=solution-$signed({5'd0,ref_phase[31:16]});
    reg [19:0] delta_latched;
    reg [37:0] phase_product;
    reg [15:0] angle;
    wire signed [9:0] sine;
    guitar_lissajous_sine u_sine(.clk(clk),.angle(angle[15:6]),.sine(sine));
    wire signed [17:0] extended_sine={{8{sine[9]}},sine};
    wire signed [17:0] scaled=(extended_sine<<<7)+(extended_sine<<<4)+(extended_sine<<<2)+extended_sine;
    reg signed [15:0] point,left_edge,right_edge;
    reg signed [15:0] first_point,last_point;
    wire line_condition=!pixel_active && pixel_x==469 && (pixel_y==511 || pixel_y<272);
    reg previous_line_condition;
    reg [8:0] last_line_y;
    // pixel_x wraps again at h=512 in vertical blanking; tag the row so
    // that only its first h=0 event starts a render.
    wire line_start=line_condition && !previous_line_condition && pixel_y!=last_line_y;
    wire [11:0] q0,q1;
    wire [11:0] back_q=front_bank ? q0 : q1;
    reg write_valid;
    reg [8:0] write_x;
    reg [1:0] write_voice;
    reg [2:0] write_coverage;
    reg [11:0] combined;
    always @* begin
        combined=back_q;
        if(write_coverage>back_q[write_voice*3+:3]) combined[write_voice*3+:3]=write_coverage;
    end
    wire clearing=rst_n && (state==INIT || state==CLEAR);
    wire [8:0] back_write_addr=clearing ? clear_addr : write_x;
    wire [11:0] back_write_data=clearing ? 12'd0 : combined;
    wire we0=(clearing && (state==INIT || front_bank)) || (write_valid && front_bank);
    wire we1=(clearing && (state==INIT || !front_bank)) || (write_valid && !front_bank);
    guitar_scanline_ram u_bank0(.clk(clk),.read_addr(front_bank ? plot_x : pixel_x),.q(q0),
        .write_addr(back_write_addr),.we(we0),.data(back_write_data));
    guitar_scanline_ram u_bank1(.clk(clk),.read_addr(front_bank ? pixel_x : plot_x),.q(q1),
        .write_addr(back_write_addr),.we(we1),.data(back_write_data));
    assign mask=front_bank ? q1 : q0;
    reg signed [16:0] pixel_left,pixel_right,overlap_left,overlap_right,overlap;
    reg [2:0] coverage;
    always @* begin
        pixel_left=$signed({2'd0,plot_x,6'd0});pixel_right=pixel_left+17'sd64;
        overlap_left=pixel_left>$signed(left_edge) ? pixel_left : $signed(left_edge);
        overlap_right=pixel_right<$signed(right_edge) ? pixel_right : $signed(right_edge);
        overlap=overlap_right-overlap_left;
        coverage=3'd1; // faint outer halo / older phase
        if(!ghost && overlap>0)begin
            if(overlap>=56)coverage=7;
            else if(overlap>=40)coverage=6;
            else if(overlap>=24)coverage=4;
            else if(overlap>=8)coverage=2;
        end
    end
    integer i;
    always @(posedge clk) begin
        if(!rst_n)begin
            visual_update<=0;state<=INIT;front_bank<=0;ready<=0;initialized<=0;deadline_miss<=0;
            clear_addr<=0;row_y<=0;plot_x<=0;plot_end<=0;settle_count<=0;
            pending<=0;history<=0;previous_strikes<=0;previous_valid<=0;
            dividend<=0;quotient<=0;remainder<=0;division_bit<=0;
            voice<=0;branch<=0;ghost<=0;delta_latched<=0;phase_product<=0;angle<=0;
            point<=0;left_edge<=0;right_edge<=0;first_point<=0;last_point<=0;
            previous_line_condition<=0;last_line_y<=510;write_valid<=0;write_x<=0;write_voice<=0;write_coverage<=0;
            display_hz<=0;display_fret<=0;display_level<=0;display_active<=0;display_flash<=0;
            for(i=0;i<4;i=i+1)begin ratios[i]<=0;old_ratios[i]<=0;flash_count[i]<=0;end
            for(i=0;i<48;i=i+1)previous_x[i]<=0;
        end else begin
            visual_update<=0;previous_line_condition<=line_condition;
            if(line_start)last_line_y<=pixel_y;
            write_valid<=state==PLOT;
            if(state==PLOT)begin write_x<=plot_x;write_voice<=voice;write_coverage<=coverage;end
            if(line_start && state!=WAIT)deadline_miss<=1;
            case(state)
                INIT: if(clear_addr==511)begin initialized<=1;clear_addr<=0;state<=WAIT;end
                      else clear_addr<=clear_addr+1'b1;
                WAIT: if(frame_start)begin settle_count<=0;state<=SETTLE;end
                      else if(line_start)begin
                          if(ready)begin front_bank<=~front_bank;ready<=0;end
                          row_y<=pixel_y+1'b1;clear_addr<=0;state<=CLEAR;
                      end
                SETTLE: if(settle_count==31)begin
                    visual_update<=1;history<=pending;pending<=snapshot;previous_valid<=0;
                    display_hz<=snapshot[331:288];display_fret<=snapshot[351:336];
                    display_level<=snapshot[367:352];display_active<=snapshot[335:332];
                    previous_strikes<=snapshot[399:368];
                    for(i=0;i<4;i=i+1)begin
                        old_ratios[i]<=ratios[i];
                        if(snapshot[368+i*8+:8]!=previous_strikes[i*8+:8])begin
                            flash_count[i]<=6;display_flash[i]<=1;
                        end else begin
                            if(flash_count[i]!=0)flash_count[i]<=flash_count[i]-1'b1;
                            display_flash[i]<=flash_count[i]>1;
                        end
                    end
                    voice<=0;dividend<={snapshot[159:128],16'd0};quotient<=0;
                    remainder<=0;division_bit<=0;state<=DIVIDE;
                end else settle_count<=settle_count+1'b1;
                DIVIDE: begin
                    dividend<=dividend<<1;quotient<=next_quotient;
                    remainder<=subtract ? trial-REF_INCREMENT : trial;
                    if(division_bit==47)begin
                        ratios[voice]<=next_quotient[17:0];
                        if(voice==3)state<=WAIT;
                        else begin
                            voice<=voice+1'b1;dividend<={pending[128+(voice+2'd1)*32+:32],16'd0};
                            quotient<=0;remainder<=0;division_bit<=0;
                        end
                    end else division_bit<=division_bit+1'b1;
                end
                CLEAR: if(clear_addr==511)begin
                    voice<=0;branch<=0;ghost<=1;
                    if(row_y<61 || row_y>210)begin ready<=1;previous_valid<=0;state<=WAIT;end
                    else state<=BRANCH;
                end else clear_addr<=clear_addr+1'b1;
                BRANCH: if(!pending[332+voice] || (ghost && !history[332+voice]) || delta<0 || delta>=WINDOW)begin
                    if(!ghost)previous_valid[crossing_index]<=0;
                    state<=NEXT;
                end else begin delta_latched<=delta[19:0];state<=PRODUCT;end
                PRODUCT: begin phase_product<=ratio*delta_latched;state<=ANGLE;end
                ANGLE: begin angle<=voice_phase+phase_product[31:16];state<=SINE_WAIT;end
                SINE_WAIT: state<=POSITION;
                POSITION: begin point<=16'sd21984+($signed(scaled)>>>4);state<=LIMITS;end
                LIMITS: begin
                    if(!ghost && previous_valid[crossing_index])begin
                        first_point<=point<previous_x[crossing_index] ? point : previous_x[crossing_index];
                        last_point<=point>previous_x[crossing_index] ? point : previous_x[crossing_index];
                    end else begin first_point<=point;last_point<=point;end
                    if(!ghost)begin previous_x[crossing_index]<=point;previous_valid[crossing_index]<=1;end
                    state<=BOUNDS;
                end
                BOUNDS: begin
                    left_edge<=first_point-16'sd32;right_edge<=last_point+16'sd32;
                    plot_x<=((first_point-16'sd32)>>>6)-2;
                    plot_end<=((last_point+16'sd32)>>>6)+2;
                    state<=PLOT;
                end
                PLOT: if(plot_x==plot_end)state<=DRAIN;else plot_x<=plot_x+1'b1;
                DRAIN: state<=NEXT;
                NEXT: if(branch==11)begin
                    branch<=0;
                    if(voice==3)begin
                        if(ghost)begin ghost<=0;voice<=0;state<=BRANCH;end
                        else begin ready<=1;state<=WAIT;end
                    end else begin voice<=voice+1'b1;state<=BRANCH;end
                end else begin branch<=branch+1'b1;state<=BRANCH;end
                default: state<=INIT;
            endcase
        end
    end
endmodule
