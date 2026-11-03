"""Freeze P2 core evidence, explicitly distinct from a production build release."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
BASE = '704fc14'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('destination',type=Path)
    args=parser.parse_args()
    dest=args.destination.resolve()
    dest.relative_to(ROOT/'build')
    if dest.exists():
        raise SystemExit('Preserve the existing archive; choose a new directory')
    original_paths=['rtl/audio_io','rtl/synth','rtl/control','rtl/display','rtl/top','constraints',
        'rtl/game/audio_mode_router.v','rtl/game/game_note_controller.v','rtl/game/game_score_rom.v',
        'rtl/game/game_chart_layout.v','rtl/game/game_snapshot_cdc.v','rtl/game/touch_game_ui.v',
        'rtl/game/touch_game_renderer.v','rtl/game/guitar_touch_game_audio.v','rtl/game/guitar_touch_game_display.v',
        'mem/jasmine_game.mem','scores/jasmine.csv','scores/jasmine.json','gowin/neo_guitar_touch_game/verification.json']
    subprocess.run(['git','diff','--exit-code',BASE,'--']+original_paths,cwd=ROOT,check=True)
    project=ROOT/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
    for file in ET.parse(project).findall('.//File'):
        assert (project.parent/file.attrib['path']).is_file(),file.attrib['path']
    catalog=read_json(ROOT/'scores/p2/catalog.json')
    assert catalog['total_events']==875 and catalog['capacity']==2048
    tests={}
    for run, benches in [('attempt1',['tb_game_p2_window']),
                         ('attempt2',['tb_game_p2_legacy_equivalence']),
                         ('attempt3',['tb_game_p2_static_bank']),
                         ('attempt4',['tb_game_p2_judgement'])]:
        folder=ROOT/f'sim/temp/game_p2/{run}'
        record=read_json(folder/'verification.json')
        assert record['status']=='PASS'
        inputs={k.replace('\\','/'):v for k,v in record['source_sha256'].items()}
        for bench in benches:
            log=folder/f'{bench}.log'
            assert digest(log)==record['log_sha256'][bench]
            text=log.read_text(encoding='utf-8-sig')
            assert 'PASS:' in text and not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):',text)
            # Confirm the actual controller and phase table used by all benches
            # still match current code. Later catalog-only data edits did not
            # invalidate controller tests that use private memory fixtures.
            for path in ['rtl/game/game_p2_window_controller.v','rtl/config/game_p2_phase.vh']:
                assert digest(ROOT/path)==inputs[path],path
            tests[bench]=dict(run=run,scope=record['scope'],pid=record['pid'],
                started=record['started'],finished=record['finished'],
                log_sha256=digest(log),tested_inputs=inputs,
                pass_lines=[line.strip() for line in text.splitlines() if 'PASS:' in line])
    current=read_json(ROOT/'sim/temp/game_p2/attempt4/verification.json')
    for path in ['mem/game_p2_static.mem','scores/p2/catalog.json','tools/game_score_v2.py',
                 'tools/generate_p2_static_scores.py','tools/test_game_score_v2.py']:
        assert digest(ROOT/path)==current['source_sha256'][path],path
    strict=ROOT/'sim/temp/game_p2/attempt3/compile_v2001.log'
    assert 'Errors: 0, Warnings: 0' in strict.read_text(encoding='utf-8-sig')
    protected={'docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md':
               '0a3cb385ed875b546d9fce420a1ec84ea18d239db01427f07b837cb7e7204de4',
               'gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json':
               '2b995b1d00a7e57de6b52dad713da091f49994fa679a059196737c8677e4500d'}
    for path,expected in protected.items():
        assert digest(ROOT/path)==expected,path
    p1=ROOT/'build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs'
    assert digest(p1)=='e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86'
    sources=[]
    for pattern in ['rtl/game/game_p2_*.v','rtl/config/game_p2_*.vh',
                    'scores/p2/*','sim/reference/game_p2/*.v','sim/tb/tb_game_p2_*.sv',
                    'tools/*p2*.py']:
        sources.extend(ROOT.glob(pattern))
    sources.extend(ROOT/p for p in ['.gitattributes','AGENTS.md','docs/P2_STATIC_ENGINE_PROTOTYPE.md',
        'mem/game_p2_static.mem','mem/jasmine_game.mem','scores/jasmine.csv','scores/jasmine.json',
        'tools/game_score_v2.py','tools/test_game_score_v2.py','tools/game_fingering.py','tools/run_game_p2_checks.ps1',
        'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj','gowin/neo_guitar_touch_game/README.md',
        'gowin/neo_guitar_touch_game/hardware_acceptance.json'])
    sources=sorted(set(sources))
    result=dict(status='CORE_RTL_PASS_NOT_INTEGRATED',base_commit=BASE,
        artifact_scope='P2 static engine prototype code/data and RTL tests only',
        production_top_integrated=False,new_board_bitstream=None,tests=tests,
        strict_verilog2001_compile_sha256=digest(strict),catalog=catalog,
        source_sha256={p.relative_to(ROOT).as_posix():digest(p) for p in sources},
        p1_bitstream_sha256=digest(p1),protected_user_files_sha256=protected,
        protected_index_entries=subprocess.check_output(['git','ls-files','--stage','--']+list(protected),cwd=ROOT).decode().splitlines(),
        not_run=['Gowin integration synthesis and actual BSRAM mapping','Full P&R/STA',
                 'P2 UI/display/router/timbre integration','Full-top synthesized pixel/audio verification','P2 hardware test'],
        limits=['12015-sample P1 comparison uses matching compressed time fixtures; actual original timestamps/DDS checked separately in Python.',
                'Ten-minute boundary uses testbench time advancement, not a ten-minute wall-clock hardware run.',
                'Timbre is catalog metadata; current P1 audio behavior is unchanged.',
                'Song-name entries are short practice loops, not full copyrighted song transcriptions.',
                'Old runs retain their original input hashes; later catalog edits are validated by current bank/Python tests.'])
    dest.mkdir(parents=True)
    with zipfile.ZipFile(dest/'source_snapshot.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for path in sources:archive.write(path,path.relative_to(ROOT).as_posix())
    for run in ['attempt1','attempt2','attempt3','attempt4']:
        folder=ROOT/f'sim/temp/game_p2/{run}'
        for path in folder.rglob('*'):
            if path.is_file() and 'work' not in path.relative_to(folder).parts and path.suffix in ['.log','.json','.sv','.v','.vh']:
                target=dest/'evidence'/run/path.relative_to(folder)
                target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(path,target)
    result['archive_files_sha256']={p.relative_to(dest).as_posix():digest(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    body=json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    (dest/'verification.json').write_text(body,encoding='utf-8')
    (ROOT/'gowin/neo_guitar_touch_game/p2_core_verification.json').write_text(body,encoding='utf-8')
    print(dest/'verification.json')


if __name__=='__main__':main()
