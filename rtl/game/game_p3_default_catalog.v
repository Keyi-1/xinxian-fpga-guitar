// Same logical slots for the retained songs. Slot1 is empty at the user's
// request; its former 256-event slow practice is absent from the P3 bank.
module game_p3_default_catalog(input wire [2:0] slot,
    output reg valid,playable,test_only,output reg [10:0] base,
    output reg [11:0] event_count,output reg [31:0] duration,
    output reg [1:0] timbre);
    always @*begin
        valid=0;playable=0;test_only=0;base=0;event_count=0;duration=0;timbre=0;
        case(slot)
            0:begin valid=1;playable=1;base=0;event_count=67;duration=1620000;timbre=0;end
            2:begin valid=1;playable=1;base=67;event_count=168;duration=9216000;timbre=2;end
            3:begin valid=1;playable=1;base=235;event_count=212;duration=7296000;timbre=1;end
            4:begin valid=1;test_only=1;base=447;event_count=256;duration=28800000;timbre=1;end
            default:begin end
        endcase
    end
endmodule
