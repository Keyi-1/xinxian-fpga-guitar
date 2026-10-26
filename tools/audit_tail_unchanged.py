"""Compare unchanged synthesized subsystem graphs instead of repeating tests."""
import hashlib
import json
import re
from pathlib import Path
from compare_synth_graph import Graph,parse
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'build/releases/touch_game/piano_short_hold_20261025/evidence/gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
CURRENT=ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(run):
    old=parse(BASE.read_text(encoding='utf-8'));new=parse(CURRENT.read_text(encoding='utf-8'))
    patterns=(r'guitar_touch_game_display',r'mcp3208_pluck_frontend',r'mpu6050_posture',r'game_p3_service',
        r'game_p3_score_bank',r'game_p2_window_controller',r'piano_voice_core(?:_[0-9]+)?',
        r'four_string_vibrato_serial',r'phase_slide_smoother(?:_[0-9]+)?')
    names=sorted(n for n in old if any(re.fullmatch(p,n) for p in patterns))
    assert len([n for n in names if re.fullmatch(r'piano_voice_core(?:_[0-9]+)?',n)])==4
    assert all(n in new for n in names)
    results={}
    for name in names:
        before=Graph(old,name).signature();after=Graph(new,name).signature()
        results[name]={'equal':before==after,'before':before,'after':after}
    record={'result':'PASS' if all(r['equal'] for r in results.values()) else 'REVIEW_REQUIRED',
        'baseline_netlist_sha256':sha(BASE),'netlist_sha256':sha(CURRENT),
        'tool_sha256':sha(Path(__file__)),'method':'Exact flattened primitive/parameter/pin-bit graph equality; no Boolean rewrites, name-only comparison or guessed simulation equivalence',
        'modules':results}
    (run/'unchanged_graph_audit.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'result':record['result'],'equal':[n for n,r in results.items() if r['equal']],
        'inspect':[n for n,r in results.items() if not r['equal']]},indent=2))
if __name__=='__main__':main(ROOT/'build/vibrato/tail_lock_v1')
