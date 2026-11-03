`timescale 1ns/1ps
module tb_guitar_radial_fft;
    reg clk=0,rst=0,valid=0;
    always #10 clk=~clk;
    reg signed [23:0] pcm=0;
    wire bv,done,busy,rv,rdone;
    wire [9:0] bi,ri;
    wire [18:0] bm,rm;
    guitar_radial_fft dut(.clk(clk),.rst_n(rst),.sample_valid(valid),.pcm(pcm),
        .bin_valid(bv),.bin_index(bi),.bin_magnitude(bm),.frame_done(done),.busy(busy));
    spectrum_fft1024 #(.FRAME_GAP_SAMPLES(1)) reference(.clk(clk),.rst_n(rst),
        .sample_valid_in(valid),.pcm_in(pcm),.bin_valid(rv),.bin_index(ri),.bin_magnitude(rm),.frame_done(rdone),.busy());
    reg [18:0] expected[0:511];
    integer comparisons=0,peak=0,peak_bin=0,count=0,frames=0;
    always @(posedge clk)begin
        #1;
        if(rst && rv)expected[ri]=rm;
        if(rst && bv)begin
            count++;
            if(bi<512)begin
                if(bm!==expected[bi])$fatal(1,"FAIL: shared FFT frame=%0d bin=%0d got=%0d reference=%0d",frames,bi,bm,expected[bi]);
                comparisons++;
            end
            if(bm>peak)begin peak=bm;peak_bin=bi;end
        end
    end
    task automatic frame(input integer mode);
        integer n;
        real v;
        begin
            @(negedge clk);rst=0;valid=0;repeat(5)@(negedge clk);rst=1;
            count=0;peak=0;peak_bin=0;
            for(n=0;n<1024;n++)begin
                case(mode)
                    0:v=5000000.0*$sin(2.0*3.141592653589793*3*n/1024);
                    1:v=1500000.0*($sin(2.0*3.141592653589793*3*n/1024)+$sin(2.0*3.141592653589793*7*n/1024)+
                        $sin(2.0*3.141592653589793*32*n/1024)+$sin(2.0*3.141592653589793*192*n/1024));
                    2:v=(n%2) ? -5000000.0 : 5000000.0;
                    default:v=0;
                endcase
                @(negedge clk);pcm=$rtoi(v);valid=1;
                @(negedge clk);valid=0;repeat(10)@(negedge clk);
            end
            wait(done);#2;
            if(count!=513)$fatal(1,"FAIL: positive bins missing Nyquist");
            if(mode==0 && peak_bin!=3)$fatal(1,"FAIL: low frequency mapping");
            if(mode==1 && (expected[3]<1000 || expected[7]<1000 || expected[32]<1000 || expected[192]<1000))
                $fatal(1,"FAIL: four simultaneous tones lost FFT components");
            if(mode==2 && peak_bin!=512)$fatal(1,"FAIL: Nyquist mapping %0d",peak_bin);
            if(mode==3 && peak!=0)$fatal(1,"FAIL: silence has energy");
            frames++;$display("PASS: shared FFT mode=%0d, 513 bins, peak=%0d magnitude=%0d",mode,peak_bin,peak);
        end
    endtask
    initial begin frame(0);frame(1);frame(2);frame(3);
        $display("PASS: shared FFT %0d positive-bin magnitudes bit-identical to original FFT; Nyquist and silence",comparisons);$finish;end
    initial begin #10000000;$fatal(1,"FAIL: FFT timeout");end
endmodule
