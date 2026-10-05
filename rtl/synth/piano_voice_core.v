`include "../config/guitar_config.vh"

// Up to 32 independent modal DDS oscillators plus a short hammer residual.
// The default eight-mode path preserves the hardware-accepted piano samples.
// Envelope interpolation is between observations every 512 audio samples.
// All playback state and synthesis run in FPGA logic; the original WAVs are
// used offline only. Their wet envelopes are an initial timbre approximation.
module piano_voice_core #(
    parameter integer HAMMER_ENABLE = 1,
    parameter integer MODES = 8,
    parameter integer CONTROL_ENABLE = 0,
    parameter [20:0] HARMONY_RATIO_Q20 = 21'd1571089,
    parameter integer MAX_SAMPLES = 131072,
    parameter integer RELEASE_SHIFT = 10,
    parameter integer FORCE_PROFILE = -1
) (
    input wire clk, rst_n, sample_ce, note_on, note_off,
    input wire [1:0] velocity_level,
    input wire [31:0] phase_inc,
    input wire [8:0] timbre_blend,
    input wire sustain_enable, harmony_enable,
    output reg sample_valid,
    output reg signed [23:0] pcm_out,
    output reg active,
    output reg busy,
    output reg deadline_miss,
    output reg [1:0] profile
);
    localparam [3:0] IDLE=0, LOAD=1, INC=2, PHASE=3, LOOKUP=4,
                     MULT=5, ACC=6, HAMMER=7, VELOCITY=8, RELEASE=9, OUT=10, ENV_B=11,
                     TIMBRE=12, TIMBRE_SUM=13;
    reg [3:0] state;
    reg [4:0] mode_index;
    reg [16:0] age;
    reg [16:0] frame_age;
    reg releasing;
    reg [23:0] release_level;
    reg [8:0] velocity_gain;
    reg [8:0] frame_timbre;
    reg [3:0] damping_shift;
    reg [1:0] sustain_age_phase;
    reg [3:0] bright_decay_phase;
    reg frame_bright_decay;
    reg harmony_latched;
    reg [31:0] increment_latched;
    reg frame_active;
    reg [31:0] mode_phase [0:MODES-1];
    reg [31:0] phase_seed [0:23];
    reg [23:0] ratio_rom [0:23];
    reg [15:0] envelope_rom [0:6143];
    reg signed [15:0] hammer_rom [0:6143];
    reg signed [15:0] sine_rom [0:1023];
    reg [25:0] ratio;
    reg [15:0] env_a, env_b, env_read, amplitude;
    reg [25:0] envelope_weight_a, envelope_weight_b;
    reg [57:0] ratio_product;
    reg [52:0] harmony_product;
    reg [23:0] bright_gain [0:MODES-1];
    reg [15:0] bright_decay_rom [0:31];
    reg [39:0] bright_decay_product;
    reg [15:0] body_level, bright_amplitude;
    reg signed [32:0] bright_product;
    reg signed [27:0] bright_accumulator, blended_body;
    reg signed [37:0] piano_blend_product, bright_blend_product;
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
    wire harmony_mode = CONTROL_ENABLE!=0 && MODES==32 && harmony_latched && mode_index>=16;
    wire [4:0] local_mode = harmony_mode ? mode_index-5'd16 : mode_index;
    wire [12:0] env_addr_a = {profile,local_mode[2:0],frame};
    wire [12:0] env_addr_b = {profile,local_mode[2:0],next_frame};
    wire [12:0] env_read_address=(state==ENV_B)?env_addr_b:env_addr_a;
    // Unsigned convex interpolation keeps both operands nonnegative. Gowin
    // 1.9.12.03 mapped the former signed (b-a)*fraction into a DSP pre-adder
    // with an incorrect sign extension after narrowing the envelope ROM.
    // These two explicit products retain the same floor-rounded samples.
    wire [9:0] envelope_fraction = {1'b0,frame_age[8:0]};
    wire [9:0] envelope_inverse = 10'd512-envelope_fraction;
    wire [26:0] envelope_sum = {1'b0,envelope_weight_a}+{1'b0,envelope_weight_b};
    wire [15:0] measured_amplitude = local_mode<8 ? envelope_sum[24:9] : 16'd0;
    wire [15:0] bright_body = local_mode==0 ? envelope_sum[24:9] : body_level;
    wire [39:0] bright_amplitude_wide = bright_body*bright_gain[mode_index];
    wire signed [27:0] component = {{2{mode_product[32]}},mode_product[32:7]};
    wire signed [27:0] hammer_component = {{4{hammer_value[15]}},hammer_value,8'd0};
    wire signed [27:0] with_hammer = accumulator + hammer_component;
    wire signed [27:0] bright_component = {{2{bright_product[32]}},bright_product[32:7]};
    wire signed [38:0] blended_body_wide =
        $signed({piano_blend_product[37],piano_blend_product})+
        $signed({bright_blend_product[37],bright_blend_product});
    wire signed [27:0] timbre_source = CONTROL_ENABLE!=0 ? blended_body : with_hammer;
    wire signed [27:0] velocity_source = CONTROL_ENABLE!=0 && harmony_latched ?
        (timbre_source>>>1)+(timbre_source>>>2) : timbre_source;
    wire signed [27:0] after_velocity = velocity_product[35:8];
    wire signed [28:0] after_release = release_product[44:16];
    wire signed [28:0] final_value = after_release + {{5{continuity[23]}},continuity};
    wire [23:0] release_delta = ((release_level >> damping_shift)==0) ?
                                24'd1 : (release_level >> damping_shift);
    wire signed [23:0] continuity_delta = continuity >>> 6;

    initial begin
        $readmemh("../../mem/sine_lut.mem",sine_rom);
        $readmemh("../../mem/piano_ratio.mem",ratio_rom);
        $readmemh("../../mem/piano_phase.mem",phase_seed);
        $readmemh("../../mem/piano_envelope.mem",envelope_rom);
        $readmemh("../../mem/piano_hammer.mem",hammer_rom);
        $readmemh("../../mem/harmonic_decay_rock.mem",bright_decay_rom);
    end

    `include "../config/piano_bright_coeffs.vh"

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
            frame_timbre<=0; damping_shift<=RELEASE_SHIFT; harmony_latched<=0;
            sustain_age_phase<=0;bright_decay_phase<=0;frame_bright_decay<=0;
            harmony_product<=0; bright_decay_product<=0; body_level<=0;
            bright_amplitude<=0; bright_product<=0; bright_accumulator<=0;
            blended_body<=0; piano_blend_product<=0; bright_blend_product<=0;
            amplitude<=0; envelope_weight_a<=0; envelope_weight_b<=0;
            ratio_product<=0; next_phase<=0; mode_enabled<=0;
            sine_value<=0; mode_product<=0; accumulator<=0; hammer_value<=0;
            velocity_product<=0; release_product<=0; continuity<=0;
            for(i=0;i<MODES;i=i+1)begin mode_phase[i]<=0;bright_gain[i]<=0;end
        end else begin
            sample_valid<=0;
            // Two neighboring frames share one physical ROM read port rather
            // than duplicating the whole envelope ROM for interpolation.
            if(state==LOAD || state==ENV_B)env_read<=envelope_rom[env_read_address];
            if(sample_ce) begin
                if(busy) deadline_miss<=1;
                else begin
                    busy<=1; state<=LOAD; mode_index<=0; accumulator<=0;
                    bright_accumulator<=0;
                    increment_latched<=phase_inc;
                    frame_timbre<=CONTROL_ENABLE!=0 ? timbre_blend : 9'd0;
                    harmony_product<=phase_inc*HARMONY_RATIO_Q20;
                    frame_active<=active | note_on;
                    frame_age<=age;
                    // Modal decay is separate from oscillator phase. Slowing
                    // these envelopes therefore extends open strings without
                    // changing their pitch or stretching the hammer transient.
                    frame_bright_decay<=CONTROL_ENABLE==0 ||
                        (sustain_enable ? bright_decay_phase==0 : bright_decay_phase[1:0]==0);
                    // Same-sample pluck wins over damping, as in play control.
                    if(note_on) begin
                        active<=1; releasing<=0; release_level<=24'hffffff;
                        velocity_gain<=gain_for_velocity(velocity_level);
                        damping_shift<=RELEASE_SHIFT;
                        sustain_age_phase<=0;bright_decay_phase<=0;frame_bright_decay<=1;
                        harmony_latched<=CONTROL_ENABLE!=0 && MODES==32 && harmony_enable;
                        profile<=selected_profile; age<=0; frame_age<=0;
                        // Preserve waveform continuity on rapid re-strikes.
                        continuity<=pcm_out;
                        for(i=0;i<MODES;i=i+1)begin
                            mode_phase[i]<=i<8 ? phase_seed[{selected_profile,3'b000}+i] :
                                (CONTROL_ENABLE!=0 && harmony_enable && i>=16 && i<24) ?
                                    phase_seed[{selected_profile,3'b000}+i-16] : 32'd0;
                            bright_gain[i]<={piano_bright_gain_for(CONTROL_ENABLE!=0 && harmony_enable && i>=16 ? i-16 : i),8'd0};
                        end
                    end else begin
                        bright_decay_phase<=bright_decay_phase+1'b1;
                        sustain_age_phase<=sustain_age_phase+1'b1;
                        if(continuity > -64 && continuity < 64) continuity<=0;
                        else continuity<=continuity-continuity_delta;
                        if(active) begin
                            damping_shift<=RELEASE_SHIFT;
                            if(note_off)begin
                                releasing<=1;
                                damping_shift<=RELEASE_SHIFT;
                            end
                            if(age >= MAX_SAMPLES-1 || (releasing && release_level<=256)) begin
                                active<=0; release_level<=0; continuity<=0;
                            end else begin
                                if(CONTROL_ENABLE==0 || !sustain_enable || age<2048 || sustain_age_phase==3)
                                    age<=age+1'b1;
                                // Sustain holds the damper after release. Its
                                // natural modal envelope still decays; turning
                                // the effect off restores ordinary damping.
                                if(releasing && !(CONTROL_ENABLE!=0 && sustain_enable))
                                    release_level<=release_level-release_delta;
                            end
                        end
                    end
                end
            end
            case(state)
                LOAD: begin
                    ratio<=local_mode<8 ? {2'd0,ratio_rom[{profile,local_mode[2:0]}]} :
                        ({21'd0,local_mode}+26'd1)<<20;
                    state<=ENV_B;
                end
                ENV_B: begin
                    env_a<=env_read;
                    state<=INC;
                end
                INC: begin
                    env_b<=env_read;
                    ratio_product<=(harmony_mode ? harmony_product[51:20] : increment_latched)*ratio;
                    state<=PHASE;
                end
                PHASE: begin
                    envelope_weight_a<=env_a*envelope_inverse;
                    envelope_weight_b<=env_b*envelope_fraction;
                    next_phase<=mode_phase[mode_index]+ratio_product[51:20];
                    mode_phase[mode_index]<=mode_phase[mode_index]+ratio_product[51:20];
                    // Suppress modes above Nyquist, without folding them down.
                    mode_enabled<=frame_active && ratio_product[57:51]==0;
                    state<=LOOKUP;
                end
                LOOKUP: begin
                    sine_value<=sine_rom[next_phase[31:22]];
                    amplitude<=mode_enabled ? (harmony_mode ? measured_amplitude>>1 : measured_amplitude) : 16'd0;
                    if(local_mode==0)body_level<=envelope_sum[24:9];
                    bright_amplitude<=CONTROL_ENABLE!=0 && mode_enabled ?
                        (harmony_mode ? bright_amplitude_wide[38:23]>>1 : bright_amplitude_wide[38:23]) : 16'd0;
                    state<=MULT;
                end
                MULT: begin
                    mode_product<=$signed(sine_value)*$signed({1'b0,amplitude});
                    bright_product<=$signed(sine_value)*$signed({1'b0,bright_amplitude});
                    bright_decay_product<=bright_gain[mode_index]*bright_decay_rom[local_mode];
                    state<=ACC;
                end
                ACC: begin
                    accumulator<=accumulator+component;
                    bright_accumulator<=bright_accumulator+bright_component;
                    if(frame_bright_decay)bright_gain[mode_index]<=bright_decay_product[38:15];
                    if(mode_index==MODES-1) state<=HAMMER;
                    else begin mode_index<=mode_index+1'b1; state<=LOAD; end
                end
                HAMMER: begin
                    if(HAMMER_ENABLE!=0 && frame_active && frame_age<2048)
                        hammer_value<=hammer_rom[{profile,frame_age[10:0]}];
                    else hammer_value<=0;
                    state<=CONTROL_ENABLE!=0 ? TIMBRE : VELOCITY;
                end
                TIMBRE: begin
                    piano_blend_product<=with_hammer*$signed({1'b0,(9'd256-frame_timbre)});
                    bright_blend_product<=bright_accumulator*$signed({1'b0,frame_timbre});
                    state<=TIMBRE_SUM;
                end
                TIMBRE_SUM: begin blended_body<=blended_body_wide[35:8];state<=VELOCITY;end
                VELOCITY: begin
                    velocity_product<=velocity_source*$signed({1'b0,velocity_gain});
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
