`timescale 1ns/1ps
module tb_posture_timbre_policy;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,enable=1,healthy=1,performance=1,switching=0;
    reg manual=0,explicit_load=0,event_valid=0,pipeline_idle=1,timbre_busy=0;
    reg [1:0] proposed=1,current=0;reg [3:0] voices=0,notes=0;
    wire load,pending;wire [1:0] loaded;
    integer loads=0;
    posture_timbre_policy dut(.clk(clk),.rst_n(rst_n),.sample_tick(tick),
        .auto_enable(enable),.sensor_healthy(healthy),.performance_mode(performance),.mode_switching(switching),
        .manual_press(manual),.explicit_timbre_load(explicit_load),.pose_event(event_valid),
        .pose_timbre(proposed),.current_timbre(current),.voice_active(voices),.pending_note_on(notes),
        .pipeline_idle(pipeline_idle),.timbre_busy(timbre_busy),.load_timbre(load),.loaded_timbre(loaded),.pending(pending));
    always @(posedge clk)if(rst_n)begin
        if(manual)current<=current==2 ? 0 : current+1'b1;
        else if(load)begin current<=loaded;loads=loads+1;end
    end
    task check(input bit ok,input string why);if(!ok)$fatal(1,"FAIL: %s",why);endtask
    task event_to(input [1:0] value);
        @(negedge clk);proposed=value;event_valid=1;@(negedge clk);event_valid=0;
    endtask
    task boundary;
        @(negedge clk);tick=1;@(negedge clk);tick=0;@(negedge clk);
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        voices=15;event_to(1);repeat(8)boundary();check(pending && loads==0,"sustain/active voices keep pending indefinitely");
        voices=0;notes=1;repeat(3)boundary();check(loads==0,"pending on must block");
        notes=0;pipeline_idle=0;repeat(3)boundary();check(loads==0,"pipeline must drain");
        pipeline_idle=1;timbre_busy=1;repeat(3)boundary();check(loads==0,"old smoother must settle");
        timbre_busy=0;boundary();
        pipeline_idle=0;@(negedge clk);pipeline_idle=1; // normal zero-sample valid pulse between boundaries
        boundary();check(loads==0,"at least two quiet boundaries, normal PCM valid does not reset count");
        boundary();check(loads==1 && current==1 && !pending,"idle commit through same enum owner");
        repeat(6)boundary();check(loads==1,"no repeated same-pose default");
        @(negedge clk);manual=1;@(negedge clk);manual=0;repeat(3)boundary();check(current==2 && loads==1,"manual wah survives same pose");
        voices=1;event_to(0);manual=1;@(negedge clk);manual=0;voices=0;repeat(5)boundary();
        check(current==0 && !pending && loads==1,"manual cancels pending auto");
        event_to(1);boundary();boundary();
        @(negedge clk);tick=1;@(negedge clk);tick=0;manual=1;
        #1;check(!load,"late manual press masks registered request");
        @(negedge clk);manual=0;check(current==1 && loads==1,"manual wins consuming edge");
        event_to(0);healthy=0;repeat(5)boundary();check(!pending && current==1,"offline holds selection");
        healthy=1;repeat(5)boundary();check(loads==1,"recovery alone cannot replay pose");
        proposed=0;event_valid=1;manual=1;@(negedge clk);event_valid=0;manual=0;
        repeat(5)boundary();check(loads==1 && current==2,"simultaneous manual/pose manual wins");
        performance=0;event_to(0);repeat(5)boundary();check(!pending && current==2,"games/menu never AUTO");
        performance=1;switching=1;event_to(0);repeat(3)boundary();check(!pending,"mode transition priority");
        switching=0;enable=0;event_to(0);repeat(3)boundary();check(loads==1,"MANUAL default no auto");
        enable=1;event_to(3);repeat(3)boundary();check(!pending && loads==1,"unavailable upright timbre rejected");
        event_to(0);boundary();boundary();
        @(negedge clk);tick=1;@(negedge clk);tick=0;notes=1;
        #1;check(!load,"new pluck masks registered request at consumer");
        @(negedge clk);notes=0;repeat(5)boundary();
        check(loads==2 && current==0 && !pending,"new-pluck deferral retains latest target");
        $display("PASS: quiet boundaries/active sustain/pending note/pipeline/smoother/manual priority and late edge/cancel/fault/mode/no replay");$finish;
    end
    initial begin #100000;$fatal(1,"FAIL: policy watchdog");end
endmodule
