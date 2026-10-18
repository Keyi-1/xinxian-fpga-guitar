// AUTO prototype: only changes the existing selection when audio is idle.
// No note/PA/effect/clock outputs; the current button module remains the owner
// of the final timbre enum and therefore continues cycling from that value.
module posture_timbre_policy #(
    parameter integer QUIET_BOUNDARIES=2
)(input wire clk,rst_n,sample_tick,
  input wire auto_enable,sensor_healthy,performance_mode,mode_switching,
  input wire manual_press,explicit_timbre_load,
  input wire pose_event,input wire [1:0] pose_timbre,current_timbre,
  input wire [3:0] voice_active,pending_note_on,
  input wire pipeline_idle,timbre_busy,
  output wire load_timbre,output reg [1:0] loaded_timbre,output reg pending);
    reg request_load;
    reg [1:0] target;
    reg [7:0] quiet;
    wire enabled=auto_enable && sensor_healthy && performance_mode && !mode_switching;
    wire quiet_sources=voice_active==0 && pending_note_on==0 && !timbre_busy;
    wire silent=quiet_sources && pipeline_idle;
    // Also mask an already registered request on the consumer's edge, so a
    // manual press one clock after the quiet decision still wins.
    assign load_timbre=request_load && enabled && silent && !pose_event && !manual_press && !explicit_timbre_load;
    always @(posedge clk)begin
        if(!rst_n)begin pending<=0;target<=0;quiet<=0;request_load<=0;loaded_timbre<=0;end
        else begin
            request_load<=0;
            if(!enabled || manual_press || explicit_timbre_load)begin pending<=0;quiet<=0;end
            else if(pose_event)begin
                // A fresh target never inherits quiet time from an older one.
                pending<=pose_timbre<=1 && pose_timbre!=current_timbre;
                target<=pose_timbre;quiet<=0;
            end else if(request_load && !silent)begin
                // A pluck arriving on the consuming edge defers the target.
                pending<=1;quiet<=0;
            end else if(!quiet_sources)quiet<=0;
            else if(sample_tick && pending)begin
                // Zero-valued audio still produces valid pulses every frame.
                // Drain is checked at frame boundaries, not throughout the
                // frame, otherwise those normal pulses prevent any progress.
                if(!pipeline_idle)quiet<=0;
                else if(target==current_timbre)begin pending<=0;quiet<=0;end
                else if(quiet>=QUIET_BOUNDARIES)begin
                    request_load<=1;loaded_timbre<=target;pending<=0;quiet<=0;
                end else quiet<=quiet+1'b1;
            end
        end
    end
endmodule
