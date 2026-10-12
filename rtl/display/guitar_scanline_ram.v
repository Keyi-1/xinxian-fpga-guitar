// One synchronous read and independent write: one coverage update/clock.
module guitar_scanline_ram(input wire clk,input wire [8:0] read_addr,
    output reg [11:0] q,input wire [8:0] write_addr,input wire we,
    input wire [11:0] data);
    reg [11:0] pixels [0:511];
    always @(posedge clk) begin
        q<=pixels[read_addr];
        if(we) pixels[write_addr]<=data;
    end
endmodule
