// Spectral/RMS parameters only. No sampled audio or filter-state table.
function signed [16:0] hammer_a1;
    input [1:0] bank; input [1:0] band;
    begin
        case ({bank,band})
            4'd0: hammer_a1=-17'sd31148;
            4'd1: hammer_a1=-17'sd26897;
            4'd2: hammer_a1=-17'sd13108;
            4'd4: hammer_a1=-17'sd32062;
            4'd5: hammer_a1=-17'sd30362;
            4'd6: hammer_a1=-17'sd19055;
            4'd8: hammer_a1=-17'sd31026;
            4'd9: hammer_a1=-17'sd27952;
            4'd10: hammer_a1=-17'sd23744;
            default: hammer_a1=0;
        endcase
    end
endfunction
function signed [16:0] hammer_a2;
    input [1:0] bank; input [1:0] band;
    begin
        case ({bank,band})
            4'd0: hammer_a2=17'sd14912;
            4'd1: hammer_a2=17'sd14964;
            4'd2: hammer_a2=17'sd8493;
            4'd4: hammer_a2=17'sd15871;
            4'd5: hammer_a2=17'sd15896;
            4'd6: hammer_a2=17'sd8493;
            4'd8: hammer_a2=17'sd14795;
            4'd9: hammer_a2=17'sd15896;
            4'd10: hammer_a2=17'sd15896;
            default: hammer_a2=0;
        endcase
    end
endfunction
function [3:0] hammer_noise_shift;
    input [1:0] bank; input [1:0] band;
    begin
        case ({bank,band})
            4'd0: hammer_noise_shift=4'd6;
            4'd1: hammer_noise_shift=4'd6;
            4'd2: hammer_noise_shift=4'd5;
            4'd4: hammer_noise_shift=4'd8;
            4'd5: hammer_noise_shift=4'd8;
            4'd6: hammer_noise_shift=4'd4;
            4'd8: hammer_noise_shift=4'd5;
            4'd9: hammer_noise_shift=4'd7;
            4'd10: hammer_noise_shift=4'd6;
            default: hammer_noise_shift=0;
        endcase
    end
endfunction
function [23:0] hammer_envelope_start;
    input [1:0] bank;
    begin
        case(bank)
            2'd0: hammer_envelope_start=24'd6111103;
            2'd1: hammer_envelope_start=24'd12421247;
            2'd2: hammer_envelope_start=24'd9257087;
            default: hammer_envelope_start=0;
        endcase
    end
endfunction
