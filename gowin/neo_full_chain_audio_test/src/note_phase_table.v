module note_phase_table (
    input  wire [5:0]  addr,
    output wire [31:0] phase_inc
);

    reg [31:0] phase_rom [0:35];

    initial begin
        $readmemh("note_phase_inc.mem", phase_rom);
    end

    assign phase_inc = (addr < 6'd36) ? phase_rom[addr] : 32'd0;

endmodule
