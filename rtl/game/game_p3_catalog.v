// Descriptor: [31:0] ceil(duration/480), [42:32] base, [54:43] count,
// [86:55] duration, [88:87] timbre. Unpublished slots use the frozen catalog.
module game_p3_catalog(input wire [2:0] slot,
    input wire [4:0] overlay_valid,input wire [479:0] overlay_data,
    output wire valid,playable,test_only,output wire [10:0] base,
    output wire [11:0] event_count,output wire [31:0] duration,progress_step,
    output wire [1:0] timbre);
    wire sv,sp,st;wire [10:0] sb;wire [11:0] sc;
    wire [31:0] sd;wire [1:0] si;
    `include "../config/game_p2_progress.vh"
    `include "../config/game_p3_slot_map.vh"
    game_p3_default_catalog frozen(.slot(slot),.valid(sv),.playable(sp),.test_only(st),
        .base(sb),.event_count(sc),.duration(sd),.timbre(si));
    wire imported=slot<5 && overlay_valid[slot];
    wire [95:0] d=({96{slot==0}}&overlay_data[0*96+:96]) |
                  ({96{slot==1}}&overlay_data[1*96+:96]) |
                  ({96{slot==2}}&overlay_data[2*96+:96]) |
                  ({96{slot==3}}&overlay_data[3*96+:96]) |
                  ({96{slot==4}}&overlay_data[4*96+:96]);
    assign valid=imported || sv;
    assign playable=imported || sp;
    assign test_only=!imported && st;
    assign base=imported ? d[42:32] : sb;
    assign event_count=imported ? d[54:43] : sc;
    assign duration=imported ? d[86:55] : sd;
    assign timbre=imported ? d[88:87] : si;
    assign progress_step=imported ? d[31:0] : sv ? game_p2_progress_step(game_p3_legacy_slot(slot)) : 32'd0;
endmodule
