`timescale 1ns/1ps
// Compile the post-synthesis main netlist with the vendor primitive models
// and a renamed RTL reference. Compare the words sampled on actual DAC pins.
module piano_gate_adc_model(input cs_n,sclk,mosi,input [3:0] mask,output reg miso=0);
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

module tb_piano_gate_audio;
    reg clk=0;always #40.690104 clk=~clk;
    reg rst_n=0;
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
    neo_guitar_main_top gate (
        .audio_clk_12m288(clk),.rst_n(rst_n),
        .ROW0(row_gate[0]),.ROW1(row_gate[1]),.ROW2(row_gate[2]),.ROW3(row_gate[3]),
        .COL0(col_gate[0]),.COL1(col_gate[1]),.COL2(col_gate[2]),.COL3(col_gate[3]),
        .COL4(col_gate[4]),.COL5(col_gate[5]),.COL6(col_gate[6]),.COL7(col_gate[7]),
        .adc_cs_n(cs_gate),.adc_sclk(sclk_gate),.adc_mosi(mosi_gate),.adc_miso(miso_gate),
        .dac_bclk(bclk_gate),.dac_lrck(lrck_gate),.dac_din(din_gate),.pa_en_n(),.event_led());
    rtlref_neo_guitar_main_top reference (
        .audio_clk_12m288(clk),.rst_n(rst_n),
        .ROW0(row_rtl[0]),.ROW1(row_rtl[1]),.ROW2(row_rtl[2]),.ROW3(row_rtl[3]),
        .COL0(col_rtl[0]),.COL1(col_rtl[1]),.COL2(col_rtl[2]),.COL3(col_rtl[3]),
        .COL4(col_rtl[4]),.COL5(col_rtl[5]),.COL6(col_rtl[6]),.COL7(col_rtl[7]),
        .adc_cs_n(cs_rtl),.adc_sclk(sclk_rtl),.adc_mosi(mosi_rtl),.adc_miso(miso_rtl),
        .dac_bclk(bclk_rtl),.dac_lrck(lrck_rtl),.dac_din(din_rtl),.pa_en_n(),.event_led());
    piano_gate_adc_model adc_gate(cs_gate,sclk_gate,mosi_gate,adc_mask,miso_gate);
    piano_gate_adc_model adc_rtl(cs_rtl,sclk_rtl,mosi_rtl,adc_mask,miso_rtl);
    reg [31:0] word_gate=0,word_rtl=0;
    integer bit_index=0,frames=0,mismatches=0,nonzero=0;
    integer output_file;
    always @(negedge rst_n)begin bit_index=0;word_gate=0;word_rtl=0;end
    always @(posedge bclk_gate)begin
        #1;
        if(rst_n)begin
            if(bclk_rtl!==1'b1 || lrck_gate!==lrck_rtl)
                $fatal(1,"FAIL: synthesized DAC frame alignment");
            word_gate={word_gate[30:0],din_gate};
            word_rtl={word_rtl[30:0],din_rtl};
            if(bit_index==31)begin
                bit_index=0;frames=frames+1;
                $fwrite(output_file,"%08h %08h\n",word_gate,word_rtl);
                if(word_rtl!=0)nonzero=nonzero+1;
                if(word_gate!==word_rtl)begin
                    mismatches=mismatches+1;
                    if(mismatches<=8)$display("MISMATCH frame=%0d gate=%08h rtl=%08h",frames,word_gate,word_rtl);
                end
            end else bit_index=bit_index+1;
        end
    end
    initial begin
        output_file=$fopen("piano_gate_serial.txt","w");
        if(!output_file)$fatal(1,"FAIL: serial export open");
        repeat(8)@(negedge clk);rst_n=1;
        #6500000;@(negedge clk);adc_mask=1; // F4 single, profile E.
        #2000000;@(negedge clk);adc_mask=0;
        #23000000;@(negedge clk);pressed=32'h10101004; // G4 E4 C4 G3.
        #7000000;
        if(reference.u_audio.stable_fret_id!==16'h5553)
            $fatal(1,"FAIL: reference matrix did not select C/E/G/G3");
        @(negedge clk);adc_mask=7;
        #2000000;@(negedge clk);adc_mask=0;
        #23000000;@(negedge clk);adc_mask=15;
        #2000000;
        if(reference.u_audio.u_board_audio_chain.voice_active!==4'hf ||
           reference.u_audio.u_board_audio_chain.piano_profile!==8'h06)
            $fatal(1,"FAIL: four voices / three reference timbre banks not exercised");
        @(negedge clk);adc_mask=0;
        #70000000;@(negedge clk);rst_n=0;
        repeat(8)@(negedge clk);rst_n=1;
        #4000000;
        $fclose(output_file);
        if(nonzero<100)$fatal(1,"FAIL: no sustained reference note");
        if(mismatches)$fatal(1,"FAIL: synthesized DAC differs: %0d/%0d frames",mismatches,frames);
        $display("PASS: %0d real 256/4 DAC frames bit-identical between synthesized GW5A primitives and RTL; %0d nonzero; single/triad/four voices, three banks, hammer/room and reset",frames,nonzero);
        $finish;
    end
endmodule
