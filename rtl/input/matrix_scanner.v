// 4x8 neck matrix scanner.
// Logical convention for the first implementation:
//   - one selected row is driven low;
//   - unselected rows are high impedance through row_oe;
//   - pressed columns are read as 0 (active low).
// The physical polarity must be confirmed against the actual NEO Dock.

module matrix_scanner #(
    parameter integer CLK_DIV        = 4,
    parameter integer SETTLE_CYCLES  = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  col_in_n,

    output reg  [3:0]  row_oe,
    output reg  [3:0]  row_drive_n,

    output reg         frame_valid,
    output reg [31:0]  fret_mask,
    output reg [15:0]  fret_id
);

    reg [31:0] work_mask;
    reg [1:0]  row_index;
    reg [31:0] div_count;
    reg [31:0] settle_count;

    wire [7:0] col_pressed;
    assign col_pressed = ~col_in_n;

    function [3:0] highest_fret;
        input [7:0] mask;
        integer k;
        begin
            highest_fret = 4'd0;
            for (k = 0; k < 8; k = k + 1) begin
                if (mask[k])
                    highest_fret = k + 1;
            end
        end
    endfunction

    // External glue should assign row_drive_n to the physical row bus
    // only when the corresponding row_oe bit is asserted.
    always @* begin
        row_oe       = 4'b0000;
        row_drive_n  = 4'b1111;

        if (rst_n) begin
            case (row_index)
                2'd0: begin row_oe = 4'b0001; row_drive_n = 4'b1110; end
                2'd1: begin row_oe = 4'b0010; row_drive_n = 4'b1101; end
                2'd2: begin row_oe = 4'b0100; row_drive_n = 4'b1011; end
                2'd3: begin row_oe = 4'b1000; row_drive_n = 4'b0111; end
                default: begin end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            work_mask   <= 32'd0;
            row_index   <= 2'd0;
            div_count   <= 32'd0;
            settle_count<= 32'd0;
            frame_valid <= 1'b0;
            fret_mask   <= 32'd0;
            fret_id     <= 16'd0;
        end
        else begin
            frame_valid <= 1'b0;

            if (div_count < CLK_DIV - 1) begin
                div_count <= div_count + 1;
            end
            else begin
                div_count <= 32'd0;

                if (settle_count < SETTLE_CYCLES) begin
                    settle_count <= settle_count + 1;
                end
                else begin
                    settle_count <= 32'd0;

                    case (row_index)
                        2'd0: begin
                            work_mask[7:0] <= col_pressed;
                        end

                        2'd1: begin
                            work_mask[15:8] <= col_pressed;
                        end

                        2'd2: begin
                            work_mask[23:16] <= col_pressed;
                        end

                        2'd3: begin
                            work_mask[31:24] <= col_pressed;

                            // Commit the complete frame, including the
                            // row captured in this clock cycle.
                            fret_mask[7:0]   <= work_mask[7:0];
                            fret_mask[15:8]  <= work_mask[15:8];
                            fret_mask[23:16] <= work_mask[23:16];
                            fret_mask[31:24] <= col_pressed;

                            fret_id[3:0]   <= highest_fret(work_mask[7:0]);
                            fret_id[7:4]   <= highest_fret(work_mask[15:8]);
                            fret_id[11:8]  <= highest_fret(work_mask[23:16]);
                            fret_id[15:12] <= highest_fret(col_pressed);

                            frame_valid <= 1'b1;
                        end

                        default: begin
                            work_mask <= 32'd0;
                        end
                    endcase

                    if (row_index == 2'd3)
                        row_index <= 2'd0;
                    else
                        row_index <= row_index + 1'b1;
                end
            end
        end
    end

endmodule
