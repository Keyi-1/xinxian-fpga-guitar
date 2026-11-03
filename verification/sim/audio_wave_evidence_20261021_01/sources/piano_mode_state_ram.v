// One32-bit simple-dual-port bank, two rows per mode: phase0/gain1.
// LOAD reads phase, ENV_B captures it and reads gain. PHASE and ACC write
// the separate rows. All use existing processing slots; reads never collide
// with writes. A32-bit SDPB consumes two physical Gowin blocks on this part.
module piano_mode_state_ram(input wire clk,read_enable,read_gain,input wire [4:0] address,
    input wire phase_write,gain_write,input wire [31:0] phase_data,
    input wire [23:0] gain_data,output reg [31:0] phase_q=0,
    output wire [23:0] gain_q);
    wire [31:0] read_word;
    assign gain_q=read_word[23:0];
    always @(posedge clk)if(read_enable && read_gain)phase_q<=read_word;
    SDPB states(.DO(read_word),.DI(gain_write ? {8'd0,gain_data} : phase_data),
        .BLKSELA(3'd0),.BLKSELB(3'd0),
        .ADA({3'd0,address,gain_write,1'b0,4'b1111}),.ADB({3'd0,address,read_gain,5'd0}),
        .CLKA(clk),.CLKB(clk),.CEA(phase_write || gain_write),.CEB(read_enable),.OCE(1'b0),.RESET(1'b0));
    defparam states.BIT_WIDTH_0=32;
    defparam states.BIT_WIDTH_1=32;
    defparam states.READ_MODE=1'b0;
endmodule
