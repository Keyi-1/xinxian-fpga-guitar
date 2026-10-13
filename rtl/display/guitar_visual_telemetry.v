// Observer only: no feedback or back-pressure into the audio path.
// Phase follows each audible fundamental, including the existing slide/damp
// policy. Accepted plucks increment counters so short events survive CDC.
module guitar_visual_telemetry #(
    parameter integer HOLD_INACTIVE_PITCH=0
)(
    input wire clk,rst_n,sample_tick,voice_sample_valid,
    input wire [127:0] phase_inc,
    input wire [3:0] note_on,voice_active,
    input wire [15:0] fret_id,
    input wire [95:0] voice_pcm,
    output wire [399:0] snapshot
);
    localparam [31:0] REF_INCREMENT=32'd19685267; // A3, 220 Hz at Fs=48000
    reg [127:0] phase_acc;
    reg [127:0] last_audible_increment;
    wire [127:0] curve_increment;
    reg [31:0] reference_phase;
    reg [31:0] strikes;
    reg [7:0] peak_count;
    reg [23:0] peaks [0:3];
    reg [15:0] levels;
    reg [43:0] hz;
    wire [23:0] magnitudes [0:3];
    genvar g;
    generate for(g=0;g<4;g=g+1) begin : voices
        // A display tail keeps rotating at the last audible pitch. Preparing
        // the next fret while silent must not make that tail jump. No audio
        // control signals are changed; the default preserves other projects.
        assign curve_increment[g*32+:32]=(!HOLD_INACTIVE_PITCH || voice_active[g] || note_on[g])
            ? phase_inc[g*32+:32] : last_audible_increment[g*32+:32];
        wire signed [23:0] pcm=voice_pcm[g*24+:24];
        assign magnitudes[g]=pcm[23] ? -pcm : pcm;
        wire [47:0] increment={16'd0,phase_inc[g*32+:32]};
        // Exact constant 48000 using shifts/adds; no extra audio DSPs.
        wire [47:0] frequency=(increment<<15)+(increment<<13)+(increment<<12)
             +(increment<<11)+(increment<<9)+(increment<<8)+(increment<<7)+48'd2147483648;
        always @(posedge clk) begin
            if(!rst_n) hz[g*11+:11]<=0;
            else hz[g*11+:11]<=frequency[42:32];
        end
    end endgenerate
    assign snapshot={strikes,levels,fret_id,voice_active,hz,reference_phase,curve_increment,phase_acc};
    integer i;
    reg [23:0] maximum;
    always @(posedge clk) begin
        if(!rst_n) begin
            phase_acc<=0;last_audible_increment<=0; reference_phase<=0; strikes<=0; peak_count<=0; levels<=0;
            for(i=0;i<4;i=i+1) peaks[i]<=0;
        end else begin
            for(i=0;i<4;i=i+1)
                if(voice_active[i] || note_on[i])last_audible_increment[i*32+:32]<=phase_inc[i*32+:32];
            if(sample_tick) begin
                reference_phase<=reference_phase+REF_INCREMENT;
                for(i=0;i<4;i=i+1) begin
                    if(note_on[i]) begin
                        phase_acc[i*32+:32]<=0;
                        strikes[i*8+:8]<=strikes[i*8+:8]+1'b1;
                    end else phase_acc[i*32+:32]<=phase_acc[i*32+:32]+curve_increment[i*32+:32];
                end
            end
            if(voice_sample_valid) begin
                peak_count<=peak_count+1'b1;
                for(i=0;i<4;i=i+1) begin
                    maximum=peaks[i]>magnitudes[i] ? peaks[i] : magnitudes[i];
                    if(peak_count==255) begin
                        levels[i*4+:4]<=!voice_active[i] ? 4'd0 :
                            |maximum[23:21] ? 4'd15 : maximum[20:17];
                        peaks[i]<=0;
                    end else peaks[i]<=maximum;
                end
            end
        end
    end
endmodule
