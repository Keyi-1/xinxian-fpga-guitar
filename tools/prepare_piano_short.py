"""Freeze the accepted vibrato source for the separate piano duration change."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ARCHIVE=ROOT/'build/releases/touch_game/p4_vibrato_20261023'
SOURCE='rtl/synth/piano_voice_core.v'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    certificate=json.loads((ARCHIVE/'verification.json').read_text(encoding='utf-8-sig'))
    assert certificate['result']=='PASS'
    old=ARCHIVE/'evidence'/SOURCE
    assert sha(old)==certificate['source_sha256'][SOURCE]
    reference=ROOT/'sim/reference/vibrato/piano_short_before.v'
    expected=old.read_text(encoding='utf-8-sig').replace('module piano_voice_core #(',
        'module short_before_piano_voice_core #(',1)
    if reference.exists():assert reference.read_text(encoding='utf-8-sig')==expected
    else:reference.write_text(expected,encoding='utf-8')
    record={'result':'PASS','baseline_bitstream_sha256':certificate['bitstream_sha256'],
        'baseline_source_sha256':sha(old),'reference_sha256':sha(reference),
        'scope':'Only the piano strike lifetime/body clock may change; accepted vibrato archive retained.'}
    folder=ROOT/'build/piano_short';folder.mkdir(exist_ok=True)
    (folder/'baseline.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))

if __name__=='__main__':main()
