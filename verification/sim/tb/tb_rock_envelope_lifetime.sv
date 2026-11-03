`timescale 1ns/1ps
module tb_rock_envelope_lifetime;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=0,on=0;
    wire valid,active,miss;
    wire signed [23:0] pcm;
    piano_voice_core #(.MODES(32),.CONTROL_ENABLE(1),.ROCK_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst_n),.sample_ce(ce),.note_on(on),.note_off(1'b0),
        .phase_inc(32'd23409859),.velocity_level(2'd3),.timbre_blend(9'd0),.rock_blend(9'd256),
        .sustain_enable(1'b0),.harmony_enable(1'b0),.sample_valid(valid),.pcm_out(pcm),
        .active(active),.busy(),.deadline_miss(miss),.profile());
    integer n,high_checks=0,mid_checks=0;
    // Observe completed amplitude calculation, beyond each independently
    // derived time boundary. No audio state is forced or counter accelerated.
    always @(posedge clk)if(rst_n&&dut.state==5)begin
        if(dut.rock_age>=31744)begin
            if(dut.rock_frame!==31)$fatal(1,"FAIL: wah time index wrapped");
            if(dut.rock_amplitude_product!==0)$fatal(1,"FAIL: high envelope wrap/restart");
            high_checks=high_checks+1;
        end
        if(dut.frame_age>=104858&&dut.mode_index>=1&&dut.mode_index<=3)begin
            if(dut.rock_amplitude_product!==0)$fatal(1,"FAIL: middle envelope wrap/restart");
            mid_checks=mid_checks+1;
        end
    end
    always @(posedge clk)if(rst_n&&dut.state==2)begin
        if(dut.rock_interpolated[12]!==0)$fatal(1,"FAIL: interpolated modal envelope out of range");
    end
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        for(n=0;n<140000;n=n+1)begin
            @(negedge clk);ce=1;on=n==0;
            @(negedge clk);ce=0;on=0;
            repeat(254)@(negedge clk);
            if(miss||$isunknown(pcm))$fatal(1,"FAIL: rock lifetime deadline/data");
            if(n>=131075&&(active||pcm!==0))$fatal(1,"FAIL: rock voice did not retire");
        end
        if(high_checks<100000||mid_checks<10000)$fatal(1,"FAIL: lifetime boundary coverage");
        $display("PASS: 140000 real-budget wah samples; saturated time index, interpolated modal bounds, no restarted tail, retired voice zero; no forced state");$finish;
    end
endmodule
