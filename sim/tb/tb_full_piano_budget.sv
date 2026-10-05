`timescale 1ns/1ps
module tb_full_piano_budget;
    reg clk=0;always #40.690104 clk=~clk;
    reg rst_n=0;
    reg [3:0] on=0;
    wire tick,valid;
    wire [3:0] active,miss;
    wire [95:0] pcm;
    four_voice_piano_audio_core #(.MODES(32),.CONTROL_ENABLE(1)) dut(
        .clk_audio_ref(clk),.rst_n(rst_n),.note_on(on),.note_off(4'd0),
        .velocity_level(8'hff),.phase_inc({32'd26276679,32'd23409859,32'd20933131,32'd19685267}),
        .timbre_select(1'b1),.sustain_enable(1'b0),.harmony_enable(1'b0),
        .sample_tick(tick),.sample_valid(valid),.voice_active(active),.voice_pcm(pcm),
        .voice_profile(),.deadline_miss(miss),.timbre_blend(),.timbre_busy());
    integer counts[0:3],nonzero[0:3];
    genvar v;
    generate for(v=0;v<4;v=v+1)begin : observe
        always @(posedge clk)begin
            if(!rst_n||tick)begin counts[v]=0;nonzero[v]=0;end
            else if(dut.voice[v].u_voice.state==5)begin
                counts[v]=counts[v]+1;
                if(dut.voice[v].u_voice.bright_amplitude!=0)nonzero[v]=nonzero[v]+1;
            end
        end
    end endgenerate
    integer cycles=0,start_cycle=0,last_valid=0,frames=0,max_components=0,latency=0;
    always @(posedge clk)begin
        cycles=cycles+1;
        if(tick)start_cycle=cycles;
        if(valid)begin
            if(dut.valid!=15||miss||$isunknown(pcm))$fatal(1,"FAIL: parallel FULL voices or deadline");
            if(counts[0]+counts[1]+counts[2]+counts[3]!=128)$fatal(1,"FAIL: component schedule");
            if(nonzero[0]+nonzero[1]+nonzero[2]+nonzero[3]>max_components)
                max_components=nonzero[0]+nonzero[1]+nonzero[2]+nonzero[3];
            if(frames>0 && cycles-last_valid!=256)$fatal(1,"FAIL: sample gap");
            latency=cycles-start_cycle;
            if(latency>=256)$fatal(1,"FAIL: sample budget exceeded");
            last_valid=cycles;frames=frames+1;
        end
    end
    initial begin
        repeat(8)@(negedge clk);rst_n=1;on=15;
        wait(valid);@(negedge clk);on=0;
        wait(frames==2000);
        if(max_components!=128||active!=15)$fatal(1,"FAIL: only %0d nonzero components",max_components);
        $display("PASS: 4 x 32 = 128 nonzero components; 2000 real 48 kHz samples; synthesis latency %0d / 256 clocks",latency);
        $finish;
    end
    initial begin #50000000;$fatal(1,"FAIL: capacity timeout");end
endmodule
