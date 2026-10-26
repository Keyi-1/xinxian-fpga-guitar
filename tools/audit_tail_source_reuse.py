"""Record source reuse without claiming synthesis graph equivalence.

The user requested verification of the affected audio paths only. The fresh
Gowin run refactors LUTs and names some ports differently even in unchanged
source modules. Preserve that diagnostic; do not turn it into an equivalence
claim or certify the new implementation with old simulation logs.
"""
from pathlib import Path
from check_tail_lock_result import BASE, RUN, ROOT, CHANGED, source_guard
from check_piano_hold_result import load, save, sha


def main():
    manifest, baseline = source_guard()
    graph = load(RUN / 'unchanged_graph_audit.json')
    vg = ROOT / 'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
    old_vg = BASE / 'evidence/gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
    assert graph['netlist_sha256'] == sha(vg)
    assert graph['baseline_netlist_sha256'] == sha(old_vg)
    assert graph['tool_sha256'] == sha(ROOT / 'tools/audit_tail_unchanged.py')
    assert graph['modules']['mcp3208_pluck_frontend']['equal']
    reused = {p: digest for p, digest in manifest.items() if p not in CHANGED}
    assert all(digest == baseline['source_sha256'][p] for p, digest in reused.items())
    record = {
        'result': 'PASS',
        'scope': 'Byte-identical source/ROM/project/constraints reuse guard only; not functional or netlist equivalence certification of untested subsystems',
        'netlist_sha256': sha(vg),
        'baseline_verification_sha256': sha(BASE / 'verification.json'),
        'source_manifest_sha256': sha(RUN / 'source_manifest.json'),
        'tool_sha256': sha(Path(__file__)),
        'graph_diagnostic_sha256': sha(RUN / 'unchanged_graph_audit.json'),
        'changed_runtime_sources': sorted(CHANGED),
        'unchanged_source_sha256': reused,
        'adc_exact_graph_equal': True,
        'other_graphs_equal': all(r['equal'] for r in graph['modules'].values()),
        'fresh_verification': 'Current actual complete audio-child VG versus current RTL and an independent frozen-chain pitch scenario; full original-project P&R/STA',
        'not_repeated': 'UI/UART/MPU simulations and unrelated completed regressions; their source bytes retained, no fresh functional certification claimed',
    }
    save(RUN / 'source_reuse_audit.json', record)
    print(f'PASS: {len(reused)} unchanged source/ROM/project/constraint hashes; 7 scoped runtime edits; ADC exact graph retained. Other graph matches are not claimed.')


if __name__ == '__main__':
    main()
