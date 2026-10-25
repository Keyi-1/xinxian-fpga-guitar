`include "../config/guitar_config.vh"

// Observe fret contacts without delaying or replacing the playing policy.
// Three qualified releases/re-presses on one sounding string enable vibrato.
// A release still selects the open string immediately in guitar_play_control.
module vibrato_v2_performance_vibrato_gesture #(
    parameter integer TAP_COUNT=`VIBRATO_TAP_COUNT,
    parameter integer MIN_RELEASE_SAMPLES=`VIBRATO_MIN_TAP_SAMPLES,
    parameter integer MAX_RELEASE_SAMPLES=`VIBRATO_MAX_TAP_SAMPLES,
    parameter integer WINDOW_SAMPLES=`VIBRATO_WINDOW_SAMPLES
)(input wire clk,rst_n,sample_tick,enable,stable_valid,
  input wire [15:0] stable_fret_id,
  input wire [3:0] pluck_valid,note_on,voice_active,
  output reg [3:0] vibrato_enable);
    function integer bits_needed;
        input integer maximum;
        integer value;
        begin
            value=maximum;bits_needed=0;
            while(value>0)begin bits_needed=bits_needed+1;value=value>>1;end
            if(bits_needed<1)bits_needed=1;
        end
    endfunction
    localparam RELEASE_BITS=bits_needed(MAX_RELEASE_SAMPLES+1);
    localparam WINDOW_BITS=bits_needed(WINDOW_SAMPLES+1);
    localparam TAP_BITS=bits_needed(TAP_COUNT-1);
    reg [15:0] previous_fret;
    reg [3:0] gesture_fret[0:3];
    reg [TAP_BITS-1:0] taps[0:3];
    reg [RELEASE_BITS-1:0] release_samples[0:3];
    reg [WINDOW_BITS-1:0] window_samples[0:3];
    reg [3:0] pending,window_active;
    integer i;
    always @(posedge clk)begin
        if(!rst_n)begin
            previous_fret<=0;vibrato_enable<=0;pending<=0;window_active<=0;
            for(i=0;i<4;i=i+1)begin
                gesture_fret[i]<=0;taps[i]<=0;release_samples[i]<=0;window_samples[i]<=0;
            end
        end else begin
            if(stable_valid)previous_fret<=stable_fret_id;
            for(i=0;i<4;i=i+1)begin
                if(!enable || !voice_active[i] || pluck_valid[i] || note_on[i])begin
                    vibrato_enable[i]<=0;pending[i]<=0;window_active[i]<=0;
                    taps[i]<=0;release_samples[i]<=0;window_samples[i]<=0;
                end else begin
                    if(sample_tick)begin
                        if(pending[i] && release_samples[i]<MAX_RELEASE_SAMPLES+1)
                            release_samples[i]<=release_samples[i]+1'b1;
                        if(window_active[i])begin
                            if(window_samples[i]>=WINDOW_SAMPLES)begin
                                window_active[i]<=0;pending[i]<=0;taps[i]<=0;
                            end else window_samples[i]<=window_samples[i]+1'b1;
                        end
                    end
                    if(stable_valid && stable_fret_id[i*4+:4]!=previous_fret[i*4+:4])begin
                        if(stable_fret_id[i*4+:4]==0)begin
                            // Recognition never holds the old pitch or gates the envelope.
                            vibrato_enable[i]<=0;pending[i]<=1;release_samples[i]<=0;
                            gesture_fret[i]<=previous_fret[i*4+:4];
                            if(!window_active[i] || gesture_fret[i]!=previous_fret[i*4+:4] ||
                               window_samples[i]>=WINDOW_SAMPLES)begin
                                window_active[i]<=1;window_samples[i]<=0;taps[i]<=0;
                            end
                        end else if(pending[i] && window_active[i] &&
                                    window_samples[i]<WINDOW_SAMPLES &&
                                    stable_fret_id[i*4+:4]==gesture_fret[i] &&
                                    release_samples[i]>=MIN_RELEASE_SAMPLES &&
                                    release_samples[i]<=MAX_RELEASE_SAMPLES)begin
                            pending[i]<=0;release_samples[i]<=0;
                            if(taps[i]==TAP_COUNT-1)begin
                                vibrato_enable[i]<=1;window_active[i]<=0;taps[i]<=0;
                            end else taps[i]<=taps[i]+1'b1;
                        end else begin
                            vibrato_enable[i]<=0;pending[i]<=0;window_active[i]<=0;taps[i]<=0;
                        end
                    end
                end
            end
        end
    end
endmodule
