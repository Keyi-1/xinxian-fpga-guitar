`timescale 1ns/1ps

// Exhaustive logical coverage for the 4x8 diode-isolated neck matrix.
// Every one of the 255 possible fret masks is applied independently to every
// string, which covers all 32 individual positions and every highest-fret
// priority combination without relying on a few representative patterns.
module tb_matrix_scanner_exhaustive;
    reg clk;
    reg rst_n;
    reg [31:0] pressed;
    wire [7:0] col_in_n;
    wire [3:0] row_oe;
    wire [3:0] row_drive_n;
    wire frame_valid;
    wire [31:0] fret_mask;
    wire [15:0] fret_id;
    integer string_index;
    integer mask_value;
    integer checked_patterns;

    assign col_in_n = row_oe[0] ? ~pressed[7:0] :
                      row_oe[1] ? ~pressed[15:8] :
                      row_oe[2] ? ~pressed[23:16] :
                      row_oe[3] ? ~pressed[31:24] : 8'hff;

    matrix_scanner #(
        .CLK_DIV(1), .SETTLE_CYCLES(0), .DEBOUNCE_FRAMES(1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .col_in_n(col_in_n),
        .row_oe(row_oe), .row_drive_n(row_drive_n),
        .frame_valid(frame_valid), .fret_mask(fret_mask),
        .fret_id(fret_id), .stable_valid(),
        .stable_fret_mask(), .stable_fret_id()
    );

    always #5 clk = ~clk;

    function [3:0] expected_highest_fret;
        input [7:0] mask;
        integer fret;
        begin
            expected_highest_fret = 4'd0;
            for (fret = 0; fret < 8; fret = fret + 1)
                if (mask[fret])
                    expected_highest_fret = fret + 1;
        end
    endfunction

    task set_one_string;
        input integer selected_string;
        input [7:0] selected_mask;
        begin
            pressed = 32'd0;
            case (selected_string)
                0: pressed[7:0] = selected_mask;
                1: pressed[15:8] = selected_mask;
                2: pressed[23:16] = selected_mask;
                default: pressed[31:24] = selected_mask;
            endcase
        end
    endtask

    task wait_and_check_frame;
        input [31:0] expected_mask;
        input [15:0] expected_id;
        integer guard;
        begin
            guard = 0;
            while (frame_valid === 1'b1)
                @(posedge clk);
            while (frame_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
                if (guard > 16) begin
                    $display("FAIL: exhaustive matrix frame timeout");
                    $fatal;
                end
            end
            if ((fret_mask !== expected_mask) ||
                (fret_id !== expected_id)) begin
                $display("FAIL: exhaustive matrix string=%0d mask=%02h got=%08h/%04h expected=%08h/%04h",
                         string_index, mask_value, fret_mask, fret_id,
                         expected_mask, expected_id);
                $fatal;
            end
            checked_patterns = checked_patterns + 1;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if ((row_oe != 4'b0001) && (row_oe != 4'b0010) &&
                (row_oe != 4'b0100) && (row_oe != 4'b1000)) begin
                $display("FAIL: scanner row enable is not one-hot: %b", row_oe);
                $fatal;
            end
            if (row_drive_n !== ~row_oe) begin
                $display("FAIL: scanner row drive mismatch oe=%b drive_n=%b",
                         row_oe, row_drive_n);
                $fatal;
            end
        end
    end

    reg [31:0] expected_mask;
    reg [15:0] expected_id;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        pressed = 32'd0;
        checked_patterns = 0;
        expected_mask = 32'd0;
        expected_id = 16'd0;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        wait_and_check_frame(32'd0, 16'd0);

        for (string_index = 0; string_index < 4;
             string_index = string_index + 1) begin
            for (mask_value = 1; mask_value < 256;
                 mask_value = mask_value + 1) begin
                set_one_string(string_index, mask_value[7:0]);
                expected_mask = 32'd0;
                expected_id = 16'd0;
                case (string_index)
                    0: begin
                        expected_mask[7:0] = mask_value[7:0];
                        expected_id[3:0] =
                            expected_highest_fret(mask_value[7:0]);
                    end
                    1: begin
                        expected_mask[15:8] = mask_value[7:0];
                        expected_id[7:4] =
                            expected_highest_fret(mask_value[7:0]);
                    end
                    2: begin
                        expected_mask[23:16] = mask_value[7:0];
                        expected_id[11:8] =
                            expected_highest_fret(mask_value[7:0]);
                    end
                    default: begin
                        expected_mask[31:24] = mask_value[7:0];
                        expected_id[15:12] =
                            expected_highest_fret(mask_value[7:0]);
                    end
                endcase
                wait_and_check_frame(expected_mask, expected_id);
            end
        end

        // Simultaneous different fret sets prove row isolation and nibble
        // ordering in the committed 32-bit frame.
        pressed = 32'h81422118;
        wait_and_check_frame(32'h81422118, 16'h8765);

        $display("PASS: exhaustive 4x8 matrix positions/priority/isolation patterns=%0d",
                 checked_patterns);
        $finish;
    end

endmodule
