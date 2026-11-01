`timescale 1ns/1ps
module tb_ks_slide_equivalence;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0,active=0;
    reg [31:0] target=0,rng=32'h12345678;
    wire [31:0] value[0:3],old_value[0:3];wire [3:0] busy,old_busy;
    integer n,checks=0;
    genvar g;
    generate for(g=0;g<4;g=g+1)begin:cases
        localparam W=g==0 ? 26 : g==1 ? 27 : 32;
        localparam S=g==3 ? 1 : 960;
        phase_slide_smoother #(.PHASE_VALUE_BITS(W),.SLIDE_SAMPLES(S),.RESOURCE_SHARED(1)) dut(
            .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.voice_active(active),.target_phase_inc(target),.phase_inc(value[g]),.busy(busy[g]));
        ks_before_phase_slide_smoother #(.PHASE_VALUE_BITS(W),.SLIDE_SAMPLES(S)) reference(
            .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.voice_active(active),.target_phase_inc(target),.phase_inc(old_value[g]),.busy(old_busy[g]));
        always @(negedge clk)if(rst_n)begin
            if(value[g]!==old_value[g] || busy[g]!==old_busy[g])$fatal(1,"slide mismatch case%0d n%0d",g,n);
        end
    end endgenerate
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(n=0;n<60000;n=n+1)begin
            @(negedge clk);ce=0;
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            if(n<12000)begin
                active=1;on=n==0;target=n<2000 ? 32'd1 : n<4000 ? 32'hffffffff : n<6000 ? 32'd0 : n<8000 ? 32'h07ffffff : n<10000 ? 32'h80000000 : 32'd30000000;
            end else begin
                active=rng[0] || rng[1];on=rng[2:0]==0;
                if(rng[4] || n%1200==0)target=rng;
            end
            repeat(3)@(negedge clk);ce=1;
            @(negedge clk);ce=0;checks=checks+4;
        end
        $display("PASS: %0d frozen smoother steps,26/27/32 bits,960/1 samples,full slides/extremes/retarget/restrike/inactive",checks);$finish;
    end
endmodule
