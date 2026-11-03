"""Freeze the accepted source/bitstream before the local tail-lock change."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'build/releases/touch_game/piano_short_hold_20261025'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    certificate=json.loads((BASE/'verification.json').read_text(encoding='utf-8-sig'))
    assert certificate['result']=='PASS'
    directory=ROOT/'sim/reference/tail_lock';directory.mkdir(exist_ok=True)
    for module,path in [('matrix_scanner','rtl/input/matrix_scanner.v'),
                        ('four_string_board_audio_chain','rtl/audio_io/four_string_board_audio_chain.v')]:
        source=BASE/'evidence'/path;assert sha(source)==certificate['source_sha256'][path]
        body=source.read_text(encoding='utf-8-sig').replace('module '+module+' ',
            'module tail_before_'+module+' ',1)
        target=directory/(module+'_before.v')
        if target.exists():assert target.read_text(encoding='utf-8-sig')==body
        else:target.write_text(body,encoding='utf-8')
    folder=ROOT/'build/tail_lock';folder.mkdir(exist_ok=True)
    record={'result':'PASS','pushed_baseline_commit':'380312970eab0b455df1f8d80f055d47fdbc5324',
        'baseline_bitstream_sha256':certificate['bitstream_sha256'],
        'baseline_verification_sha256':sha(BASE/'verification.json'),
        'references':{p.relative_to(ROOT).as_posix():sha(p) for p in directory.glob('*.v')}}
    (folder/'baseline.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))
if __name__=='__main__':main()
