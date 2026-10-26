`timescale 1ns/1ps
// Diagnostic of the pushed, unmodified scanner at production cycle counts.
module tb_matrix_release_visibility;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tracking=0;
    reg [3:0] physical_fret=0;
    reg [7:0] pins,meta=255,sync=255;
    wire [3:0] row,drive;
    wire frame_valid,stable_valid;
    wire [15:0] raw_fret,stable_fret;
    integer raw_zeros,stable_zeros,total=0,merged=0,observed=0,fd;
    always @*begin
        pins=255;
        if(row[0] && physical_fret!=0)pins=~(8'b1<<(physical_fret-1));
    end
    always @(posedge clk)begin
        if(!rst_n)begin meta<=255;sync<=255;end
        else begin meta<=pins;sync<=meta;end
        #1;
        if(rst_n && tracking)begin
            if(frame_valid && raw_fret[3:0]==0)raw_zeros=raw_zeros+1;
            if(stable_valid && stable_fret[3:0]==0)stable_zeros=stable_zeros+1;
        end
    end
    matrix_scanner #(.CLK_DIV(768),.SETTLE_CYCLES(3),.DEBOUNCE_FRAMES(5)) dut(
        .clk(clk),.rst_n(rst_n),.col_in_n(sync),.row_oe(row),.row_drive_n(drive),
        .frame_valid(frame_valid),.fret_mask(),.fret_id(raw_fret),
        .stable_valid(stable_valid),.stable_fret_mask(),.stable_fret_id(stable_fret));
    function integer gap_cycles(input integer index);
        case(index)
            0:gap_cycles=3072;1:gap_cycles=6144;2:gap_cycles=12288;
            3:gap_cycles=24576;4:gap_cycles=36864;5:gap_cycles=49152;
            6:gap_cycles=61440;7:gap_cycles=98304;default:gap_cycles=737280;
        endcase
    endfunction
    integer g,offset,gap;
    initial begin
        fd=$fopen("matrix_release_baseline.csv","w");
        $fwrite(fd,"gap_cycles,gap_us,phase_cycles,raw_empty_frames,stable_release_events\n");
        for(g=0;g<9;g=g+1)for(offset=0;offset<4;offset=offset+1)begin
            tracking=0;rst_n=0;physical_fret=0;repeat(4)@(negedge clk);rst_n=1;
            physical_fret=1;wait(stable_valid && stable_fret[3:0]==1);@(negedge clk);
            repeat(offset*3072)@(negedge clk);
            raw_zeros=0;stable_zeros=0;tracking=1;physical_fret=0;gap=gap_cycles(g);
            repeat(gap)@(negedge clk);physical_fret=3;
            wait(stable_valid && stable_fret[3:0]==3);@(negedge clk);tracking=0;
            total=total+1;
            if(raw_zeros>0 && stable_zeros==0)merged=merged+1;
            if(stable_zeros>0)observed=observed+1;
            if(g>=7 && stable_zeros==0)$fatal(1,"FAIL: production long release invisible");
            $fwrite(fd,"%0d,%0f,%0d,%0d,%0d\n",gap,1000000.0*gap/12288000.0,offset*3072,raw_zeros,stable_zeros);
        end
        $fclose(fd);
        if(merged==0 || observed==0)$fatal(1,"FAIL: diagnostic coverage");
        $display("PASS: production scanner release diagnostic %0d gaps/phases, %0d raw-observed releases merged by stable debounce, %0d stable releases; scan frame12288 clocks=1ms, debounce5frames",total,merged,observed);
        $finish;
    end
    initial begin #100000000;$fatal(1,"FAIL: scanner diagnostic watchdog");end
endmodule
