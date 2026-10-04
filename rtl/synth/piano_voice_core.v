`include "../config/guitar_config.vh"

// Eight independent modal DDS oscillators plus a 42.7-ms hammer residual ROM.
// One shared pipeline per voice completes a frame in 61 reference clocks.
// Envelope interpolation is between observations every 512 audio samples.
// All playback state and synthesis run in FPGA logic; the original WAVs are
// used offline only. Their wet envelopes are an initial timbre approximation.
module piano_voice_core #(
    parameter integer HAMMER_ENABLE = 1,
    parameter integer MAX_SAMPLES = 131072,
    parameter integer RELEASE_SHIFT = 10,
    parameter integer FORCE_PROFILE = -1
) (
    input wire clk, rst_n, sample_ce, note_on, note_off,
    input wire [1:0] velocity_level,
    input wire [31:0] phase_inc,
    output reg sample_valid,
    output reg signed [23:0] pcm_out,
    output reg active,
    output reg busy,
    output reg deadline_miss,
    output reg [1:0] profile
);
    localparam [3:0] IDLE=0, LOAD=1, INC=2, PHASE=3, LOOKUP=4,
                     MULT=5, ACC=6, HAMMER=7, VELOCITY=8, RELEASE=9, OUT=10, ENV_B=11;
    reg [3:0] state;
    reg [2:0] mode_index;
    reg [16:0] age;
    reg [16:0] frame_age;
    reg releasing;
    reg [23:0] release_level;
    reg [8:0] velocity_gain;
    reg [31:0] increment_latched;
    reg frame_active;
    reg [31:0] mode_phase [0:7];
    reg [31:0] phase_seed [0:23];
    reg [23:0] ratio_rom [0:23];
    reg [15:0] envelope_rom [0:6143];
    reg signed [15:0] hammer_rom [0:6143];
    reg signed [15:0] sine_rom [0:1023];
    reg [23:0] ratio;
    reg [15:0] env_a, env_b, env_read, amplitude;
    reg [25:0] envelope_weight_a, envelope_weight_b;
    reg [55:0] ratio_product;
    reg [31:0] next_phase;
    reg mode_enabled;
    reg signed [15:0] sine_value;
    reg signed [32:0] mode_product;
    reg signed [27:0] accumulator;
    reg signed [15:0] hammer_value;
    reg signed [37:0] velocity_product;
    reg signed [44:0] release_product;
    reg signed [23:0] continuity;
    integer i;

    wire [1:0] selected_profile = (FORCE_PROFILE >= 0) ? FORCE_PROFILE[1:0] :
        (phase_inc < 32'd26276679) ? 2'd0 :
        (phase_inc < 32'd32164062) ? 2'd1 : 2'd2;
    wire [7:0] frame = frame_age[16:9];
    wire [7:0] next_frame = (frame == 255) ? 8'd255 : frame + 1'b1;
    wire [12:0] env_addr_a = {profile,mode_index,frame};
    wire [12:0] env_addr_b = {profile,mode_index,next_frame};
    wire [12:0] env_read_address=(state==ENV_B)?env_addr_b:env_addr_a;
    // Unsigned convex interpolation keeps both operands nonnegative. Gowin
    // 1.9.12.03 mapped the former signed (b-a)*fraction into a DSP pre-adder
    // with an incorrect sign extension after narrowing the envelope ROM.
    // These two explicit products retain the same floor-rounded samples.
    wire [9:0] envelope_fraction = {1'b0,frame_age[8:0]};
    wire [9:0] envelope_inverse = 10'd512-envelope_fraction;
    wire [26:0] envelope_sum = {1'b0,envelope_weight_a}+{1'b0,envelope_weight_b};
    wire signed [27:0] component = {{2{mode_product[32]}},mode_product[32:7]};
    wire signed [27:0] hammer_component = {{4{hammer_value[15]}},hammer_value,8'd0};
    wire signed [27:0] with_hammer = accumulator + hammer_component;
    wire signed [27:0] after_velocity = velocity_product[35:8];
    wire signed [28:0] after_release = release_product[44:16];
    wire signed [28:0] final_value = after_release + {{5{continuity[23]}},continuity};
    wire [23:0] release_delta = ((release_level >> RELEASE_SHIFT)==0) ?
                                24'd1 : (release_level >> RELEASE_SHIFT);
    wire signed [23:0] continuity_delta = continuity >>> 6;

    initial begin
        $readmemh("../../mem/sine_lut.mem",sine_rom);
        $readmemh("../../mem/piano_ratio.mem",ratio_rom);
        $readmemh("../../mem/piano_phase.mem",phase_seed);
        $readmemh("../../mem/piano_envelope.mem",envelope_rom);
        $readmemh("../../mem/piano_hammer.mem",hammer_rom);
    end

    function [8:0] gain_for_velocity;
        input [1:0] level;
        begin
            case(level)
                0: gain_for_velocity=9'd112;
                1: gain_for_velocity=9'd160;
                2: gain_for_velocity=9'd208;
                default: gain_for_velocity=9'd256;
            endcase
        end
    endfunction
    function signed [23:0] saturate;
        input signed [28:0] value;
        begin
            if(value>29'sd8388607) saturate=24'sh7fffff;
            else if(value < -29'sd8388608) saturate=24'sh800000;
            else saturate=value[23:0];
        end
    endfunction

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE; mode_index<=0; age<=0; frame_age<=0;
            active<=0; busy<=0; deadline_miss<=0; sample_valid<=0; pcm_out<=0;
            profile<=0; releasing<=0; release_level<=0; velocity_gain<=0;
            increment_latched<=0; frame_active<=0; ratio<=0; env_a<=0; env_b<=0;env_read<=0;
            amplitude<=0; envelope_weight_a<=0; envelope_weight_b<=0;
            ratio_product<=0; next_phase<=0; mode_enabled<=0;
            sine_value<=0; mode_product<=0; accumulator<=0; hammer_value<=0;
            velocity_product<=0; release_product<=0; continuity<=0;
            for(i=0;i<8;i=i+1) mode_phase[i]<=0;
        end else begin
            sample_valid<=0;
            // Two neighboring frames share one physical ROM read port rather
            // than duplicating the whole envelope ROM for interpolation.
            if(state==LOAD || state==ENV_B)env_read<=envelope_rom[env_read_address];
            if(sample_ce) begin
                if(busy) deadline_miss<=1;
                else begin
                    busy<=1; state<=LOAD; mode_index<=0; accumulator<=0;
                    increment_latched<=phase_inc;
                    frame_active<=active | note_on;
                    frame_age<=age;
                    // Same-sample pluck wins over damping, as in play control.
                    if(note_on) begin
                        active<=1; releasing<=0; release_level<=24'hffffff;
                        velocity_gain<=gain_for_velocity(velocity_level);
                        profile<=selected_profile; age<=0; frame_age<=0;
                        // Preserve waveform continuity on rapid re-strikes.
                        continuity<=pcm_out;
                        for(i=0;i<8;i=i+1)
                            mode_phase[i]<=phase_seed[{selected_profile,3'b000}+i];
                    end else begin
                        if(continuity > -64 && continuity < 64) continuity<=0;
                        else continuity<=continuity-continuity_delta;
                        if(active) begin
                            if(note_off) releasing<=1;
                            if(age >= MAX_SAMPLES-1 || (releasing && release_level<=256)) begin
                                active<=0; release_level<=0; continuity<=0;
                            end else begin
                                age<=age+1'b1;
                                if(releasing) release_level<=release_level-release_delta;
                            end
                        end
                    end
                end
            end
            case(state)
                LOAD: begin
                    ratio<=ratio_rom[{profile,mode_index}];
                    state<=ENV_B;
                end
                ENV_B: begin
                    env_a<=env_read;
                    state<=INC;
                end
                INC: begin env_b<=env_read;ratio_product<=increment_latched*ratio; state<=PHASE; end
                PHASE: begin
                    envelope_weight_a<=env_a*envelope_inverse;
                    envelope_weight_b<=env_b*envelope_fraction;
                    next_phase<=mode_phase[mode_index]+ratio_product[51:20];
                    mode_phase[mode_index]<=mode_phase[mode_index]+ratio_product[51:20];
                    // Suppress modes above Nyquist, without folding them down.
                    mode_enabled<=frame_active && ratio_product[55:51]==0;
                    state<=LOOKUP;
                end
                LOOKUP: begin
                    sine_value<=sine_rom[next_phase[31:22]];
                    amplitude<=mode_enabled ? envelope_sum[24:9] : 16'd0;
                    state<=MULT;
                end
                MULT: begin
                    mode_product<=$signed(sine_value)*$signed({1'b0,amplitude});
                    state<=ACC;
                end
                ACC: begin
                    accumulator<=accumulator+component;
                    if(mode_index==7) state<=HAMMER;
                    else begin mode_index<=mode_index+1'b1; state<=LOAD; end
                end
                HAMMER: begin
                    if(HAMMER_ENABLE!=0 && frame_active && frame_age<2048)
                        hammer_value<=hammer_rom[{profile,frame_age[10:0]}];
                    else hammer_value<=0;
                    state<=VELOCITY;
                end
                VELOCITY: begin
                    velocity_product<=with_hammer*$signed({1'b0,velocity_gain});
                    state<=RELEASE;
                end
                RELEASE: begin
                    release_product<=after_velocity*$signed({1'b0,release_level[23:8]});
                    state<=OUT;
                end
                OUT: begin pcm_out<=saturate(final_value); sample_valid<=1; busy<=0; state<=IDLE; end
                default: begin end
            endcase
        end
    end
endmodule
