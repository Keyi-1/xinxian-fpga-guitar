// Key 1 cycles piano/bright/rock. Key 2 short release toggles chorus, long hold
// toggles harmony. Key 3 cycles dry/sustain/light room once per qualified press.
module guitar_effect_buttons #(
    parameter integer DEBOUNCE_CYCLES=245760,
    parameter integer LONG_PRESS_CYCLES=12288000,
    parameter integer LONG_PRESS_ENABLE=1,EXTERNAL_TIMBRE_ENABLE=0
)(
    input wire clk,rst_n,key_timbre_n,key_chorus_n,key_space_n,
    input wire load_timbre,input wire [1:0] loaded_timbre,
    output wire timbre_select,rock_select,
    output reg [1:0] timbre_mode,
    output reg chorus_enable,
    output wire sustain_enable,reverb_enable,
    output reg [1:0] space_mode,
    output reg harmony_enable,
    output wire manual_timbre_press
);
    wire timbre_press,unused_timbre_state,unused_space_state,space_press;
    assign manual_timbre_press=timbre_press;
    debounced_toggle #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_timbre(
        .clk(clk),.rst_n(rst_n),.button_n(key_timbre_n),
        .toggle_state(unused_timbre_state),.pressed_pulse(timbre_press));
    debounced_toggle #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_space(
        .clk(clk),.rst_n(rst_n),.button_n(key_space_n),
        .toggle_state(unused_space_state),.pressed_pulse(space_press));
    reg sync1,sync2,stable_n,long_sent;
    reg [31:0] debounce_count,hold_count;
    assign sustain_enable=space_mode==1;
    assign reverb_enable=space_mode==2;
    assign timbre_select=timbre_mode==1;
    assign rock_select=timbre_mode==2;
    always @(posedge clk) begin
        if(!rst_n)begin
            sync1<=1;sync2<=1;stable_n<=1;long_sent<=0;
            debounce_count<=0;hold_count<=0;space_mode<=0;timbre_mode<=0;harmony_enable<=0;chorus_enable<=0;
        end else begin
            sync1<=key_chorus_n;sync2<=sync1;
            if(EXTERNAL_TIMBRE_ENABLE && load_timbre && loaded_timbre<=2)timbre_mode<=loaded_timbre;
            else if(timbre_press)timbre_mode<=timbre_mode==2 ? 2'd0 : timbre_mode+1'b1;
            if(space_press)space_mode<=space_mode==2 ? 2'd0 : space_mode+1'b1;
            if(sync2==stable_n)debounce_count<=0;
            else if(DEBOUNCE_CYCLES<=1 || debounce_count>=DEBOUNCE_CYCLES-1)begin
                stable_n<=sync2;debounce_count<=0;
                if(!sync2)begin hold_count<=0;long_sent<=0;end
                else if(!long_sent)chorus_enable<=~chorus_enable;
            end else debounce_count<=debounce_count+1'b1;
            // Stop counting when the physical key has been released, including
            // its release debounce interval, so a short press stays short.
            if(!stable_n && !sync2 && !long_sent)begin
                if(LONG_PRESS_ENABLE!=0 && hold_count>=LONG_PRESS_CYCLES-1)begin
                    harmony_enable<=~harmony_enable;long_sent<=1;
                end else if(hold_count<LONG_PRESS_CYCLES)hold_count<=hold_count+1'b1;
            end
        end
    end
endmodule
