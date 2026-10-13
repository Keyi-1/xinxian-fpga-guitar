`timescale 1ns/1ps
module tb_guitar_visual_tail;
    reg clk=0,rst_n=0,tick=0;
    always #5 clk=~clk;
    reg [127:0] inc={32'd1100,32'd900,32'd700,32'd500};
    reg [3:0] active=0,notes=0;
    wire [399:0] tail,normal;
    guitar_visual_telemetry #(.HOLD_INACTIVE_PITCH(1)) dut(.clk(clk),.rst_n(rst_n),
        .sample_tick(tick),.voice_sample_valid(1'b0),.phase_inc(inc),.note_on(notes),
        .voice_active(active),.fret_id(16'd0),.voice_pcm(96'd0),.snapshot(tail));
    guitar_visual_telemetry baseline(.clk(clk),.rst_n(rst_n),
        .sample_tick(tick),.voice_sample_valid(1'b0),.phase_inc(inc),.note_on(notes),
        .voice_active(active),.fret_id(16'd0),.voice_pcm(96'd0),.snapshot(normal));
    task automatic sample;
        begin @(negedge clk);tick=1;@(negedge clk);tick=0;end
    endtask
    integer i,j;
    reg [127:0] old_phase,held;
    initial begin
        repeat(4)@(negedge clk);rst_n=1;sample();
        if(tail[255:128]!=0 || tail[127:0]!=0)$fatal(1,"FAIL: initial silent pitch has a tail");
        notes=15;sample();notes=0;active=15;
        repeat(3)sample();
        if(tail!==normal)$fatal(1,"FAIL: audible pitch/phase is changed");
        for(i=0;i<4;i++)begin
            held=tail[255:128];old_phase=tail[127:0];active[i]=0;
            inc[i*32+:32]=9000+i*200;
            for(j=0;j<4;j++)begin
                sample();
                if(tail[128+i*32+:32]!=held[i*32+:32])$fatal(1,"FAIL: silent fret preparation changes tail pitch");
                if(tail[i*32+:32]!=old_phase[i*32+:32]+held[i*32+:32])
                    $fatal(1,"FAIL: tail phase does not continue without a jump");
                if(tail[335:332]!=active || tail[399:288]!=normal[399:288])
                    $fatal(1,"FAIL: tail changes real lifecycle/fret/Hz/strike labels");
                old_phase=tail[127:0];
            end
        end
        notes=15;sample();notes=0;
        if(tail[255:128]!=inc || tail[127:0]!=0)$fatal(1,"FAIL: fresh attack does not adopt prepared pitch");
        active=15;repeat(3)sample();
        if(tail!==normal)$fatal(1,"FAIL: audible retrigger telemetry differs");
        // A slide to open while audible must remain live, never frozen.
        inc[31:0]=333;sample();
        if(tail[159:128]!=333)$fatal(1,"FAIL: open-string continuation frozen");
        active=0;repeat(5)sample();
        if(tail[159:128]!=333)$fatal(1,"FAIL: last open pitch not retained");
        $display("PASS: display tails retain last audible DDS, continuously advance phase, follow audible slides/retrigger, and preserve actual active/Hz/fret/strike telemetry; default parameter remains unchanged");
        $finish;
    end
endmodule
