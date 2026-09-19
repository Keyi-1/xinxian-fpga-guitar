`timescale 1ns/1ps

module tb_spectrum_bar_cdc;
    reg src_clk;
    reg dst_clk;
    reg rst_n;
    reg src_frame_update;
    wire [4:0] src_read_index;
    reg [8:0] src_bar_height;
    reg [8:0] src_peak_height;
    reg [4:0] dst_read_index;
    wire [8:0] dst_bar_height;
    wire [8:0] dst_peak_height;
    wire dst_frame_update;
    wire src_overrun;
    integer offset;
    integer i;

    spectrum_bar_cdc dut (
        .src_clk(src_clk), .src_rst_n(rst_n),
        .src_frame_update(src_frame_update),
        .src_read_index(src_read_index), .src_bar_height(src_bar_height),
        .src_peak_height(src_peak_height), .src_overrun(src_overrun),
        .dst_clk(dst_clk), .dst_rst_n(rst_n),
        .dst_read_index(dst_read_index), .dst_bar_height(dst_bar_height),
        .dst_peak_height(dst_peak_height), .dst_frame_update(dst_frame_update)
    );

    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;
    always @* begin
        src_bar_height = offset + src_read_index;
        src_peak_height = offset + 100 + src_read_index;
    end

    task transfer_and_check;
        input integer expected_offset;
        begin
            @(negedge src_clk);
            src_frame_update = 1'b1;
            @(negedge src_clk);
            src_frame_update = 1'b0;
            wait (dst_frame_update);
            #1;
            for (i = 0; i < 32; i = i + 1) begin
                dst_read_index = i;
                #1;
                if ((dst_bar_height !== expected_offset + i) ||
                    (dst_peak_height !== expected_offset + 100 + i)) begin
                    $display("FAIL: CDC snapshot index=%0d got=%0d/%0d", i,
                             dst_bar_height, dst_peak_height);
                    $finish;
                end
            end
        end
    endtask

    initial begin
        src_clk = 1'b0;
        dst_clk = 1'b0;
        rst_n = 1'b0;
        src_frame_update = 1'b0;
        dst_read_index = 5'd0;
        offset = 0;
        repeat (4) @(posedge src_clk);
        #1 rst_n = 1'b1;
        transfer_and_check(0);
        repeat (6) @(posedge src_clk);
        offset = 200;
        transfer_and_check(200);
        if (src_overrun) begin
            $display("FAIL: CDC overrun during normal transfers");
            $finish;
        end
        $display("PASS: coherent 32-bar asynchronous snapshot handshake");
        $finish;
    end
endmodule
