`timescale 1ns/1ps
module tb_vibrato_serial;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0;
    reg [3:0] enable=0,check_math=15;
    reg [127:0] base={32'h08000000,32'hffffffff,32'd1,32'd0};
    wire [127:0] phase,wide_phase;
    wire busy,deadline,wide_busy,wide_deadline;
    four_string_vibrato_serial dut(.clk(clk),.rst_n(rst_n),.sample_tick(tick),
        .enable(enable),.base_phase_inc(base),.phase_inc(phase),.busy(busy),.deadline_miss(deadline));
    four_string_vibrato_serial #(.DEPTH_Q15(65535)) wide(.clk(clk),.rst_n(rst_n),
        .sample_tick(tick),.enable(enable),.base_phase_inc(base),.phase_inc(wide_phase),
        .busy(wide_busy),.deadline_miss(wide_deadline));
    reg bad_rst=0,bad_tick=0;
    wire bad_deadline;
    four_string_vibrato_serial overloaded(.clk(clk),.rst_n(bad_rst),.sample_tick(bad_tick),
        .enable(4'hf),.base_phase_inc(128'd1),.phase_inc(),.busy(),.deadline_miss(bad_deadline));
    reg [31:0] oracle_lfo[0:3];
    integer samples_checked=0,phase_checks=0,clocks_busy=0,max_busy=0;
    integer i;
    reg saw_above=0,saw_below=0;
    function [31:0] ideal(input [31:0] b,input [31:0] lfo,input integer depth);
        reg signed [63:0] triangle_model,scale,delta,value;
        begin
            triangle_model=lfo[31] ? 64'sd32767-{48'd0,lfo[30:15]} :
                             -64'sd32768+{48'd0,lfo[30:15]};
            scale=(triangle_model*depth)>>>15;
            delta=($signed({1'b0,b})*scale)>>>15;
            value=$signed({1'b0,b})+delta;
            ideal=value<0 ? 0 : value>64'sd4294967295 ? 32'hffffffff : value[31:0];
        end
    endfunction
    always @(posedge clk)begin
        if(!rst_n)begin
            for(i=0;i<4;i=i+1)oracle_lfo[i]=32'h40000000;
            clocks_busy=0;
        end else begin
            if(busy)begin clocks_busy=clocks_busy+1;if(clocks_busy>max_busy)max_busy=clocks_busy;end
            else clocks_busy=0;
            if(clocks_busy>78)$fatal(1,"FAIL: serial work exceeded 78 clocks");
            if(deadline || wide_deadline)$fatal(1,"FAIL: production budget deadline");
            if(tick)begin
                for(i=0;i<4;i=i+1)begin
                    if(phase[i*32+:32] !== (enable[i] && check_math[i] ?
                        ideal(base[i*32+:32],oracle_lfo[i],380) : base[i*32+:32]))
                        $fatal(1,"FAIL: Q15 phase sample=%d string=%d got=%h ideal=%h lfo=%h",samples_checked,i,phase[i*32+:32],ideal(base[i*32+:32],oracle_lfo[i],380),oracle_lfo[i]);
                    if(wide_phase[i*32+:32] !== (enable[i] && check_math[i] ?
                        ideal(base[i*32+:32],oracle_lfo[i],65535) : base[i*32+:32]))
                        $fatal(1,"FAIL: wide coefficient / saturation");
                    phase_checks=phase_checks+2;
                end
                if(phase[127:96]>base[127:96])saw_above=1;
                if(phase[127:96]<base[127:96])saw_below=1;
                samples_checked=samples_checked+1;
            end
            for(i=0;i<4;i=i+1)
                if(!enable[i])oracle_lfo[i]=32'h40000000;
                else if(tick)oracle_lfo[i]=oracle_lfo[i]+32'd536871;
        end
    end
    task period;
        @(negedge clk);tick=1;
        @(negedge clk);tick=0;
        repeat(254)@(negedge clk);
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        repeat(2)period();enable=15;
        repeat(20000)period();
        if(!saw_above || !saw_below)$fatal(1,"FAIL: six-Hz modulation did not cross base");
        // A changing input invalidates that job, even if it returns to its old value.
        @(negedge clk);tick=1;@(negedge clk);tick=0;
        repeat(20)@(negedge clk);base[31:0]=32'h07000001;check_math[0]=0;
        repeat(10)@(negedge clk);base[31:0]=0;
        repeat(224)@(negedge clk);
        period();check_math[0]=1;period();
        // Drop/re-enable during an in-flight multiply cannot publish an old LFO result.
        @(negedge clk);tick=1;@(negedge clk);tick=0;
        repeat(20)@(negedge clk);enable[2]=0;check_math[2]=0;
        repeat(10)@(negedge clk);enable[2]=1;
        repeat(224)@(negedge clk);
        period();check_math[2]=1;repeat(8)period();
        enable=0;repeat(2)period();
        base={32'h7fffffff,32'hffffffff,32'h01c20d2f,32'h00000001};enable=15;
        repeat(1000)period();
        @(negedge clk);tick=1;@(negedge clk);tick=0;
        repeat(12)@(negedge clk);rst_n=0;
        repeat(3)@(negedge clk);rst_n=1;repeat(4)period();
        bad_rst=1;@(negedge clk);bad_tick=1;@(negedge clk);bad_tick=0;
        repeat(20)@(negedge clk);bad_tick=1;@(negedge clk);bad_tick=0;
        repeat(3)@(negedge clk);
        if(!bad_deadline)$fatal(1,"FAIL: missing overloaded deadline detection");
        $display("PASS: serial vibrato %0d samples/%0d phase checks, exact signed Q15/saturation, dynamic inputs/reset, max busy %0d clocks, production and deliberately missed deadlines",samples_checked,phase_checks,max_busy);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: serial vibrato timeout");end
endmodule
