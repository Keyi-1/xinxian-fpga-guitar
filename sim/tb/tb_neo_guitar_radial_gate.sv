`timescale 1ns/1ps
// Compile the post-synthesis main netlist with the vendor primitive models
// and a renamed RTL reference. Compare the words sampled on actual DAC pins.
module radial_gate_adc_model(input cs_n,sclk,mosi,input [3:0] mask,output reg miso=0);
    integer rises=0;
    reg [4:0] command=0;
    reg [11:0] code=0;
    always @(negedge cs_n)begin rises=0;miso=0;command=0;end
    always @(posedge sclk)if(!cs_n)begin
        rises=rises+1;
        if(rises<=5)command={command[3:0],mosi};
        if(rises==5)code=mask[command[1:0]]?12'd2253:12'd2053;
    end
    always @(negedge sclk)if(!cs_n)begin
        if(rises>=7 && rises<=18)miso=code[18-rises];else miso=0;
    end
endmodule

module tb_neo_guitar_radial_gate;
    reg clk=0;always #40.690104 clk=~clk;
    reg sys_clk=0;always #10 sys_clk=~sys_clk;
    reg k1=1,k2=1,k3=1;
    reg [3:0] adc_mask=0;
    reg [31:0] pressed=32'h00000001;
    tri [3:0] row_gate,row_rtl;
    wire [7:0] col_gate=(row_gate[0]===0)?~pressed[7:0]:
        (row_gate[1]===0)?~pressed[15:8]:(row_gate[2]===0)?~pressed[23:16]:
        (row_gate[3]===0)?~pressed[31:24]:8'hff;
    wire [7:0] col_rtl=(row_rtl[0]===0)?~pressed[7:0]:
        (row_rtl[1]===0)?~pressed[15:8]:(row_rtl[2]===0)?~pressed[23:16]:
        (row_rtl[3]===0)?~pressed[31:24]:8'hff;
    wire cs_gate,sclk_gate,mosi_gate,miso_gate,bclk_gate,lrck_gate,din_gate;
    wire cs_rtl,sclk_rtl,mosi_rtl,miso_rtl,bclk_rtl,lrck_rtl,din_rtl;
    wire gp,gh,gv,gd,gl,rp,rh,rv,rd,rl;
    wire [5:0] gr,gg,gb,rr,rg,rb;
    integer lcd_clocks=0,lcd_pixels=0;
    always @(posedge sys_clk)begin
        #2;
        if(reference.u_display.initialized)begin
            lcd_clocks++;
            if({gp,gh,gv,gd,gl,gr,gg,gb}!=={rp,rh,rv,rd,rl,rr,rg,rb})
                $fatal(1,"FAIL: synthesized LCD output differs at clock %0d",lcd_clocks);
        end
    end
    always @(posedge gp)if(gd)lcd_pixels++;
    neo_guitar_radial_top gate (
        .audio_clk_12m288(clk),.sys_clk_50m(sys_clk),.USER_BUTTON1_n(k1),.USER_BUTTON2_n(k2),.USER_BUTTON3_n(k3),
        .ROW0(row_gate[0]),.ROW1(row_gate[1]),.ROW2(row_gate[2]),.ROW3(row_gate[3]),
        .COL0(col_gate[0]),.COL1(col_gate[1]),.COL2(col_gate[2]),.COL3(col_gate[3]),
        .COL4(col_gate[4]),.COL5(col_gate[5]),.COL6(col_gate[6]),.COL7(col_gate[7]),
        .adc_cs_n(cs_gate),.adc_sclk(sclk_gate),.adc_mosi(mosi_gate),.adc_miso(miso_gate),
        .dac_bclk(bclk_gate),.dac_lrck(lrck_gate),.dac_din(din_gate),.pa_en_n(),.event_led(),
        .lcd_pclk(gp),.lcd_hsync(gh),.lcd_vsync(gv),.lcd_de(gd),.lcd_backlight(gl),.lcd_r(gr),.lcd_g(gg),.lcd_b(gb));
    rtlref_neo_guitar_radial_top reference (
        .audio_clk_12m288(clk),.sys_clk_50m(sys_clk),.USER_BUTTON1_n(k1),.USER_BUTTON2_n(k2),.USER_BUTTON3_n(k3),
        .ROW0(row_rtl[0]),.ROW1(row_rtl[1]),.ROW2(row_rtl[2]),.ROW3(row_rtl[3]),
        .COL0(col_rtl[0]),.COL1(col_rtl[1]),.COL2(col_rtl[2]),.COL3(col_rtl[3]),
        .COL4(col_rtl[4]),.COL5(col_rtl[5]),.COL6(col_rtl[6]),.COL7(col_rtl[7]),
        .adc_cs_n(cs_rtl),.adc_sclk(sclk_rtl),.adc_mosi(mosi_rtl),.adc_miso(miso_rtl),
        .dac_bclk(bclk_rtl),.dac_lrck(lrck_rtl),.dac_din(din_rtl),.pa_en_n(),.event_led(),
        .lcd_pclk(rp),.lcd_hsync(rh),.lcd_vsync(rv),.lcd_de(rd),.lcd_backlight(rl),.lcd_r(rr),.lcd_g(rg),.lcd_b(rb));
    radial_gate_adc_model adc_gate(cs_gate,sclk_gate,mosi_gate,adc_mask,miso_gate);
    radial_gate_adc_model adc_rtl(cs_rtl,sclk_rtl,mosi_rtl,adc_mask,miso_rtl);
    reg [31:0] word_gate=0,word_rtl=0;
    integer bit_index=0,frames=0,mismatches=0,nonzero=0,slow_wah_frames=0;
    integer output_file;
    always @(posedge bclk_gate)begin
        #1;
        if(reference.audio_rst_n)begin
            if(bclk_rtl!==1'b1 || lrck_gate!==lrck_rtl)
                $fatal(1,"FAIL: synthesized DAC frame alignment");
            word_gate={word_gate[30:0],din_gate};
            word_rtl={word_rtl[30:0],din_rtl};
            if(bit_index==31)begin
                bit_index=0;frames=frames+1;
                $fwrite(output_file,"%08h %08h\n",word_gate,word_rtl);
                if(word_rtl!=0)nonzero=nonzero+1;
                if(reference.rock_select && reference.u_audio.u_board_audio_chain.g_piano.u_core.voice[0].u_voice.frame_age>=2048)
                    slow_wah_frames=slow_wah_frames+1;
                if(word_gate!==word_rtl)begin
                    mismatches=mismatches+1;
                    if(mismatches<=8)$display("MISMATCH frame=%0d gate=%08h rtl=%08h",frames,word_gate,word_rtl);
                end
            end else bit_index=bit_index+1;
        end
    end
    // Accelerate only mechanical timing counters in BOTH designs. All audio
    // registers, ROMs, multipliers and actual DAC pins are unforced. The default
    // debounce/long constants and full-width compare logic stay in the netlist.
    task qualify;
        repeat(4)@(negedge clk);
        force gate.u_buttons.u_timbre.debounce_count=32'd245760;
        force gate.u_buttons.u_space.debounce_count=32'd245760;
        force gate.u_buttons.debounce_count=32'd245760;
        force reference.u_buttons.u_timbre.debounce_count=32'd245760;
        force reference.u_buttons.u_space.debounce_count=32'd245760;
        force reference.u_buttons.debounce_count=32'd245760;
        repeat(4)@(negedge clk);
        release gate.u_buttons.u_timbre.debounce_count;
        release gate.u_buttons.u_space.debounce_count;
        release gate.u_buttons.debounce_count;
        release reference.u_buttons.u_timbre.debounce_count;
        release reference.u_buttons.u_space.debounce_count;
        release reference.u_buttons.debounce_count;
        repeat(4)@(negedge clk);
    endtask
    task short_key(input integer key);
        if(key==1)k1=0;else if(key==2)k2=0;else k3=0;
        qualify();k1=1;k2=1;k3=1;qualify();
    endtask
    task long_key2;
        k2=0;qualify();
        force gate.u_buttons.hold_count=24'd12288000;
        force reference.u_buttons.hold_count=32'd12288000;
        repeat(3)@(negedge clk);
        release gate.u_buttons.hold_count;
        release reference.u_buttons.hold_count;
        k2=1;qualify();
    endtask
    task pluck;
        @(negedge clk);adc_mask=15;
        #2000000;@(negedge clk);adc_mask=0;
    endtask
    initial begin
        output_file=$fopen("guitar_lissajous_gate_serial.txt","w");
        if(!output_file)$fatal(1,"FAIL: serial export open");
        pressed=32'h10101004;
        #7000000;
        if(reference.u_audio.stable_fret_id!==16'h5553)
            $fatal(1,"FAIL: full reference fret selection");
        pluck();#4000000; // default accepted piano, all four voices
        short_key(1);#6000000; // 32-component bright timbre
        short_key(2);#6000000; // chorus
        short_key(3);#2000000; // sustain only
        @(negedge clk);pressed=0;
        #30000000; // real matrix release plus complete 20 ms slide to open
        if(reference.u_audio.u_board_audio_chain.phase_inc!==
           {32'h00C879A3,32'h010B9A2B,32'h0151285D,32'h01C20D2F} ||
           reference.u_audio.u_board_audio_chain.note_off!==0 ||
           reference.u_audio.u_board_audio_chain.voice_active!==15)
            $fatal(1,"FAIL: full reference release must continue at each open-string pitch");
        $display("PASS: synthesized/RTL real-matrix four-string open release, no fret damping");
        @(negedge clk);pressed=32'h10101004;
        #7000000;
        short_key(3);#6000000; // light room, sustain off
        long_key2();#1000000;
        if(!reference.harmony_enable||!reference.chorus_enable||!reference.reverb_enable)
            $fatal(1,"FAIL: full reference key states / long hold");
        pluck();#6000000; // actual additional fifth oscillators on new strike
        if(reference.u_audio.u_board_audio_chain.voice_active!==15)
            $fatal(1,"FAIL: four FULL voices");
        short_key(1);#6000000; // rock crossfade + fifth + chorus + light room
        if(!reference.rock_select||reference.timbre_mode!=2)$fatal(1,"FAIL: rock key state");
        pluck();#60000000; // measured wah, including transition to half-speed envelope after 2048 samples
        short_key(1);#6000000; // return piano + fifth + chorus + light room
        if(reference.rock_select||reference.timbre_mode!=0)$fatal(1,"FAIL: three-tone wrap");
        short_key(2);short_key(3);long_key2();#6000000;
        if(reference.space_mode!=0||reference.chorus_enable||reference.harmony_enable)
            $fatal(1,"FAIL: controls did not return to dry");
        $fclose(output_file);
        if(nonzero<100)$fatal(1,"FAIL: no nonzero FULL audio");
        if(slow_wah_frames<500)$fatal(1,"FAIL: half-speed wah gate coverage %0d",slow_wah_frames);
        if(mismatches)$fatal(1,"FAIL: FULL synthesized DAC differs %0d/%0d",mismatches,frames);
        $display("PASS: %0d actual DAC frames bit-identical; 4x32 piano/bright/rock, chorus, independent sustain/light room, fifth harmony, power-on initialization; %0d nonzero, %0d half-speed wah frames",frames,nonzero,slow_wah_frames);
        if(lcd_pixels<500000)$fatal(1,"FAIL: insufficient synthesized LCD coverage");
        $display("PASS: synthesized LCD %0d board clocks, %0d visible pixels EXACTLY match native-pixel RTL, scanline BRAM/ROM/CDC/palette",lcd_clocks,lcd_pixels);
        $finish;
    end
endmodule
