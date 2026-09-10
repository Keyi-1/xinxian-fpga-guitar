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

    output reg  [`ENV_LEVEL_BITS-1:0]            env_level,
    output reg                                   active
);

    localparam integer FULL_SCALE = `ENV_FULL_SCALE;

    localparam integer ATTACK_STEP =
        (FULL_SCALE + ATTACK_SAMPLES - 1) / ATTACK_SAMPLES;

    localparam integer DECAY_STEP =
        (FULL_SCALE - SUSTAIN_LEVEL + DECAY_SAMPLES - 1)
        / DECAY_SAMPLES;

    localparam integer RELEASE_STEP =
        (SUSTAIN_LEVEL + RELEASE_SAMPLES - 1)
        / RELEASE_SAMPLES;

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_ATTACK  = 3'd1;
    localparam [2:0] STATE_DECAY   = 3'd2;
    localparam [2:0] STATE_SUSTAIN = 3'd3;
    localparam [2:0] STATE_RELEASE = 3'd4;

    reg [2:0] state;

    always @(posedge clk) begin
        if (!rst_n) begin
            env_level <= 0;
            active    <= 1'b0;
            state     <= STATE_IDLE;
        end
        else if (sample_ce) begin
            if (note_on) begin
                env_level <= 0;
                active    <= 1'b1;
                state     <= STATE_ATTACK;
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

                        if (env_level + ATTACK_STEP >= FULL_SCALE) begin
                            env_level <= FULL_SCALE;
                            state     <= STATE_DECAY;
                        end
                        else begin
                            env_level <= env_level + ATTACK_STEP;
                        end
                    end

                    STATE_DECAY: begin
                        active <= 1'b1;

                        if (env_level <= SUSTAIN_LEVEL + DECAY_STEP) begin
                            env_level <= SUSTAIN_LEVEL;
                            state     <= STATE_SUSTAIN;
                        end
                        else begin
                            env_level <= env_level - DECAY_STEP;
                        end
                    end

                    STATE_SUSTAIN: begin
                        env_level <= SUSTAIN_LEVEL;
                        active    <= 1'b1;
                    end

                    STATE_RELEASE: begin
                        if (env_level <= RELEASE_STEP) begin
                            env_level <= 0;
                            active    <= 1'b0;
                            state     <= STATE_IDLE;
                        end
                        else begin
                            env_level <= env_level - RELEASE_STEP;
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