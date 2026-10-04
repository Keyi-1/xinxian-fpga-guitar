`include "../config/guitar_config.vh"

// Balanced hard stereo with optional pitch-aware choice and smooth attenuation
// of the older member of a close, non-unison pair within one channel.
module four_voice_antibeat_allocator #(
    parameter integer ENABLE = 1,
    parameter integer NEAR_GAP_HZ = 80,
    parameter [8:0] PAIR_GAIN_Q8 = 9'd128,
    parameter [8:0] GAIN_STEP_Q8 = 9'd2
) (
    input wire clk, rst_n, sample_tick,
    input wire [3:0] note_on, voice_active,
    input wire [127:0] selected_phase_inc, audible_phase_inc,
    output reg [3:0] pan_right,
    output wire [35:0] gain_q8
);
    localparam [63:0] GAP_WIDE = (64'd4294967296 * NEAR_GAP_HZ) / `SAMPLE_RATE_HZ;
    localparam [31:0] GAP_PHASE = GAP_WIDE[31:0];
    wire [31:0] selected_gap [0:15];
    wire [31:0] audible_gap [0:15];
    genvar a, c;
    generate for (a = 0; a < 4; a = a + 1) begin : gap_a
        for (c = 0; c < 4; c = c + 1) begin : gap_c
            if (a == c) begin : same
                assign selected_gap[a*4+c] = 0;
                assign audible_gap[a*4+c] = 0;
            end else if (a < c) begin : ordered
                assign selected_gap[a*4+c] =
                    (selected_phase_inc[a*32 +: 32] >= selected_phase_inc[c*32 +: 32]) ?
                    selected_phase_inc[a*32 +: 32] - selected_phase_inc[c*32 +: 32] :
                    selected_phase_inc[c*32 +: 32] - selected_phase_inc[a*32 +: 32];
                assign audible_gap[a*4+c] =
                    (audible_phase_inc[a*32 +: 32] >= audible_phase_inc[c*32 +: 32]) ?
                    audible_phase_inc[a*32 +: 32] - audible_phase_inc[c*32 +: 32] :
                    audible_phase_inc[c*32 +: 32] - audible_phase_inc[a*32 +: 32];
            end else begin : reverse
                assign selected_gap[a*4+c] = selected_gap[c*4+a];
                assign audible_gap[a*4+c] = audible_gap[c*4+a];
            end
        end
    end endgenerate
    reg tie_right, tie_work;
    reg [3:0] plan, occupied;
    integer left_count, right_count, i, j;
    reg [31:0] left_gap, right_gap, comparison_gap;
    always @* begin
        plan = pan_right;
        occupied = voice_active;
        tie_work = tie_right;
        left_count = 0;
        right_count = 0;
        left_gap = 32'hffffffff;
        right_gap = 32'hffffffff;
        comparison_gap = 0;
        for (i = 0; i < 4; i = i + 1)
            if (voice_active[i]) begin
                if (pan_right[i]) right_count = right_count + 1;
                else left_count = left_count + 1;
            end
        for (i = 0; i < 4; i = i + 1) begin
            if (note_on[i] && !voice_active[i]) begin
                left_gap = 32'hffffffff;
                right_gap = 32'hffffffff;
                for (j = 0; j < 4; j = j + 1) begin
                    // Exact unison has no difference-frequency beating.
                    comparison_gap = (selected_gap[i*4+j] == 0) ?
                                     32'hffffffff : selected_gap[i*4+j];
                    if (occupied[j]) begin
                        if (plan[j] && comparison_gap < right_gap)
                            right_gap = comparison_gap;
                        if (!plan[j] && comparison_gap < left_gap)
                            left_gap = comparison_gap;
                    end
                end
                if (left_count < right_count) plan[i] = 0;
                else if (right_count < left_count) plan[i] = 1;
                else if (ENABLE != 0 && left_count != 0 && left_gap != right_gap)
                    plan[i] = (right_gap > left_gap);
                else begin
                    plan[i] = tie_work;
                    tie_work = ~tie_work;
                end
                occupied[i] = 1;
                if (plan[i]) right_count = right_count + 1;
                else left_count = left_count + 1;
            end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin pan_right <= 0; tie_right <= 0; end
        else if (|note_on) begin pan_right <= plan; tie_right <= tie_work; end
    end

    generate if (ENABLE == 0) begin : bypass
        assign gain_q8 = {4{9'd256}};
    end else begin : mitigation
        reg [15:0] age [0:3];
        reg [8:0] gain [0:3];
        reg [8:0] goal [0:3];
        integer v, w;
        always @* begin
            for (v = 0; v < 4; v = v + 1) goal[v] = 9'd256;
            for (v = 0; v < 4; v = v + 1)
                for (w = v+1; w < 4; w = w + 1)
                    if (voice_active[v] && voice_active[w] &&
                        pan_right[v] == pan_right[w] &&
                        audible_gap[v*4+w] != 0 && audible_gap[v*4+w] < GAP_PHASE) begin
                        if (age[v] >= age[w]) goal[v] = PAIR_GAIN_Q8;
                        else goal[w] = PAIR_GAIN_Q8;
                    end
        end
        integer k;
        always @(posedge clk) begin
            if (!rst_n) begin
                for (k = 0; k < 4; k = k + 1) begin age[k] <= 0; gain[k] <= 9'd256; end
            end else if (sample_tick) begin
                for (k = 0; k < 4; k = k + 1) begin
                    if (note_on[k] || !voice_active[k]) begin
                        age[k] <= 0;
                        gain[k] <= 9'd256;
                    end else begin
                        if (age[k] != 16'hffff) age[k] <= age[k] + 1'b1;
                        if (gain[k] < goal[k])
                            gain[k] <= (goal[k] - gain[k] <= GAIN_STEP_Q8) ?
                                       goal[k] : gain[k] + GAIN_STEP_Q8;
                        else if (gain[k] > goal[k])
                            gain[k] <= (gain[k] - goal[k] <= GAIN_STEP_Q8) ?
                                       goal[k] : gain[k] - GAIN_STEP_Q8;
                    end
                end
            end
        end
        for (a = 0; a < 4; a = a + 1) begin : pack
            assign gain_q8[a*9 +: 9] = gain[a];
        end
    end endgenerate
endmodule
