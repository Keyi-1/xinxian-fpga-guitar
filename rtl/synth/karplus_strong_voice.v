// Four voices operate concurrently. Each voice owns eight independent physical
// string states; two hardware pipelines update four slots each per audio frame.
// Eight disjoint delay regions fit one 1024x18 dual-port BSRAM at D3 and above.
module karplus_strong_voice #(parameter [31:0] SEED=32'h6d2b79f5, parameter integer CONTEXTS=1, parameter integer AUDITION_PART=0)(
    input wire clk,rst_n,start,strike,enabled,sustain,harmony,
    input wire [31:0] increment,harmony_increment,
    input wire [1:0] context_index,
    output reg signed [27:0] value,
    output wire busy
);
    reg running,launch;
    reg [3:0] preparing;
    reg [31:0] source_increment_q;
    reg [1:0] slot;
    reg strike_frame,enabled_frame,sustain_frame,harmony_frame;
    // Layout changes restart all eight loops of this voice before any address
    // or capacity changes are used. Other voices retain their own layout.
    reg [3:0] layout_valid,layout_harmony;
    wire layout_changed=layout_valid[context_index] && layout_harmony[context_index]!=harmony;
    reg [31:0] fundamental,fifth;
    wire [11:0] address[0:1];
    wire [17:0] write_data[0:1],read_data[0:1];
    wire [1:0] write_enable,read_enable,lane_busy,state_write,state_read;
    wire [5:0] state_address[0:1];
    wire [15:0] state_di[0:1],state_q[0:1];
    // The old32 RNG streams are exact linear combinations of five LFSRs.
    // Advance this basis once after every complete four-context audio frame.
    reg [31:0] noise_base0,noise_base1,noise_mix1,noise_mix2,noise_mix3;
    reg [8:0] voice_age[0:3];
    function [31:0] next_noise;
        input [31:0] x;
        begin next_noise={x[30:0],x[31]^x[21]^x[1]^x[0]};end
    endfunction
    wire [31:0] slot_noise=slot==0 ? 32'd0 : slot==1 ? noise_mix1 : slot==2 ? noise_mix2 : noise_mix3;
    wire [31:0] context_noise=context_index==0 ? 32'd0 : context_index==1 ? noise_mix1 : context_index==2 ? noise_mix2 : noise_mix3;
    wire [31:0] model_increment[0:1];
    reg [16:0] model_period[0:1];
    reg [1:0] model_period_ok;
    reg period_first_received;
    wire period_valid,period_ok;
    wire [16:0] period_result;
    ks_period_pipeline period_engine(.clk(clk),.rst_n(rst_n),
        .request(preparing==4 || preparing==5),
        .increment(preparing==4 ? model_increment[0] : model_increment[1]),
        .valid(period_valid),.period_q8(period_result),.in_range(period_ok));
    integer age_index;
    reg initializing;
    reg [3:0] clear_slot;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin initializing<=1;clear_slot<=0;end
        else if(initializing)begin
            if(clear_slot==15)initializing<=0;else clear_slot<=clear_slot+1'b1;
        end
    end
    // Compressed55-bit contexts use four16-bit words per model. One DPB,
    // one independent port per filter lane, replaces1760 context flip-flops.
    // Only the word containing validity is cleared; other fields initialize
    // lazily. Port address ranges0..63 and64..127 cannot collide.
    DPB #(.BIT_WIDTH_0(16),.BIT_WIDTH_1(16),.READ_MODE0(1'b0),.READ_MODE1(1'b0),
        .WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00)) context_state(
        .CLKA(clk),.CLKB(clk),.CEA(initializing || state_read[0] || state_write[0]),
        .CEB(initializing || state_read[1] || state_write[1]),
        .WREA(initializing || state_write[0]),.WREB(initializing || state_write[1]),
        .ADA({3'd0,1'b0,(initializing ? {clear_slot,2'd3} : state_address[0]),4'b0011}),
        .ADB({3'd0,1'b1,(initializing ? {clear_slot,2'd3} : state_address[1]),4'b0011}),
        .DIA(initializing ? 16'd0 : state_di[0]),.DIB(initializing ? 16'd0 : state_di[1]),
        .DOA(state_q[0]),.DOB(state_q[1]),.OCEA(1'b0),.OCEB(1'b0),
        .RESETA(1'b0),.RESETB(1'b0),.BLKSELA(3'd0),.BLKSELB(3'd0));
    wire signed [15:0] audio[0:1];
    wire [17:0] qa[0:CONTEXTS-1],qb[0:CONTEXTS-1];
    reg signed [27:0] sum;
    wire signed [27:0] audio_a={{12{audio[0][15]}},audio[0]};
    wire signed [27:0] audio_b={{12{audio[1][15]}},audio[1]};
    // Off gains remain128,64,32,16,16,8,16,8. Fifth mode keeps the root
    // fundamental/body and gives the new1.4983x loop its own clear voice:
    // roots[128,48,8,4], fifths[80,16,8,4]. No multiplier or extra model.
    wire signed [27:0] weighted_a=harmony_frame ?
        (slot==0 ? audio_a<<<7 : slot==1 ? audio_a<<<3 :
         slot==2 ? (audio_a<<<6)+(audio_a<<<4) : audio_a<<<3) :
        (slot==0 ? audio_a<<<7 : slot==1 ? audio_a<<<5 : audio_a<<<4);
    wire signed [27:0] weighted_b=harmony_frame ?
        (slot==0 ? (audio_b<<<5)+(audio_b<<<4) : slot==1 ? audio_b<<<2 :
         slot==2 ? audio_b<<<4 : audio_b<<<2) :
        (slot==0 ? audio_b<<<6 : slot==1 ? audio_b<<<4 : audio_b<<<3);
    reg signed [27:0] weighted_a_q,weighted_b_q,pair_q;
    // Audio is held from lane stage19 through four context-store cycles.
    // Two mix stages finish before lane_busy falls, isolating gain/add paths.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin weighted_a_q<=0;weighted_b_q<=0;pair_q<=0;end
        else begin weighted_a_q<=weighted_a;weighted_b_q<=weighted_b;pair_q<=weighted_a_q+weighted_b_q;end
    end
    wire signed [27:0] pair_value;
    // Compile-time audition isolates sums only; every loop still runs. The
    // production default0 contains the complete mix and removes these masks.
    generate if(AUDITION_PART==1)begin:audition_root
        assign pair_value=harmony_frame && slot>=2 ? 28'sd0 : pair_q;
    end else if(AUDITION_PART==2)begin:audition_fifth
        assign pair_value=harmony_frame && slot>=2 ? pair_q : 28'sd0;
    end else begin:production_mix
        assign pair_value=pair_q;
    end endgenerate
    genvar bank;
    generate for(bank=0;bank<CONTEXTS;bank=bank+1)begin:delay_banks
        DPX9B #(.BIT_WIDTH_0(18),.BIT_WIDTH_1(18),.READ_MODE0(1'b0),.READ_MODE1(1'b0),
            .WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00)) ram(
            .CLKA(clk),.CLKB(clk),.CEA((read_enable[0] || write_enable[0]) && address[0][11:10]==bank),
            .CEB((read_enable[1] || write_enable[1]) && address[1][11:10]==bank),
            .WREA(write_enable[0]),.WREB(write_enable[1]),.OCEA(1'b0),.OCEB(1'b0),
            .RESETA(1'b0),.RESETB(1'b0),.BLKSELA(3'd0),.BLKSELB(3'd0),
            .ADA({address[0][9:0],4'b0011}),.ADB({address[1][9:0],4'b0011}),
            .DIA(write_data[0]),.DIB(write_data[1]),.DOA(qa[bank]),.DOB(qb[bank]));
    end endgenerate
    assign read_data[0]=qa[address[0][11:10]];assign read_data[1]=qb[address[1][11:10]];
    assign busy=running || initializing;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            running<=0;launch<=0;preparing<=0;source_increment_q<=0;slot<=0;value<=0;sum<=0;
            strike_frame<=0;enabled_frame<=0;sustain_frame<=0;harmony_frame<=0;layout_valid<=0;layout_harmony<=0;
            fundamental<=0;fifth<=0;
            noise_base0<=(SEED^32'h12345678)|32'd1;noise_base1<=(SEED^32'h9abcdef0)|32'd1;
            noise_mix1<=32'h9e3779b8;noise_mix2<=32'h3c6ef372;noise_mix3<=32'hdaa66d2a;
            for(age_index=0;age_index<4;age_index=age_index+1)voice_age[age_index]<=0;
            model_period[0]<=0;model_period[1]<=0;model_period_ok<=0;period_first_received<=0;
        end else begin
            launch<=0;
            if(start && !running)begin
                running<=1;preparing<=3;slot<=0;sum<=0;
                strike_frame<=strike || layout_changed;enabled_frame<=enabled;sustain_frame<=sustain;harmony_frame<=harmony;
                layout_valid[context_index]<=1;layout_harmony[context_index]<=harmony;
                fundamental<=increment;fifth<=harmony_increment;
                if(strike || layout_changed)voice_age[context_index]<=0;
            end else if(initializing)begin end
            else if(preparing==3)begin
                source_increment_q<=slot>=2 && harmony_frame ? fifth : fundamental;preparing<=2;
            end else if(preparing==2)preparing<=1;
            else if(preparing==1)begin preparing<=4;period_first_received<=0;end
            else if(preparing==4)preparing<=5;
            else if(preparing==5)preparing<=6;
            else if(preparing==6)begin
                if(period_valid)begin
                    if(!period_first_received)begin
                        model_period[0]<=period_result;model_period_ok[0]<=period_ok;period_first_received<=1;
                    end else begin
                        model_period[1]<=period_result;model_period_ok[1]<=period_ok;launch<=1;preparing<=0;
                    end
                end
            end
            else if(running && !launch && lane_busy==0)begin
                if(slot==3)begin
                    value<=sum+pair_value;running<=0;
                    if(voice_age[context_index]<511)voice_age[context_index]<=voice_age[context_index]+1'b1;
                    if(context_index==CONTEXTS-1)begin
                        noise_base0<=next_noise(noise_base0);noise_base1<=next_noise(noise_base1);
                        noise_mix1<=next_noise(noise_mix1);noise_mix2<=next_noise(noise_mix2);noise_mix3<=next_noise(noise_mix3);
                    end
                end
                else begin sum<=sum+pair_value;slot<=slot+1'b1;preparing<=3;end
            end
        end
    end
    genvar k;
    generate for(k=0;k<2;k=k+1)begin:strings
        // Off layout is byte-for-byte unchanged (1020 words). Fifth layout
        // [336,168,68,50,224,76,56,46] uses exactly1024 words, no new BSRAM.
        wire [9:0] off_base=slot==0 ? (k==0 ? 10'd0 : 10'd336) :
            slot==1 ? (k==0 ? 10'd504 : 10'd616) :
            slot==2 ? (k==0 ? 10'd700 : 10'd812) : (k==0 ? 10'd896 : 10'd964);
        wire [8:0] off_capacity=slot==0 ? (k==0 ? 9'd336 : 9'd168) :
            slot==1 ? (k==0 ? 9'd112 : 9'd84) :
            slot==2 ? (k==0 ? 9'd112 : 9'd84) : (k==0 ? 9'd68 : 9'd56);
        wire [9:0] fifth_base=slot==0 ? (k==0 ? 10'd0 : 10'd336) :
            slot==1 ? (k==0 ? 10'd504 : 10'd572) :
            slot==2 ? (k==0 ? 10'd622 : 10'd846) : (k==0 ? 10'd922 : 10'd978);
        wire [8:0] fifth_capacity=slot==0 ? (k==0 ? 9'd336 : 9'd168) :
            slot==1 ? (k==0 ? 9'd68 : 9'd50) :
            slot==2 ? (k==0 ? 9'd224 : 9'd76) : (k==0 ? 9'd56 : 9'd46);
        wire [9:0] region_base=harmony_frame ? fifth_base : off_base;
        wire [8:0] region_capacity=harmony_frame ? fifth_capacity : off_capacity;
        // Off: [1,2,3,4,3,4,5,6]. On: roots[1,2,5,7],
        // fifth source x[1,3,4,5], source supplied by the existing7-semitone Q20 ratio.
        wire [31:0] off_operand_a=slot==0 ? (k==0 ? source_increment_q : source_increment_q<<1) :
            slot==1 ? (k==0 ? source_increment_q : source_increment_q<<2) :
            slot==2 ? (k==0 ? source_increment_q : source_increment_q<<2) :
            (k==0 ? source_increment_q : source_increment_q<<1);
        wire [31:0] off_operand_b=slot==1 && k==0 || slot==2 && k==0 ? source_increment_q<<1 :
            slot==3 ? source_increment_q<<2 : 32'd0;
        wire [31:0] fifth_operand_a=slot==0 ? (k==0 ? source_increment_q : source_increment_q<<1) :
            slot==1 ? (k==0 ? source_increment_q : source_increment_q<<3) :
            slot==2 ? source_increment_q : (k==0 ? source_increment_q<<2 : source_increment_q);
        wire [31:0] fifth_operand_b=slot==1 ? (k==0 ? source_increment_q<<2 : ~source_increment_q) :
            slot==2 && k==1 ? source_increment_q<<1 :
            slot==3 && k==1 ? source_increment_q<<2 : 32'd0;
        wire [31:0] operand_a=harmony_frame ? fifth_operand_a : off_operand_a;
        wire [31:0] operand_b=harmony_frame ? fifth_operand_b : off_operand_b;
        // 7f=8f+~f+1 uses the existing split carry chain, not a new32-bit subtractor.
        wire subtract_carry=harmony_frame && slot==1 && k==1;
        reg [16:0] increment_low;
        reg [15:0] increment_high_a,increment_high_b;
        reg [31:0] model_increment_q;
        assign model_increment[k]=model_increment_q;
        wire [16:0] increment_high={1'b0,increment_high_a}+{1'b0,increment_high_b}+increment_low[16];
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin increment_low<=0;increment_high_a<=0;increment_high_b<=0;model_increment_q<=0;end
            else begin
                if(preparing==2)begin
                    increment_low<={1'b0,operand_a[15:0]}+{1'b0,operand_b[15:0]}+subtract_carry;
                    increment_high_a<=operand_a[31:16];increment_high_b<=operand_b[31:16];
                end
                if(preparing==1)model_increment_q<={increment_high[15:0],increment_low[15:0]};
            end
        end
        ks_string_lane #(.SLOTS(CONTEXTS*4),.SEED(SEED ^ (k==0 ? 32'h12345678 : 32'h9abcdef0))) lane(
            .clk(clk),.rst_n(rst_n),.start(launch),.strike(strike_frame),
            .enabled(enabled_frame),.sustain(sustain_frame),.period_input(model_period[k]),.period_in_range(model_period_ok[k]),
            .frame_noise((k==0 ? noise_base0 : noise_base1)^slot_noise^context_noise),.frame_age(voice_age[context_index]),
            .slot({context_index,slot}),.base_address({context_index,region_base}),.capacity(region_capacity),
            .state_address(state_address[k]),.state_write_data(state_di[k]),.state_read_data(state_q[k]),
            .state_write(state_write[k]),.state_read(state_read[k]),
            .address(address[k]),.write_data(write_data[k]),.read_data(read_data[k]),
            .write_enable(write_enable[k]),.read_enable(read_enable[k]),.audio(audio[k]),.busy(lane_busy[k]));
    end endgenerate
endmodule

module ks_string_lane #(parameter [31:0] SEED=32'h12345678, parameter integer SLOTS=4)(
    input wire clk,rst_n,start,strike,enabled,sustain,
    input wire [16:0] period_input,
    input wire period_in_range,
    input wire [31:0] frame_noise,
    input wire [8:0] frame_age,
    input wire [3:0] slot,
    input wire [11:0] base_address,
    input wire [8:0] capacity,
    output wire [5:0] state_address,
    output wire [15:0] state_write_data,
    input wire [15:0] state_read_data,
    output wire state_write,state_read,
    output wire [11:0] address,
    output wire [17:0] write_data,
    input wire [17:0] read_data,
    output wire write_enable,read_enable,
    output reg signed [15:0] audio,
    output wire busy
);
    reg [4:0] stage;
    reg [9:0] raw_offset,first_offset;
    reg [11:0] first_address,second_address;
    reg signed [27:0] dc_delta;
    reg signed [18:0] interpolation_delta;
    reg [17:0] loss_magnitude;
    reg [8:0] rounded_loss;
    reg [8:0] pointer,delay_integer;
    // Excitation is needed for at most335 samples (capacity<=336). Saturating
    // at511 preserves all decisions formerly made by the10-bit age counter.
    reg [8:0] age;
    reg [63:0] state_buffer;
    reg [1:0] state_word_index;
    reg strike_latched;
    reg [3:0] current_slot;
    reg [11:0] current_base;
    reg [8:0] current_capacity;
    reg [7:0] fraction;
    reg [31:0] random_state;
    reg run_frame,hold_frame;
    reg [16:0] period_q8;
    reg signed [17:0] first,interpolated,previous,filtered,feedback,write_value;
    // Noise lies in [-65536,65534]; convex interpolation, averaging and loss
    // cannot enlarge it. DC tracks write_data*1024 monotonically from zero,
    // hence fits signed27 bits. The difference needs one extra sign bit.
    reg signed [26:0] dc_q12;
    wire [63:0] packed_state={9'd0,1'b1,dc_q12,previous,pointer};
    assign state_address={current_slot,state_word_index};
    assign state_write_data=packed_state[state_word_index*16+:16];
    assign state_write=rst_n && stage==26;
    assign state_read=rst_n && stage==23;
    wire signed [26:0] dc_target={write_data[16:0],10'd0};
    reg signed [18:0] difference;
    reg [25:0] interpolation_product;
    reg [17:0] difference_abs;
    reg interpolation_negative;
    wire [17:0] difference_magnitude=difference[18] ? -difference : difference;
    wire signed [18:0] filter_sum=$signed(interpolated)+$signed(previous);
    wire signed [17:0] noise_now=$signed({random_state[15:0],2'b0})>>>1;
    wire exciting=age<={1'b0,delay_integer}+10'd1;
    assign address=stage==13 ? current_base+{3'd0,pointer} :
        stage==7 ? second_address : first_address;
    assign read_enable=rst_n && (stage==6 || stage==7);
    assign write_enable=rst_n && stage==13;
    assign write_data=write_value;
    assign busy=stage!=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            raw_offset<=0;first_offset<=0;first_address<=0;second_address<=0;
            dc_delta<=0;interpolation_delta<=0;loss_magnitude<=0;rounded_loss<=0;
            current_slot<=0;current_base<=0;current_capacity<=336;
            state_buffer<=0;state_word_index<=0;strike_latched<=0;
            stage<=0;pointer<=0;age<=0;audio<=0;dc_q12<=0;run_frame<=0;hold_frame<=0;
            random_state<=SEED | 32'd1;previous<=0;first<=0;difference<=0;
            interpolated<=0;filtered<=0;feedback<=0;write_value<=0;interpolation_product<=0;interpolation_negative<=0;difference_abs<=0;
            period_q8<=0;
            delay_integer<=0;fraction<=0;
        end else begin
            case(stage)
                0: if(start) begin
                    stage<=23;state_word_index<=0;strike_latched<=strike;period_q8<=period_input;
                    current_slot<=slot;current_base<=base_address;current_capacity<=capacity;
                    run_frame<=enabled && period_in_range;hold_frame<=sustain;
                end
                23:stage<=24;
                24:begin
                    state_buffer[state_word_index*16+:16]<=state_read_data;
                    if(state_word_index==3)stage<=25;
                    else begin state_word_index<=state_word_index+1'b1;stage<=23;end
                end
                25:begin
                    pointer<=state_buffer[54] && !strike_latched ? state_buffer[8:0] : 9'd0;
                    age<=frame_age;
                    previous<=state_buffer[54] && !strike_latched ? state_buffer[26:9] : 18'd0;
                    dc_q12<=state_buffer[54] && !strike_latched ? state_buffer[53:27] : 27'd0;
                    random_state<=frame_noise;
                    stage<=5;
                end
                5: begin
                    // Two-point averaging loop filter contributes exactly half a sample.
                    delay_integer<=(period_q8-17'd128)>>8;
                    if(((period_q8-17'd128)>>8)>=current_capacity-1)run_frame<=0;
                    fraction<=period_q8[7:0]-8'd128;stage<=16;
                end
                16:begin raw_offset<={1'b0,pointer}+{1'b0,current_capacity}-{1'b0,delay_integer};stage<=17;end
                17:begin first_offset<=raw_offset>={1'b0,current_capacity} ? raw_offset-{1'b0,current_capacity} : raw_offset;stage<=18;end
                18:begin
                    first_address<=current_base+first_offset;
                    second_address<=current_base+(first_offset==0 ? {1'b0,current_capacity}-10'd1 : first_offset-10'd1);
                    stage<=6;
                end
                6: stage<=7;
                7: begin first<=$signed(read_data);stage<=8;end
                8: begin difference<=$signed(read_data)-$signed(first);stage<=28;end
                28:begin difference_abs<=difference_magnitude;interpolation_negative<=difference[18];stage<=9;end
                9: begin interpolation_product<=difference_abs*fraction;stage<=20;end
                20:begin interpolation_delta<=interpolation_negative ?
                    -$signed({1'b0,interpolation_product[25:8]}) : $signed({1'b0,interpolation_product[25:8]});stage<=10;end
                10:begin interpolated<=first+interpolation_delta;stage<=11;end
                11:begin
                    filtered<=($signed(filter_sum)+$signed({18'd0,filter_sum[18]}))>>>1;
                    previous<=exciting || !run_frame ? 18'sd0 : interpolated;stage<=21;
                end
                21:begin loss_magnitude<=filtered[17] ? -filtered : filtered;stage<=22;end
                22:begin
                    rounded_loss<=hold_frame ? {3'd0,loss_magnitude[17:12]}+{8'd0,(|loss_magnitude[11:0])} :
                        {1'b0,loss_magnitude[17:10]}+{8'd0,(|loss_magnitude[9:0])};stage<=12;
                end
                12:begin
                    feedback<=filtered[17] ? filtered+$signed({1'b0,rounded_loss}) : filtered-$signed({1'b0,rounded_loss});stage<=27;
                end
                27:begin write_value<=!run_frame ? 18'd0 : exciting ? noise_now : feedback;stage<=13;end
                13:begin dc_delta<=$signed({dc_target[26],dc_target})-$signed({dc_q12[26],dc_q12});stage<=19;end
                19:begin
                    audio<=($signed(write_data)>>>2)-(dc_q12>>>12);
                    dc_q12<=dc_q12+(dc_delta>>>10);pointer<=pointer==current_capacity-1 ? 9'd0 : pointer+1'b1;
                    state_word_index<=0;stage<=26;
                end
                26:begin
                    if(state_word_index==3)stage<=0;
                    else state_word_index<=state_word_index+1'b1;
                end
            endcase
        end
    end
endmodule

// II=1 period front-end, shared by both KS lanes. Consecutive requests carry
// their own exponent/fraction/range flags through every pipeline stage.
module ks_period_pipeline(input wire clk,rst_n,request,input wire [31:0] increment,
    output wire valid,output reg [16:0] period_q8,output reg in_range)
    /* synthesis syn_romstyle = "logic" */;
    `include "../config/ks_reciprocal.vh"
    reg [5:0] valid_pipe;
    reg [31:0] frequency0;
    reg [5:0] index1;
    reg [7:0] fraction1,fraction2;
    reg [4:0] exponent1,exponent2,exponent3,exponent4;
    reg range1,range2,range3,range4;
    reg [42:0] coefficients2;
    reg [25:0] product3;
    reg [24:0] base3,reciprocal4;
    reg [4:0] exponent;
    reg [31:0] normalized;
    integer bit_index;
    always @*begin
        exponent=23;
        for(bit_index=23;bit_index<32;bit_index=bit_index+1)
            if(frequency0[bit_index])exponent=bit_index;
        normalized=frequency0<<(31-exponent);
    end
    wire [24:0] period_wide=reciprocal4>>(exponent4-16);
    assign valid=valid_pipe[5];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            valid_pipe<=0;frequency0<=0;index1<=0;fraction1<=0;fraction2<=0;
            exponent1<=23;exponent2<=23;exponent3<=23;exponent4<=23;
            range1<=0;range2<=0;range3<=0;range4<=0;
            coefficients2<=0;product3<=0;base3<=0;reciprocal4<=0;period_q8<=0;in_range<=0;
        end else begin
            valid_pipe<={valid_pipe[4:0],request};
            if(request)frequency0<=increment;
            index1<=normalized[30:25];fraction1<=normalized[24:17];exponent1<=exponent;
            range1<=frequency0>=32'd8421505 && frequency0<=32'd536870912;
            coefficients2<=ks_reciprocal(index1);fraction2<=fraction1;exponent2<=exponent1;range2<=range1;
            product3<=coefficients2[17:0]*fraction2;base3<=coefficients2[42:18];exponent3<=exponent2;range3<=range2;
            reciprocal4<=base3-(product3>>8);exponent4<=exponent3;range4<=range3;
            period_q8<=period_wide>130560 ? 17'd130560 : period_wide<2048 ? 17'd2048 : period_wide[16:0];
            in_range<=range4;
        end
    end
endmodule
