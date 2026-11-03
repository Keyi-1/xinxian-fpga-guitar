`timescale 1ns/1ps
module tb_tail_lock_policy;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick=0,stable=0;
    reg [15:0] fret=0;
    reg [3:0] pluck=0,active=15,released=0;
    wire [3:0] on,off;
    wire [127:0] target;
    reg [31:0] rom[0:35];
    reg [127:0] expected;
    integer checks=0,s;
    guitar_play_control #(.EARLY_RELEASE_ENABLE(1)) dut(.clk(clk),.rst_n(rst_n),.sample_tick(tick),
        .stable_valid(stable),.stable_fret_id(fret),.fret_release(released),.pluck_valid(pluck),
        .voice_active(active),.smoothed_phase_inc(128'd0),.note_on(on),.note_off(off),.target_phase_inc(target));
    task check(input bit okay,input [255:0] label_text);
        if(!okay)$fatal(1,"FAIL: %0s",label_text);else checks=checks+1;
    endtask
    task contacts(input [15:0] value);
        @(negedge clk);fret=value;stable=1;
        @(negedge clk);stable=0;#1;
    endtask
    task strike(input [3:0] mask);
        @(negedge clk);pluck=mask;#1;
        @(negedge clk);pluck=0;
        @(negedge clk);tick=1;#1;
        check(on==mask && off==0,"exact queued real strike");
        @(negedge clk);tick=0;#1;
    endtask
    task early(input [3:0] mask);
        @(negedge clk);released=mask;
        @(negedge clk);released=0;#1;
    endtask
    initial begin
        $readmemh("../../mem/note_phase_inc.mem",rom);
        repeat(3)@(negedge clk);rst_n=1;
        contacts(16'h1111);strike(15);
        expected={rom[28],rom[19],rom[10],rom[1]};check(target==expected,"initial four fretted notes");
        contacts(0);contacts(16'h3333);
        check(target==expected && on==0 && off==0,"release then third fret retains first-fret tail");
        check(dut.tail_locked==15,"four independent tail locks");
        strike(1);expected[31:0]=rom[3];check(target==expected,"new strike uses prepared third fret");
        check(dut.tail_locked==14,"one restrike unlocks only that string");
        contacts(16'h3335);expected[31:0]=rom[5];
        check(target==expected,"continuous fifth-fret transition still slides");
        contacts(16'h0000);strike(1);expected[31:0]=rom[0];
        check(target==expected,"open-string real restrike");
        // The other strings remain locked through repeated new preparations.
        contacts(16'h8760);check(target==expected,"new preparations do not retune locked neighbors");
        active=0;@(negedge clk);contacts(16'h1111);active=15;strike(15);
        expected={rom[28],rom[19],rom[10],rom[1]};
        early(1);check(dut.tail_locked==1,"short raw release locks before stable zero");
        strike(1);expected[31:0]=rom[0];
        check(target==expected,"short-release debounce window prepares a real open strike");
        contacts(16'h1113);expected[31:0]=rom[3];
        check(target==expected,"new stable contact after open strike can slide");
        for(s=0;s<4;s=s+1)begin
            early(4'(1<<s));
            contacts(16'h8888);
            check(target[s*32+:32]==expected[s*32+:32],"per-string early tail lock");
            strike(4'(1<<s));expected[s*32+:32]=rom[s*9+8];
            check(target[s*32+:32]==expected[s*32+:32],"per-string prepared strike");
            contacts(16'h1111);
            // Unlocked strings follow this continuous transition.
            for(integer j=0;j<4;j=j+1)if(!dut.tail_locked[j])expected[j*32+:32]=rom[j*9+1];
        end
        @(negedge clk);released=15;pluck=15;tick=1;#1;
        check(on==15,"same-tick real pluck wins");
        @(negedge clk);released=0;pluck=0;tick=0;#1;
        check(dut.tail_locked==0 && off==0,"coincident release cannot re-lock fresh strike");
        $display("PASS: tail lock/prepared pitch/continuous slides/open restrikes/short-release preparation/four-string isolation/same-tick pluck priority, %0d checks; no note_off or synthetic Attack",checks);
        $finish;
    end
endmodule
