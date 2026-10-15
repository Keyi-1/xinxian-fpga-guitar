`timescale 1ns/1ps
// Exact-clock component comparison. Includes input activity during reduction,
// interrupted frames and resets, without changing the frozen implementation.
module tb_radial_bands_equivalence;
`ifndef BANDS_CANDIDATE
    `define BANDS_CANDIDATE guitar_radial_bands_direct_log
`endif
    reg clk=0,rst_n=0,bin_valid=0,frame_done=0;
    reg [9:0] bin_index=0;
    reg [18:0] bin_magnitude=0;
    always #10 clk=~clk;
    wire [159:0] original_targets,candidate_targets;
    wire original_update,candidate_update;
    guitar_radial_bands_frozen original(.clk(clk),.rst_n(rst_n),
        .bin_valid(bin_valid),.frame_done(frame_done),.bin_index(bin_index),
        .bin_magnitude(bin_magnitude),.targets(original_targets),.update(original_update));
    `BANDS_CANDIDATE candidate(.clk(clk),.rst_n(rst_n),
        .bin_valid(bin_valid),.frame_done(frame_done),.bin_index(bin_index),
        .bin_magnitude(bin_magnitude),.targets(candidate_targets),.update(candidate_update));
`ifdef BANDS_GATE
    GSR GSR(.GSRI(1'b1));
`endif
    integer cycles=0,publications=0,j,age=-1;
    reg [159:0] previous_targets=0;
    reg check_deadline=0;
    always @(posedge clk)begin
        #2;
        cycles=cycles+1;
        if({candidate_update,candidate_targets} !== {original_update,original_targets})
            $fatal(1,"FAIL: output mismatch cycle=%0d rst=%b valid=%b done=%b bin=%0d magnitude=%0d ref_update=%b candidate_update=%b ref_targets=%h candidate_targets=%h",cycles,rst_n,bin_valid,frame_done,bin_index,bin_magnitude,original_update,candidate_update,original_targets,candidate_targets);
        if(!rst_n)age=-1;
        else begin
            if(frame_done)age=0;
            else if(age>=0)age=age+1;
            if(candidate_targets!==previous_targets && !candidate_update)
                $fatal(1,"FAIL: torn target publication at cycle %0d",cycles);
            if(candidate_update)begin
                publications=publications+1;
                if(check_deadline && age!=32)
                    $fatal(1,"FAIL: reduction deadline %0d instead of 32",age);
            end
        end
        previous_targets=candidate_targets;
`ifndef BANDS_GATE
        if({candidate.maximum,candidate.reference,candidate.agc,candidate.index,
            candidate.reducing,candidate.pending_targets} !==
           {original.maximum,original.reference,original.agc,original.index,
            original.reducing,original.pending_targets})
            $fatal(1,"FAIL: state mismatch at cycle %0d",cycles);
        for(j=0;j<32;j=j+1)if(candidate.work[j]!==original.work[j])
            $fatal(1,"FAIL: band %0d state mismatch at cycle %0d",j,cycles);
`endif
    end
    // Fixed LCG seed: identical stimulus across RTL and synthesized runs.
    reg [31:0] random_state=32'h4670cafe;
    function automatic [31:0] next_random(input [31:0] unused);
        begin
            random_state=random_state*32'd1664525+32'd1013904223;
            next_random=random_state;
        end
    endfunction
    task automatic drive(input bit v,input bit d,input integer b,input integer m);
        begin
            @(negedge clk);bin_valid=v;frame_done=d;bin_index=b;bin_magnitude=m;
        end
    endtask
    task automatic idle(input integer n);
        repeat(n)drive(0,0,0,0);
    endtask
    task automatic reset;
        begin
            @(negedge clk);rst_n=0;bin_valid=0;frame_done=0;
            repeat(5)@(negedge clk);
            rst_n=1;
        end
    endtask
    integer value,bit_index,frame,b,k,m,pubs_before;
    reg [18:0] four_state;
    reg [31:0] sample;
    initial begin
`ifndef BANDS_GATE
        for(value=0;value<524288;value=value+1)
            if(candidate.log2q3(value)!==original.log2q3(value))
                $fatal(1,"FAIL: logarithm input %0d",value);
        // Highest-one selection must also preserve the old Verilog if semantics.
        for(bit_index=0;bit_index<19;bit_index=bit_index+1)begin
            for(k=0;k<19;k=k+1)begin
                four_state=19'd1<<k;four_state[bit_index]=1'bx;
                if(candidate.log2q3(four_state)!==original.log2q3(four_state))
                    $fatal(1,"FAIL: X semantics %b",four_state);
                four_state[bit_index]=1'bz;
                if(candidate.log2q3(four_state)!==original.log2q3(four_state))
                    $fatal(1,"FAIL: Z semantics %b",four_state);
            end
        end
        $display("PASS: all 524288 binary logarithm inputs and 722 X/Z probes");
`endif
        reset();check_deadline=1;
        // Known tone, DC rejection, low-frequency and Nyquist mapping.
        for(b=0;b<=512;b=b+1)
            drive(1,b==512,b,b==0 ? 200000 : b==7 ? 12000 : b==32 ? 4000 : b==512 ? 3000 : 0);
        idle(34);
        if(candidate_targets[30+:5]!=27 || candidate_targets[85+:5]==0 ||
           candidate_targets[155+:5]==0 || candidate_targets[0+:5]!=0)
            $fatal(1,"FAIL: independent known-tone/DC/Nyquist expectation");
        // Dense FFT streams, exact small-value thresholds, powers of two,
        // clipping maximum, and gaps at every mapped frequency boundary.
        for(frame=0;frame<256;frame=frame+1)begin
            pubs_before=publications;
            for(b=0;b<=512;b=b+1)begin
                sample=next_random(0);
                case(frame%16)
                    0:m=0; 1:m=7; 2:m=8; 3:m=31; 4:m=32;
                    5:m=1023; 6:m=1024; 7:m=524287;
                    8:m=(1<<(b%19));
                    9:m=(1<<(b%19))-1;
                    10:m=(1<<(b%18))+1;
                    11:m=b; 12:m=512-b;
                    default:m=sample[18:0];
                endcase
                if(frame%7==0)idle(sample[1:0]);
                drive(1,b==512,b,m);
            end
            idle(34);
            if(publications!=pubs_before+1)$fatal(1,"FAIL: missing/double publication");
        end
        // Silence traverses the full AGC decay down to its clamp.
        for(frame=0;frame<192;frame=frame+1)begin
            drive(1,1,512,0);idle(34);
            if(candidate_targets!=0)$fatal(1,"FAIL: residual silent band");
        end
        // Concurrent aggregation / clear, repeated frame_done restarts,
        // duplicate and nonmonotonic bins, including all 10-bit indices.
        for(frame=0;frame<96;frame=frame+1)begin
            for(k=0;k<83;k=k+1)begin
                sample=next_random(0);
                drive(sample[0] | sample[1],k==11 || k==12 || k==40,
                      sample[28:19],sample[18:0]);
            end
            idle(35);
        end
        // Reset during accumulation and during reduction, then recover.
        for(frame=0;frame<32;frame=frame+1)begin
            for(k=0;k<frame;k=k+1)drive(1,0,k+1,524287-k);
            drive(1,1,512,32768);idle(frame);reset();
            drive(1,1,18,4096);idle(34);
        end
        // Unstructured changing inputs, then a deterministic final publication.
        for(k=0;k<20000;k=k+1)begin
            sample=next_random(0);
            drive(sample[0],sample[7:2]==0,sample[28:19],sample[18:0]);
        end
        idle(40);drive(0,1,0,0);idle(34);
        if(publications<500)$fatal(1,"FAIL: insufficient completed frames");
        $display("PASS: exact-cycle bands equivalence: %0d clocks, %0d publications; thresholds, AGC decay, dynamic reduction inputs, restarts, reset and 32-clock deadline",cycles,publications);
        $finish;
    end
    initial begin #100000000; $fatal(1,"FAIL: timeout");end
endmodule
