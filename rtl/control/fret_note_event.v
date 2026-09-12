`include "../config/guitar_config.vh"

// Converts debounced fret states into four independent string events.
// pluck_valid is intentionally separate from the left-hand matrix:
// pressing a fret selects pitch but does not itself pluck a note.
module fret_note_event (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stable_valid,
    input  wire [15:0] stable_fret_id,
    input  wire [3:0]  pluck_valid,

    output reg  [3:0]  note_on,
    output reg  [3:0]  note_off,
    output reg  [3:0]  slide_valid,
    output reg  [3:0]  voice_active,
    output reg  [15:0] current_fret_id,
    output reg  [127:0] phase_inc
);

    wire [3:0] fret0 = stable_fret_id[3:0];
    wire [3:0] fret1 = stable_fret_id[7:4];
    wire [3:0] fret2 = stable_fret_id[11:8];
    wire [3:0] fret3 = stable_fret_id[15:12];

    wire [5:0] addr0 = (fret0 <= 4'd8) ? fret0 : 6'd0;
    wire [5:0] addr1 = 6'd9  + ((fret1 <= 4'd8) ? fret1 : 6'd0);
    wire [5:0] addr2 = 6'd18 + ((fret2 <= 4'd8) ? fret2 : 6'd0);
    wire [5:0] addr3 = 6'd27 + ((fret3 <= 4'd8) ? fret3 : 6'd0);

    wire [31:0] target_phase0;
    wire [31:0] target_phase1;
    wire [31:0] target_phase2;
    wire [31:0] target_phase3;

    note_phase_table u_phase_table0 (.addr(addr0), .phase_inc(target_phase0));
    note_phase_table u_phase_table1 (.addr(addr1), .phase_inc(target_phase1));
    note_phase_table u_phase_table2 (.addr(addr2), .phase_inc(target_phase2));
    note_phase_table u_phase_table3 (.addr(addr3), .phase_inc(target_phase3));

    reg [15:0] previous_fret_id;

    always @(posedge clk) begin
        if (!rst_n) begin
            note_on         <= 4'd0;
            note_off        <= 4'd0;
            slide_valid     <= 4'd0;
            voice_active    <= 4'd0;
            current_fret_id <= 16'd0;
            previous_fret_id<= 16'd0;

            // Initialize each string to its open-string pitch.
            phase_inc[31:0]   <= target_phase0;
            phase_inc[63:32]  <= target_phase1;
            phase_inc[95:64]  <= target_phase2;
            phase_inc[127:96] <= target_phase3;
        end
        else begin
            note_on     <= 4'd0;
            note_off    <= 4'd0;
            slide_valid <= 4'd0;

            if (stable_valid) begin
                current_fret_id <= stable_fret_id;

                // String 0: fret changes while sounding slide; releasing
                // the last fret enters release and holds the old pitch.
                if (fret0 != previous_fret_id[3:0]) begin
                    if (fret0 == 4'd0) begin
                        if (voice_active[0]) begin
                            note_off[0]     <= 1'b1;
                            voice_active[0] <= 1'b0;
                        end
                        else begin
                            phase_inc[31:0] <= target_phase0;
                        end
                    end
                    else begin
                        phase_inc[31:0] <= target_phase0;
                        if (voice_active[0])
                            slide_valid[0] <= 1'b1;
                    end
                end

                if (fret1 != previous_fret_id[7:4]) begin
                    if (fret1 == 4'd0) begin
                        if (voice_active[1]) begin
                            note_off[1]     <= 1'b1;
                            voice_active[1] <= 1'b0;
                        end
                        else begin
                            phase_inc[63:32] <= target_phase1;
                        end
                    end
                    else begin
                        phase_inc[63:32] <= target_phase1;
                        if (voice_active[1])
                            slide_valid[1] <= 1'b1;
                    end
                end

                if (fret2 != previous_fret_id[11:8]) begin
                    if (fret2 == 4'd0) begin
                        if (voice_active[2]) begin
                            note_off[2]     <= 1'b1;
                            voice_active[2] <= 1'b0;
                        end
                        else begin
                            phase_inc[95:64] <= target_phase2;
                        end
                    end
                    else begin
                        phase_inc[95:64] <= target_phase2;
                        if (voice_active[2])
                            slide_valid[2] <= 1'b1;
                    end
                end

                if (fret3 != previous_fret_id[15:12]) begin
                    if (fret3 == 4'd0) begin
                        if (voice_active[3]) begin
                            note_off[3]     <= 1'b1;
                            voice_active[3] <= 1'b0;
                        end
                        else begin
                            phase_inc[127:96] <= target_phase3;
                        end
                    end
                    else begin
                        phase_inc[127:96] <= target_phase3;
                        if (voice_active[3])
                            slide_valid[3] <= 1'b1;
                    end
                end

                previous_fret_id <= stable_fret_id;
            end

            // A pluck starts or retriggers only the selected string.
            if (pluck_valid[0]) begin
                note_on[0]      <= 1'b1;
                voice_active[0] <= 1'b1;
            end
            if (pluck_valid[1]) begin
                note_on[1]      <= 1'b1;
                voice_active[1] <= 1'b1;
            end
            if (pluck_valid[2]) begin
                note_on[2]      <= 1'b1;
                voice_active[2] <= 1'b1;
            end
            if (pluck_valid[3]) begin
                note_on[3]      <= 1'b1;
                voice_active[3] <= 1'b1;
            end
        end
    end

endmodule
