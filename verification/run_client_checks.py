"""Run unchanged protocol and desktop tests against current production paths."""
from pathlib import Path
import importlib
import json
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'verification/tools')]
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

def main():
    suite = unittest.TestSuite()
    for name in ('test_game_score_upload', 'test_windows_score_uploader', 'test_windows_score_preview'):
        module = importlib.import_module(name)
        # Adapt data/output roots without modifying the archived test bytes.
        if hasattr(module, 'ROOT'):
            module.ROOT = ROOT
        if hasattr(module, 'OUT'):
            module.OUT = ROOT/'verification/results/windows_preview'
        suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    out = ROOT/'verification/results'
    out.mkdir(parents=True, exist_ok=True)
    (out/'client_checks.json').write_text(json.dumps(dict(
        result='PASS' if result.wasSuccessful() else 'FAIL', tests=result.testsRun,
        failures=len(result.failures), errors=len(result.errors), hardware_access=False), indent=2)+'\n', encoding='utf-8')
    return 0 if result.wasSuccessful() else 1

if __name__ == '__main__':
    raise SystemExit(main())
