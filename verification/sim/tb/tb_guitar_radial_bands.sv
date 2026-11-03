`timescale 1ns/1ps
module tb_guitar_radial_bands;
    reg clk=0,rst=0,valid=0,done=0;
    always #10 clk=~clk;
    reg [9:0] index=0;
    reg [18:0] magnitude=0;
    wire [159:0] targets;
    wire update;
    guitar_radial_bands dut(.clk(clk),.rst_n(rst),.bin_valid(valid),.frame_done(done),
        .bin_index(index),.bin_magnitude(magnitude),.targets(targets),.update(update));
    reg [159:0] old=0;
    always @(posedge clk)begin #1;
        if(rst && targets!==old && !update)$fatal(1,"FAIL: torn frequency-band publication");
        old=targets;
    end
    integer i;
    task automatic feed_bins(input integer silence);
        begin
            for(i=0;i<=512;i++)begin
                @(negedge clk);valid=1;index=i;done=i==512;
                magnitude=silence ? 0 : i==0 ? 200000 : i==7 ? 12000 : i==32 ? 4000 : i==512 ? 3000 : 0;
            end
            @(negedge clk);valid=0;done=0;wait(update);#2;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;feed_bins(0);
        if(targets[6*5+:5]!=27 || targets[17*5+:5]==0 || targets[31*5+:5]==0)
            $fatal(1,"FAIL: tone/band/Nyquist log heights %h",targets);
        if(targets[0+:5]!=0)$fatal(1,"FAIL: DC contaminates spectrum");
        feed_bins(1);if(targets!=0)$fatal(1,"FAIL: silence retains bin energy");
        $display("PASS: FFT band aggregation, logarithmic AGC, Nyquist coverage, DC rejection, coherent publication and silence");$finish;
    end
endmodule
