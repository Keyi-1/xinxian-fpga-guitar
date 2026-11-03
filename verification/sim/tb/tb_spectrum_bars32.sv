`timescale 1ns/1ps

module tb_spectrum_bars32;
    reg clk;
    reg rst_n;
    reg bin_valid;
    reg [9:0] bin_index;
    reg [18:0] bin_magnitude;
    reg frame_done;
    reg [4:0] read_index;
    wire [8:0] bar_height_read;
    wire [8:0] peak_height_read;
    wire frame_update;

    spectrum_bars32 dut (
        .clk(clk), .rst_n(rst_n), .bin_valid(bin_valid),
        .bin_index(bin_index), .bin_magnitude(bin_magnitude),
        .frame_done(frame_done), .read_index(read_index),
        .bar_height_read(bar_height_read),
        .peak_height_read(peak_height_read), .frame_update(frame_update)
    );

    always #5 clk = ~clk;

    task send_bin;
        input [9:0] index_value;
        input [18:0] magnitude_value;
        input last_value;
        begin
            @(negedge clk);
            bin_valid = 1'b1;
            bin_index = index_value;
            bin_magnitude = magnitude_value;
            frame_done = last_value;
            @(negedge clk);
            bin_valid = 1'b0;
            frame_done = 1'b0;
        end
    endtask

    task check_bar;
        input [4:0] index_value;
        input [8:0] expected_bar;
        input [8:0] expected_peak;
        begin
            read_index = index_value;
            #1;
            if ((bar_height_read !== expected_bar) ||
                (peak_height_read !== expected_peak)) begin
                $display("FAIL: bar %0d got height/peak=%0d/%0d expected=%0d/%0d",
                         index_value, bar_height_read, peak_height_read,
                         expected_bar, expected_peak);
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        bin_valid = 1'b0;
        bin_index = 10'd0;
        bin_magnitude = 19'd0;
        frame_done = 1'b0;
        read_index = 5'd0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        send_bin(10'd1, 19'd1600, 1'b0);
        send_bin(10'd20, 19'd3200, 1'b0);
        send_bin(10'd500, 19'd8000, 1'b1);
        check_bar(5'd0, 9'd100, 9'd100);
        check_bar(5'd15, 9'd200, 9'd200);
        check_bar(5'd31, 9'd400, 9'd400);

        // Empty next frame drops bars immediately while peak markers decay.
        send_bin(10'd0, 19'd0, 1'b1);
        check_bar(5'd0, 9'd0, 9'd96);
        check_bar(5'd15, 9'd0, 9'd196);
        check_bar(5'd31, 9'd0, 9'd396);

        $display("PASS: 512 FFT bins map to 32 log bars with saturation and peak decay");
        $finish;
    end
endmodule
