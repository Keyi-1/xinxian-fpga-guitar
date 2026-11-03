// Two synchronous ports, no reset on the array: inferred block RAM.
// Display reads the front bank while the renderer copies/plots the back bank.
module lcd_lissajous_ram (
    input wire clk,
    input wire [16:0] video_addr,
    output reg [3:0] video_q,
    input wire [16:0] render_addr,
    input wire render_we,
    input wire [3:0] render_data,
    output reg [3:0] render_q
);
    reg [3:0] pixels [0:131071] /* synthesis syn_ramstyle = "block_ram" */;
    always @(posedge clk) video_q <= pixels[video_addr];
    always @(posedge clk) begin
        // Normal read mode: do not request unsupported read-before-write DPB.
        if (!render_we) render_q <= pixels[render_addr];
        if (render_we) pixels[render_addr] <= render_data;
    end
endmodule
