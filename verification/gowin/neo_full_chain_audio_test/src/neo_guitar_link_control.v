// Single-clock playing policy for the dual-PCB validation project.
// Only real plucks start a voice. Fret changes slide an existing voice;
// the final fret release damps it at its current audible pitch.
module neo_guitar_link_control (
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
    reg [15:0] previous_fret;
    reg [3:0] pending_pluck;
    reg [3:0] pending_release;
    reg [3:0] damped;
    wire [3:0] release_now;
    wire [3:0] launch_mask = pending_pluck | pluck_valid;

    // Keep events until an audio tick; an event arriving ON that tick is
    // consumed immediately. A same-tick pluck wins over a fret release.
    assign note_on = launch_mask & {4{sample_tick}};
    assign note_off = (pending_release | release_now) & ~launch_mask &
                      {4{sample_tick}};

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin : string_pitch
        wire [3:0] fret = stable_fret_id[g*4 +: 4];
        localparam [5:0] BASE_ADDR = g * 9;
        wire [5:0] addr = BASE_ADDR + {2'b00, fret};
        note_phase_table u_table (
            .addr(addr), .phase_inc(selected_phase[g*32 +: 32])
        );
        assign release_now[g] = stable_valid &&
            (previous_fret[g*4 +: 4] != 0) && (fret == 0) &&
            voice_active[g] && !damped[g];
        // This bypass gives a fresh pluck its selected pitch on the very
        // same sample as Attack, including a new open-string pluck.
        assign target_phase_inc[g*32 +: 32] = note_on[g] ?
            selected_phase[g*32 +: 32] : release_now[g] ?
            smoothed_phase_inc[g*32 +: 32] : held_target[g*32 +: 32];
    end endgenerate

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            previous_fret <= 16'd0;
            pending_pluck <= 4'd0;
            pending_release <= 4'd0;
            damped <= 4'd0;
            held_target <= {32'h00C879A3, 32'h010B9A2B,
                            32'h0151285D, 32'h01C20D2F};
        end
        else begin
            if (sample_tick) begin
                pending_pluck <= 4'd0;
                pending_release <= 4'd0;
            end
            else begin
                pending_pluck <= launch_mask;
                pending_release <= (pending_release | release_now) &
                                   ~launch_mask;
            end
            if (stable_valid)
                previous_fret <= stable_fret_id;

            for (i = 0; i < 4; i = i + 1) begin
                if (stable_valid) begin
                    if (release_now[i]) begin
                        held_target[i*32 +: 32] <=
                            smoothed_phase_inc[i*32 +: 32];
                        damped[i] <= 1'b1;
                    end
                    else if (!voice_active[i] ||
                             (!damped[i] &&
                              stable_fret_id[i*4 +: 4] != 0)) begin
                        held_target[i*32 +: 32] <=
                            selected_phase[i*32 +: 32];
                    end
                end
                if (note_on[i]) begin
                    held_target[i*32 +: 32] <= selected_phase[i*32 +: 32];
                    damped[i] <= 1'b0;
                end
            end
        end
    end
endmodule
