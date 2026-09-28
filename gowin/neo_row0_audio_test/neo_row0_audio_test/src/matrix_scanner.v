module matrix_scanner #(
    parameter integer CLK_DIV         = 25000,
    parameter integer DEBOUNCE_FRAMES = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  col_in_n,
 
    output reg  [3:0]  row_oe,
    output reg  [15:0] stable_fret_id
);
 
    reg [31:0] div_count;
    reg [1:0]  row_index;
    reg [7:0]  row0_mask;
    reg [7:0]  row1_mask;
    reg [7:0]  row2_mask;
    reg [15:0] cand_id;
    reg [3:0]  cand_cnt;
 
    wire [7:0] col_pressed = ~col_in_n;
 
    function [3:0] highest_fret;
        input [7:0] mask;
        integer k;
        begin
            highest_fret = 4'd0;
            for (k = 0; k < 8; k = k + 1)
                if (mask[k])
                    highest_fret = k + 1;
        end
    endfunction
 
    // 当 row_index==3 时，col_pressed 就是第 3 行的读数
    wire [15:0] frame_id = {
        highest_fret(col_pressed),
        highest_fret(row2_mask),
        highest_fret(row1_mask),
        highest_fret(row0_mask)
    };
 
    // 每次只把一根 ROW 拉低，其余高阻
    always @* begin
        row_oe = 4'b0000;
        if (rst_n) begin
            case (row_index)
                2'd0: row_oe = 4'b0001;
                2'd1: row_oe = 4'b0010;
                2'd2: row_oe = 4'b0100;
                2'd3: row_oe = 4'b1000;
            endcase
        end
    end
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_count      <= 32'd0;
            row_index      <= 2'd0;
            row0_mask      <= 8'd0;
            row1_mask      <= 8'd0;
            row2_mask      <= 8'd0;
            cand_id        <= 16'd0;
            cand_cnt       <= 4'd0;
            stable_fret_id <= 16'd0;
        end
        else if (div_count < CLK_DIV - 1) begin
            div_count <= div_count + 1'b1;
        end
        else begin
            div_count <= 32'd0;
            row_index <= row_index + 1'b1;
 
            case (row_index)
                2'd0: row0_mask <= col_pressed;
                2'd1: row1_mask <= col_pressed;
                2'd2: row2_mask <= col_pressed;
                2'd3: begin
                    // 整帧状态连续 DEBOUNCE_FRAMES 次相同才确认
                    if (frame_id == cand_id) begin
                        if (cand_cnt < DEBOUNCE_FRAMES)
                            cand_cnt <= cand_cnt + 1'b1;
                        if (cand_cnt + 1 >= DEBOUNCE_FRAMES)
                            stable_fret_id <= frame_id;
                    end
                    else begin
                        cand_id  <= frame_id;
                        cand_cnt <= 4'd1;
                    end
                end
            endcase
        end
    end
 
endmodule