// Reset-domain conditioner. The external active-low reset asserts the local
// reset immediately; deassertion is delayed through three clocked stages so
// every consumer in the domain leaves reset on a clean clock edge.
module reset_sync (
    input  wire clk,
    input  wire arst_n,
    output wire srst_n
);

    (* syn_preserve = 1 *) reg [2:0] release_pipe;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            release_pipe <= 3'b000;
        else
            release_pipe <= {release_pipe[1:0], 1'b1};
    end

    assign srst_n = release_pipe[2];

endmodule
