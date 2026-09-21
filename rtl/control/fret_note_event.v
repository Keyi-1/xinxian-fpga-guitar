`include "../config/guitar_config.vh"

// Converts debounced fret states into four independent string events.
// pluck_valid is intentionally separate from the left-hand matrix:
// pressing a fret selects pitch but does not itself pluck a note.
module fret_note_event #(
    parameter integer VIBRATO_TAP_COUNT      = `VIBRATO_TAP_COUNT,
    parameter integer VIBRATO_MIN_INTERVAL   = `VIBRATO_MIN_TAP_SAMPLES,
    parameter integer VIBRATO_MAX_INTERVAL   = `VIBRATO_MAX_TAP_SAMPLES,
    parameter integer VIBRATO_EXIT_INTERVAL  = `VIBRATO_EXIT_SAMPLES,
    parameter integer VIBRATO_WINDOW         = `VIBRATO_WINDOW_SAMPLES
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stable_valid,
    input  wire [15:0] stable_fret_id,
    input  wire [3:0]  pluck_valid,
    input  wire        sample_ce,

    output reg  [3:0]  note_on,
    output reg  [3:0]  note_off,
    output reg  [3:0]  slide_valid,
    output reg  [3:0]  vibrato_enable,
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
    reg [3:0]  gesture_fret [0:3];
    reg [1:0]  tap_count [0:3];
    reg        gesture_active [0:3];
    reg        release_pending [0:3];
    reg [15:0] release_count [0:3];
    reg [15:0] window_count [0:3];
    integer i;

    function [3:0] fret_at;
        input [15:0] fret_id;
        input integer index;
        begin
            fret_at = fret_id >> (index * 4);
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            note_on         <= 4'd0;
            note_off        <= 4'd0;
            slide_valid     <= 4'd0;
            voice_active    <= 4'd0;
            current_fret_id <= 16'd0;
            previous_fret_id<= 16'd0;
            vibrato_enable  <= 4'd0;

            for (i = 0; i < 4; i = i + 1) begin
                gesture_fret[i] <= 4'd0;
                tap_count[i] <= 2'd0;
                gesture_active[i] <= 1'b0;
                release_pending[i] <= 1'b0;
                release_count[i] <= 16'd0;
                window_count[i] <= 16'd0;
            end

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

            // Candidate and exit timers advance only at the audio sample rate.
            if (sample_ce) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (gesture_active[i]) begin
                        if (window_count[i] >= VIBRATO_WINDOW) begin
                            gesture_active[i] <= 1'b0;
                            tap_count[i] <= 2'd0;
                        end
                        else begin
                            window_count[i] <= window_count[i] + 1'b1;
                        end
                    end

                    if (release_pending[i]) begin
                        if (release_count[i] >= VIBRATO_EXIT_INTERVAL) begin
                            note_off[i] <= 1'b1;
                            voice_active[i] <= 1'b0;
                            vibrato_enable[i] <= 1'b0;
                            gesture_active[i] <= 1'b0;
                            release_pending[i] <= 1'b0;
                            tap_count[i] <= 2'd0;
                        end
                        else begin
                            release_count[i] <= release_count[i] + 1'b1;
                        end
                    end
                end
            end

            if (stable_valid) begin
                current_fret_id <= stable_fret_id;

                for (i = 0; i < 4; i = i + 1) begin
                    if (fret_at(stable_fret_id, i) !=
                        fret_at(previous_fret_id, i)) begin
                        if (fret_at(stable_fret_id, i) == 4'd0) begin
                            if (voice_active[i]) begin
                                // Delay a final release long enough to recognize
                                // a same-fret tap gesture. No note_off is sent yet.
                                gesture_fret[i] <= fret_at(previous_fret_id, i);
                                release_pending[i] <= 1'b1;
                                release_count[i] <= 16'd0;
                                if (VIBRATO_EXIT_INTERVAL == 0) begin
                                    note_off[i] <= 1'b1;
                                    voice_active[i] <= 1'b0;
                                    vibrato_enable[i] <= 1'b0;
                                    release_pending[i] <= 1'b0;
                                end
                                if (!gesture_active[i]) begin
                                    gesture_active[i] <= 1'b1;
                                    tap_count[i] <= 2'd0;
                                    window_count[i] <= 16'd0;
                                end
                            end
                            else begin
                                phase_inc[i*32 +: 32] <=
                                    (i == 0) ? target_phase0 :
                                    (i == 1) ? target_phase1 :
                                    (i == 2) ? target_phase2 : target_phase3;
                            end
                        end
                        else if (release_pending[i] &&
                                 (fret_at(stable_fret_id, i) == gesture_fret[i])) begin
                            // A valid same-fret re-press is a vibrato tap.
                            if (gesture_active[i] &&
                                (release_count[i] >= VIBRATO_MIN_INTERVAL) &&
                                (release_count[i] <= VIBRATO_MAX_INTERVAL)) begin
                                if (tap_count[i] + 1 >= VIBRATO_TAP_COUNT) begin
                                    vibrato_enable[i] <= 1'b1;
                                    gesture_active[i] <= 1'b0;
                                    tap_count[i] <= 2'd0;
                                end
                                else
                                    tap_count[i] <= tap_count[i] + 1'b1;
                            end
                            else begin
                                gesture_active[i] <= 1'b0;
                                tap_count[i] <= 2'd0;
                            end
                            release_pending[i] <= 1'b0;
                            release_count[i] <= 16'd0;
                        end
                        else begin
                            // A different non-zero fret is an ordinary slide.
                            gesture_active[i] <= 1'b0;
                            release_pending[i] <= 1'b0;
                            tap_count[i] <= 2'd0;
                            vibrato_enable[i] <= 1'b0;
                            phase_inc[i*32 +: 32] <=
                                (i == 0) ? target_phase0 :
                                (i == 1) ? target_phase1 :
                                (i == 2) ? target_phase2 : target_phase3;
                            if (voice_active[i])
                                slide_valid[i] <= 1'b1;
                        end
                    end
                end

                previous_fret_id <= stable_fret_id;
            end

            // A pluck starts or retriggers only the selected string.
            if (pluck_valid[0]) begin
                note_on[0]      <= 1'b1;
                voice_active[0] <= 1'b1;
                vibrato_enable[0] <= 1'b0;
                gesture_active[0] <= 1'b0;
                release_pending[0] <= 1'b0;
            end
            if (pluck_valid[1]) begin
                note_on[1]      <= 1'b1;
                voice_active[1] <= 1'b1;
                vibrato_enable[1] <= 1'b0;
                gesture_active[1] <= 1'b0;
                release_pending[1] <= 1'b0;
            end
            if (pluck_valid[2]) begin
                note_on[2]      <= 1'b1;
                voice_active[2] <= 1'b1;
                vibrato_enable[2] <= 1'b0;
                gesture_active[2] <= 1'b0;
                release_pending[2] <= 1'b0;
            end
            if (pluck_valid[3]) begin
                note_on[3]      <= 1'b1;
                voice_active[3] <= 1'b1;
                vibrato_enable[3] <= 1'b0;
                gesture_active[3] <= 1'b0;
                release_pending[3] <= 1'b0;
            end
        end
    end

endmodule
