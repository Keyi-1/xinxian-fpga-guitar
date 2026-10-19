`timescale 1ns/1ps
module tb_velocity_audio_path;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #40.690104 clk=~clk;
    reg rst_n=0,command_valid=0;reg [1:0] command_mode=1;
    reg tone=0,rock=0,chorus=0,sustain=0,harmony=0,room=0;
    reg [47:0] adc_values={4{12'd2053}};wire cs,sclk,mosi,miso,ack;
    wire [31:0] conversions;wire [5:0] outputs,oracle_outputs;
    wire valid,oracle_valid;wire signed [23:0] pcm,oracle_pcm;wire [3:0] note_guard;
    reg [7:0] expected_velocity=8'haa;integer t,g,n,attacks=0,conversions_total=0;
    integer samples=0,stats,peak,rails,sv,svabs,gain,expected_attacks;
    reg signed [63:0] energy,voice_energy,previous_energy;
    reg measuring=0,check_outputs=0;
    guitar_touch_game_audio #(.USE_P2(1),.WRITABLE(1)) dut(
      .clk(clk),.rst_n(rst_n),.command_valid(command_valid),.command_mode(command_mode),.command_ack(ack),
      .fret_col_in_n(8'hff),.command_slot(3'd3),.display_clk(clk),.display_read(1'b0),.display_address(11'd0),
      .display_data(),.timbre_load(),.timbre_code(),.overlay_valid(5'd0),.overlay_data(480'd0),
      .write_enable(1'b0),.write_address(11'd0),.write_data(96'd0),.storage_idle(),.fret_row_oe(),.fret_row_drive_n(),
      .adc_cs_n(cs),.adc_sclk(sclk),.adc_mosi(mosi),.adc_miso(miso),
      .timbre_select(tone),.rock_select(rock),.chorus_enable(chorus),.sustain_enable(sustain),.harmony_enable(harmony),.reverb_enable(room),
      .dac_bclk(outputs[0]),.dac_lrck(outputs[1]),.dac_din(outputs[2]),.i2s_bclk(outputs[3]),.i2s_ws(outputs[4]),.i2s_data(outputs[5]),
      .visual_snapshot(),.game_snapshot(),.final_pcm_valid(valid),.final_pcm(pcm),.posture_sample_tick(),.posture_performance(),
      .posture_pipeline_idle(),.posture_timbre_busy(),.posture_voice_active(),.posture_note_guard(note_guard));
    mcp3208_test_slave adc(.rst_n(rst_n),.cs_n(cs),.sclk(sclk),.mosi(mosi),.values(adc_values),.miso(miso),.conversions(conversions));
    // Same accepted synthesis chain with an independently chosen expected grade.
    // It receives actual note/phase events, never ADC-derived velocity.
    four_string_board_audio_chain #(.EXTERNAL_CONTROL_ENABLE(1),.GAME_CUE_ENABLE(1),.I2S_ENABLE(1),.USE_PIANO(1),
      .CONTROL_PHASE_VALUE_BITS(27),.PIANO_MODES(32),.PIANO_CONTROL_ENABLE(1),.PIANO_ROCK_ENABLE(1)) oracle(
      .clk_audio_ref(clk),.rst_n(rst_n),.stable_valid(1'b0),.stable_fret_id(16'd0),.pluck_valid(4'd0),.velocity_level(expected_velocity),
      .timbre_select(tone),.rock_select(rock),.chorus_enable(chorus),.sustain_enable(sustain),.harmony_enable(harmony),.reverb_enable(room),
      .sample_tick(),.pcm_mix_valid(oracle_valid),.pcm_mix(oracle_pcm),.voice_active(),.voice_pcm(),
      .dac_bclk(oracle_outputs[0]),.dac_lrck(oracle_outputs[1]),.dac_din(oracle_outputs[2]),
      .i2s_bclk(oracle_outputs[3]),.i2s_ws(oracle_outputs[4]),.i2s_data(oracle_outputs[5]),
      .display_phase_inc(),.display_note_on(),.display_voice_sample_valid(),
      .external_note_on(dut.note_on),.external_note_off(dut.note_off),.external_force_release(dut.force_release),
      .external_phase_inc(dut.target_phase),.game_cue_enable(dut.mode==2 && !dut.switching),.game_miss_event(dut.miss_event),
      .control_pipeline_idle(),.control_timbre_busy());
    always @(posedge clk)begin
      #2;
      if(rst_n)begin
        if(check_outputs && {outputs,valid,pcm}!=={oracle_outputs,oracle_valid,oracle_pcm})
          $fatal(1,"FAIL: physical ADC->grade->PCM/PT8211/I2S differs t%0d g%0d",t,g);
        if(dut.u_adc.capture_pending && (note_guard & dut.u_adc.capture_pending)!==dut.u_adc.capture_pending)
          $fatal(1,"FAIL: posture guard ignores in-progress capture");
        if(dut.note_on)attacks=attacks+1;
        if(dut.u_chain.deadline_miss)$fatal(1,"FAIL: velocity audio deadline");
        if(measuring && valid)begin
          sv=$signed(dut.voice_pcm[23:0]);voice_energy=voice_energy+$signed(sv)*$signed(sv);
          sv=$signed(pcm);energy=energy+$signed(sv)*$signed(sv);
          svabs=sv<0 ? -sv : sv;if(svabs>peak)peak=svabs;
          if(dut.u_chain.pcm16_left_out==32767 || dut.u_chain.pcm16_left_out==-32768)rails=rails+1;
          samples=samples+1;
        end
      end
    end
    task start;
      @(negedge clk);rst_n=0;command_valid=0;adc_values={4{12'd2053}};check_outputs=0;
      repeat(8)@(negedge clk);rst_n=1;repeat(260)@(negedge clk);
      command_valid=1;@(negedge clk);command_valid=0;wait(ack);wait(dut.mode==1 && !dut.switching);
      repeat(77000)@(negedge clk);check_outputs=1;
    endtask
    initial begin
      stats=$fopen("velocity_loudness.csv","w");$fwrite(stats,"timbre,level,gain_q8,samples,rms_pcm24,peak_pcm24,hard_rail_samples,voice_energy\n");
      for(t=0;t<3;t=t+1)begin
        tone=t==1;rock=t==2;previous_energy=0;
        for(g=0;g<4;g=g+1)begin
          expected_velocity={6'b101010,g[1:0]};start();expected_attacks=attacks+1;
          case(g)0:n=220;1:n=280;2:n=430;3:n=620;endcase
          adc_values[11:0]=2053+n;
          wait(dut.pluck_valid[0]);#2;if(dut.velocity[1:0]!==g[1:0])$fatal(1,"FAIL: physical velocity");
          wait(dut.note_on[0]);repeat(2)@(negedge clk);
          case(g)0:gain=64;1:gain=128;2:gain=192;3:gain=256;endcase
          if(dut.u_chain.g_piano.u_core.voice[0].u_voice.velocity_gain!==gain[8:0])$fatal(1,"FAIL: actual attack gain");
          samples=0;energy=0;voice_energy=0;peak=0;rails=0;measuring=1;
          wait(samples>=1024);@(negedge clk);measuring=0;
          if(attacks!=expected_attacks || voice_energy<=previous_energy || energy<=0 || rails!=0)
            $fatal(1,"FAIL: dynamics/order/retrigger/clipping t%0d g%0d attacks%0d rails%0d",t,g,attacks,rails);
          previous_energy=voice_energy;
          $fwrite(stats,"%0d,%0d,%0d,%0d,%f,%0d,%0d,%0d\n",t,g,gain,samples,$sqrt(real'(energy)/samples),peak,rails,voice_energy);
        end
      end
      // Exercise the unchanged effects on the same full-velocity input.
      chorus=1;sustain=1;harmony=1;room=1;expected_velocity=8'hff;start();adc_values={4{12'd2853}};
      wait(dut.note_on!=0);repeat(300000)@(negedge clk);
      $fclose(stats);
      $display("PASS: real default SPI ADC->P2 performance->all3 timbres x4 calibrated levels,1024 samples each,exact existing-gain PCM/PT8211/I2S oracle,monotone voice energy,no hard rails/extra attack/deadlines,capture guards posture,all effects");$finish;
    end
    initial begin #1000000000;$fatal(1,"FAIL: velocity audio path watchdog t%0d g%0d",t,g);end
endmodule
