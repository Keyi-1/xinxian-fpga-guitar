"""Review the two expressly requested literal changes before original-project P&R."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent.parent
RUN=ROOT/'build/velocity_calibration/dynamics_v1'
PROJECT=ROOT/'gowin/neo_guitar_touch_game'
BASE='df770fa0daa64c1cb8f1c1f0c39791bb977b351e'
EDITS={
 'rtl/config/guitar_config.vh':("`define PLUCK_TRIGGER_THRESHOLD_CH0    12'd150", "`define PLUCK_TRIGGER_THRESHOLD_CH0    12'd220"),
 'rtl/synth/piano_voice_core.v':("0: gain_for_velocity=9'd112;", "0: gain_for_velocity=9'd64;")}

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def old(commit,p):return subprocess.check_output(['git','show',f'{commit}:{p}'],cwd=ROOT).decode('utf-8').replace('\r\n','\n')

def source_guard():
    manifest={p.replace('\\','/'):v for p,v in load(RUN/'source_manifest.json').items()}
    process=load(RUN/'process.json');runtime=process['source_commit'];changed=set()
    for p,v in manifest.items():
        assert digest(ROOT/p)==v and digest(RUN/'source_archive'/p)==v,p
        current=(ROOT/p).read_text(encoding='utf-8-sig')
        before=old(BASE,p)
        if p in EDITS:
            a,b=EDITS[p];assert before.count(a)==1
            assert current==before.replace(a,b),('unreviewed runtime edit',p)
            changed.add(p)
        else:assert current==before,('unrelated runtime changed',p)
        assert current==old(runtime,p),('uncommitted runtime',p)
    assert changed==set(EDITS)
    for p,v in load(RUN/'protected_user_files.json').items():
        assert digest(ROOT/p)==v['sha256'],p
        assert subprocess.check_output(['git','ls-files','--stage','--',p],cwd=ROOT,text=True).strip()==v['index']
    frozen=ROOT/'sim/reference/velocity_teammate/piano_voice_before_dynamics.v'
    assert frozen.read_text(encoding='utf-8')==old(BASE,'rtl/synth/piano_voice_core.v').replace('module piano_voice_core ','module accepted_velocity_voice ')
    return manifest,runtime

def main():
    manifest,runtime=source_guard()
    stdout=(RUN/'build.stdout.log').read_text(encoding='utf-8-sig')
    assert 'SYNTHESIS_TCL_FINISHED' in stdout and 'SYNTHESIS_TCL_FAILED' not in stdout
    assert not (RUN/'build.stderr.log').read_text(encoding='utf-8-sig').strip()
    log=(PROJECT/'impl/gwsynthesis/neo_guitar_touch_game.log').read_text(encoding='utf-8-sig')
    assert not re.search(r'^\s*ERROR|inferr?ed.*latch|latch.*inferr?ed',log,re.I|re.M)
    root=ET.parse(PROJECT/'impl/gwsynthesis/neo_guitar_touch_game_syn_rsc.xml').getroot()
    number=lambda key:int(re.match(r'\d+',root.attrib['T_'+key])[0])
    resources={key:number(attr) for key,attr in [('Register','Register'),('LUT','Lut'),('ALU','Alu'),('BSRAM_logical','Bsram')]}
    assert resources['LUT']+resources['ALU']<=59904 and resources['Register']<=60780 and resources['BSRAM_logical']<=118
    dsp={k:v for k,v in root.attrib.items() if k.startswith('T_MULT')}
    previous=load(ROOT/'build/velocity_calibration/synth_v1/synthesis_review.json')
    assert dsp==previous['dsp_primitive_counts']
    vg=PROJECT/'impl/gwsynthesis/neo_guitar_touch_game.vg'
    started=datetime.fromisoformat(load(RUN/'process.json')['started']).timestamp()
    for p in [vg,PROJECT/'impl/gwsynthesis/neo_guitar_touch_game.log',PROJECT/'impl/gwsynthesis/neo_guitar_touch_game_syn_rsc.xml']:
        assert p.stat().st_mtime>=started,p
    record=dict(result='PASS',source_commit=runtime,netlist_sha256=digest(vg),resources_synthesis=resources,
        logic_synthesis=resources['LUT']+resources['ALU'],dsp_primitive_counts=dsp,
        source_manifest_sha256=digest(RUN/'source_manifest.json'),authorized_changes={p:dict(before=a,after=b) for p,(a,b) in EDITS.items()},
        generated_at=datetime.now().astimezone().isoformat())
    process=load(RUN/'process.json')
    process.update(status='SYNTHESIS_REVIEW_PASS',reviewed_at=record['generated_at'],netlist_sha256=record['netlist_sha256'])
    (RUN/'process.json').write_text(json.dumps(process,indent=2)+'\n',encoding='utf-8')
    (RUN/'synthesis_review.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))

if __name__=='__main__':main()
