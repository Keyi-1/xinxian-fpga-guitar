// 50 MHz, 115200 8N1 by default. RX observes the second synchronizer stage;
// physical bytes never wait for an internal ready signal.
module game_p3_uart #(parameter integer CLKS_PER_BIT=434)(
    input wire clk,rst_n,rx,output reg tx,
    output reg rx_valid,output reg [7:0] rx_data,output reg framing_error,
    input wire tx_valid,input wire [7:0] tx_data,output wire tx_ready);
    reg rx_meta,rx_sync;
    reg [1:0] rx_state;
    reg [15:0] rx_count,tx_count;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    reg tx_busy;
    reg [3:0] tx_bit;
    reg [9:0] tx_shift;
    assign tx_ready=!tx_busy;
    always @(posedge clk)begin
        if(!rst_n)begin
            rx_meta<=1;rx_sync<=1;rx_state<=0;rx_count<=0;rx_bit<=0;rx_shift<=0;
            rx_valid<=0;rx_data<=0;framing_error<=0;
            tx<=1;tx_busy<=0;tx_count<=0;tx_bit<=0;tx_shift<=10'h3ff;
        end else begin
            rx_meta<=rx;rx_sync<=rx_meta;rx_valid<=0;framing_error<=0;
            case(rx_state)
                0:if(!rx_sync)begin rx_count<=CLKS_PER_BIT/2-1;rx_state<=1;end
                1:if(rx_count!=0)rx_count<=rx_count-1'b1;
                  else if(rx_sync)rx_state<=0;
                  else begin rx_state<=2;rx_bit<=0;rx_count<=CLKS_PER_BIT-1;end
                2:if(rx_count!=0)rx_count<=rx_count-1'b1;
                  else begin
                      rx_shift[rx_bit]<=rx_sync;rx_count<=CLKS_PER_BIT-1;
                      if(rx_bit==7)rx_state<=3;else rx_bit<=rx_bit+1'b1;
                  end
                3:if(rx_count!=0)rx_count<=rx_count-1'b1;
                  else if(rx_sync)begin rx_data<=rx_shift;rx_valid<=1;rx_state<=0;end
                  else begin framing_error<=1;rx_state<=0;end
            endcase
            if(!tx_busy)begin
                if(tx_valid)begin tx_shift<={1'b1,tx_data,1'b0};tx<=0;tx_count<=CLKS_PER_BIT-1;tx_bit<=0;tx_busy<=1;end
            end else if(tx_count!=0)tx_count<=tx_count-1'b1;
            else if(tx_bit==9)begin tx<=1;tx_busy<=0;end
            else begin tx_shift<={1'b1,tx_shift[9:1]};tx<=tx_shift[1];tx_bit<=tx_bit+1'b1;tx_count<=CLKS_PER_BIT-1;end
        end
    end
endmodule
