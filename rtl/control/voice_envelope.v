`include "../config/guitar_config.vh"

module voice_envelope #(
    parameter integer ATTACK_SAMPLES  = `ENV_ATTACK_SAMPLES,
    parameter integer DECAY_SAMPLES   = `ENV_DECAY_SAMPLES,
    parameter integer RELEASE_SAMPLES = `ENV_RELEASE_SAMPLES,
    parameter integer SUSTAIN_LEVEL   = `ENV_SUSTAIN_LEVEL
) (
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  sample_ce,
    input  wire                                  note_on,
    input  wire                                  note_off,
    input  wire [1:0]                            velocity_level,

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
        end
        else if (sample_ce) begin
            if (note_on) begin
                env_level <= 0;
                active    <= 1'b1;
                state     <= STATE_ATTACK;
                attack_target <= velocity_attack_target(velocity_level);
                sustain_target <= velocity_sustain_target(velocity_level);
                attack_step <= velocity_attack_step(velocity_level);
                decay_step <= velocity_decay_step(velocity_level);
                release_step <= velocity_release_step(velocity_level);
            end
            else if (note_off &&
                     state != STATE_IDLE &&
                     state != STATE_RELEASE) begin
                state  <= STATE_RELEASE;
                active <= 1'b1;
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
                        end
                        else begin
                            env_level <= env_level + attack_step;
                        end
                    end

                    STATE_DECAY: begin
                        active <= 1'b1;

                        if (env_level <= sustain_target + decay_step) begin
                            env_level <= sustain_target;
                            state     <= STATE_SUSTAIN;
                        end
                        else begin
                            env_level <= env_level - decay_step;
                        end
                    end

                    STATE_SUSTAIN: begin
                        env_level <= sustain_target;
                        active    <= 1'b1;
                    end

                    STATE_RELEASE: begin
                        if (env_level <= release_step) begin
                            env_level <= 0;
                            active    <= 1'b0;
                            state     <= STATE_IDLE;
                        end
                        else begin
                            env_level <= env_level - release_step;
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
