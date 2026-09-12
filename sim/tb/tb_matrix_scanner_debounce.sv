`timescale 1ns/1ps

module tb_matrix_scanner_debounce;

    reg         clk;
    reg         rst_n;
    reg [31:0]  pressed;

    wire [7:0]  col_in_n;
    wire [3:0]  row_oe;
    wire [3:0]  row_drive_n;
    wire        frame_valid;
    wire [31:0] fret_mask;
    wire [15:0] fret_id;
    wire        stable_valid;
    wire [31:0] stable_fret_mask;
    wire [15:0] stable_fret_id;

    assign col_in_n = row_oe[0] ? ~pressed[7:0]   :
                      row_oe[1] ? ~pressed[15:8]  :
                      row_oe[2] ? ~pressed[23:16] :
                      row_oe[3] ? ~pressed[31:24] :
                      8'hff;

    matrix_scanner #(
        .CLK_DIV         (2),
        .SETTLE_CYCLES   (1),
        .DEBOUNCE_FRAMES (2)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .col_in_n         (col_in_n),
        .row_oe           (row_oe),
        .row_drive_n      (row_drive_n),
        .frame_valid      (frame_valid),
        .fret_mask        (fret_mask),
        .fret_id          (fret_id),
        .stable_valid     (stable_valid),
        .stable_fret_mask (stable_fret_mask),
        .stable_fret_id   (stable_fret_id)
    );

    always #5 clk = ~clk;

    task wait_frame;
        integer guard;
        begin
            guard = 0;

            while (frame_valid === 1'b1)
                @(posedge clk);

            while (frame_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
                if (guard > 100) begin
                    $display("FAIL: matrix frame timeout");
                    $finish;
                end
            end
        end
    endtask

    task check_stable;
        input [31:0] expected_mask;
        input [15:0] expected_id;
        input        expected_valid;
        begin
            if ((stable_fret_mask !== expected_mask) ||
                (stable_fret_id   !== expected_id)   ||
                (stable_valid     !== expected_valid)) begin
                $display("FAIL: stable mismatch mask=%h/%h id=%h/%h valid=%b/%b",
                         stable_fret_mask, expected_mask,
                         stable_fret_id, expected_id,
                         stable_valid, expected_valid);
                $finish;
            end
        end
    endtask

    initial begin
        clk     = 1'b0;
        rst_n   = 1'b0;
        pressed = 32'd0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        // Initial release needs two identical complete frames.
        wait_frame;
        check_stable(32'h00000000, 16'h0000, 1'b0);
        wait_frame;
        check_stable(32'h00000000, 16'h0000, 1'b1);

        // Simulate contact bounce: press, release, press. None of the
        // transient states may update the stable result.
        pressed = 32'h00000001;
        wait_frame;
        check_stable(32'h00000000, 16'h0000, 1'b0);

        pressed = 32'h00000000;
        wait_frame;
        check_stable(32'h00000000, 16'h0000, 1'b0);

        pressed = 32'h00000001;
        wait_frame;
        check_stable(32'h00000000, 16'h0000, 1'b0);

        // The second consecutive pressed frame is accepted.
        wait_frame;
        check_stable(32'h00000001, 16'h0001, 1'b1);

        // Highest-fret priority is also applied to the stable output.
        pressed = 32'h00000081;
        wait_frame;
        check_stable(32'h00000001, 16'h0001, 1'b0);
        wait_frame;
        check_stable(32'h00000081, 16'h0008, 1'b1);

        // Release also requires two consecutive frames.
        pressed = 32'h00000000;
        wait_frame;
        check_stable(32'h00000081, 16'h0008, 1'b0);
        wait_frame;
        check_stable(32'h00000000, 16'h0000, 1'b1);

        $display("PASS: matrix debounce and stable fret state");
        $finish;
    end

endmodule
