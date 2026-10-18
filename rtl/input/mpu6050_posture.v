// Sensor-frame to body-frame mapping is explicit and synthesizes to wires.
// Default mounting: module +X toward neck, +Z toward front, +Y completes axes.
module mpu6050_posture #(
    parameter integer CLK_HZ=50000000,I2C_QUARTER=125,
    parameter integer BODY_X_AXIS=0,BODY_Y_AXIS=1,BODY_Z_AXIS=2,
    parameter integer BODY_X_NEGATE=0,BODY_Y_NEGATE=0,BODY_Z_NEGATE=0,
    parameter integer CALIBRATION_LOG2=8,HEALTH_MS=1000,STABLE_MS=500,COOLDOWN_MS=1000
)(input wire clk,rst_n,tick_ms,calibrate,inout wire scl,sda,
  output wire ready,calibrated,calibrating,healthy,
  output wire [1:0] stable_pose,output wire pose_event,pose_timbre_valid,
  output wire [1:0] pose_timbre,output wire deadline_miss);
    wire sample_valid;
    wire signed [15:0] ax,ay,az,gx,gy,gz;
    wire [15:0] sample_sequence;
    function signed [16:0] axis;
        input integer which;
        input signed [15:0] x,y,z;
        case(which)
            0:axis={x[15],x};1:axis={y[15],y};default:axis={z[15],z};
        endcase
    endfunction
    wire signed [16:0] body_ax=BODY_X_NEGATE ? -axis(BODY_X_AXIS,ax,ay,az) : axis(BODY_X_AXIS,ax,ay,az);
    wire signed [16:0] body_ay=BODY_Y_NEGATE ? -axis(BODY_Y_AXIS,ax,ay,az) : axis(BODY_Y_AXIS,ax,ay,az);
    wire signed [16:0] body_az=BODY_Z_NEGATE ? -axis(BODY_Z_AXIS,ax,ay,az) : axis(BODY_Z_AXIS,ax,ay,az);
    wire signed [16:0] body_gx=BODY_X_NEGATE ? -axis(BODY_X_AXIS,gx,gy,gz) : axis(BODY_X_AXIS,gx,gy,gz);
    wire signed [16:0] body_gy=BODY_Y_NEGATE ? -axis(BODY_Y_AXIS,gx,gy,gz) : axis(BODY_Y_AXIS,gx,gy,gz);
    wire signed [16:0] body_gz=BODY_Z_NEGATE ? -axis(BODY_Z_AXIS,gx,gy,gz) : axis(BODY_Z_AXIS,gx,gy,gz);
    mpu6050_reader #(.CLK_HZ(CLK_HZ),.I2C_QUARTER(I2C_QUARTER)) reader(
        .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.scl(scl),.sda(sda),.ready(ready),.sample_valid(sample_valid),
        .ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),.sample_sequence(sample_sequence),.fault_count(),.fault_code());
    imu_posture_classifier #(.CALIBRATION_LOG2(CALIBRATION_LOG2),.HEALTH_MS(HEALTH_MS),
        .STABLE_MS(STABLE_MS),.COOLDOWN_MS(COOLDOWN_MS)) classifier(
        .clk(clk),.rst_n(rst_n),.tick_ms(tick_ms),.calibrate(calibrate),.reader_ready(ready),
        .sample_valid(sample_valid),.sample_sequence(sample_sequence),
        .ax(body_ax),.ay(body_ay),.az(body_az),.gx(body_gx),.gy(body_gy),.gz(body_gz),
        .calibrated(calibrated),.calibrating(calibrating),.healthy(healthy),
        .stable_pose(stable_pose),.pose_event(pose_event),.pose_timbre_valid(pose_timbre_valid),
        .pose_timbre(pose_timbre),.busy(),.deadline_miss(deadline_miss));
endmodule
