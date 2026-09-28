module note_phase_rom (
    output wire [31:0] e4_phase_inc
);

    reg [31:0] phase_rom [0:35];

    initial begin
        $readmemh("note_phase_inc.mem", phase_rom);
    end

    assign e4_phase_inc = phase_rom[0];

endmodule