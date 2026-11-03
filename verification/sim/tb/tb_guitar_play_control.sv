`timescale 1ns/1ps
module tb_guitar_play_control;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, tick = 0, stable = 0;
    reg [15:0] fret = 0;
    reg [3:0] pluck = 0, active = 0;
    reg [127:0] smooth = {32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01DCD01D};
    wire [3:0] on_event, off_event;
    wire [127:0] target;
    guitar_play_control dut (
        .clk(clk), .rst_n(rst_n), .sample_tick(tick),
        .stable_valid(stable), .stable_fret_id(fret), .pluck_valid(pluck),
        .voice_active(active), .smoothed_phase_inc(smooth),
        .note_on(on_event), .note_off(off_event), .target_phase_inc(target)
    );
    task check(input bit ok, input string message);
        if (!ok) $fatal(1, "FAIL: %s", message);
    endtask
    task step(input bit t, input bit v, input [15:0] f, input [3:0] p,
              input [3:0] expected_on, input [3:0] expected_off);
        begin
            @(negedge clk);
            tick = t; stable = v; fret = f; pluck = p;
            #1;
            check(on_event === expected_on && off_event === expected_off,
                  "sample-boundary event ordering");
            @(posedge clk); #1;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        step(0,1,16'h0001,0,0,0); // selection is silent
        step(0,0,16'h0001,4'b0001,0,0); // queue between ticks
        step(0,0,16'h0001,0,0,0);
        step(1,0,16'h0001,0,4'b0001,0);
        step(1,0,16'h0001,0,0,0); // consume exactly once
        active = 1;
        step(1,0,16'h0001,4'b0001,4'b0001,0); // arrival on tick
        step(1,0,16'h0001,0,0,0);

        // Releasing a sounding fret selects the open pitch without an event.
        step(0,1,0,0,0,0);
        check(target[31:0] == 32'h01C20D2F, "release selects open pitch before repluck");
        step(0,0,0,1,0,0);
        step(1,0,0,0,1,0);
        check(target[31:0] == 32'h01C20D2F, "open pitch after queued repluck");
        step(1,0,0,0,0,0);

        step(0,1,16'h0001,0,0,0);
        step(1,1,0,1,1,0); // final release and pluck exactly together
        check(target[31:0] == 32'h01C20D2F, "same-tick release/pluck open pitch");
        step(1,0,0,0,0,0);

        step(0,1,16'h0002,0,0,0);
        step(0,1,0,0,0,0);
        step(1,0,0,0,0,0);
        check(target[31:0] == 32'h01C20D2F, "release never damps or freezes pitch");
        step(1,1,16'h0008,0,0,0);
        check(target[31:0] == 32'h02CA6987, "press after release follows pitch without Attack");
        step(1,0,16'h0008,0,0,0);
        step(1,0,16'h0008,1,1,0);
        check(target[31:0] == 32'h02CA6987, "new pluck uses latest selected fret");

        // Four raw events arriving together are one tick-aligned chord.
        step(0,1,16'h1234,4'b1111,0,0);
        step(1,0,16'h1234,0,4'b1111,0);
        step(1,0,16'h1234,0,0,0);
        active=15;
        step(0,1,0,0,0,0);
        check(target=={32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01C20D2F},
              "four-string release chooses each open pitch independently");
        step(1,0,0,0,0,0);
        // Uncommitted matrix data cannot change a held target.
        step(0,0,16'h8888,0,0,0);
        check(target=={32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01C20D2F},
              "pitch updates require stable_valid");
        active=0;
        step(1,1,16'h8888,0,0,0); // finished voices are not restarted
        step(1,1,0,0,0,0);
        $display("PASS: queued/on-tick plucks, open-string release without note_off/retrigger, silent selection, four-string batching");
        $finish;
    end
endmodule
