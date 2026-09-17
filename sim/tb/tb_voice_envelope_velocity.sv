`timescale 1ns/1ps

module tb_voice_envelope_velocity;

    reg clk;
    reg rst_n;
    reg sample_ce;
    reg [3:0] note_on;
    reg [3:0] note_off;

    wire [15:0] env0;
    wire [15:0] env1;
    wire [15:0] env2;
    wire [15:0] env3;

    voice_envelope u_env0 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on[0]), .note_off(note_off[0]), .velocity_level(2'd0),
        .env_level(env0), .active()
    );
    voice_envelope u_env1 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on[1]), .note_off(note_off[1]), .velocity_level(2'd1),
        .env_level(env1), .active()
    );
    voice_envelope u_env2 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on[2]), .note_off(note_off[2]), .velocity_level(2'd2),
        .env_level(env2), .active()
    );
    voice_envelope u_env3 (
        .clk(clk), .rst_n(rst_n), .sample_ce(sample_ce),
        .note_on(note_on[3]), .note_off(note_off[3]), .velocity_level(2'd3),
        .env_level(env3), .active()
    );

    always #5 clk = ~clk;

    task envelope_tick;
        input [3:0] on_value;
        input [3:0] off_value;
        begin
            @(negedge clk);
            sample_ce = 1'b1;
            note_on = on_value;
            note_off = off_value;
            @(negedge clk);
            sample_ce = 1'b0;
            note_on = 4'd0;
            note_off = 4'd0;
        end
    endtask

    integer k;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_ce = 1'b0;
        note_on = 4'd0;
        note_off = 4'd0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        envelope_tick(4'b1111, 4'd0);
        for (k = 0; k < 32; k = k + 1)
            envelope_tick(4'd0, 4'd0);

        if ((env0 !== 16'd12288) || (env1 !== 16'd16384) ||
            (env2 !== 16'd24576) || (env3 !== 16'd32767)) begin
            $display("FAIL: velocity attack targets %0d %0d %0d %0d",
                     env0, env1, env2, env3);
            $finish;
        end

        envelope_tick(4'd0, 4'b1111);
        envelope_tick(4'd0, 4'd0);
        if ((env0 !== 16'd12283) || (env1 !== 16'd16380) ||
            (env2 !== 16'd24573) || (env3 !== 16'd32765)) begin
            $display("FAIL: velocity release rates %0d %0d %0d %0d",
                     env0, env1, env2, env3);
            $finish;
        end

        $display("PASS: four-level velocity amplitude and release envelope");
        $finish;
    end

endmodule
