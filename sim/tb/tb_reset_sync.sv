`timescale 1ns/1ps

module tb_reset_sync;
    reg clk;
    reg arst_n;
    wire srst_n;
    integer release_edges;

    reset_sync dut (
        .clk(clk), .arst_n(arst_n), .srst_n(srst_n)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        arst_n = 1'b0;
        release_edges = 0;
        #1;
        if (srst_n !== 1'b0) begin
            $display("FAIL: reset synchronizer did not assert immediately");
            $fatal;
        end

        // Deassert away from a clock edge. Local reset must remain asserted
        // for two complete edges and release only after the third edge.
        #7 arst_n = 1'b1;
        repeat (2) begin
            @(posedge clk);
            #1;
            release_edges = release_edges + 1;
            if (srst_n !== 1'b0) begin
                $display("FAIL: reset released early edge=%0d", release_edges);
                $fatal;
            end
        end
        @(posedge clk);
        #1;
        release_edges = release_edges + 1;
        if (srst_n !== 1'b1) begin
            $display("FAIL: reset did not release on third edge");
            $fatal;
        end

        // Assert again between active clock edges; this transition must not
        // wait for the next edge.
        #2 arst_n = 1'b0;
        #1;
        if (srst_n !== 1'b0) begin
            $display("FAIL: second reset assertion was not asynchronous");
            $fatal;
        end

        #3 arst_n = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        if (srst_n !== 1'b1) begin
            $display("FAIL: second reset release did not synchronize");
            $fatal;
        end

        $display("PASS: reset asynchronous assertion and three-edge synchronous release");
        $finish;
    end

endmodule
