module game_p2_catalog(input wire [2:0] slot,
    output reg valid,playable,test_only,output reg [10:0] base,
    output reg [11:0] event_count,output reg [31:0] duration,
    output reg [1:0] timbre);
    always @*begin
        valid=0;playable=0;test_only=0;base=0;event_count=0;duration=0;timbre=0;
        `include "../config/game_p2_catalog.vh"
    end
endmodule
