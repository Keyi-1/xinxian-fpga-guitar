"""Accept only a current, routed and timing-clean dual-output implementation."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

PROJECT=Path(__file__).resolve().parent
REPO=PROJECT.parent.parent
NAME='neo_guitar_i2s'
PNR=PROJECT/'impl/pnr'
BASELINE='e55c7cb'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def baseline(path):
    return subprocess.check_output(['git','show',f'{BASELINE}:{path}'],cwd=REPO).decode('utf-8')


def tokens(text):
    return re.sub(r'\s+','',re.sub(r'//[^\n]*','',text))


def check_evidence(directory,log_paths):
    evidence=json.loads((directory/'verification.json').read_text(encoding='utf-8-sig'))
    assert evidence['result']=='PASS'
    for path,expected in evidence['source_sha256'].items():
        assert digest(REPO/path)==expected,('source changed after simulation',path)
    for key,path in log_paths.items():
        log=path.read_text(encoding='utf-8')
        assert 'PASS:' in log and not re.search(r'FAIL:|MISMATCH|\*\* (Error|Fatal)',log),path
        if 'log_sha256' in evidence:
            assert digest(path)==evidence['log_sha256'][key],path
    return evidence


def main():
    # Explicitly prove the new entry preserves every audio/display/control
    # statement, removing only the new port and its enable/connections.
    top=(REPO/'rtl/top/neo_guitar_i2s_top.v').read_text(encoding='utf-8')
    top=top.replace('neo_guitar_i2s_top','neo_guitar_radial_top')
    top=top.replace('output wire [5:0] lcd_r,lcd_g,lcd_b,\n    output wire i2s_bclk,i2s_ws,i2s_data',
                    'output wire [5:0] lcd_r,lcd_g,lcd_b')
    top=top.replace('.I2S_ENABLE(1),','')
    top=top.replace('.i2s_bclk(i2s_bclk),.i2s_ws(i2s_ws),.i2s_data(i2s_data),','')
    assert tokens(top)==tokens(baseline('rtl/top/neo_guitar_radial_top.v')),'entry changed beyond I2S'
    unchanged=[]
    for folder in ['rtl/synth','rtl/control','rtl/input','rtl/display','rtl/config','mem']:
        for path in (REPO/folder).rglob('*'):
            if path.is_file() and path.suffix in ['.v','.vh','.mem']:
                relative=path.relative_to(REPO).as_posix()
                assert path.read_bytes().replace(b'\r\n',b'\n')==baseline(relative).encode().replace(b'\r\n',b'\n'),relative
                unchanged.append(relative)
    for relative in ['rtl/audio_io/pt8211_tx.v','rtl/audio_io/pcm24_to_16.v',
                     'rtl/audio_io/piano_stereo_effects.v','rtl/audio_io/piano_stereo_chorus.v',
                     'rtl/audio_io/piano_stereo_room.v','rtl/audio_io/four_voice_piano_audio_core.v']:
        assert tokens((REPO/relative).read_text(encoding='utf-8'))==tokens(baseline(relative)),relative
        unchanged.append(relative)

    rtl_dir=REPO/'sim/temp/i2s'
    rtl_evidence=check_evidence(rtl_dir,{b:rtl_dir/f'{b}.log' for b in ['tb_i2s_tx','tb_board_dual_audio']})
    assert digest(rtl_dir/'i2s_tx.vcd')==rtl_evidence['waveform_sha256']
    gate_dir=REPO/'sim/temp/guitar_i2s_gate'
    gate_evidence=check_evidence(gate_dir,{'gate':gate_dir/'run.log'})
    gate=(gate_dir/'run.log').read_text(encoding='utf-8')
    assert re.search(r'PASS: (\d+) synthesized standard I2S stereo pairs',gate)
    assert 'synthesized LCD' in gate and 'actual DAC frames bit-identical' in gate
    allowed=r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'
    for line in gate.splitlines():
        if line.startswith('# ** Warning:'):assert re.search(allowed,line),line

    report=(PNR/f'{NAME}.rpt.txt').read_text(encoding='utf-8')
    timing=(PNR/f'{NAME}_tr_content.html').read_text(encoding='utf-8')
    console=(PROJECT/'build_console.log').read_text(encoding='utf-8')
    assert 'Bitstream generation completed' in console and 'ERROR' not in console
    assert 'ERROR' not in report and 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
    command=(PNR/'cmd.do').read_text()
    for option,value in [('place_option','4'),('route_option','2'),('clock_route_order','1'),('correct_hold','1')]:
        assert re.search(rf'^-{option}\s+{value}\s*$',command,re.M),(option,value)
    cfg=(PNR/'device.cfg').read_text()
    for option in ['CPU','SSPI','I2C']:assert f'set {option} regular_io = true' in cfg
    assert 'set JTAG regular_io = false' in cfg
    ide_path=PROJECT/f'impl/{NAME}_process_config.json'
    ide=json.loads(ide_path.read_text())
    assert (ide['Place_Option'],ide['Route_Option'],ide['Clock_Route_Order'],ide['CPU'])==('4','2',1,True)
    assert ide['TopModule']=='neo_guitar_i2s_top' and ide['Correct_Hold_Violation'] is True
    cst=(REPO/'constraints/neo_guitar_i2s.cst').read_text()
    pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',cst))
    old_pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',baseline('constraints/neo_guitar_radial.cst')))
    assert len(pins)==55 and len(set(pins.values()))==55
    assert all(pins[p]==v for p,v in old_pins.items())
    assert {p:pins[p] for p in ['i2s_bclk','i2s_ws','i2s_data']}==dict(i2s_bclk='P19',i2s_ws='R19',i2s_data='T21')
    rows={}
    for line in report.splitlines():
        fields=[v.strip() for v in line.split('|')]
        if len(fields)>8 and fields[0] in pins:rows[fields[0]]=fields
    for port,ball in pins.items():
        assert rows[port][2].split('/')[0]==ball and rows[port][3]=='Y',port
        assert rows[port][7]==('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33'),port
    sdc=(REPO/'constraints/neo_guitar_i2s.sdc').read_text()
    assert '81.380208' in sdc and '20.000' in sdc
    assert 'set_max_delay 40.000 -to [get_ports {i2s_bclk i2s_ws i2s_data}]' in sdc
    assert not re.search(r'set_false_path[^\n]*i2s',sdc)
    violations={}
    for kind in ['Setup','Hold']:
        m=re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>',timing)
        assert m and int(m[1])==0,kind
        violations[kind.lower()]=int(m[1])
    clocks={}
    for clock,required in [('audio_clk_12m288',12.288),('sys_clk_50m',50.)]:
        m=re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>',timing)
        assert m and float(m[2])>=required,clock
        clocks[clock]=dict(required_mhz=required,fmax_mhz=float(m[2]))
    resources={}
    for label in ['Logic','Register','BSRAM','DSP']:
        m=re.search(rf'^\s+{label}\s+\|\s+([\d.]+)/([\d.]+)',report,re.M)
        assert m and float(m[1])<=float(m[2]),label
        resources[label]=dict(used=float(m[1]),available=float(m[2]))
    assert resources['BSRAM']['used']==86 and resources['DSP']['used']==115.5
    tree=ET.parse(PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml').getroot()
    tx=[n for n in tree.iter() if n.get('name')=='standard_i2s.u_tx']
    assert len(tx)==1
    assert all(int(v.split('(')[0])==0 for k,v in tx[0].attrib.items() if k=='T_Bsram' or k.startswith('T_MULT'))
    netlist=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert digest(netlist)==gate_evidence['netlist_sha256']
    assert digest(gate_dir/'compiled.vg')==gate_evidence['netlist_sha256']
    fs=PNR/f'{NAME}.fs'
    assert fs.stat().st_size>10000000
    result=dict(result='PASS',baseline_commit=BASELINE,clocks=clocks,violations=violations,resources=resources,
        standard_i2s=dict(sample_rate_hz=48000,bclk_hz=3072000,slot_bits=32,data_bits=16,msb_delay_bits=1,
            fpga_pins={p:pins[p] for p in ['i2s_bclk','i2s_ws','i2s_data']},new_dsp=0,new_bsram=0,
            serializer_synthesis_attributes=tx[0].attrib),
        bitstream_sha256=digest(fs),netlist_sha256=digest(netlist),i2s_waveform_sha256=rtl_evidence['waveform_sha256'],
        unchanged_audio_display_assets_sha256={p:digest(REPO/p) for p in unchanged},
        source_sha256=gate_evidence['source_sha256'],
        evidence_sha256={str(p.relative_to(REPO)):digest(p) for p in
            [rtl_dir/'verification.json',gate_dir/'verification.json',gate_dir/'run.log',
             PNR/f'{NAME}.rpt.txt',PNR/f'{NAME}_tr_content.html',PROJECT/'build_console.log',
             REPO/'constraints/neo_guitar_i2s.cst',REPO/'constraints/neo_guitar_i2s.sdc',ide_path]},
        hardware_status='See README.md for user acceptance; this check verifies digital evidence only')
    (PROJECT/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['result','clocks','violations','resources','standard_i2s','bitstream_sha256']},indent=2))


if __name__=='__main__':main()
