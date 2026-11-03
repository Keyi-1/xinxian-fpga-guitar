"""Expose the actual original-project audio child, with audited boundary pins.

The complete production VG is compiled unchanged. The focused harness uses
its real audio child (matrix/router/control/synth/effects/DAC), avoiding repeat
simulations of the unchanged UI/UART/MPU subsystems. No functional net is edited.
"""
import hashlib
import json
import re
import sys
from pathlib import Path
from compare_synth_graph import parse

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(vg,out):
    modules=parse(vg.read_text(encoding='utf-8'))
    top=modules['neo_guitar_touch_game_top'];audio=modules['guitar_touch_game_audio']
    cells=[(k,n,p) for k,n,p in top['cells'] if k=='guitar_touch_game_audio']
    assert len(cells)==1 and cells[0][1]=='u_audio'
    parent=cells[0][2]
    inv=[(k,n,p) for k,n,p in top['cells'] if p.get('O')=='pa_en_n_d_4']
    assert len(inv)==1 and inv[0][0]=='INV' and inv[0][2]['I']=='audio_rst_n'
    # Parent optimizations expose a handful of LUT-derived inputs (catalog
    # read controls and tone decodes). Audit their value for the deliberately
    # idle catalog and dry piano fixture instead of guessing generated names.
    constants={};drivers={}
    for kind,name,pins in top['cells']:
        if kind in ('GND','VCC'):
            for node in pins.values():constants[node]=int(kind=='VCC')
        elif re.fullmatch(r'LUT[1-4]',kind):
            size=int(kind[3:]);drivers[pins['F']]=(int(top['params'][name]['INIT'].split("'h")[1],16),[pins[f'I{i}'] for i in range(size)])
    buttons=modules['guitar_effect_buttons']
    button_instance=next(p for k,n,p in top['cells'] if k=='guitar_effect_buttons')
    for kind,name,pins in buttons['cells']:
        if re.fullmatch(r'LUT[1-4]',kind) and pins['F'] in button_instance:
            size=int(kind[3:]);drivers[button_instance[pins['F']]]=(int(buttons['params'][name]['INIT'].split("'h")[1],16),
                [pins[f'I{i}'] for i in range(size)])
    roots=set()
    def quiet(node,seen=()):
        assert node not in seen,('loop',node)
        if node in constants:return constants[node]
        if re.fullmatch(r'(?:state(?:_\d+)?|verify_address|display_address|timbre_mode_Z|space_mode_Z)\[\d+\]',node):
            roots.add(node);return 0
        assert node in drivers,('unsupported parent boundary',node)
        init,ports=drivers[node]
        return (init>>sum(quiet(p,seen+(node,))<<i for i,p in enumerate(ports)))&1
    inputs={};outputs={
        'dac_bclk_d':'pins[0]','dac_lrck_d':'pins[1]','dac_din_d':'pins[2]',
        'i2s_bclk_d':'pins[3]','i2s_ws_d':'pins[4]','i2s_data_d':'pins[5]',
        'final_pcm_valid':'valid','final_pcm':'pcm','posture_sample_tick':'tick',
        'dst_command_ack':'ack','mode_Z':'mode','switching_Z':'switching','row_index':'row_index'}
    fixed={'audio_clk_12m288_d':'clk','sys_clk_50m_d':'sysclk','audio_rst_n':'rst_n','pa_en_n_d_4':'~rst_n',
        'dst_command_valid':'command_valid','dst_command':"{3'd0,command_mode}",
        'score_write':"1'b0",'adc_miso_d':"1'b0",'harmony_enable_Z':"1'b0",'chorus_enable_Z':"1'b0",
        'timbre_mode_Z':"2'd0",'space_mode_Z':"2'd0",'audio_catalog_valid':"5'd0"}
    for port,(kind,bits) in audio['ports'].items():
        if kind!='input':continue
        if port in fixed:inputs[port]=fixed[port]
        elif match:=re.fullmatch(r'COL([0-7])_d',port):inputs[port]=f'columns[{match[1]}]'
        elif re.fullmatch(r'score_write_data_\d+|audio_catalog_data_\d+',port):inputs[port]="1'b0"
        elif port in ('score_write_address','verify_address','display_address','state'):
            inputs[port]=f"{len(bits)}'d0"
        elif re.fullmatch(r'n\d+_\d+',port):
            assert quiet(parent[port])==0,(port,parent[port]);inputs[port]="1'b0"
        else:raise AssertionError(('unmapped audio input',port,kind,bits))
    assert all(p in audio['ports'] and audio['ports'][p][0]=='output' for p in outputs)
    assert audio['ports']['final_pcm']==('output',list(range(23,7,-1)))
    assert audio['ports']['row_index']==('output',[1,0])
    adc=modules['mcp3208_pluck_frontend']
    assert adc['ports']['pluck_valid_Z']==('output',[3,2,1,0])
    assert adc['ports']['velocity']==('output',list(range(7,-1,-1)))
    assert adc['ports']['capture_pending']==('output',[3,2,1,0])
    adc_instance=next(p for k,n,p in audio['cells'] if n=='u_adc' and k=='mcp3208_pluck_frontend')
    assert adc_instance['pluck_valid_Z']=='pluck_valid_Z[3:0]'
    connections=[]
    for port,(kind,bits) in audio['ports'].items():
        value=inputs[port] if kind=='input' else outputs.get(port,'')
        connections.append(f'.{port}({value})')
    body='''module tail_gate_audio(input wire clk,sysclk,rst_n,input wire [31:0] contacts,
 input wire [3:0] pluck,input wire command_valid,input wire [1:0] command_mode,
 output wire [5:0] pins,output wire valid,ack,tick,switching,
 output wire [15:0] pcm,output wire [1:0] mode,output wire [3:0] rows);
 wire [1:0] row_index;reg [7:0] columns;
 assign rows=rst_n ? (4'b1<<row_index) : 4'd0;
 always @*begin
  columns=255;
  for(integer s=0;s<4;s=s+1)if(rows[s])columns=~contacts[s*8+:8];
 end
 guitar_touch_game_audio u_audio('''+','.join(connections)+''');
 initial begin
  force u_audio.u_adc.pluck_valid_Z=pluck;
  force u_audio.u_adc.velocity=8'haa;
  force u_audio.u_adc.capture_pending=4'd0;
 end
endmodule
'''
    wrapper=out/'tail_gate_audio.sv';wrapper.write_text(body,encoding='utf-8')
    record={'result':'PASS','netlist_sha256':sha(vg),'wrapper_sha256':sha(wrapper),'tool_sha256':sha(Path(__file__)),
        'scope':'Actual full production audio child, all original matrix/control/router/synth/effects/dual output logic; no UI/UART/MPU repetition; real matrix inputs and only registered ADC event/velocity/pending outputs stimulated',
        'parent_instance':cells[0],'reset_inversion':inv[0],'inputs':inputs,'observed_outputs':outputs,
        'quiescent_parent_roots':sorted(roots),'adc_boundary':adc_instance}
    (out/'mapping.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print('PASS: actual production audio-child boundary/parent LUT controls/reset/registered ADC ports audited; no netlist edits')
if __name__=='__main__':main(Path(sys.argv[1]),Path(sys.argv[2]))
