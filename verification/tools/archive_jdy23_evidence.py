"""Freeze completed implementation reports and changed software without re-running checks."""
from pathlib import Path
import hashlib
import json
import shutil

R=Path(__file__).resolve().parents[1]
E=R/'build/jdy23/v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    cert=json.loads((E/'verification.json').read_text())
    assert cert['result']=='PASS'
    fs=R/'gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs'
    vg=R/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
    assert sha(fs)==cert['implementation']['bitstream_sha256'] and sha(vg)==cert['implementation']['netlist_sha256']
    paths=[p for folder in ('gwsynthesis','pnr') for p in (R/'gowin/neo_guitar_touch_game/impl'/folder).iterdir()
        if p.is_file() and p.suffix in ('.vg','.fs','.log','.xml','.txt','.html','.do')]
    paths+=list((R/'mobile/android/app/src/main').rglob('*.java'))
    paths+=list((R/'mobile/android/app/src/main').rglob('*.xml'))
    paths+=list((R/'firmware/jdy23').iterdir())
    paths+=list((R/'tools').glob('*jdy23*'))
    paths+=[R/'sim/tb/tb_jdy23_uart_9600.sv',R/'sim/tb/tb_jdy23_xg3.sv',R/'AGENTS.md']
    records={}
    for p in sorted(set(paths)):
        if not p.is_file():continue
        name=p.relative_to(R).as_posix();target=E/'final_evidence'/name
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
        assert sha(target)==sha(p)
        records[name]=sha(target)
    (E/'evidence_manifest.json').write_text(json.dumps({'result':'PASS','files':records,'no_tests_repeated':True},indent=2))
    print('Archived final implementation reports, VG, FS, Android inputs, configuration and tools; no checks or tests re-run')

if __name__=='__main__':main()
