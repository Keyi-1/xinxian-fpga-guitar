"""Audit actual top-to-ADC pins and complementary reset before leaf simulation."""
from pathlib import Path
import hashlib
import json
import sys
from compare_synth_graph import parse
from prepare_posture_gate import main as prepare_posture


def main(vg,out):
    prepare_posture(vg,out)
    modules=parse(vg.read_text(encoding='utf-8'))
    ports=modules['mcp3208_pluck_frontend']['ports']
    names={'audio_clk_12m288_d':'clk','pa_en_n_d_4':'~rst_n','audio_rst_n':'rst_n','adc_miso_d':'gmiso',
           'adc_cs_n_d':'gcs','adc_mosi_d':'gmosi','adc_sclk_d':'gsclk',
           'pluck_valid_Z':'gpluck','velocity':'gvelocity','capture_pending':'gpending'}
    assert set(ports)==set(names),ports
    assert ports['velocity']==('output',list(range(7,-1,-1)))
    assert ports['capture_pending']==('output',list(range(3,-1,-1)))
    top=modules['neo_guitar_touch_game_top']
    inversions=[(k,n,p) for k,n,p in top['cells'] if p.get('O')=='pa_en_n_d_4']
    assert len(inversions)==1 and inversions[0][0]=='INV' and inversions[0][2]['I']=='audio_rst_n'
    adc=[(k,n,p) for k,n,p in modules['guitar_touch_game_audio']['cells'] if n=='u_adc']
    assert len(adc)==1 and adc[0][0]=='mcp3208_pluck_frontend'
    for n in names:
        value=adc[0][2][n]
        assert value==n or value==n+'[7:0]' or value==n+'[3:0]',(n,value)
    body='mcp3208_pluck_frontend gate_adc('+','.join('.'+n+'('+v+')' for n,v in names.items())+');\n'
    header=out/'velocity_gate_adc.vh';header.write_text(body,encoding='utf-8')
    p=out/'mapping.json';record=json.loads(p.read_text(encoding='utf-8'))
    record['velocity_adc']=dict(module='mcp3208_pluck_frontend',ports=ports,
        actual_parent_instance=adc[0],parent_reset_inversion=inversions[0],
        header_sha256=hashlib.sha256(header.read_bytes()).hexdigest(),
        scope='Actual complete VG ADC frontend, all live velocity/capture outputs and unchanged SPI data reconstruction; reset normalized using proven top INV; no forces')
    p.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print('PASS: actual ADC hierarchy/all8 velocity bits/all4 capture bits/top complementary reset audited')


if __name__=='__main__':main(Path(sys.argv[1]),Path(sys.argv[2]))
