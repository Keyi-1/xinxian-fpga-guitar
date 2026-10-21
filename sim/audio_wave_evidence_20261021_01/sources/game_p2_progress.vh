// Generated from the same catalogue; ceil(samples/480).
function [31:0] game_p2_progress_step;
    input [2:0] slot;
    begin case(slot)
        3'd0:game_p2_progress_step=32'd3375;
        3'd1:game_p2_progress_step=32'd25600;
        3'd2:game_p2_progress_step=32'd19200;
        3'd3:game_p2_progress_step=32'd15200;
        3'd4:game_p2_progress_step=32'd60000;
        default:game_p2_progress_step=32'd3375;
    endcase end
endfunction
