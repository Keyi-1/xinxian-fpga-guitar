`timescale 1ns/1ps
// Production KS kernels, independently accumulated root/fifth/full outputs.
// The host only packages these already-generated samples into listening order.
module tb_ks_fifth_audition;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,strike=0,harmony=1;
    reg [31:0] inc=0,notes[0:3];
    wire [52:0] hproduct=inc*21'd1571089;
    wire [31:0] hinc=hproduct[51:20];
    wire signed [27:0] root_value,fifth_value,mix_value,off_value,before_value;
    wire [4:0] busy;
    integer note_index,n,cycles,max_cycles=0,frames=0,file;
    integer updates[0:7];reg [63:0] energy[0:7];
    integer m;
    reg transition=0,changed=0;
    function signed [27:0] harmony_gain(input signed [27:0] x);
        harmony_gain=(x>>>1)+(x>>>2);
    endfunction
    karplus_strong_voice #(.AUDITION_PART(1)) root_dut(
        .clk(clk),.rst_n(rst_n),.start(start),.strike(strike),.enabled(1'b1),.sustain(1'b0),
        .harmony(harmony),.increment(inc),.harmony_increment(hinc),.context_index(2'd0),.value(root_value),.busy(busy[0]));
    karplus_strong_voice #(.AUDITION_PART(2)) fifth_dut(
        .clk(clk),.rst_n(rst_n),.start(start),.strike(strike),.enabled(1'b1),.sustain(1'b0),
        .harmony(harmony),.increment(inc),.harmony_increment(hinc),.context_index(2'd0),.value(fifth_value),.busy(busy[1]));
    karplus_strong_voice mix_dut(
        .clk(clk),.rst_n(rst_n),.start(start),.strike(strike),.enabled(1'b1),.sustain(1'b0),
        .harmony(harmony),.increment(inc),.harmony_increment(hinc),.context_index(2'd0),.value(mix_value),.busy(busy[2]));
    karplus_strong_voice off_dut(
        .clk(clk),.rst_n(rst_n),.start(start),.strike(strike),.enabled(1'b1),.sustain(1'b0),
        .harmony(1'b0),.increment(inc),.harmony_increment(hinc),.context_index(2'd0),.value(off_value),.busy(busy[3]));
    baseline_karplus_strong_voice before_dut(
        .clk(clk),.rst_n(rst_n),.start(start),.strike(strike),.enabled(1'b1),.sustain(1'b0),
        .harmony(1'b0),.increment(inc),.harmony_increment(hinc),.context_index(2'd0),.value(before_value),.busy(busy[4]));
    function [9:0] expected_base(input integer model,input reg mode);
        begin
            if(mode)case(model)
                0:expected_base=0;1:expected_base=336;2:expected_base=504;3:expected_base=572;
                4:expected_base=622;5:expected_base=846;6:expected_base=922;7:expected_base=978;
            endcase
            else case(model)
                0:expected_base=0;1:expected_base=336;2:expected_base=504;3:expected_base=616;
                4:expected_base=700;5:expected_base=812;6:expected_base=896;7:expected_base=964;
            endcase
        end
    endfunction
    function [8:0] expected_capacity(input integer model,input reg mode);
        begin
            if(mode)case(model)
                0:expected_capacity=336;1:expected_capacity=168;2:expected_capacity=68;3:expected_capacity=50;
                4:expected_capacity=224;5:expected_capacity=76;6:expected_capacity=56;7:expected_capacity=46;
            endcase
            else case(model)
                0:expected_capacity=336;1:expected_capacity=168;2:expected_capacity=112;3:expected_capacity=84;
                4:expected_capacity=112;5:expected_capacity=84;6:expected_capacity=68;7:expected_capacity=56;
            endcase
        end
    endfunction
    function [31:0] expected_frequency(input integer model,input reg mode);
        begin
            if(mode)case(model)
                0:expected_frequency=inc;1:expected_frequency=inc*2;2:expected_frequency=inc*5;3:expected_frequency=inc*7;
                4:expected_frequency=hinc;5:expected_frequency=hinc*3;6:expected_frequency=hinc*4;7:expected_frequency=hinc*5;
            endcase
            else case(model)
                0:expected_frequency=inc;1:expected_frequency=inc*2;2:expected_frequency=inc*3;3:expected_frequency=inc*4;
                4:expected_frequency=inc*3;5:expected_frequency=inc*4;6:expected_frequency=inc*5;7:expected_frequency=inc*6;
            endcase
        end
    endfunction
    genvar lane;
    generate for(lane=0;lane<2;lane=lane+1)begin:audit
        wire [1:0] selected=mix_dut.strings[lane].lane.current_slot[1:0];
        wire [11:0] base=mix_dut.strings[lane].lane.current_base;
        wire [8:0] capacity=mix_dut.strings[lane].lane.current_capacity;
        wire signed [17:0] data=mix_dut.write_data[lane];
        always @(posedge clk)if(rst_n)begin
            if(mix_dut.strings[lane].lane.start && mix_dut.model_increment[lane]!==expected_frequency(mix_dut.slot*2+lane,mix_dut.harmony_frame))
                $fatal(1,"wrong independent model frequency lane=%0d slot=%0d",lane,mix_dut.slot);
            if(mix_dut.write_enable[lane])begin
                if(base!==expected_base(selected*2+lane,mix_dut.harmony_frame) || capacity!==expected_capacity(selected*2+lane,mix_dut.harmony_frame))
                    $fatal(1,"wrong mode-specific RAM allocation");
                if(mix_dut.address[lane]<base || mix_dut.address[lane]>=base+capacity || mix_dut.address[lane]>1023)
                    $fatal(1,"RAM overlap/out of bank");
                if(mix_dut.strings[lane].lane.run_frame!==1)$fatal(1,"unexpected muted model");
                if(transition && changed && mix_dut.strings[lane].lane.pointer!==0)$fatal(1,"layout transition kept old pointer");
                updates[selected*2+lane]=updates[selected*2+lane]+1;
                energy[selected*2+lane]=energy[selected*2+lane]+(data<0 ? -data : data);
            end
        end
    end endgenerate
    // The gain pipeline must have settled by the original accumulation edge.
    always @(posedge clk)if(rst_n && mix_dut.running && mix_dut.preparing==0 && !mix_dut.launch && mix_dut.lane_busy==0)
        if(mix_dut.pair_q!==mix_dut.weighted_a+mix_dut.weighted_b)$fatal(1,"mix pipeline not settled");
    task frame;
        begin
            start=1;@(negedge clk);start=0;cycles=0;
            while(busy!=0)begin @(negedge clk);cycles=cycles+1;if(cycles>205)$fatal(1,"KS deadline");end
            if(cycles>max_cycles)max_cycles=cycles;
            if(^mix_value===1'bx || ^root_value===1'bx || ^fifth_value===1'bx)$fatal(1,"unknown PCM");
            if(mix_value!==root_value+fifth_value)$fatal(1,"root+fifth != complete RTL mix");
            if(off_value!==before_value)$fatal(1,"off timbre changed at frame %0d",frames);
            frames=frames+1;
        end
    endtask
    initial begin
        file=$fopen("audition_pcm.txt","w");$readmemh("notes.mem",notes);
        for(m=0;m<8;m=m+1)begin updates[m]=0;energy[m]=0;end
        for(note_index=0;note_index<4;note_index=note_index+1)begin
            rst_n=0;repeat(4)@(negedge clk);inc=notes[note_index];harmony=1;rst_n=1;
            wait(busy==0);@(negedge clk);
            for(n=0;n<72000;n=n+1)begin
                strike=n==0;frame();
                $fwrite(file,"%0d %0d %0d %0d %0d %0d %0d %0d %0d\n",note_index,n,off_value,root_value,fifth_value,mix_value,harmony_gain(root_value),harmony_gain(fifth_value),harmony_gain(mix_value));
            end
        end
        transition=1;inc=notes[0];
        for(n=0;n<256;n=n+1)begin
            strike=n==0;changed=n==32 || n==96 || n==160 || n==224;
            if(changed)harmony=~harmony;
            frame();
        end
        for(m=0;m<8;m=m+1)if(updates[m]!=288256 || energy[m]==0)$fatal(1,"unserviced independent state");
        $fclose(file);
        $display("PASS: %0d off PCM exact vs successful source; independent1.4983x state, 8 disjoint regions, root+fifth=mix; four no-strike layout changes; maxbusy=%0d",frames,max_cycles);
        $finish;
    end
endmodule
