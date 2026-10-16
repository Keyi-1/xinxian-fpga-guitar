"""Archive a certified P2 result; never overwrite P1 or an earlier release."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT=Path(__file__).resolve().parent.parent
PROJECT=ROOT/'gowin/neo_guitar_touch_game'


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--build-dir',type=Path,required=True)
    p.add_argument('--gate-dir',type=Path,required=True)
    p.add_argument('--name',default='p2_static_songs_20261016')
    a=p.parse_args()
    cert=PROJECT/'p2_integration_verification.json'
    data=json.loads(cert.read_text(encoding='utf-8'))
    assert data['result']=='PASS'
    assert data['artifact_scope']['kind']=='original_gprj_integrated_p2'
    for path,value in data['source_sha256'].items():assert digest(ROOT/path)==value,path
    for path,value in data['artifacts_sha256'].items():assert digest(ROOT/path)==value,path
    root=ROOT/'build/releases/touch_game'
    directory=root/a.name
    output=root/'neo_guitar_touch_game_p2_static_songs.fs'
    assert not directory.exists() and not output.exists(), 'release outputs already exist; never replace them'
    directory.mkdir(parents=True)
    def copy(src,dst):
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    fs=PROJECT/'impl/pnr/neo_guitar_touch_game.fs'
    assert digest(fs)==data['bitstream_sha256']
    copy(fs,output)
    copy(cert,directory/'verification.json')
    for path in data['source_sha256']:copy(ROOT/path,directory/'source'/path)
    for file in (ROOT/'scores/p2').rglob('*'):
        if file.is_file():copy(file,directory/'source'/file.relative_to(ROOT))
    for path in data['artifacts_sha256']:
        original=ROOT/path
        if original.suffix not in ['.fs','.vg']:copy(original,directory/'evidence'/path)
    copy(PROJECT/'impl/gwsynthesis/neo_guitar_touch_game.vg',directory/'netlist/neo_guitar_touch_game.vg')
    for subdir in ['touch_game','p2_final_connection','p2_final_audio','p2_button_compat','game_p2/explicit_dpb_final']:
        run=ROOT/'sim/temp'/subdir
        for file in run.iterdir():
            if file.is_file() and file.suffix in ['.log','.json','.ppm']:
                copy(file,directory/'rtl'/subdir/file.name)
    for file in (ROOT/'sim/temp/p2_bank_gate_r1').iterdir():
        if file.is_file() and file.suffix in ['.json','.log','.vg','.v']:
            copy(file,directory/'bank_gate'/file.name)
    for file in a.gate_dir.iterdir():
        if file.is_file() and file.suffix in ['.log','.json','.sv','.vh','.ps1']:
            copy(file,directory/'gate'/file.name)
    for file in a.build_dir.iterdir():
        if file.is_file() and file.suffix in ['.log','.json','.tcl']:
            copy(file,directory/'build'/file.name)
    for relative in ['tools/run_game_p2_gate.ps1','tools/generate_game_p2_gate_bench.py',
                     'tools/check_game_p2_result.py','tools/archive_game_p2_integration.py',
                     'tools/run_touch_game_checks.ps1','tools/run_game_p2_checks.ps1','tools/generate_game_p2_bsram.py',
                     'tools/continue_game_p2_gate.ps1','tools/check_game_p2_font.py',
                     'tools/game_score_v2.py','tools/generate_p2_static_scores.py','tools/compile_p2_score.py',
                     'tools/generate_game_ui_font.py','tools/game_fingering.py','tools/test_game_fingering.py',
                     'tools/test_game_score_v2.py']:
        copy(ROOT/relative,directory/'tools'/Path(relative).name)
    for relative in ['AGENTS.md','docs/P2_STATIC_SONG_INTEGRATION.md',
                     'docs/P2_STATIC_ENGINE_PROTOTYPE.md',
                     'gowin/neo_guitar_touch_game/README.md',
                     'gowin/neo_guitar_touch_game/hardware_acceptance.json']:
        copy(ROOT/relative,directory/'documentation'/relative)
    for file in (ROOT/'build/p2_integration/previews').glob('p2_ready_*.png'):
        copy(file,directory/'previews'/file.name)
    record=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
        bitstream=str(output.relative_to(ROOT)).replace('\\','/'),bitstream_sha256=digest(output),
        verification_sha256=digest(cert),artifact_scope=data['artifact_scope'],
        files_sha256={str(f.relative_to(directory)).replace('\\','/'):digest(f) for f in directory.rglob('*') if f.is_file()})
    (directory/'archive.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:record[k] for k in ['source_commit','bitstream','bitstream_sha256','verification_sha256']},indent=2))


if __name__=='__main__':main()
