// Stereo chorus at 48 kHz: 15..23 ms fractional delays, opposite triangle
// modulation at 0.55 Hz. Synchronous dual-port RAM keeps it compact on GW5AT.
module piano_stereo_chorus #(
    parameter integer BASE_DELAY=720,
    parameter integer MOD_DEPTH=384,
    parameter [31:0] LFO_INCREMENT=32'd49213
)(
    input wire clk,rst_n,sample_valid_in,
    input wire signed [23:0] left_in,right_in,
    input wire chorus_enable,
    output reg sample_valid,
    output reg signed [23:0] left_out,right_out,
    output wire [8:0] effect_blend,
    output wire effect_busy
);
    localparam integer DEPTH=2048;
    reg signed [15:0] delay_left[0:DEPTH-1],delay_right[0:DEPTH-1];
    reg [10:0] ptr,write_ptr;
    reg [11:0] fill;
    reg [31:0] lfo_phase;
    reg [8:0] blend;
    reg [2:0] state;
    reg signed [15:0] ram_la,ram_ra;
    reg signed [23:0] dry_l,dry_r;
    reg [7:0] frac_l,frac_r;
    reg ready;
    reg [8:0] frame_blend;
    reg signed [25:0] interp_la,interp_lb,interp_ra,interp_rb;
    reg signed [23:0] wet_l,wet_r;
    reg signed [34:0] dry_product_l,dry_product_r,wet_product_l,wet_product_r;
    wire [15:0] triangle=lfo_phase[31] ? ~lfo_phase[30:15] : lfo_phase[30:15];
    wire [31:0] mod_product=triangle*MOD_DEPTH;
    wire [19:0] offset_l=mod_product[27:8];
    wire [19:0] offset_r=(MOD_DEPTH<<8)-offset_l;
    wire [19:0] delay_l=(BASE_DELAY<<8)+offset_l;
    wire [19:0] delay_r=(BASE_DELAY<<8)+offset_r;
    wire [10:0] addr_la=ptr-delay_l[18:8];
    wire [10:0] addr_ra=ptr-delay_r[18:8];
    // Use one read port per channel on two consecutive clocks; never depend
    // on SP read-before-write. The second neighbor is one sample older.
    wire [10:0] read_l=state==1 ? write_ptr-delay_l[18:8]-1'b1 : addr_la;
    wire [10:0] read_r=state==1 ? write_ptr-delay_r[18:8]-1'b1 : addr_ra;
    wire [8:0] inverse_l=9'd256-{1'b0,frac_l};
    wire [8:0] inverse_r=9'd256-{1'b0,frac_r};
    wire signed [26:0] interp_l=$signed({interp_la[25],interp_la})+$signed({interp_lb[25],interp_lb});
    wire signed [26:0] interp_r=$signed({interp_ra[25],interp_ra})+$signed({interp_rb[25],interp_rb});
    wire [9:0] wet_weight={1'b0,frame_blend}>>2;
    wire [9:0] dry_weight=10'd256-wet_weight;
    wire signed [35:0] out_l_wide=$signed({dry_product_l[34],dry_product_l})+$signed({wet_product_l[34],wet_product_l});
    wire signed [35:0] out_r_wide=$signed({dry_product_r[34],dry_product_r})+$signed({wet_product_r[34],wet_product_r});
    assign effect_blend=blend;
    assign effect_busy=chorus_enable ? blend<256 : blend!=0;
    function signed [23:0] sat;
        input signed [27:0] value;
        begin
            if(value>28'sd8388607)sat=24'sh7fffff;
            else if(value < -28'sd8388608)sat=24'sh800000;
            else sat=value[23:0];
        end
    endfunction
    // Address and PCM are latched at frame start. Delay modulation advances
    // only after both neighbors have been read, so their fractions agree.
    always @(posedge clk)begin
        if(sample_valid_in || state==1)begin
            ram_la<=delay_left[read_l];ram_ra<=delay_right[read_r];
        end
        if(state==1)begin
            delay_left[write_ptr]<=dry_l[23:8];
            delay_right[write_ptr]<=dry_r[23:8];
        end
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            ptr<=0;write_ptr<=0;fill<=0;lfo_phase<=0;blend<=0;state<=0;
            dry_l<=0;dry_r<=0;frac_l<=0;frac_r<=0;ready<=0;frame_blend<=0;
            interp_la<=0;interp_lb<=0;interp_ra<=0;interp_rb<=0;
            wet_l<=0;wet_r<=0;dry_product_l<=0;dry_product_r<=0;
            wet_product_l<=0;wet_product_r<=0;sample_valid<=0;left_out<=0;right_out<=0;
        end else begin
            sample_valid<=0;
            if(sample_valid_in)begin
                dry_l<=left_in;dry_r<=right_in;write_ptr<=ptr;
                frac_l<=delay_l[7:0];frac_r<=delay_r[7:0];
                ready<=fill>=BASE_DELAY+MOD_DEPTH+1;frame_blend<=blend;state<=1;
                if(chorus_enable && blend<256)blend<=blend+1'b1;
                else if(!chorus_enable && blend!=0)blend<=blend-1'b1;
            end
            case(state)
                1:begin
                    // First RAM output arrives from frame-start read.
                    interp_la<=$signed(ram_la)*$signed({1'b0,inverse_l});
                    interp_ra<=$signed(ram_ra)*$signed({1'b0,inverse_r});
                    state<=2;
                end
                2:begin
                    // Second RAM output arrives from the adjacent read.
                    interp_lb<=$signed(ram_la)*$signed({2'b00,frac_l});
                    interp_rb<=$signed(ram_ra)*$signed({2'b00,frac_r});
                    state<=3;
                end
                3:begin
                    // Q8 interpolation on PCM16 produces PCM24 directly.
                    wet_l<=ready ? interp_l[23:0] : 24'sd0;
                    wet_r<=ready ? interp_r[23:0] : 24'sd0;
                    state<=4;
                end
                4:begin
                    dry_product_l<=dry_l*$signed({1'b0,dry_weight});
                    dry_product_r<=dry_r*$signed({1'b0,dry_weight});
                    wet_product_l<=wet_l*$signed({1'b0,wet_weight});
                    wet_product_r<=wet_r*$signed({1'b0,wet_weight});
                    state<=5;
                end
                5:begin
                    left_out<=sat(out_l_wide[35:8]);right_out<=sat(out_r_wide[35:8]);
                    sample_valid<=1;state<=0;
                    ptr<=ptr+1'b1;
                    if(fill<DEPTH)fill<=fill+1'b1;
                    lfo_phase<=lfo_phase+LFO_INCREMENT;
                end
                default:begin end
            endcase
        end
    end
endmodule
