// Body axes: X along neck, +Z outward through the front of the instrument.
// Neck-up and neck-down use the same inclination limits. The mounting may
// reverse X/Y without changing the flat/guitar classification.
// 100Hz, +/-4g (8192LSB/g), +/-250dps (131LSB/dps). Explicit stationary,
// face-up calibration; no orientation decision before calibration/health.
module imu_posture_classifier #(
    parameter integer CALIBRATION_LOG2=8,
    parameter integer HEALTH_MS=1000,STABLE_MS=500,COOLDOWN_MS=1000,
    parameter integer MAX_GAP_MS=30,OFFLINE_MS=100
)(input wire clk,rst_n,tick_ms,calibrate,reader_ready,sample_valid,
  input wire [15:0] sample_sequence,
  input wire signed [16:0] ax,ay,az,gx,gy,gz,
  output reg calibrated,calibrating,healthy,
  output reg [1:0] stable_pose,output reg pose_event,
  output wire pose_timbre_valid,output wire [1:0] pose_timbre,
  output wire busy,output reg deadline_miss);
    localparam UNKNOWN=0,FACE_UP=1,GUITAR=2,UPRIGHT=3;
    reg [31:0] now_ms,last_ms,health_since,candidate_since,last_auto_ms;
    reg [15:0] last_sequence;
    reg seen,candidate_valid,filter_initialized;
    reg [1:0] candidate_pose;
    reg [CALIBRATION_LOG2:0] calibration_count;
    reg signed [31:0] sum_ax,sum_ay,sum_az,sum_gx,sum_gy,sum_gz;
    reg signed [16:0] bias_ax,bias_ay,bias_az,bias_gx,bias_gy,bias_gz;
    reg signed [16:0] calibration_x,calibration_y,calibration_z;
    wire signed [17:0] calibration_dx={ax[16],ax}-{calibration_x[16],calibration_x};
    wire signed [17:0] calibration_dy={ay[16],ay}-{calibration_y[16],calibration_y};
    wire signed [17:0] calibration_dz={az[16],az}-{calibration_z[16],calibration_z};
    wire signed [17:0] cx_wide={ax[16],ax}-{bias_ax[16],bias_ax};
    wire signed [17:0] cy_wide={ay[16],ay}-{bias_ay[16],bias_ay};
    wire signed [17:0] cz_wide={az[16],az}-{bias_az[16],bias_az};
    wire signed [17:0] cgx={gx[16],gx}-{bias_gx[16],bias_gx};
    wire signed [17:0] cgy={gy[16],gy}-{bias_gy[16],bias_gy};
    wire signed [17:0] cgz={gz[16],gz}-{bias_gz[16],bias_gz};
    // Corrected values beyond 17-bit signed bounds are rejected, not truncated.
    wire corrected_range=cx_wide[17]==cx_wide[16] && cy_wide[17]==cy_wide[16] && cz_wide[17]==cz_wide[16];
    wire signed [16:0] cx=cx_wide[16:0],cy=cy_wide[16:0],cz=cz_wide[16:0];
    reg signed [21:0] filter_x,filter_y,filter_z;
    wire signed [21:0] tx={{1{cx[16]}},cx,4'd0};
    wire signed [21:0] ty={{1{cy[16]}},cy,4'd0};
    wire signed [21:0] tz={{1{cz[16]}},cz,4'd0};
    wire signed [21:0] next_fx=filter_initialized ? filter_x+((tx-filter_x)>>>3) : tx;
    wire signed [21:0] next_fy=filter_initialized ? filter_y+((ty-filter_y)>>>3) : ty;
    wire signed [21:0] next_fz=filter_initialized ? filter_z+((tz-filter_z)>>>3) : tz;
    reg signed [16:0] previous_x,previous_y,previous_z;
    wire signed [17:0] dx={cx[16],cx}-{previous_x[16],previous_x};
    wire signed [17:0] dy={cy[16],cy}-{previous_y[16],previous_y};
    wire signed [17:0] dz={cz[16],cz}-{previous_z[16],previous_z};
    wire saturated=ax>=32700 || ax<=-32700 || ay>=32700 || ay<=-32700 || az>=32700 || az<=-32700 ||
        gx>=32700 || gx<=-32700 || gy>=32700 || gy<=-32700 || gz>=32700 || gz<=-32700;
    wire fresh=sample_valid && (!seen || sample_sequence!=last_sequence);
    wire [31:0] gap=now_ms-last_ms;
    wire calibration_ok=!saturated && ax>-2048 && ax<2048 && ay>-2048 && ay<2048 && az>7000 && az<9500 &&
        gx>-500 && gx<500 && gy>-500 && gy<500 && gz>-500 && gz<500 && (!seen || gap<=MAX_GAP_MS) &&
        (calibration_count==0 || (calibration_dx>-983 && calibration_dx<983 &&
         calibration_dy>-983 && calibration_dy<983 && calibration_dz>-983 && calibration_dz<983));
    reg [1:0] state;
    reg [3:0] operation;
    reg good_motion;
    reg signed [16:0] raw_x,raw_y,raw_z,filtered_x,filtered_y,filtered_z;
    reg [35:0] raw_norm,x_squared,y_squared,z_squared,norm;
    reg [71:0] enter_ratio,guitar_hold_z,guitar_hold_x;
    reg multiply_start;
    wire multiply_busy,multiply_done;
    wire [71:0] product;
    reg [35:0] operand_a,operand_b;
    function [16:0] magnitude;
        input signed [16:0] value;
        begin magnitude=value[16] ? -value : value;end
    endfunction
    always @*begin
        operand_a=0;operand_b=0;
        case(operation)
            0:begin operand_a={19'd0,magnitude(raw_x)};operand_b=operand_a;end
            1:begin operand_a={19'd0,magnitude(raw_y)};operand_b=operand_a;end
            2:begin operand_a={19'd0,magnitude(raw_z)};operand_b=operand_a;end
            3:begin operand_a={19'd0,magnitude(filtered_x)};operand_b=operand_a;end
            4:begin operand_a={19'd0,magnitude(filtered_y)};operand_b=operand_a;end
            5:begin operand_a={19'd0,magnitude(filtered_z)};operand_b=operand_a;end
            6:begin operand_a=norm;operand_b=36'd28935;end
            7:begin operand_a=norm;operand_b=36'd21988;end
            8:begin operand_a=norm;operand_b=36'd26915;end
            default:begin end
        endcase
    end
    imu_serial_multiplier arithmetic(.clk(clk),.rst_n(rst_n),.start(multiply_start),
        .a(operand_a),.b(operand_b),.busy(multiply_busy),.done(multiply_done),.product(product));
    assign busy=state!=0;
    assign pose_timbre_valid=stable_pose==FACE_UP || stable_pose==GUITAR;
    assign pose_timbre=stable_pose==GUITAR ? 2'd1 : 2'd0;
    reg [1:0] classified;
    reg holding;
    wire [71:0] xs={36'd0,x_squared}<<15,zs={36'd0,z_squared}<<15;
    wire [35:0] norm_three=norm+(norm<<1);
    always @*begin
        holding=0;classified=UNKNOWN;
        case(stable_pose)
            FACE_UP:holding=filtered_z>0 && (z_squared<<2)>=norm_three;
            GUITAR:holding=filtered_z>=0 && zs<=guitar_hold_z && xs<=guitar_hold_x;
            UPRIGHT:holding=filtered_z>=-1229 && (x_squared<<2)>=norm_three;
            default:holding=0;
        endcase
        if(holding)classified=stable_pose;
        else if(filtered_z>0 && zs>=enter_ratio)classified=FACE_UP;
        else if(filtered_z>=-1229 && xs>=enter_ratio)classified=UPRIGHT;
        else if(filtered_z>=0 && (z_squared<<1)<=norm && (x_squared<<2)<=norm_three)classified=GUITAR;
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            now_ms<=0;last_ms<=0;health_since<=0;candidate_since<=0;last_auto_ms<=0;
            last_sequence<=0;seen<=0;calibrated<=0;calibrating<=0;healthy<=0;
            stable_pose<=UNKNOWN;candidate_pose<=UNKNOWN;candidate_valid<=0;pose_event<=0;
            calibration_count<=0;sum_ax<=0;sum_ay<=0;sum_az<=0;sum_gx<=0;sum_gy<=0;sum_gz<=0;
            bias_ax<=0;bias_ay<=0;bias_az<=0;bias_gx<=0;bias_gy<=0;bias_gz<=0;
            calibration_x<=0;calibration_y<=0;calibration_z<=0;
            filter_x<=0;filter_y<=0;filter_z<=0;filter_initialized<=0;
            previous_x<=0;previous_y<=0;previous_z<=0;state<=0;operation<=0;
            good_motion<=0;raw_x<=0;raw_y<=0;raw_z<=0;filtered_x<=0;filtered_y<=0;filtered_z<=0;
            raw_norm<=0;x_squared<=0;y_squared<=0;z_squared<=0;norm<=0;
            enter_ratio<=0;guitar_hold_z<=0;guitar_hold_x<=0;multiply_start<=0;deadline_miss<=0;
        end else begin
            if(tick_ms)now_ms<=now_ms+1'b1;
            pose_event<=0;multiply_start<=0;
            if(!reader_ready || (seen && gap>=OFFLINE_MS))begin
                healthy<=0;health_since<=now_ms;candidate_valid<=0;
                if(calibrating)begin
                    calibration_count<=0;sum_ax<=0;sum_ay<=0;sum_az<=0;sum_gx<=0;sum_gy<=0;sum_gz<=0;
                end
            end
            if(calibrate)begin
                calibrated<=0;calibrating<=1;healthy<=0;calibration_count<=0;
                sum_ax<=0;sum_ay<=0;sum_az<=0;sum_gx<=0;sum_gy<=0;sum_gz<=0;
                filter_initialized<=0;candidate_valid<=0;stable_pose<=UNKNOWN;
            end else if(fresh && reader_ready)begin
                seen<=1;last_sequence<=sample_sequence;last_ms<=now_ms;
                if(calibrating)begin
                    calibration_x<=ax;calibration_y<=ay;calibration_z<=az;
                    if(!calibration_ok)begin
                        calibration_count<=0;sum_ax<=0;sum_ay<=0;sum_az<=0;sum_gx<=0;sum_gy<=0;sum_gz<=0;
                    end else begin
                        sum_ax<=sum_ax+ax;sum_ay<=sum_ay+ay;sum_az<=sum_az+az;
                        sum_gx<=sum_gx+gx;sum_gy<=sum_gy+gy;sum_gz<=sum_gz+gz;
                        if(calibration_count==(1<<CALIBRATION_LOG2)-1)begin
                            bias_ax<=(sum_ax+ax)>>>CALIBRATION_LOG2;
                            bias_ay<=(sum_ay+ay)>>>CALIBRATION_LOG2;
                            bias_az<=((sum_az+az)>>>CALIBRATION_LOG2)-8192;
                            bias_gx<=(sum_gx+gx)>>>CALIBRATION_LOG2;
                            bias_gy<=(sum_gy+gy)>>>CALIBRATION_LOG2;
                            bias_gz<=(sum_gz+gz)>>>CALIBRATION_LOG2;
                            calibrated<=1;calibrating<=0;healthy<=0;health_since<=now_ms;
                        end else calibration_count<=calibration_count+1'b1;
                    end
                end else if(calibrated)begin
                    if(!seen || gap>MAX_GAP_MS)begin healthy<=0;health_since<=now_ms;candidate_valid<=0;end
                    else if(now_ms-health_since>=HEALTH_MS)healthy<=1;
                    if(state!=0)begin deadline_miss<=1;candidate_valid<=0;end
                    else if(corrected_range && !saturated)begin
                        raw_x<=cx;raw_y<=cy;raw_z<=cz;
                        filter_x<=next_fx;filter_y<=next_fy;filter_z<=next_fz;filter_initialized<=1;
                        filtered_x<=next_fx>>>4;filtered_y<=next_fy>>>4;filtered_z<=next_fz>>>4;
                        good_motion<=filter_initialized && gap<=MAX_GAP_MS &&
                            cgx>-3275 && cgx<3275 && cgy>-3275 && cgy<3275 && cgz>-3275 && cgz<3275 &&
                            dx>-983 && dx<983 && dy>-983 && dy<983 && dz>-983 && dz<983;
                        previous_x<=cx;previous_y<=cy;previous_z<=cz;
                        state<=1;operation<=0;
                    end else candidate_valid<=0;
                end
            end
            case(state)
                1:if(!multiply_busy)begin multiply_start<=1;state<=2;end
                2:if(multiply_done)begin
                    case(operation)
                        0:raw_norm<=product[35:0];
                        1,2:raw_norm<=raw_norm+product[35:0];
                        3:begin x_squared<=product[35:0];norm<=product[35:0];end
                        4:begin y_squared<=product[35:0];norm<=norm+product[35:0];end
                        5:begin z_squared<=product[35:0];norm<=norm+product[35:0];end
                        6:enter_ratio<=product;
                        7:guitar_hold_z<=product;
                        8:guitar_hold_x<=product;
                        default:begin end
                    endcase
                    if(operation==8)state<=3;
                    else begin operation<=operation+1'b1;state<=1;end
                end
                3:begin
                    state<=0;
                    if(calibrate || !reader_ready || !calibrated || !healthy || gap>MAX_GAP_MS || !good_motion ||
                       raw_norm<42949673 || raw_norm>96636764 || norm<42949673 || norm>96636764 || classified==UNKNOWN)candidate_valid<=0;
                    else if(classified==stable_pose)candidate_valid<=0;
                    else if(!candidate_valid || candidate_pose!=classified)begin
                        candidate_pose<=classified;candidate_since<=now_ms;candidate_valid<=1;
                    end else if(now_ms-candidate_since>=STABLE_MS && now_ms-last_auto_ms>=COOLDOWN_MS)begin
                        stable_pose<=classified;pose_event<=1;last_auto_ms<=now_ms;candidate_valid<=0;
                    end
                end
                default:begin end
            endcase
        end
    end
endmodule
