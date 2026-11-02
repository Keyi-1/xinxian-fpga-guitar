// P3 keeps the event bank fixed and moves only the visible built-in slots.
// Use the legacy P2 title/progress tables without changing their fixtures.
function [2:0] game_p3_legacy_slot;
    input [2:0] slot;
    begin case(slot)
        3'd1:game_p3_legacy_slot=3'd2;
        3'd2:game_p3_legacy_slot=3'd3;
        default:game_p3_legacy_slot=slot;
    endcase end
endfunction
