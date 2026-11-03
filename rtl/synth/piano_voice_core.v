`include "../config/guitar_config.vh"

// Modal piano/wah synthesis and parallel Karplus-Strong bright strings.
// The accepted modal body is retained; the former recorded residual is removed.
// Envelope interpolation is between observations every 512 audio samples.
// Offline observations identify parameters, never a played audio waveform.
module piano_voice_core #(
    parameter integer HAMMER_ENABLE = 1,
    parameter integer KS_EXTERNAL_ENABLE = 0,
    parameter [31:0] HAMMER_SEED = 32'h6d2b79f5,
    parameter integer MODES = 8,
    parameter integer CONTROL_ENABLE = 0,
    parameter integer ROCK_ENABLE = 0,
    parameter [20:0] HARMONY_RATIO_Q20 = 21'd1571089,
    parameter integer MAX_SAMPLES = 131072,
    parameter integer RELEASE_SHIFT = 10,
    parameter integer FORCE_PROFILE = -1,
    parameter integer FORCE_RELEASE_ENABLE = 0
) (
    input wire clk, rst_n, sample_ce, note_on, note_off,
    input wire signed [27:0] ks_external_value,
    input wire ks_external_busy,
    output wire ks_request,ks_strike,ks_enabled,ks_harmony_enable,
    output wire [31:0] ks_increment,ks_harmony_increment,
    input wire [1:0] velocity_level,
    input wire [31:0] phase_inc,
    input wire [8:0] timbre_blend,
    input wire [8:0] rock_blend,
    input wire sustain_enable, harmony_enable,
    input wire force_release,
    output reg sample_valid,
    output reg signed [23:0] pcm_out,
    output reg active,
    output reg busy,
    output reg deadline_miss,
    output reg [1:0] profile
);
    localparam [3:0] IDLE=0, LOAD=1, INC=2, PHASE=3, LOOKUP=4,
                     MULT=5, ACC=6, HAMMER=7, VELOCITY=8, RELEASE=9, OUT=10, ENV_B=11,
                     TIMBRE=12, TIMBRE_SUM=13, ROCK_MIX=14, ROCK_SUM=15;
    reg [3:0] state;
    reg [4:0] mode_index;
    reg [16:0] age;
    reg [16:0] frame_age;
    reg short_piano_note;
    reg releasing;
    reg forced_releasing;
    reg [23:0] release_level;
    reg [8:0] velocity_gain;
    reg [8:0] frame_timbre;
    reg [8:0] frame_rock;
    reg [24:0] rock_envelope_rom[0:3071];
    reg [24:0] rock_env_read;
    reg [21:0] rock_env_product;
    reg [11:0] rock_interp_level;
    reg [27:0] rock_amplitude_product;
    wire [15:0] rock_gain_read;
    reg signed [32:0] rock_product;
    reg signed [27:0] rock_accumulator;
    reg signed [37:0] prior_blend_product,rock_blend_product;
    reg [3:0] damping_shift;
    reg [1:0] sustain_age_phase;
    reg harmony_latched;
    reg [31:0] increment_latched;
    reg frame_active;
    reg clear_modes,frame_initialize,frame_attack,initialize_harmony,initialize_rock;
    wire [31:0] stored_phase,mode_phase_value,mode_phase_next;
    reg [31:0] phase_seed [0:23];
    reg [23:0] ratio_rom [0:23];
    reg [15:0] envelope_rom [0:6143];
    reg signed [15:0] sine_rom [0:1023];
    reg [25:0] ratio;
    reg [15:0] env_a, env_b, env_read, amplitude;
    reg [25:0] envelope_weight_a, envelope_weight_b;
    reg [57:0] ratio_product;
    reg [52:0] harmony_product;
    reg signed [27:0] blended_body;
    reg signed [37:0] piano_blend_product, bright_blend_product;
    reg [31:0] next_phase;
    reg mode_enabled;
    reg signed [15:0] sine_value;
    reg signed [34:0] mode_product;
    reg signed [27:0] accumulator;
    reg signed [15:0] hammer_value;
    reg signed [37:0] velocity_product;
    reg signed [44:0] release_product;
    reg signed [23:0] continuity;
    integer i;

    wire [1:0] selected_profile = (FORCE_PROFILE >= 0) ? FORCE_PROFILE[1:0] :
        (phase_inc < 32'd26276679) ? 2'd0 :
        (phase_inc < 32'd32164062) ? 2'd1 : 2'd2;

    // Choose once at the strike so a timbre crossfade cannot jump the
    // envelope clock. Pure piano plays its measured body at twice the rate;
    // oscillator phase and the procedural hammer keep their original time.
    wire strike_is_piano=CONTROL_ENABLE==0 ||
        (timbre_blend==0 && (ROCK_ENABLE==0 || rock_blend==0));
    // Natural-end gating bounds a short note to age<=65535, including
    // inactive frames. Thus the doubled age cannot overflow 17 bits.
    wire [16:0] envelope_age=short_piano_note ?
        {frame_age[15:0],1'b0} : frame_age;
    wire natural_end=short_piano_note ? age>=(MAX_SAMPLES+1)/2-1 : age>=MAX_SAMPLES-1;

    wire signed [17:0] hammer_operand_a;
    wire signed [16:0] hammer_operand_b;
    wire signed [15:0] procedural_hammer_value;
    wire hammer_multiply=HAMMER_ENABLE!=0 &&
        ((state==LOAD && mode_index<=3) || (state==ENV_B && mode_index<3));
    wire signed [17:0] shared_operand_a=state==MULT ?
        $signed({{2{sine_value[15]}},sine_value}) : hammer_operand_a;
    wire signed [16:0] shared_operand_b=state==MULT ?
        $signed({1'b0,amplitude}) : hammer_operand_b;
    generate if(HAMMER_ENABLE!=0)begin : procedural_hammer
        piano_hammer_model #(.SEED(HAMMER_SEED)) u_hammer(
            .clk(clk),.rst_n(rst_n),.sample_ce(sample_ce && !busy),.note_on(note_on),
            .strike_profile(selected_profile),.profile(profile),.band(mode_index[1:0]),
            .age(age),.frame_age(frame_age),.frame_active(frame_active),
            .first_multiply(state==LOAD),
            .save_first(state==ENV_B && mode_index<3),
            .update_filter(state==PHASE && mode_index<3),
            .lowpass_ce(mode_index<3 && (state==LOAD || state==ENV_B || state==INC || state==PHASE)),
            .lowpass_stage(state==LOAD ? 2'd3 : state==ENV_B ? 2'd2 : state==INC ? 2'd1 : 2'd0),
            .capture_gain(state==ENV_B && mode_index==3),.product(mode_product),
            .operand_a(hammer_operand_a),.operand_b(hammer_operand_b),.value(procedural_hammer_value));
    end else begin : no_hammer
        assign hammer_operand_a=0;assign hammer_operand_b=0;assign procedural_hammer_value=0;
    end endgenerate

    wire signed [27:0] physical_bright;
    assign ks_request=state==LOAD && mode_index==0;
    assign ks_harmony_enable=harmony_latched;
    assign ks_strike=frame_attack;assign ks_enabled=frame_active;
    assign ks_increment=increment_latched;assign ks_harmony_increment=harmony_product[51:20];
    generate if(CONTROL_ENABLE!=0 && KS_EXTERNAL_ENABLE!=0)begin:external_ks
        assign physical_bright=ks_external_value;
    end else if(CONTROL_ENABLE!=0) begin:ks_bright
        karplus_strong_voice #(.SEED(HAMMER_SEED)) string_model(
            .clk(clk),.rst_n(rst_n),.context_index(2'd0),.start(ks_request),
            .strike(frame_attack),.enabled(frame_active),.sustain(sustain_enable),
            .harmony(harmony_latched),.increment(increment_latched),
            .harmony_increment(harmony_product[51:20]),.value(physical_bright),.busy());
    end else begin:no_ks_bright
        assign physical_bright=28'sd0;
    end endgenerate

    wire [7:0] frame = envelope_age[16:9];
    wire [7:0] next_frame = (frame == 255) ? 8'd255 : frame + 1'b1;
    wire harmony_mode = CONTROL_ENABLE!=0 && MODES==32 && harmony_latched && mode_index>=16;
    wire [4:0] local_mode = harmony_mode ? mode_index-5'd16 : mode_index;
    wire [4:0] initialize_mode=initialize_harmony && mode_index>=16 ? mode_index-5'd16 : mode_index;
    wire [31:0] initial_phase=initialize_rock ? rock_phase_for(profile,initialize_mode) :
        (mode_index<8 || (CONTROL_ENABLE!=0 && initialize_harmony && mode_index>=16 && mode_index<24)) ?
            phase_seed[{profile,mode_index[2:0]}] : 32'd0;
    assign mode_phase_value=frame_initialize ? (frame_attack ? initial_phase : 32'd0) : stored_phase;
    assign mode_phase_next=mode_phase_value+ratio_product[51:20];
    piano_mode_state_ram mode_state(.clk(clk),.read_enable(rst_n && (state==LOAD || state==ENV_B)),
        .read_gain(state==ENV_B),.address(mode_index),
        .phase_write(rst_n && state==PHASE),.gain_write(1'b0),
        .phase_data(mode_phase_next),.gain_data(24'd0),
        .phase_q(stored_phase),.gain_q());
    generate if(ROCK_ENABLE!=0)begin:rock_gain_storage
        piano_rock_gain_rom gain(.clk(clk),.read_enable(state==LOAD),
            .address({profile,local_mode}),.data(rock_gain_read));
    end else begin:no_rock_gain_storage
        assign rock_gain_read=16'd0;
    end endgenerate
    // Three measured dry-wah profiles, 32 modes x 32 envelope observations.
    // Keep the first 2048 samples intact, then play only the wah envelope at
    // half speed. DDS phase, piano/bright envelopes and pick ramp still use
    // their original clocks. No extra ROM, DSP or component cycles required.
    // age/2 + 1024 equals 2048 + (age-2048)/2 after the initial transient.
    wire [16:0] rock_age=frame_age<2048 ? frame_age :
        {1'b0,frame_age[16:1]}+17'd1024;
    // Saturate before narrowing. Interpolation multiplies ABS(delta) unsigned
    // and applies its sign in LUTs, with floor rounding for negative slopes.
    wire [4:0] rock_frame=rock_age>=31744 ? 5'd31 : rock_age[14:10];
    wire [11:0] rock_env_address={profile,local_mode,rock_frame};
    wire [12:0] rock_delta_abs=rock_env_read[12] ?
        (~rock_env_read[12:0]+13'd1) : rock_env_read[12:0];
    wire [11:0] rock_mul_operand=state==ENV_B ? rock_delta_abs[11:0] : rock_interp_level;
    wire [9:0] rock_mul_weight=state==ENV_B ? rock_age[9:0] :
        frame_age<32 ? {5'd0,frame_age[4:0]} : 10'd32;
    wire [22:0] rock_negative_round={1'b0,rock_env_product}+23'd1023;
    wire [12:0] rock_interpolated=rock_env_read[12] ?
        {1'b0,rock_env_read[24:13]}-rock_negative_round[22:10] :
        {1'b0,rock_env_read[24:13]}+{1'b0,rock_env_product[21:10]};
    wire [14:0] rock_amplitude=harmony_mode ? rock_amplitude_product[27:13]>>1 : rock_amplitude_product[27:13];
    wire signed [27:0] rock_component={{2{rock_product[32]}},rock_product[32:7]};
    wire signed [38:0] rock_body_wide=$signed({prior_blend_product[37],prior_blend_product})+
        $signed({rock_blend_product[37],rock_blend_product});
    wire [12:0] env_addr_a = {profile,local_mode[2:0],frame};
    wire [12:0] env_addr_b = {profile,local_mode[2:0],next_frame};
    wire [12:0] env_read_address=(state==ENV_B)?env_addr_b:env_addr_a;
    // Unsigned convex interpolation keeps both operands nonnegative. Gowin
    // 1.9.12.03 mapped the former signed (b-a)*fraction into a DSP pre-adder
    // with an incorrect sign extension after narrowing the envelope ROM.
    // These two explicit products retain the same floor-rounded samples.
    wire [9:0] envelope_fraction = {1'b0,envelope_age[8:0]};
    wire [9:0] envelope_inverse = 10'd512-envelope_fraction;
    wire [26:0] envelope_sum = {1'b0,envelope_weight_a}+{1'b0,envelope_weight_b};
    wire [15:0] measured_amplitude = local_mode<8 ? envelope_sum[24:9] : 16'd0;
    wire signed [27:0] component = {{2{mode_product[32]}},mode_product[32:7]};
    wire signed [27:0] hammer_component = {{4{hammer_value[15]}},hammer_value,8'd0};
    wire signed [27:0] with_hammer = accumulator + hammer_component;
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
        if(ROCK_ENABLE!=0)$readmemh("../../mem/rock_envelope.mem",rock_envelope_rom);
    end

    `include "../config/rock_coeffs.vh"

    function [8:0] gain_for_velocity;
        input [1:0] level;
        begin
            case(level)
                0: gain_for_velocity=9'd64;
                1: gain_for_velocity=9'd128;
                2: gain_for_velocity=9'd192;
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
            short_piano_note<=0;
            active<=0; busy<=0; deadline_miss<=0; sample_valid<=0; pcm_out<=0;
            profile<=0; releasing<=0; forced_releasing<=0; release_level<=0; velocity_gain<=0;
            increment_latched<=0; frame_active<=0; ratio<=0; env_a<=0; env_b<=0;env_read<=0;
            frame_timbre<=0; damping_shift<=RELEASE_SHIFT; harmony_latched<=0;
            frame_rock<=0;rock_env_read<=0;rock_amplitude_product<=0;rock_product<=0;
            rock_env_product<=0;rock_interp_level<=0;
            rock_accumulator<=0;prior_blend_product<=0;rock_blend_product<=0;
            sustain_age_phase<=0;
            harmony_product<=0;

            blended_body<=0; piano_blend_product<=0; bright_blend_product<=0;
            amplitude<=0; envelope_weight_a<=0; envelope_weight_b<=0;
            ratio_product<=0; next_phase<=0; mode_enabled<=0;
            sine_value<=0; mode_product<=0; accumulator<=0; hammer_value<=0;
            velocity_product<=0; release_product<=0; continuity<=0;
            clear_modes<=1;frame_initialize<=0;frame_attack<=0;initialize_harmony<=0;initialize_rock<=0;
        end else begin
            sample_valid<=0;
            // One physical 18 x 17 DSP, time-shared with the hammer filters.
            // The ordinary seven-clock modal schedule remains unchanged.
            if(state==MULT || hammer_multiply)
                mode_product<=shared_operand_a*shared_operand_b;
            // Two neighboring frames share one physical ROM read port rather
            // than duplicating the whole envelope ROM for interpolation.
            if(state==LOAD || state==ENV_B)env_read<=envelope_rom[env_read_address];
            if(ROCK_ENABLE!=0 && state==LOAD)
                rock_env_read<=rock_envelope_rom[rock_env_address];
            // One shared unsigned DSP: interpolate in ENV_B, apply the pick
            // ramp in PHASE. The component schedule needs no extra cycles.
            if(ROCK_ENABLE!=0 && (state==ENV_B || state==PHASE))
                rock_env_product<=rock_mul_operand*rock_mul_weight;
            if(sample_ce) begin
                if(busy) deadline_miss<=1;
                else begin
                    busy<=1; state<=LOAD; mode_index<=0; accumulator<=0;
                    rock_accumulator<=0;
                    increment_latched<=phase_inc;
                    frame_timbre<=CONTROL_ENABLE!=0 ? timbre_blend : 9'd0;
                    frame_rock<=CONTROL_ENABLE!=0 && ROCK_ENABLE!=0 ? rock_blend : 9'd0;
                    harmony_product<=phase_inc*HARMONY_RATIO_Q20;
                    frame_active<=active | note_on;
                    frame_age<=age;
                    // Lazy per-mode initialization replaces the parallel
                    // register-array reset/restrike, before each first use.
                    frame_initialize<=clear_modes || note_on;frame_attack<=note_on;clear_modes<=0;
                    // Same-sample pluck wins over damping, as in play control.
                    if(note_on) begin
                        active<=1; releasing<=0; forced_releasing<=0; release_level<=24'hffffff;
                        velocity_gain<=gain_for_velocity(velocity_level);
                        damping_shift<=RELEASE_SHIFT;
                        sustain_age_phase<=0;
                        harmony_latched<=CONTROL_ENABLE!=0 && MODES==32 && harmony_enable;
                        profile<=selected_profile; age<=0; frame_age<=0;
                        short_piano_note<=strike_is_piano;
                        // Preserve waveform continuity on rapid re-strikes.
                        continuity<=pcm_out;
                        initialize_harmony<=harmony_enable;
                        initialize_rock<=ROCK_ENABLE!=0 && rock_blend>=128;
                    end else begin
                        sustain_age_phase<=sustain_age_phase+1'b1;
                        if(continuity > -64 && continuity < 64) continuity<=0;
                        else continuity<=continuity-continuity_delta;
                        if(active) begin
                            damping_shift<=FORCE_RELEASE_ENABLE!=0 && forced_releasing ? 5'd7 : RELEASE_SHIFT;
                            if(FORCE_RELEASE_ENABLE!=0 && force_release)begin
                                releasing<=1;forced_releasing<=1;damping_shift<=7;
                            end else if(note_off)begin
                                releasing<=1;
                                damping_shift<=RELEASE_SHIFT;
                            end
                            if(natural_end || (releasing && release_level<=256)) begin
                                active<=0; release_level<=0; continuity<=0;
                            end else begin
                                if(CONTROL_ENABLE==0 || !sustain_enable || age<2048 || sustain_age_phase==3)
                                    age<=age+1'b1;
                                // Sustain holds the damper after release. Its
                                // natural modal envelope still decays; turning
                                // the effect off restores ordinary damping.
                                if(releasing && (FORCE_RELEASE_ENABLE!=0 && forced_releasing || !(CONTROL_ENABLE!=0 && sustain_enable)))
                                    release_level<=release_level-release_delta;
                            end
                        end
                    end
                end
            end
            case(state)
                LOAD: begin
                    ratio<=ROCK_ENABLE!=0 && frame_rock>=128 ? rock_ratio_for(local_mode) :
                        local_mode<8 ? {2'd0,ratio_rom[{profile,local_mode[2:0]}]} :
                        ({21'd0,local_mode}+26'd1)<<20;
                    state<=ENV_B;
                end
                ENV_B: begin
                    env_a<=env_read;
                    state<=INC;
                end
                INC: begin
                    env_b<=env_read;
                    if(ROCK_ENABLE!=0)rock_interp_level<=rock_age>=ROCK_DRY_CUTOFF ? 12'd0 : rock_interpolated[11:0];
                    ratio_product<=(harmony_mode ? harmony_product[51:20] : increment_latched)*ratio;
                    state<=PHASE;
                end
                PHASE: begin
                    envelope_weight_a<=env_a*envelope_inverse;
                    envelope_weight_b<=env_b*envelope_fraction;
                    next_phase<=mode_phase_next;
                    // Suppress modes above Nyquist, without folding them down.
                    mode_enabled<=frame_active && ratio_product[57:51]==0;
                    state<=LOOKUP;
                end
                LOOKUP: begin
                    sine_value<=sine_rom[next_phase[31:22]];
                    amplitude<=mode_enabled ? (harmony_mode ? measured_amplitude>>1 : measured_amplitude) : 16'd0;
                    rock_amplitude_product<=ROCK_ENABLE!=0 && mode_enabled ?
                        rock_env_product[16:5]*rock_gain_read : 28'd0;
                    state<=MULT;
                end
                MULT: begin
                    rock_product<=$signed(sine_value)*$signed({1'b0,rock_amplitude});
                    state<=ACC;
                end
                ACC: begin
                    accumulator<=accumulator+component;
                    rock_accumulator<=rock_accumulator+rock_component;
                    if(mode_index==MODES-1) state<=HAMMER;
                    else begin mode_index<=mode_index+1'b1; state<=LOAD; end
                end
                HAMMER: begin
                    if(HAMMER_ENABLE!=0 && frame_active && frame_age<2048)
                        hammer_value<=procedural_hammer_value;
                    else hammer_value<=0;
                    state<=CONTROL_ENABLE!=0 ? TIMBRE : VELOCITY;
                end
                TIMBRE: if(KS_EXTERNAL_ENABLE==0 || !ks_external_busy)begin
                    piano_blend_product<=with_hammer*$signed({1'b0,(9'd256-frame_timbre)});
                    bright_blend_product<=physical_bright*$signed({1'b0,frame_timbre});
                    state<=TIMBRE_SUM;
                end
                TIMBRE_SUM: begin blended_body<=blended_body_wide[35:8];state<=ROCK_ENABLE!=0 ? ROCK_MIX : VELOCITY;end
                ROCK_MIX: begin
                    // Modal-sum bound <= 16388 PCM16 units plus 2048 hammer;
                    // both sums fit far below signed 27 bits. Narrowing only
                    // redundant sign bits maps each product to one DSP slice.
                    prior_blend_product<=$signed(blended_body[26:0])*$signed({1'b0,(9'd256-frame_rock)});
                    rock_blend_product<=$signed(rock_accumulator[26:0])*$signed({1'b0,frame_rock});
                    state<=ROCK_SUM;
                end
                ROCK_SUM: begin blended_body<=rock_body_wide[35:8];state<=VELOCITY;end
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
