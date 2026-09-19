// Gowin dual-port BSRAM inference template (normal read mode).
module gowin_dpb_ram #(
    parameter integer WIDTH = 18,
    parameter integer ADDR_BITS = 10,
    parameter integer DEPTH = 1024
) (
    input  wire                  clk,
    input  wire                  ena,
    input  wire                  wea,
    input  wire [ADDR_BITS-1:0]  addra,
    input  wire [WIDTH-1:0]      dina,
    output reg  [WIDTH-1:0]      douta,
    input  wire                  enb,
    input  wire                  web,
    input  wire [ADDR_BITS-1:0]  addrb,
    input  wire [WIDTH-1:0]      dinb,
    output reg  [WIDTH-1:0]      doutb
);
    reg [WIDTH-1:0] mem [0:DEPTH-1]
        /* synthesis syn_ramstyle = "block_ram" */;

    always @(posedge clk)
        if (ena && !wea) douta <= mem[addra];
    always @(posedge clk)
        if (ena && wea) mem[addra] <= dina;
    always @(posedge clk)
        if (enb && !web) doutb <= mem[addrb];
    always @(posedge clk)
        if (enb && web) mem[addrb] <= dinb;
endmodule
