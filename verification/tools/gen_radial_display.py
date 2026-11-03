"""Generate display-only logic tables and a separate, native 150px renderer."""
from pathlib import Path
import math

root = Path(__file__).resolve().parent.parent
display = root / 'rtl/display'
cos = [int(x, 16) for x in (root/'mem/fft1024_cos_q15.mem').read_text().split()]
sin = [int(x, 16) for x in (root/'mem/fft1024_sin_q15.mem').read_text().split()]
assert len(cos) == len(sin) == 512
lines = ['// Explicit asynchronous logic lookup: no additional FFT RAM.',
         'module guitar_radial_twiddle(input wire [8:0] index,output reg [31:0] value) /* synthesis syn_romstyle="logic" */;',
         '    always @* case(index)']
lines += [f"        9'd{i}:value=32'h{c:04x}{s:04x};" for i,(c,s) in enumerate(zip(cos,sin))]
lines += ["        default:value=32'h7fff0000;",'    endcase','endmodule','']
(display/'guitar_radial_twiddle.v').write_text('\n'.join(lines),encoding='utf-8')
lines = ['// asin((y-135.5)/74.5), principal phase Q16. Explicit logic table.',
         'module guitar_radial_arcsine(input wire clk,input wire [7:0] y,',
         '    output reg signed [17:0] theta) /* synthesis syn_romstyle="logic" */;',
         '    reg signed [17:0] value;', '    always @* case(y)']
for y in range(256):
    v = round(math.asin(max(-1,min(1,(2*y-271)/149)))*65536/(2*math.pi))
    lines.append(f"        8'd{y}:value=18'h{v&0x3ffff:05x};")
lines += ["        default:value=18'sd0;",'    endcase',
          '    always @(posedge clk)theta<=value;','endmodule','']
(display/'guitar_radial_arcsine.v').write_text('\n'.join(lines),encoding='utf-8')
s = (display/'guitar_lissajous_renderer.v').read_text()
s = s.replace('centered (240,136), radius 94','centered (343.5,135.5), radius 74.5')
s = s.replace('module guitar_lissajous_renderer','module guitar_radial_curve_renderer')
s = s.replace('guitar_lissajous_arcsine','guitar_radial_arcsine')
s = s.replace('wire signed [17:0] scaled=(extended_sine<<<6)+(extended_sine<<<5)-(extended_sine<<<1);',
    'wire signed [17:0] scaled=(extended_sine<<<7)+(extended_sine<<<4)+(extended_sine<<<2)+extended_sine;')
s = s.replace('row_y<42 || row_y>230','row_y<61 || row_y>210')
s = s.replace("point<=16'sd15360+($signed(scaled)>>>3)","point<=16'sd21984+($signed(scaled)>>>4)")
s = s.replace('output reg [3:0] display_active,display_flash,output reg deadline_miss);',
    'output reg [3:0] display_active,display_flash,output reg deadline_miss,\n'
    '    output wire [31:0] display_strikes,output reg visual_update);')
s = s.replace('    reg [399:0] pending,history;',
    '    reg [399:0] pending,history;\n    assign display_strikes=pending[399:368];')
s = s.replace('state<=INIT;front_bank<=0;', 'visual_update<=0;state<=INIT;front_bank<=0;')
s = s.replace('            previous_line_condition<=line_condition;',
    '            visual_update<=0;previous_line_condition<=line_condition;')
s = s.replace('history<=pending;pending<=snapshot;previous_valid<=0;',
    'visual_update<=1;history<=pending;pending<=snapshot;previous_valid<=0;')
s=s.replace('input wire [399:0] snapshot,input wire [8:0] pixel_x,pixel_y,',
    'input wire [399:0] snapshot,input wire [3:0] curve_active,input wire [8:0] pixel_x,pixel_y,')
s=s.replace('    reg [399:0] pending,history;',
    '    reg [399:0] pending,history;\n    reg [3:0] current_curve_active,history_curve_active;')
s=s.replace('pending<=0;history<=0;previous_strikes<=0;',
    'pending<=0;history<=0;current_curve_active<=0;history_curve_active<=0;previous_strikes<=0;')
s=s.replace('visual_update<=1;history<=pending;pending<=snapshot;previous_valid<=0;',
    'visual_update<=1;history<=pending;pending<=snapshot;previous_valid<=0;\n'
    '                    history_curve_active<=current_curve_active;')
s=s.replace('if(voice==3)state<=WAIT;',
    'if(voice==3)begin current_curve_active<=curve_active;state<=WAIT;end')
s=s.replace('!pending[332+voice] || (ghost && !history[332+voice])',
    '!current_curve_active[voice] || (ghost && !history_curve_active[voice])')
(display/'guitar_radial_curve_renderer.v').write_text(s,encoding='utf-8')
print('Generated radial twiddle, arcsine and 150px native curve renderer')
