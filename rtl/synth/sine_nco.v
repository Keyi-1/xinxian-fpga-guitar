`include "../config/guitar_config.vh"

module sine_nco (
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire                                sample_ce,
    input  wire [`PHASE_ACC_BITS-1:0]          phase_inc,
    output reg  signed [`SINE_LUT_VALUE_BITS-1:0] sample_out,
    output reg                                 sample_valid
);

    localparam integer LUT_SIZE = (1 << `SINE_LUT_ADDR_BITS);

    reg [`PHASE_ACC_BITS-1:0] phase_acc;
    reg signed [`SINE_LUT_VALUE_BITS-1:0] sine_lut [0:LUT_SIZE-1];

    wire [`PHASE_ACC_BITS-1:0] phase_next;
    wire [`SINE_LUT_ADDR_BITS-1:0] lut_addr;

    assign phase_next = phase_acc + phase_inc;

    assign lut_addr =
        phase_next[`PHASE_ACC_BITS-1 -: `SINE_LUT_ADDR_BITS];


    initial begin
        $readmemh("../../mem/sine_lut.mem", sine_lut);
    end

    always @(posedge clk) begin
    	if (!rst_n) begin
        	phase_acc   <= {`PHASE_ACC_BITS{1'b0}};
        	sample_out  <= {`SINE_LUT_VALUE_BITS{1'b0}};
        	sample_valid <= 1'b0;
    	end
    	else begin
        	sample_valid <= 1'b0;

        	if (sample_ce) begin
            	phase_acc    <= phase_next;
            	sample_out   <= sine_lut[lut_addr];
            	sample_valid <= 1'b1;
        	end
    	end
	end

endmodule