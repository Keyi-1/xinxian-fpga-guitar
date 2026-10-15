"""Archive successful and unsuccessful component experiments with explicit scope."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
BASE = '8230217e56952ee2793b97d98ef90e2740fff54b'
BUILDS = ROOT/'build/radial_bands_experiment'
SIM = ROOT/'sim/temp/radial_bands_experiment'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def synthesis(folder):
    log = (folder/'synthesis.log').read_text()
    assert 'GowinSynthesis finish' in log and 'ERROR' not in log
    attributes = ET.parse(folder/'impl/gwsynthesis/bands_syn_rsc.xml').getroot().attrib
    timing = (folder/'impl/gwsynthesis/bands_syn.rpt.html').read_text()
    clock = re.search(r'<td>clk</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
    assert clock
    return dict(register=int(attributes['Register']), lut=int(attributes['Lut']),
                alu=int(attributes['Alu']), bsram=int(attributes.get('Bsram', 0)),
                estimated_fmax_mhz=float(clock[2]),
                estimate_clock_constraint_mhz=float(clock[1]),
                netlist_sha256=digest(folder/'impl/gwsynthesis/bands.vg'))


def implementation(folder):
    pnr = folder/'impl/pnr'
    log = (folder/'route.log').read_text()
    assert 'Placement and routing completed' in log
    assert 'Power analysis completed' in log
    assert not re.search(r'\bERROR\b|\bPR0004\b|\b[1-9]\d*\s+unrout', log, re.I)
    report = (pnr/'bands.rpt.txt').read_text()
    resources = {}
    for label in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        m = re.search(rf'^\s+{label}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
        resources[label] = float(m[1]) if m else 0
    latches = re.findall(r'Register as Latch\s*\|\s*(\d+)/', report)
    assert latches and all(int(n) == 0 for n in latches)
    timing = (pnr/'bands_tr_content.html').read_text()
    clock = re.search(r'<td>clk</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
    assert clock and float(clock[1]) == 50
    violations = {}
    for kind in ['Setup', 'Hold']:
        m = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert m and int(m[1]) == 0
        violations[kind.lower()] = int(m[1])
    cmd = (pnr/'cmd.do').read_text()
    assert '-correct_hold 1' in cmd
    return dict(resources=resources, clock_constraint_mhz=float(clock[1]),
                fmax_mhz=float(clock[2]), violations=dict(violations, latch=0, unrouted=0),
                clock_scope='standalone clk register paths; automatic IO placement, no board CST or IO timing certification')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    dest = args.destination.resolve()
    dest.relative_to(ROOT/'build')
    if dest.exists():
        raise SystemExit('Choose a new archive directory')
    assert subprocess.check_output(['git', 'rev-parse', 'master'], cwd=ROOT).decode().strip() == BASE
    subprocess.run(['git', 'diff', '--exit-code', BASE, '--', 'rtl', 'mem', 'constraints',
                    'gowin/neo_guitar_touch_game/verification.json'], cwd=ROOT, check=True)
    variants = {}
    build_roots = []
    for attempt, candidate in [('direct_log_attempt1', 'direct_log'), ('balanced_log_attempt1', 'balanced_log')]:
        folder = BUILDS/attempt
        build_roots.append(folder)
        variants[candidate] = {name:dict(synthesis=synthesis(folder/name)) for name in ['baseline', candidate]}
        if candidate == 'balanced_log':
            for name in ['baseline', candidate]:
                variants[candidate][name]['implementation'] = implementation(folder/name)
    test_names = ['rtl_direct_log_v2', 'rtl_balanced_log',
                  'gate_direct_log_paired_v2', 'gate_balanced_log_paired']
    tests = {}
    for name in test_names:
        folder = SIM/name
        record = read_json(folder/'verification.json')
        assert record['status'] == 'PASS'
        assert digest(folder/'run.log') == record['log_sha256']
        assert digest(folder/'compile.log') == record['compile_log_sha256']
        log = (folder/'run.log').read_text()
        assert '209515 clocks, 734 publications' in log
        assert not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):', log)
        if name.startswith('rtl_'):
            assert 'all 524288 binary logarithm inputs and 722 X/Z probes' in log
        else:
            candidate = record['candidate']
            assert record['source_sha256']['synthesized_netlist'] == variants[candidate][candidate]['synthesis']['netlist_sha256']
            assert record['source_sha256']['baseline_synthesized_netlist'] == variants[candidate]['baseline']['synthesis']['netlist_sha256']
        tests[name] = record
    observations = ['rtl_direct_log', 'gate_direct_log', 'gate_direct_log_debug',
                    'gate_baseline_diagnostic', 'gate_direct_log_paired']
    for name in ['gate_direct_log_debug', 'gate_baseline_diagnostic']:
        log = (SIM/name/'run.log').read_text()
        assert 'output mismatch cycle=187145' in log
    # Preserve diagnostics rather than promoting a partial RTL/netlist comparison.
    result = dict(artifact_scope='independent bands experiment; no production RTL change or new board release',
                  production_master=BASE, production_image_unchanged=True,
                  integration_status='not_integrated', variants=variants, tests=tests,
                  observations=dict(
                      first_concat_candidate='All binary inputs passed; X/Z propagation differed. Final addition restored; final candidates pass all probes.',
                      standalone_warm_reset='Both original and direct-log standalone netlists differ from original RTL on first publication after a later reset, cycle 187145. Cause not yet established. Both candidate netlists match paired baseline netlists for the full sequence.',
                      harness_retry='First paired-netlist compile failed due PowerShell scalar/array expansion; corrected without changing stimulus or assertions.',
                      preserved_runs=observations),
                  limitations=['No full-system synthesis, P&R, pixel/audio regression or hardware test for these candidates.',
                               'Standalone automatic IO placement results cannot predict production CLS or Fmax.',
                               'Warm-reset RTL/netlist discrepancy remains a component experiment observation, not a newly certified reset contract.'])
    source_paths = sorted({p for folder in ['experiments/radial_bands', 'sim/reference/radial_bands']
                           for p in (ROOT/folder).glob('*.v')})
    source_paths += [ROOT/p for p in ['rtl/display/guitar_radial_bands.v',
                     'sim/tb/tb_radial_bands_equivalence.sv',
                     'docs/RADIAL_BANDS_RESOURCE_EXPERIMENT.md',
                     'tools/prepare_radial_bands_experiment.py',
                     'tools/run_radial_bands_experiment_checks.ps1',
                     'tools/start_radial_bands_experiment.ps1',
                     'tools/archive_radial_bands_experiment.py']]
    result['source_sha256'] = {p.relative_to(ROOT).as_posix():digest(p) for p in source_paths}
    protected = ['docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md',
                 'gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json']
    result['protected_user_files_sha256'] = {p:digest(ROOT/p) for p in protected}
    result['protected_index_entries'] = subprocess.check_output(['git', 'ls-files', '--stage', '--']+protected, cwd=ROOT).decode().splitlines()
    result['production_bitstream_sha256'] = digest(ROOT/'build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs')
    assert result['production_bitstream_sha256'] == 'e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86'
    dest.mkdir(parents=True)
    with zipfile.ZipFile(dest/'source_snapshot.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in source_paths:
            archive.write(path, path.relative_to(ROOT).as_posix())
    suffixes = {'.v', '.sv', '.vg', '.ps1', '.tcl', '.sdc', '.xml', '.html', '.txt', '.log', '.json', '.do', '.cfg'}
    for folder in build_roots + [SIM/n for n in test_names+observations]:
        for path in folder.rglob('*'):
            if path.is_file() and path.suffix in suffixes and 'work' not in path.relative_to(folder).parts:
                target = dest/'evidence'/path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
    result['archive_files_sha256'] = {p.relative_to(dest).as_posix():digest(p)
                                       for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'verification.json').write_text(json.dumps(result, indent=2)+'\n')
    print(dest/'verification.json')


if __name__ == '__main__':
    main()
