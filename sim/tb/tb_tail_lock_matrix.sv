`timescale 1ns/1ps
module tb_tail_lock_matrix;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tracking=0;
    reg [15:0] physical=0;
    reg [7:0] columns,meta=255,sync=255;
    wire [3:0] row,drive,old_row,old_drive,released;
    wire frame,stable,old_frame,old_stable;
    wire [31:0] raw_mask,stable_mask,old_mask,old_stable_mask;
    wire [15:0] fret,raw_fret,old_fret,old_raw;
    integer pulses[0:3],zeros,merged=0,cases=0,clock_checks=0;
    always @*begin
        columns=255;
        for(integer s=0;s<4;s=s+1)if(row[s] && physical[s*4+:4]!=0)
            columns=~(8'b1<<(physical[s*4+:4]-1));
    end
    matrix_scanner #(.CLK_DIV(768),.SETTLE_CYCLES(3),.DEBOUNCE_FRAMES(5)) dut(
        .clk(clk),.rst_n(rst_n),.col_in_n(sync),.row_oe(row),.row_drive_n(drive),
        .frame_valid(frame),.fret_mask(raw_mask),.fret_id(raw_fret),
        .stable_valid(stable),.stable_fret_mask(stable_mask),.stable_fret_id(fret),.release_event(released));
    tail_before_matrix_scanner #(.CLK_DIV(768),.SETTLE_CYCLES(3),.DEBOUNCE_FRAMES(5)) frozen(
        .clk(clk),.rst_n(rst_n),.col_in_n(sync),.row_oe(old_row),.row_drive_n(old_drive),
        .frame_valid(old_frame),.fret_mask(old_mask),.fret_id(old_raw),
        .stable_valid(old_stable),.stable_fret_mask(old_stable_mask),.stable_fret_id(old_fret));
    always @(posedge clk)begin
        if(!rst_n)begin meta<=255;sync<=255;end else begin meta<=columns;sync<=meta;end
        #1;
        if({row,drive,frame,raw_mask,raw_fret,stable,stable_mask,fret}!==
           {old_row,old_drive,old_frame,old_mask,old_raw,old_stable,old_stable_mask,old_fret})
            $fatal(1,"FAIL: original matrix outputs changed");
        clock_checks=clock_checks+1;
        if(tracking)begin
            for(integer i=0;i<4;i=i+1)if(released[i])pulses[i]=pulses[i]+1;
            if(stable && fret==0)zeros=zeros+1;
        end
    end
    integer g,offset,gap,s;
    initial begin
        for(g=0;g<6;g=g+1)for(offset=0;offset<4;offset=offset+1)begin
            rst_n=0;tracking=0;physical=0;repeat(4)@(negedge clk);rst_n=1;
            physical=16'h1111;wait(stable && fret==16'h1111);@(negedge clk);
            repeat(offset*3072)@(negedge clk);
            for(s=0;s<4;s=s+1)pulses[s]=0;
            zeros=0;tracking=1;physical=0;
            gap=g==0 ? 6144 : g==1 ? 12288 : g==2 ? 24576 : g==3 ? 36864 : g==4 ? 49152 : 98304;
            repeat(gap)@(negedge clk);physical=16'h3333;
            wait(stable && fret==16'h3333);@(negedge clk);tracking=0;
            for(s=0;s<4;s=s+1)begin
                if(g>=2 && pulses[s]!=1)$fatal(1,"FAIL: qualified short/long release g%0d s%0d pulse%0d",g,s,pulses[s]);
                if(g<=1 && pulses[s]!=0)$fatal(1,"FAIL: one-sample dropout qualified");
            end
            if(g>=2 && g<=4)begin
                if(zeros!=0)$fatal(1,"FAIL: stable output diagnostic changed");
                merged=merged+1;
            end
            cases=cases+1;
        end
        $display("PASS: production matrix two-empty release qualification all4 strings/%0d gaps-phases; %0d merged stable gaps now exposed; %0d clocks original row/raw/stable outputs exactly frozen; one-sample dropout rejected",cases,merged,clock_checks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: matrix release watchdog");end
endmodule
