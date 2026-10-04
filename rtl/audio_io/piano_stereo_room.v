// One shared damped space for all four notes. Dry stereo is narrow; the room
// adds different taps to L/R. Gain 1/2 on each feedback edge bounds the loop.
// Pointer/fill reset prevents reading uninitialized block RAM after reset.
module piano_stereo_room #(
    parameter integer ENABLE=1,
    parameter integer DELAY_A=1487,
    parameter integer DELAY_B=1993,
    parameter integer DELAY_C=2711
) (
    input wire clk,rst_n,sample_valid_in,
    input wire signed [23:0] left_in,right_in,
    output reg sample_valid,
    output reg signed [23:0] left_out,right_out
);
    generate if(ENABLE==0) begin : bypass
        always @(posedge clk) begin
            if(!rst_n) begin sample_valid<=0; left_out<=0; right_out<=0; end
            else begin
                sample_valid<=sample_valid_in;
                if(sample_valid_in) begin left_out<=left_in; right_out<=right_in; end
            end
        end
    end else begin : room
        reg signed [23:0] mem_a[0:DELAY_A-1],mem_b[0:DELAY_B-1],mem_c[0:DELAY_C-1];
        reg [11:0] ptr_a,ptr_b,ptr_c,fill_a,fill_b,fill_c;
        reg [11:0] write_ptr_a,write_ptr_b,write_ptr_c;
        reg signed [23:0] ram_a,ram_b,ram_c,dry_left,dry_right,source;
        reg have_a,have_b,have_c;
        wire signed [23:0] tap_a=have_a?ram_a:24'sd0;
        wire signed [23:0] tap_b=have_b?ram_b:24'sd0;
        wire signed [23:0] tap_c=have_c?ram_c:24'sd0;
        reg busy;
        wire signed [24:0] mono_sum=$signed({left_in[23],left_in})+$signed({right_in[23],right_in});
        wire signed [24:0] write_a=$signed({source[23],source})+($signed({tap_b[23],tap_b})>>>1);
        wire signed [24:0] write_b=$signed({source[23],source})+($signed({tap_c[23],tap_c})>>>1);
        wire signed [24:0] write_c=$signed({source[23],source})+($signed({tap_a[23],tap_a})>>>1);
        wire signed [25:0] left_wide=$signed({{2{dry_left[23]}},dry_left})-
            ($signed({{2{dry_left[23]}},dry_left})>>>3)+
            ($signed({{2{tap_a[23]}},tap_a})>>>5)+($signed({{2{tap_c[23]}},tap_c})>>>5);
        wire signed [25:0] right_wide=$signed({{2{dry_right[23]}},dry_right})-
            ($signed({{2{dry_right[23]}},dry_right})>>>3)+
            ($signed({{2{tap_b[23]}},tap_b})>>>5)+($signed({{2{tap_c[23]}},tap_c})>>>5);
        function signed [23:0] sat;
            input signed [25:0] x;
            begin
                if(x>26'sd8388607) sat=24'sh7fffff;
                else if(x < -26'sd8388608) sat=24'sh800000;
                else sat=x[23:0];
            end
        endfunction
        // Separate registered write addresses infer simple dual-port RAM.
        // GW5AT does not support the SP read-before-write mode selected when
        // read and write addresses are the very same pointer signal.
        always @(posedge clk) begin
            if(busy) begin
                mem_a[write_ptr_a]<=sat({write_a[24],write_a});
                mem_b[write_ptr_b]<=sat({write_b[24],write_b});
                mem_c[write_ptr_c]<=sat({write_c[24],write_c});
            end
            if(sample_valid_in) begin
                ram_a<=mem_a[ptr_a];ram_b<=mem_b[ptr_b];ram_c<=mem_c[ptr_c];
            end
        end
        always @(posedge clk) begin
            if(!rst_n) begin
                ptr_a<=0;ptr_b<=0;ptr_c<=0;fill_a<=0;fill_b<=0;fill_c<=0;
                write_ptr_a<=0;write_ptr_b<=0;write_ptr_c<=0;
                have_a<=0;have_b<=0;have_c<=0;dry_left<=0;dry_right<=0;source<=0;
                busy<=0;sample_valid<=0;left_out<=0;right_out<=0;
            end else begin
                sample_valid<=0;
                if(sample_valid_in) begin
                    dry_left<=left_in;dry_right<=right_in;source<=mono_sum[24:1];
                    write_ptr_a<=ptr_a;write_ptr_b<=ptr_b;write_ptr_c<=ptr_c;
                    have_a<=fill_a>=DELAY_A;have_b<=fill_b>=DELAY_B;have_c<=fill_c>=DELAY_C;
                    busy<=1;
                end
                if(busy) begin
                    ptr_a<=(ptr_a==DELAY_A-1)?12'd0:ptr_a+1'b1;
                    ptr_b<=(ptr_b==DELAY_B-1)?12'd0:ptr_b+1'b1;
                    ptr_c<=(ptr_c==DELAY_C-1)?12'd0:ptr_c+1'b1;
                    if(fill_a<DELAY_A)fill_a<=fill_a+1'b1;
                    if(fill_b<DELAY_B)fill_b<=fill_b+1'b1;
                    if(fill_c<DELAY_C)fill_c<=fill_c+1'b1;
                    left_out<=sat(left_wide);right_out<=sat(right_wide);
                    sample_valid<=1;busy<=0;
                end
            end
        end
    end endgenerate
endmodule
