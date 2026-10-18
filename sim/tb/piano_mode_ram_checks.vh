    reg [31:0] expected_phase[0:31];reg [23:0] expected_gain[0:31];
    integer i,j,reads=0,writes=0;reg [31:0] pattern,held_phase;reg [23:0] held_gain;
    task automatic read_word(input integer row);
        begin
            @(negedge clk);address=row;read_enable=1;read_gain=0;phase_write=0;gain_write=0;
            @(posedge clk);#1;
            @(negedge clk);read_gain=1;
            @(posedge clk);#1;
            if(phase_q!==expected_phase[row] || gain_q!==expected_gain[row])$fatal(1,"FAIL: modal RAM row%0d",row);
            held_phase=phase_q;held_gain=gain_q;reads=reads+1;
            @(negedge clk);read_enable=0;read_gain=0;address=~row;
            repeat(2)begin @(posedge clk);#1;
                if(phase_q!==held_phase || gain_q!==held_gain)$fatal(1,"FAIL: modal RAM read-enable hold");end
        end
    endtask
    task automatic write_word(input integer row,input bit wp,wg,input [31:0] pd,input [23:0] gd);
        begin
            if(wp && wg)$fatal(1,"FAIL: mode-state write collision");
            @(negedge clk);address=row;read_enable=0;read_gain=0;phase_write=wp;gain_write=wg;phase_data=pd;gain_data=gd;
            @(posedge clk);#1;
            if(wp)expected_phase[row]=pd;if(wg)expected_gain[row]=gd;
            writes=writes+1;
            @(negedge clk);phase_write=0;gain_write=0;
        end
    endtask
    initial begin
        for(i=0;i<32;i=i+1)begin expected_phase[i]=0;expected_gain[i]=0;end
        for(i=0;i<32;i=i+1)read_word(i);
        for(j=0;j<3;j=j+1)for(i=0;i<32;i=i+1)begin
            pattern=(32'h9e3779b9*i)^(32'h80808080*j);
            write_word(i,1,0,pattern,24'hffffff);read_word(i);
            write_word(i,0,1,32'hffffffff,~pattern[23:0]);read_word(i);
            write_word(i,1,0,~pattern,0);write_word(i,0,1,0,pattern[23:0]);read_word(i);
        end
        for(i=31;i>=0;i=i-1)read_word(i);
        $display("PASS: modal state RAM %0d reads/%0d writes, every32-bit phase/24-bit gain byte and all32 addresses, independent writes/preservation, synchronous read/enable hold, no read-write collision",reads,writes);
        $finish;
    end
    initial begin #100000;$fatal(1,"FAIL: modal RAM watchdog");end
