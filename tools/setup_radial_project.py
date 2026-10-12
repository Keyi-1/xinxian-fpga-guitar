"""Create the separate physical project and adapt the established tests."""
from pathlib import Path
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parent.parent
old=root/'gowin/neo_guitar_lissajous'
new=root/'gowin/neo_guitar_radial'
new.mkdir(exist_ok=True)
extra=['rtl/top/neo_guitar_radial_top.v','rtl/display/guitar_pcm_cdc.v',
    'rtl/display/guitar_radial_display.v','rtl/display/guitar_radial_fft.v',
    'rtl/display/guitar_radial_twiddle.v','rtl/display/guitar_radial_bands.v',
    'rtl/display/guitar_radial_arcsine.v','rtl/display/guitar_radial_curve_renderer.v',
    'rtl/display/guitar_radial_palette.v','rtl/display/gowin_dpb_ram.v']
build=(old/'build.tcl').read_text().replace('neo_guitar_lissajous','neo_guitar_radial')
build=build.replace('    rtl/top/neo_guitar_radial_top.v\n','')
build=build.replace('} { add_file', '\n'.join('    '+p for p in extra)+'\n} { add_file')
(new/'build.tcl').write_text(build,encoding='utf-8')
for ext in ('cst','sdc'):
    (root/f'constraints/neo_guitar_radial.{ext}').write_text(
        (root/f'constraints/neo_guitar_lissajous.{ext}').read_text(),encoding='utf-8')
tree=ET.parse(old/'neo_guitar_lissajous.gprj');files=tree.getroot().find('FileList')
for f in files:
    if f.get('path').endswith('neo_guitar_lissajous_top.v'): files.remove(f)
    elif 'constraints/neo_guitar_lissajous.' in f.get('path'):
        f.set('path',f.get('path').replace('neo_guitar_lissajous','neo_guitar_radial'))
for p in extra:
    ET.SubElement(files,'File',path='../../'+p,type='file.verilog',enable='1')
for p in ['mem/hann1024_q15.mem','mem/fft1024_cos_q15.mem','mem/fft1024_sin_q15.mem']:
    ET.SubElement(files,'File',path='../../'+p,type='file.other',enable='1')
ET.indent(tree,space='    ');tree.write(new/'neo_guitar_radial.gprj',encoding='utf-8',xml_declaration=True)
s=(root/'sim/tb/tb_guitar_lissajous_renderer.sv').read_text().replace('tb_guitar_lissajous_renderer','tb_guitar_radial_renderer')
s=s.replace('guitar_lissajous_renderer dut','guitar_radial_curve_renderer dut')
s=s.replace('.deadline_miss(miss)', '.deadline_miss(miss),.visual_update(),.display_strikes()')
s=s.replace('px<142 || px>337 || row<42 || row>230','px<266 || px>422 || row<61 || row>210')
s=s.replace('row>=42 && row<=230','row>=61 && row<=210')
s=s.replace('(row-136.0)/94.0','(row-135.5)/74.5').replace('xx=240+94*','xx=343.5+74.5*')
(root/'sim/tb/tb_guitar_radial_renderer.sv').write_text(s,encoding='utf-8')
s=(root/'sim/tb/tb_neo_guitar_lissajous.sv').read_text().replace('tb_neo_guitar_lissajous','tb_neo_guitar_radial')
s=s.replace('neo_guitar_lissajous_top','neo_guitar_radial_top').replace('performance_','radial_')
s=s.replace('            if(dut.u_display.renderer_deadline_miss)',
    '            if(dut.u_display.pcm_overrun)$fatal(1,"FAIL: PCM mailbox overrun");\n'
    '            if(dut.u_display.renderer_deadline_miss)')
s=s.replace('    integer i;\n    initial begin','    integer i,fft_frames=0;\n    always @(posedge sys_clk)if(dut.u_display.fft_done)fft_frames++;\n    initial begin')
s=s.replace('        $display("PASS: integrated four-fret',
    '        if(fft_frames<15)$fatal(1,"FAIL: spectrum stopped");\n'
    '        $display("PASS: radial FFT windows %0d, no PCM loss or row misses",fft_frames);\n'
    '        $display("PASS: integrated four-fret')
(root/'sim/tb/tb_neo_guitar_radial.sv').write_text(s,encoding='utf-8')
print('Created radial physical project and independent curve/full-audio comparison tests')
