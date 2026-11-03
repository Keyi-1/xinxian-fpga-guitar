// 1024-point fixed-point radix-2 FFT using two inferred dual-port B-SRAMs.
module spectrum_fft1024 #(
    parameter integer FRAME_GAP_SAMPLES = 512
) (
    input wire clk, input wire rst_n,
    input wire sample_valid_in, input wire signed [23:0] pcm_in,
    output reg bin_valid, output reg [9:0] bin_index,
    output reg [18:0] bin_magnitude, output reg frame_done,
    output reg busy
);
    localparam [2:0] CAPTURE=0, FFT_READ=1, FFT_WRITE=2,
                     OUTPUT_READ=3, OUTPUT_EMIT=4, GAP=5;
    reg [2:0] state;
    reg [9:0] capture_count, output_count, gap_count;
    reg [3:0] stage;
    reg [8:0] butterfly_count;

    reg signed [15:0] hann_rom [0:1023];
    reg signed [15:0] cos_rom [0:511];
    reg signed [15:0] sin_rom [0:511];
    initial begin
        $readmemh("../../mem/hann1024_q15.mem", hann_rom);
        $readmemh("../../mem/fft1024_cos_q15.mem", cos_rom);
        $readmemh("../../mem/fft1024_sin_q15.mem", sin_rom);
    end

    reg ram_ena, ram_wea, ram_enb, ram_web;
    reg [9:0] ram_addra, ram_addrb;
    reg [17:0] real_dina, real_dinb, imag_dina, imag_dinb;
    wire [17:0] real_douta, real_doutb, imag_douta, imag_doutb;

    gowin_dpb_ram u_real_ram (
        .clk(clk), .ena(ram_ena), .wea(ram_wea), .addra(ram_addra),
        .dina(real_dina), .douta(real_douta), .enb(ram_enb),
        .web(ram_web), .addrb(ram_addrb), .dinb(real_dinb),
        .doutb(real_doutb)
    );
    gowin_dpb_ram u_imag_ram (
        .clk(clk), .ena(ram_ena), .wea(ram_wea), .addra(ram_addra),
        .dina(imag_dina), .douta(imag_douta), .enb(ram_enb),
        .web(ram_web), .addrb(ram_addrb), .dinb(imag_dinb),
        .doutb(imag_doutb)
    );

    function [9:0] reverse10;
        input [9:0] value; integer k;
        begin for(k=0;k<10;k=k+1) reverse10[k]=value[9-k]; end
    endfunction

    integer half_size, group_number, butterfly_offset;
    integer index_a, index_b, twiddle_index;
    reg signed [15:0] pcm16;
    reg signed [31:0] window_product;
    reg signed [17:0] windowed_sample;
    reg signed [17:0] a_re,a_im,b_re,b_im;
    reg signed [15:0] tw_cos,tw_sin;
    reg signed [34:0] product_re,product_im;
    reg signed [18:0] tw_re,tw_im;
    reg signed [19:0] sum_re,sum_im,diff_re,diff_im;
    reg [18:0] abs_re,abs_im,magnitude;

    always @* begin
        pcm16 = pcm_in[23:8];
        window_product = $signed(pcm16)*$signed(hann_rom[capture_count]);
        windowed_sample = window_product >>> 15;
        half_size = 1 << stage;
        group_number = butterfly_count >> stage;
        butterfly_offset = butterfly_count & (half_size-1);
        index_a = (group_number << (stage+1)) + butterfly_offset;
        index_b = index_a + half_size;
        twiddle_index = butterfly_offset << (9-stage);
        a_re=$signed(real_douta); a_im=$signed(imag_douta);
        b_re=$signed(real_doutb); b_im=$signed(imag_doutb);
        tw_cos=cos_rom[twiddle_index]; tw_sin=sin_rom[twiddle_index];
        product_re=$signed(b_re)*$signed(tw_cos)+$signed(b_im)*$signed(tw_sin);
        product_im=$signed(b_im)*$signed(tw_cos)-$signed(b_re)*$signed(tw_sin);
        tw_re=product_re>>>15; tw_im=product_im>>>15;
        sum_re=($signed(a_re)+$signed(tw_re))>>>1;
        sum_im=($signed(a_im)+$signed(tw_im))>>>1;
        diff_re=($signed(a_re)-$signed(tw_re))>>>1;
        diff_im=($signed(a_im)-$signed(tw_im))>>>1;
        abs_re=a_re[17] ? -$signed(a_re) : a_re;
        abs_im=a_im[17] ? -$signed(a_im) : a_im;
        magnitude=(abs_re>=abs_im)?abs_re+(abs_im>>1):abs_im+(abs_re>>1);

        ram_ena=1'b0; ram_wea=1'b0; ram_enb=1'b0; ram_web=1'b0;
        ram_addra=10'd0; ram_addrb=10'd0;
        real_dina=18'd0; real_dinb=18'd0;
        imag_dina=18'd0; imag_dinb=18'd0;
        case(state)
            CAPTURE: if(sample_valid_in) begin
                ram_ena=1; ram_wea=1; ram_addra=reverse10(capture_count);
                real_dina=windowed_sample; imag_dina=18'd0;
            end
            FFT_READ: begin
                ram_ena=1; ram_enb=1; ram_addra=index_a; ram_addrb=index_b;
            end
            FFT_WRITE: begin
                ram_ena=1; ram_wea=1; ram_enb=1; ram_web=1;
                ram_addra=index_a; ram_addrb=index_b;
                real_dina=sum_re[17:0]; imag_dina=sum_im[17:0];
                real_dinb=diff_re[17:0]; imag_dinb=diff_im[17:0];
            end
            OUTPUT_READ: begin ram_ena=1; ram_addra=output_count; end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=CAPTURE; capture_count<=0; output_count<=0; gap_count<=0;
            stage<=0; butterfly_count<=0; bin_valid<=0; bin_index<=0;
            bin_magnitude<=0; frame_done<=0; busy<=0;
        end else begin
            bin_valid<=0; frame_done<=0;
            case(state)
                CAPTURE: begin
                    busy<=0;
                    if(sample_valid_in) begin
                        if(capture_count==1023) begin
                            capture_count<=0; stage<=0; butterfly_count<=0;
                            state<=FFT_READ; busy<=1;
                        end else capture_count<=capture_count+1'b1;
                    end
                end
                FFT_READ: begin busy<=1; state<=FFT_WRITE; end
                FFT_WRITE: begin
                    busy<=1;
                    if(butterfly_count==511) begin
                        butterfly_count<=0;
                        if(stage==9) begin output_count<=0; state<=OUTPUT_READ; end
                        else begin stage<=stage+1'b1; state<=FFT_READ; end
                    end else begin butterfly_count<=butterfly_count+1'b1; state<=FFT_READ; end
                end
                OUTPUT_READ: begin busy<=1; state<=OUTPUT_EMIT; end
                OUTPUT_EMIT: begin
                    busy<=1; bin_valid<=1; bin_index<=output_count;
                    bin_magnitude<=magnitude;
                    if(output_count==511) begin
                        frame_done<=1; gap_count<=0; state<=GAP; busy<=0;
                    end else begin output_count<=output_count+1'b1; state<=OUTPUT_READ; end
                end
                default: begin
                    busy<=0;
                    if(sample_valid_in) begin
                        if(gap_count==FRAME_GAP_SAMPLES-1) begin
                            gap_count<=0; capture_count<=0; state<=CAPTURE;
                        end else gap_count<=gap_count+1'b1;
                    end
                end
            endcase
        end
    end
endmodule
