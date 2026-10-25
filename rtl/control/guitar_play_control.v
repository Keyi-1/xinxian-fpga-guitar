// Single-clock playing policy for the dual-PCB validation project.
// Only real plucks start a voice. Releasing a fret retains the last pitch
// and natural envelope. A new pluck with no contact starts an open string.
module guitar_play_control (
    input wire clk,
    input wire rst_n,
    input wire sample_tick,
    input wire stable_valid,
    input wire [15:0] stable_fret_id,
    input wire [3:0] pluck_valid,
    input wire [3:0] voice_active,
    input wire [127:0] smoothed_phase_inc,
    output wire [3:0] note_on,
    output wire [3:0] note_off,
    output wire [127:0] target_phase_inc
);
    wire [127:0] selected_phase;
    reg [127:0] held_target;
    reg [3:0] pending_pluck;
    wire [3:0] launch_mask = pending_pluck | pluck_valid;

    // Keep events until an audio tick; an event arriving ON that tick is
    // consumed immediately. A fresh pluck uses the current selected pitch.
    assign note_on = launch_mask & {4{sample_tick}};
    // Fret contact duration never gates sound duration. This playing-policy
    // interface has no explicit mute command; natural voice decay ends notes.
    assign note_off = 4'b0000;

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : string_pitch
        wire [3:0] fret = stable_fret_id[g*4 +: 4];
        localparam [5:0] BASE_ADDR = g * 9;
        wire [5:0] addr = BASE_ADDR + {2'b00, fret};
        note_phase_table u_table (
            .addr(addr), .phase_inc(selected_phase[g*32 +: 32])
        );
        // This bypass gives a fresh pluck its selected pitch on the very
        // same sample as Attack, including a new open-string pluck.
        // Resolve a queued pluck before the tick. This removes sample_tick
        // from the long slide-step arithmetic path; the smoother still only
        // consumes it on the same note_on/sample boundary as before.
        assign target_phase_inc[g*32 +: 32] = launch_mask[g] ?
            selected_phase[g*32 +: 32] : held_target[g*32 +: 32];
    end endgenerate

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            pending_pluck <= 4'd0;
            held_target <= {32'h00C879A3, 32'h010B9A2B,
                            32'h0151285D, 32'h01C20D2F};
        end
        else begin
            if (sample_tick) begin
                pending_pluck <= 4'd0;
            end
            else begin
                pending_pluck <= launch_mask;
            end

            for (i = 0; i < 4; i = i + 1) begin
                // Store fretted pitches, whether sounding or silent. A
                // release alone holds the pitch; a real open-string pluck
                // still replaces it with fret zero at the attack boundary.
                // Only note_on reaches the envelope; a pitch update cannot
                // synthesize a hammer-on or resurrect a finished voice.
                if ((stable_valid && stable_fret_id[i*4 +: 4]!=0) || note_on[i]) begin
                    held_target[i*32 +: 32] <= selected_phase[i*32 +: 32];
                end
            end
        end
    end
endmodule
