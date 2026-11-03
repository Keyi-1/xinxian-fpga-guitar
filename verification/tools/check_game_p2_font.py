"""Compare every existing glyph/title tile to the frozen pre-integration ROM."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parent.parent
BASELINE='1b88992'


def check():
    def old(path):
        return subprocess.check_output(['git','show',f'{BASELINE}:{path}'],cwd=ROOT)
    before=json.loads(old('scores/game_font.json').decode('utf-8'))
    after=json.loads((ROOT/'scores/game_font.json').read_text(encoding='utf-8'))
    frozen=[int(x,16) for x in old('mem/game_font_16.mem').splitlines()]
    current=[int(x,16) for x in (ROOT/'mem/game_font_16.mem').read_text(encoding='ascii').splitlines()]
    assert len(current)==2048 and len(set(after['characters']))==len(after['characters'])
    for i,char in enumerate(before['characters']):
        j=after['characters'].index(char)
        assert frozen[i*16:(i+1)*16]==current[j*16:(j+1)*16],char
    b=before['stage_title']['tile_base']*16
    a=after['stage_title']['tile_base']*16
    assert frozen[b:b+192]==current[a:a+192]
    assert after['stage_title']['tile_base']+12<=128
    return dict(result='PASS',baseline_commit=BASELINE,unchanged_glyphs=len(before['characters']),unchanged_title_tiles=12,
        source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in [
            'mem/game_font_16.mem','scores/game_font.json','tools/generate_game_ui_font.py']})


if __name__=='__main__':
    data=check();print(json.dumps(data,indent=2))
