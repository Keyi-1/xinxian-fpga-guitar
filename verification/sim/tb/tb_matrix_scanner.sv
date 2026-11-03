`timescale 1ns/1ps

module tb_matrix_scanner;

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

    // Diode-isolated matrix model: only the selected row contributes to
    // the column input. A pressed key pulls its column low.
    assign col_in_n = row_oe[0] ? ~pressed[7:0]   :
                      row_oe[1] ? ~pressed[15:8]  :
                      row_oe[2] ? ~pressed[23:16] :
                      row_oe[3] ? ~pressed[31:24] :
                      8'hff;

    matrix_scanner #(
        .CLK_DIV       (2),
        .SETTLE_CYCLES (1)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .col_in_n    (col_in_n),
        .row_oe      (row_oe),
        .row_drive_n (row_drive_n),
        .frame_valid (frame_valid),
        .fret_mask   (fret_mask),
        .fret_id     (fret_id),
        .stable_valid(stable_valid),
        .stable_fret_mask(stable_fret_mask),
        .stable_fret_id(stable_fret_id)
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

    task check_frame;
        input [31:0] expected_mask;
        input [15:0] expected_id;
        begin
            if ((fret_mask !== expected_mask) ||
                (fret_id   !== expected_id)) begin
                $display("FAIL: matrix frame mismatch mask=%h/%h id=%h/%h",
                         fret_mask, expected_mask, fret_id, expected_id);
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

        // All released.
        wait_frame;
        check_frame(32'h00000000, 16'h0000);

        // Single key: string 0, fret 1.
        pressed = 32'h00000001;
        wait_frame;
        check_frame(32'h00000001, 16'h0001);

        // Multiple frets on one string: highest fret wins.
        pressed = 32'h00000081;
        wait_frame;
        check_frame(32'h00000081, 16'h0008);

        // Multiple strings and frets, with row isolation.
        pressed = 32'h80100200;
        wait_frame;
        check_frame(32'h80100200, 16'h8520);

        // All released again.
        pressed = 32'h00000000;
        wait_frame;
        check_frame(32'h00000000, 16'h0000);

        $display("PASS: 4x8 matrix scan, row isolation and highest fret priority");
        $finish;
    end

endmodule
