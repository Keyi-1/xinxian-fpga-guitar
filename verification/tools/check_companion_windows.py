"""Persist the desktop regressions and their exact source inputs for release review."""
from pathlib import Path
import hashlib
import io
import json
import os
import unittest

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/companion_ui/windows_checks'
OUT.mkdir(parents=True,exist_ok=True)
os.environ['QT_QPA_PLATFORM']='offscreen'
suite=unittest.TestLoader().discover(str(ROOT/'tools'),pattern='test_windows_score_*.py')
log=io.StringIO()
result=unittest.TextTestRunner(stream=log,verbosity=2).run(suite)
(OUT/'tests.log').write_text(log.getvalue(),encoding='utf-8')
files=list((ROOT/'tools/windows_score_uploader').rglob('*.py'))
files+=[ROOT/'tools'/p for p in ('test_windows_score_uploader.py','test_windows_score_preview.py',
                                'game_score_upload.py','game_score_v2.py','game_fingering.py')]
record=dict(result='PASS' if result.wasSuccessful() else 'FAIL',tests_run=result.testsRun,
    failures=len(result.failures),errors=len(result.errors),physical_com_opened=False,
    source_sha256={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files})
(OUT/'verification.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(record['result']+': '+str(result.testsRun)+' Windows checks')
if not result.wasSuccessful():raise SystemExit(log.getvalue())
