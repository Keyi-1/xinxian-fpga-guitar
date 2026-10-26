// Single-clock playing policy for the dual-PCB validation project.
// Only real plucks start a voice. A qualified release locks that voice's
// tail pitch; later contacts prepare the next strike without retuning it.
module guitar_play_control #(
    parameter integer EARLY_RELEASE_ENABLE=0
) (
    input wire clk,
    input wire rst_n,
    input wire sample_tick,
    input wire stable_valid,
    input wire [15:0] stable_fret_id,
    input wire [3:0] pluck_valid,
    input wire [3:0] voice_active,
    input wire [3:0] fret_release,
    input wire [127:0] smoothed_phase_inc,
    output wire [3:0] note_on,
    output wire [3:0] note_off,
    output wire [127:0] target_phase_inc
);
    wire [127:0] selected_phase;
    reg [127:0] held_target;
    reg [3:0] pending_pluck;
    reg [3:0] tail_locked,previous_contact,release_prepared;
    wire [3:0] launch_mask = pending_pluck | pluck_valid;
    wire [3:0] early_release=EARLY_RELEASE_ENABLE!=0 ? fret_release : 4'd0;

    // Keep events until an audio tick; an event arriving ON that tick is
    // consumed immediately. A fresh pluck uses the current selected pitch.
    assign note_on = launch_mask & {4{sample_tick}};
    // Fret contact duration never gates sound duration. This playing-policy
    // interface has no explicit mute command; natural voice decay ends notes.
    assign note_off = 4'b0000;

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : string_pitch
        // A short confirmed release can precede stable_fret_id becoming
        // zero. Prepare an open strike until a new stable contact arrives.
        wire [3:0] fret = early_release[g] || (release_prepared[g] && !stable_valid) ?
            4'd0 : stable_fret_id[g*4 +: 4];
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
            tail_locked<=0;previous_contact<=0;release_prepared<=0;
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
                if(stable_valid)begin
                    previous_contact[i]<=stable_fret_id[i*4+:4]!=0;
                    release_prepared[i]<=0;
                end
                if(early_release[i])release_prepared[i]<=1;

                // A real strike wins over a coincident release. The direct
                // launch bypass and natural envelope schedule are unchanged.
                if(note_on[i])begin
                    held_target[i*32+:32]<=selected_phase[i*32+:32];
                    tail_locked[i]<=0;
                end else if(!voice_active[i])begin
                    tail_locked[i]<=0;
                    if(stable_valid && stable_fret_id[i*4+:4]!=0)
                        held_target[i*32+:32]<=selected_phase[i*32+:32];
                end else if(early_release[i] ||
                    (stable_valid && previous_contact[i] && stable_fret_id[i*4+:4]==0))begin
                    tail_locked[i]<=1;
                end else if(stable_valid && stable_fret_id[i*4+:4]!=0 && !tail_locked[i])begin
                    // Contact-to-contact moves without a release still slide.
                    held_target[i*32+:32]<=selected_phase[i*32+:32];
                end
            end
        end
    end
endmodule
