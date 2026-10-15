`timescale 1ns/1ps
// Touch UI -> atomic CDC -> release router -> buttons -> real audio chain.
module tb_game_p2_connection;
    GSR GSR(.GSRI(1'b1));
    reg ac=0,sc=0;always #40.690104 ac=~ac;always #10 sc=~sc;
    reg rst=0,click=0,dbl=0;reg [8:0] cx=0,cy=0;
    wire send,busy,done,valid,ack,transition,flush,load,tick,switching,miss;
    wire [1:0] command,mode,code,timbre;
    wire [2:0] page,slot;wire [4:0] destination;
    wire [255:0] snapshot,ui_snapshot;wire update;
    wire [3:0] on,off,release_voice,active;reg [3:0] pluck=0;
    wire [127:0] target,phase;wire [7:0] velocity;
    reg key=1;wire bright,rock,chorus,sustain,room,harmony;wire [1:0] space;
    wire pcm_valid;wire signed [23:0] pcm;
    integer samples=0,loads=0,nonzero=0,s,before_sample;
    touch_game_ui #(.USE_P2(1)) ui(.clk(sc),.rst_n(rst),.tick_ms(1'b0),.touch_ready(1'b1),
        .click(click),.double_click(dbl),.click_x(cx),.click_y(cy),.game_snapshot(ui_snapshot),
        .command_busy(busy),.command_done(done),.command_send(send),.command_mode(command),
        .selected_slot(slot),.display_fault(1'b0),.page(page),.flush_gesture(flush),.transition(transition));
    mode_command_cdc #(.WIDTH(5)) cdc(.src_clk(sc),.src_rst_n(rst),.src_send(send),.src_mode({slot,command}),
        .src_busy(busy),.src_done(done),.dst_clk(ac),.dst_rst_n(rst),.dst_valid(valid),.dst_mode(destination),.dst_ack(ack));
    // Requests more frequently than video; same held-word CDC protocol.
    reg [9:0] frame_counter=0;
    always @(posedge sc)frame_counter<=frame_counter+1'b1;
    game_snapshot_cdc snap(.src_clk(ac),.src_rst_n(rst),.src_snapshot(snapshot),.dst_clk(sc),.dst_rst_n(rst),
        .dst_request(frame_counter==0),.dst_snapshot(ui_snapshot),.dst_update(update));
    game_p2_mode_router #(.COUNTDOWN_SAMPLES(4)) router(.clk(ac),.rst_n(rst),.sample_tick(tick),
        .command_valid(valid),.command_mode(destination[1:0]),.command_slot(destination[4:2]),
        .stable_valid(1'b0),.fret_id(16'd0),.pluck_valid(pluck),.voice_active(active),.velocity(8'haa),.audible_phase(phase),
        .display_clk(sc),.display_read(1'b0),.display_address(11'd0),.display_data(),
        .command_ack(ack),.mode(mode),.switching(switching),.timbre_load(load),.timbre_code(code),
        .note_on(on),.note_off(off),.force_release(release_voice),.target_phase(target),.note_velocity(velocity),
        .game_snapshot(snapshot),.miss_event(miss));
    guitar_effect_buttons #(.DEBOUNCE_CYCLES(2),.EXTERNAL_TIMBRE_ENABLE(1)) buttons(.clk(ac),.rst_n(rst),
        .key_timbre_n(key),.key_chorus_n(1'b1),.key_space_n(1'b1),.load_timbre(load),.loaded_timbre(code),
        .timbre_select(bright),.rock_select(rock),.timbre_mode(timbre),.chorus_enable(chorus),.sustain_enable(sustain),
        .reverb_enable(room),.space_mode(space),.harmony_enable(harmony));
    four_string_board_audio_chain #(.EXTERNAL_CONTROL_ENABLE(1),.GAME_CUE_ENABLE(1),.I2S_ENABLE(1),.USE_PIANO(1),
        .PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) chain(
        .clk_audio_ref(ac),.rst_n(rst),.stable_valid(1'b0),.stable_fret_id(16'd0),.pluck_valid(4'd0),
        .velocity_level(velocity),.timbre_select(bright),.rock_select(rock),.chorus_enable(chorus),.sustain_enable(1'b1),
        .harmony_enable(harmony),.reverb_enable(room),.sample_tick(tick),.pcm_mix_valid(pcm_valid),.pcm_mix(pcm),
        .voice_active(active),.voice_pcm(),.display_phase_inc(phase),.display_note_on(),.display_voice_sample_valid(),
        .external_note_on(on),.external_note_off(off),.external_force_release(release_voice),.external_phase_inc(target),
        .game_cue_enable(mode==2 && !switching),.game_miss_event(miss),
        .dac_bclk(),.dac_lrck(),.dac_din(),.i2s_bclk(),.i2s_ws(),.i2s_data());
    always @(negedge ac)if(rst)begin
        if(tick)samples=samples+1;
        if(pcm_valid && pcm!=0)nonzero=nonzero+1;
        if(load)begin
            if(active!=0)$fatal(1,"FAIL: tone changed with active old voices");
            loads=loads+1;
        end
        if(|chain.deadline_miss || snapshot[234])$fatal(1,"FAIL: integrated audio/score deadline");
    end
    task tap(input integer x,y);
        @(negedge sc);cx=x;cy=y;click=1;@(negedge sc);click=0;repeat(20)@(negedge sc);
    endtask
    task settle;
        wait(!transition);repeat(20)@(negedge sc);
    endtask
    task exit_game;
        before_sample=samples;@(negedge sc);dbl=1;@(negedge sc);dbl=0;
        wait(page==0);settle();
        if(active!=0 || samples-before_sample>1920)$fatal(1,"FAIL: sustained exit deadline");
    endtask
    initial begin
        repeat(8)@(negedge ac);rst=1;
        tap(330,150);if(page!=2)$fatal(1,"FAIL: song menu");
        tap(100,242);if(page!=2 || slot!=0)$fatal(1,"FAIL: diagnostic slot enabled");
        for(s=0;s<4;s=s+1)begin
            tap(100,62+s*44);if(page!=3 || slot!=s)$fatal(1,"FAIL: touch selected wrong slot");
            tap(100,220);wait(page==4 || page==5);settle();
            if(mode!=2 || timbre!=(s==0 ? 0 : s==2 ? 2 : 1) || router.engine.active_slot!=s)
                $fatal(1,"FAIL: actual selected song/tone mismatch slot=%0d",s);
            wait(!router.engine.countdown);repeat(100)@(negedge ac);
            pluck=15;@(negedge ac);pluck=0;
            before_sample=samples;nonzero=0;wait(samples>=before_sample+1800);
            if(nonzero==0 || active==0)$fatal(1,"FAIL: selected timbre produced no audio");
            if(s==3)begin
                key=0;repeat(10)@(negedge ac);key=1;repeat(10)@(negedge ac);
                if(timbre!=2)$fatal(1,"FAIL: manual tone key disabled after automatic selection");
            end
            exit_game();tap(330,150);
        end
        // Preview uses the same selection and produces real notes without plucks.
        tap(100,150);tap(330,220);wait(page==4 || page==5);settle();
        before_sample=samples;nonzero=0;wait(samples>=before_sample+1800);
        if(mode!=3 || timbre!=2 || nonzero==0)$fatal(1,"FAIL: selected wah preview");
        force router.engine.controller.fault=1'b1;
        wait(page==6);settle();
        if(mode!=0 || active!=0)$fatal(1,"FAIL: score fault did not release and enter results");
        release router.engine.controller.fault;
        tap(100,230);if(page!=3 || slot!=2)$fatal(1,"FAIL: replay lost selected song");
        tap(330,220);wait(page==4 || page==5);settle();
        before_sample=samples;nonzero=0;wait(samples>=before_sample+1800);
        if(mode!=3 || page!=5 || nonzero==0)$fatal(1,"FAIL: stale fault canceled replay");
        exit_game();
        if(loads!=6)$fatal(1,"FAIL: repeated/missing automatic tone application");
        $display("PASS: four touch slots, disabled test slot, atomic async commands, all three actual timbres, manual tone, preview, sustained exit, fault, fresh-generation replay; %0d samples",samples);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: P2 connection watchdog");end
endmodule
