// 4x8 neck matrix scanner.
// Logical convention for the first implementation:
//   - one selected row is driven low;
//   - unselected rows are high impedance through row_oe;
//   - pressed columns are read as 0 (active low).
// The physical polarity must be confirmed against the actual NEO Dock.

module matrix_scanner #(
    parameter integer CLK_DIV        = 4,
    parameter integer SETTLE_CYCLES  = 1,
    parameter integer DEBOUNCE_FRAMES = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  col_in_n,

    output reg  [3:0]  row_oe,
    output reg  [3:0]  row_drive_n,

    output reg         frame_valid,
    output reg [31:0]  fret_mask,
    output reg [15:0]  fret_id,

    output reg         stable_valid,
    output reg [31:0]  stable_fret_mask,
    output reg [15:0]  stable_fret_id,
    output reg [3:0]   release_event
);

    reg [31:0] work_mask;
    reg [1:0]  row_index;
    reg [31:0] div_count;
    reg [31:0] settle_count;
    reg [31:0] candidate_mask;
    reg [31:0] candidate_count;
    reg [3:0] empty_seen,release_reported;
    integer s;

    wire [7:0] col_pressed;
    assign col_pressed = ~col_in_n;

    wire [31:0] frame_mask_next;
    wire [15:0] frame_id_next;

    assign frame_mask_next = {col_pressed, work_mask[23:0]};
    assign frame_id_next = {
        highest_fret(col_pressed),
        highest_fret(work_mask[23:16]),
        highest_fret(work_mask[15:8]),
        highest_fret(work_mask[7:0])
    };

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
            candidate_mask <= 32'd0;
            candidate_count <= 32'd0;
            frame_valid <= 1'b0;
            fret_mask   <= 32'd0;
            fret_id     <= 16'd0;
            stable_valid <= 1'b0;
            stable_fret_mask <= 32'd0;
            stable_fret_id <= 16'd0;
            release_event <= 0;empty_seen <= 0;release_reported <= 0;
        end
        else begin
            frame_valid <= 1'b0;
            stable_valid <= 1'b0;
            release_event <= 0;

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

                    // Separate per-string release observations leave the
                    // five-frame stable mask used by the game unchanged.
                    // Two empty samples one frame apart reject one dropout
                    // while retaining gaps shorter than full debounce.
                    for(s=0;s<4;s=s+1)begin
                        if(row_index==s)begin
                            if(col_pressed==0)begin
                                empty_seen[s]<=1;
                                if(empty_seen[s] && !release_reported[s] &&
                                   stable_fret_id[s*4+:4]!=0)begin
                                    release_event[s]<=1;release_reported[s]<=1;
                                end
                            end else begin
                                empty_seen[s]<=0;release_reported[s]<=0;
                            end
                        end
                    end

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
                            fret_mask <= frame_mask_next;
                            fret_id   <= frame_id_next;

                            frame_valid <= 1'b1;

                            // A state must appear in consecutive complete
                            // frames before it becomes stable. Raw outputs
                            // above remain available for diagnostics.
                            if (candidate_mask == frame_mask_next) begin
                                if (candidate_count < DEBOUNCE_FRAMES) begin
                                    candidate_count <= candidate_count + 1;

                                    if ((candidate_count + 1) >= DEBOUNCE_FRAMES) begin
                                        stable_fret_mask <= frame_mask_next;
                                        stable_fret_id   <= frame_id_next;
                                        stable_valid     <= 1'b1;
                                    end
                                end
                            end
                            else begin
                                candidate_mask  <= frame_mask_next;
                                candidate_count <= 32'd1;

                                if (DEBOUNCE_FRAMES <= 1) begin
                                    stable_fret_mask <= frame_mask_next;
                                    stable_fret_id   <= frame_id_next;
                                    stable_valid     <= 1'b1;
                                end
                            end
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
