// 1024-point Hann FFT. One shared 18x16 multiplier, two complex work RAMs
// and one window ROM. Twiddles are explicit logic cases, not BSRAMs.
// Captures consecutive 48 kHz samples; analysis pauses about 0.85 ms per FFT.
module guitar_radial_fft(input wire clk,rst_n,sample_valid,
    input wire signed [23:0] pcm,output reg bin_valid,
    output reg [9:0] bin_index,output reg [18:0] bin_magnitude,
    output reg frame_done,output wire busy);
    localparam CAPTURE=0,WINDOW_MUL=1,CAPTURE_WRITE=2,READ=3,LOAD=4,
        MUL0=5,MUL1=6,MUL2=7,MUL3=8,COMBINE=9,WRITE=10,OUT_READ=11,OUT_EMIT=12;
    reg [3:0] state;
    reg [9:0] capture_count,output_count;
    reg [3:0] stage;
    reg [8:0] butterfly;
    reg signed [15:0] hann [0:1023];
    reg signed [15:0] hann_q,pcm16,tw_cos,tw_sin;
    initial $readmemh("../../mem/hann1024_q15.mem",hann);
    always @(posedge clk)hann_q<=hann[capture_count];
    wire [31:0] twiddle;
    reg [9:0] half_size,offset,index_a,index_b;
    reg [8:0] twiddle_index;
    always @* begin
        half_size=10'd1<<stage;
        offset={1'b0,butterfly}&(half_size-1'b1);
        index_a=(({1'b0,butterfly}>>stage)<<(stage+1'b1))+offset;
        index_b=index_a+half_size;
        twiddle_index=offset<<(9-stage);
    end
    guitar_radial_twiddle u_twiddle(.index(twiddle_index),.value(twiddle));
    function [9:0] reverse10;
        input [9:0] value;integer k;
        begin for(k=0;k<10;k=k+1)reverse10[k]=value[9-k];end
    endfunction
    reg ena,wea,enb,web;
    reg [9:0] addra,addrb;
    reg [17:0] rdina,rdinb,idina,idinb;
    wire [17:0] rqa,rqb,iqa,iqb;
    gowin_dpb_ram u_real(.clk(clk),.ena(ena),.wea(wea),.addra(addra),.dina(rdina),.douta(rqa),
        .enb(enb),.web(web),.addrb(addrb),.dinb(rdinb),.doutb(rqb));
    gowin_dpb_ram u_imag(.clk(clk),.ena(ena),.wea(wea),.addra(addra),.dina(idina),.douta(iqa),
        .enb(enb),.web(web),.addrb(addrb),.dinb(idinb),.doutb(iqb));
    reg signed [17:0] windowed,a_re,a_im,b_re,b_im;
    reg signed [18:0] tw_re,tw_im;
    reg signed [33:0] p0,p1,p2,p3;
    reg signed [17:0] mul_a;
    reg signed [15:0] mul_b;
    wire signed [33:0] product=mul_a*mul_b;
    wire signed [34:0] product_re=$signed({p0[33],p0})+$signed({p1[33],p1});
    wire signed [34:0] product_im=$signed({p2[33],p2})-$signed({p3[33],p3});
    wire signed [19:0] sum_re=($signed({{2{a_re[17]}},a_re})+$signed({tw_re[18],tw_re}))>>>1;
    wire signed [19:0] sum_im=($signed({{2{a_im[17]}},a_im})+$signed({tw_im[18],tw_im}))>>>1;
    wire signed [19:0] diff_re=($signed({{2{a_re[17]}},a_re})-$signed({tw_re[18],tw_re}))>>>1;
    wire signed [19:0] diff_im=($signed({{2{a_im[17]}},a_im})-$signed({tw_im[18],tw_im}))>>>1;
    wire [18:0] abs_re=rqa[17] ? -$signed({rqa[17],rqa}) : {1'b0,rqa};
    wire [18:0] abs_im=iqa[17] ? -$signed({iqa[17],iqa}) : {1'b0,iqa};
    always @* begin
        mul_a=b_re;mul_b=tw_cos;
        case(state)
            WINDOW_MUL:begin mul_a={{2{pcm16[15]}},pcm16};mul_b=hann_q;end
            MUL1:begin mul_a=b_im;mul_b=tw_sin;end
            MUL2:begin mul_a=b_im;mul_b=tw_cos;end
            MUL3:begin mul_a=b_re;mul_b=tw_sin;end
            default:begin end
        endcase
        ena=0;enb=0;wea=0;web=0;addra=index_a;addrb=index_b;
        rdina=0;rdinb=0;idina=0;idinb=0;
        case(state)
            CAPTURE_WRITE:begin ena=1;wea=1;addra=reverse10(capture_count);rdina=windowed;end
            READ:begin ena=1;enb=1;end
            WRITE:begin ena=1;wea=1;enb=1;web=1;
                rdina=sum_re[17:0];idina=sum_im[17:0];rdinb=diff_re[17:0];idinb=diff_im[17:0];end
            OUT_READ:begin ena=1;addra=output_count;end
            default:begin end
        endcase
    end
    assign busy=state!=CAPTURE;
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=CAPTURE;capture_count<=0;output_count<=0;stage<=0;butterfly<=0;
            bin_valid<=0;bin_index<=0;bin_magnitude<=0;frame_done<=0;
            pcm16<=0;windowed<=0;a_re<=0;a_im<=0;b_re<=0;b_im<=0;
            tw_cos<=0;tw_sin<=0;p0<=0;p1<=0;p2<=0;p3<=0;tw_re<=0;tw_im<=0;
        end else begin
            bin_valid<=0;frame_done<=0;
            case(state)
                CAPTURE:if(sample_valid)begin pcm16<=pcm[23:8];state<=WINDOW_MUL;end
                WINDOW_MUL:begin windowed<=product>>>15;state<=CAPTURE_WRITE;end
                CAPTURE_WRITE:if(capture_count==1023)begin
                    capture_count<=0;stage<=0;butterfly<=0;state<=READ;
                end else begin capture_count<=capture_count+1'b1;state<=CAPTURE;end
                READ:state<=LOAD;
                LOAD:begin
                    a_re<=rqa;a_im<=iqa;b_re<=rqb;b_im<=iqb;
                    tw_cos<=twiddle[31:16];tw_sin<=twiddle[15:0];state<=MUL0;
                end
                MUL0:begin p0<=product;state<=MUL1;end
                MUL1:begin p1<=product;state<=MUL2;end
                MUL2:begin p2<=product;state<=MUL3;end
                MUL3:begin p3<=product;state<=COMBINE;end
                COMBINE:begin tw_re<=product_re>>>15;tw_im<=product_im>>>15;state<=WRITE;end
                WRITE:if(butterfly==511)begin
                    butterfly<=0;
                    if(stage==9)begin output_count<=0;state<=OUT_READ;end
                    else begin stage<=stage+1'b1;state<=READ;end
                end else begin butterfly<=butterfly+1'b1;state<=READ;end
                OUT_READ:state<=OUT_EMIT;
                OUT_EMIT:begin
                    bin_valid<=1;bin_index<=output_count;
                    bin_magnitude<=abs_re>=abs_im ? abs_re+(abs_im>>1) : abs_im+(abs_re>>1);
                    if(output_count==512)begin frame_done<=1;state<=CAPTURE;end
                    else begin output_count<=output_count+1'b1;state<=OUT_READ;end
                end
                default:state<=CAPTURE;
            endcase
        end
    end
endmodule
