`include "../config/guitar_config.vh"

module voice_envelope #(
    parameter integer ATTACK_SAMPLES  = `ENV_ATTACK_SAMPLES,
    parameter integer DECAY_SAMPLES   = `ENV_DECAY_SAMPLES,
    parameter integer RELEASE_SAMPLES = `ENV_RELEASE_SAMPLES,
    parameter integer SUSTAIN_LEVEL   = `ENV_SUSTAIN_LEVEL,
    // Optional multiplier-free plucked-string mode.  The default keeps the
    // original ADSR behaviour for legacy callers; current main tops opt in.
    parameter integer PLUCK_MODE               = 0,
    parameter integer PLUCK_ATTACK_SAMPLES     = 96,
    parameter integer PLUCK_FAST_DECAY_SAMPLES = 9600,
    parameter integer PLUCK_FAST_SHIFT         = 13,
    parameter integer PLUCK_SLOW_SHIFT         = 16,
    parameter integer PLUCK_RELEASE_SHIFT      = 10,
    parameter integer PLUCK_IDLE_LEVEL         = 64
) (
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  sample_ce,
    input  wire                                  note_on,
    input  wire                                  note_off,
    input  wire [1:0]                            velocity_level,
    input  wire                                  sustain_enable,

    output reg  [`ENV_LEVEL_BITS-1:0]            env_level,
    output reg                                   active
);

    localparam integer FULL_SCALE = `ENV_FULL_SCALE;

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_ATTACK  = 3'd1;
    localparam [2:0] STATE_DECAY   = 3'd2;
    localparam [2:0] STATE_SUSTAIN = 3'd3;
    localparam [2:0] STATE_RELEASE = 3'd4;

    reg [2:0] state;
    reg [`ENV_LEVEL_BITS-1:0] attack_target;
    reg [`ENV_LEVEL_BITS-1:0] sustain_target;
    reg [`ENV_LEVEL_BITS-1:0] attack_step;
    reg [`ENV_LEVEL_BITS-1:0] decay_step;
    reg [`ENV_LEVEL_BITS-1:0] release_step;
    reg [`ENV_LEVEL_BITS-1:0] active_release_step;
    reg [31:0] pluck_decay_age;
    reg pluck_release_sustain;

    wire [`ENV_LEVEL_BITS-1:0] pluck_fast_delta;
    wire [`ENV_LEVEL_BITS-1:0] pluck_slow_delta;
    wire [`ENV_LEVEL_BITS-1:0] pluck_release_delta;
    wire [31:0] pluck_attack_step_wide;

    assign pluck_fast_delta =
        ((env_level >> PLUCK_FAST_SHIFT) == 0) ? 1'b1 :
        (env_level >> PLUCK_FAST_SHIFT);
    assign pluck_slow_delta =
        ((env_level >> PLUCK_SLOW_SHIFT) == 0) ? 1'b1 :
        (env_level >> PLUCK_SLOW_SHIFT);
    // KEY3 can prolong damping in the optional harmonic path. Capture it at
    // note_off, like ADSR, so switching later cannot abruptly change this tail.
    assign pluck_release_delta = pluck_release_sustain ?
        (((env_level >> (PLUCK_RELEASE_SHIFT + 2)) == 0) ? 1'b1 :
         (env_level >> (PLUCK_RELEASE_SHIFT + 2))) :
        (((env_level >> PLUCK_RELEASE_SHIFT) == 0) ? 1'b1 :
         (env_level >> PLUCK_RELEASE_SHIFT));

    function [`ENV_LEVEL_BITS-1:0] velocity_attack_target;
        input [1:0] velocity;
        begin
            case (velocity)
                2'd0: velocity_attack_target = 16'd12288;
                2'd1: velocity_attack_target = 16'd16384;
                2'd2: velocity_attack_target = 16'd24576;
                default: velocity_attack_target = FULL_SCALE;
            endcase
        end
    endfunction

    function [`ENV_LEVEL_BITS-1:0] velocity_sustain_target;
        input [1:0] velocity;
        begin
            case (velocity)
                2'd0: velocity_sustain_target = 16'd9216;
                2'd1: velocity_sustain_target = 16'd12288;
                2'd2: velocity_sustain_target = 16'd18432;
                default: velocity_sustain_target = SUSTAIN_LEVEL;
            endcase
        end
    endfunction

    function [`ENV_LEVEL_BITS-1:0] velocity_attack_step;
        input [1:0] velocity;
        begin
            case (velocity)
                2'd0: velocity_attack_step = 16'd384;
                2'd1: velocity_attack_step = 16'd512;
                2'd2: velocity_attack_step = 16'd768;
                default: velocity_attack_step =
                    (FULL_SCALE + ATTACK_SAMPLES - 1) / ATTACK_SAMPLES;
            endcase
        end
    endfunction

    function [`ENV_LEVEL_BITS-1:0] velocity_decay_step;
        input [1:0] velocity;
        begin
            case (velocity)
                2'd0: velocity_decay_step = 16'd3;
                2'd1: velocity_decay_step = 16'd2;
                2'd2: velocity_decay_step = 16'd2;
                default: velocity_decay_step =
                    (FULL_SCALE - SUSTAIN_LEVEL + DECAY_SAMPLES - 1)
                    / DECAY_SAMPLES;
            endcase
        end
    endfunction

    function [`ENV_LEVEL_BITS-1:0] velocity_release_step;
        input [1:0] velocity;
        begin
            case (velocity)
                2'd0: velocity_release_step = 16'd5;
                2'd1: velocity_release_step = 16'd4;
                2'd2: velocity_release_step = 16'd3;
                default: velocity_release_step =
                    (SUSTAIN_LEVEL + RELEASE_SAMPLES - 1) / RELEASE_SAMPLES;
            endcase
        end
    endfunction

    // Parameter arithmetic is 32-bit in Verilog.  The maximum quotient is
    // the 16-bit attack target itself, so the explicit low-half selection is
    // lossless and avoids an implicit 32-to-16 truncation in synthesis.
    assign pluck_attack_step_wide =
        (velocity_attack_target(velocity_level) +
         PLUCK_ATTACK_SAMPLES - 1) /
        PLUCK_ATTACK_SAMPLES;

    always @(posedge clk) begin
        if (!rst_n) begin
            env_level <= 0;
            active    <= 1'b0;
            state     <= STATE_IDLE;
            attack_target <= 0;
            sustain_target <= 0;
            attack_step <= 0;
            decay_step <= 0;
            release_step <= 0;
            active_release_step <= 0;
            pluck_decay_age <= 0;
            pluck_release_sustain <= 1'b0;
        end
        else if (sample_ce) begin
            if (note_on) begin
                env_level <= 0;
                active    <= 1'b1;
                state     <= STATE_ATTACK;
                attack_target <= velocity_attack_target(velocity_level);
                sustain_target <= velocity_sustain_target(velocity_level);
                if (PLUCK_MODE != 0)
                    attack_step <= pluck_attack_step_wide[15:0];
                else
                    attack_step <= velocity_attack_step(velocity_level);
                decay_step <= velocity_decay_step(velocity_level);
                release_step <= velocity_release_step(velocity_level);
                active_release_step <= velocity_release_step(velocity_level);
                pluck_decay_age <= 0;
                pluck_release_sustain <= 1'b0;
            end
            else if (note_off &&
                     state != STATE_IDLE &&
                     state != STATE_RELEASE) begin
                state  <= STATE_RELEASE;
                pluck_release_sustain <= sustain_enable;
                active <= 1'b1;
                if (sustain_enable) begin
                    if ((release_step >> 2) == 0)
                        active_release_step <= 1;
                    else
                        active_release_step <= release_step >> 2;
                end
                else
                    active_release_step <= release_step;
            end
            else begin
                case (state)

                    STATE_IDLE: begin
                        env_level <= 0;
                        active    <= 1'b0;
                    end

                    STATE_ATTACK: begin
                        active <= 1'b1;

                        if (env_level + attack_step >= attack_target) begin
                            env_level <= attack_target;
                            state     <= STATE_DECAY;
                            pluck_decay_age <= 0;
                        end
                        else begin
                            env_level <= env_level + attack_step;
                        end
                    end

                    STATE_DECAY: begin
                        active <= 1'b1;

                        if (PLUCK_MODE != 0) begin
                            if (env_level <= PLUCK_IDLE_LEVEL +
                                             pluck_fast_delta) begin
                                env_level <= 0;
                                active    <= 1'b0;
                                state     <= STATE_IDLE;
                            end
                            else begin
                                env_level <= env_level - pluck_fast_delta;
                                if (pluck_decay_age >=
                                    PLUCK_FAST_DECAY_SAMPLES - 1) begin
                                    state <= STATE_SUSTAIN;
                                    pluck_decay_age <= 0;
                                end
                                else begin
                                    pluck_decay_age <= pluck_decay_age + 1'b1;
                                end
                            end
                        end
                        else if (env_level <= sustain_target + decay_step) begin
                            env_level <= sustain_target;
                            state     <= STATE_SUSTAIN;
                        end
                        else begin
                            env_level <= env_level - decay_step;
                        end
                    end

                    STATE_SUSTAIN: begin
                        if (PLUCK_MODE != 0) begin
                            if (env_level <= PLUCK_IDLE_LEVEL +
                                             pluck_slow_delta) begin
                                env_level <= 0;
                                active    <= 1'b0;
                                state     <= STATE_IDLE;
                            end
                            else begin
                                env_level <= env_level - pluck_slow_delta;
                                active    <= 1'b1;
                            end
                        end
                        else begin
                            env_level <= sustain_target;
                            active    <= 1'b1;
                        end
                    end

                    STATE_RELEASE: begin
                        if ((PLUCK_MODE != 0) &&
                            (env_level <= PLUCK_IDLE_LEVEL +
                                          pluck_release_delta)) begin
                            env_level <= 0;
                            active    <= 1'b0;
                            state     <= STATE_IDLE;
                        end
                        else if (PLUCK_MODE != 0) begin
                            env_level <= env_level - pluck_release_delta;
                            active    <= 1'b1;
                        end
                        else if (env_level <= active_release_step) begin
                            env_level <= 0;
                            active    <= 1'b0;
                            state     <= STATE_IDLE;
                        end
                        else begin
                            env_level <= env_level - active_release_step;
                            active    <= 1'b1;
                        end
                    end

                    default: begin
                        env_level <= 0;
                        active    <= 1'b0;
                        state     <= STATE_IDLE;
                    end

                endcase
            end
        end
    end

endmodule
