"""Prepare paired, immutable component builds, outside the production project.

Both variants use the same top name, device B, timing and synthesis options.
This is not a production build or a source of full-system resource/Fmax claims.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BASE = '8230217e56952ee2793b97d98ef90e2740fff54b'
SOURCE = 'rtl/display/guitar_radial_bands.v'
FROZEN = 'sim/reference/radial_bands/guitar_radial_bands_frozen.v'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    parser.add_argument('--candidate', choices=['direct_log', 'balanced_log'], default='direct_log')
    args = parser.parse_args()
    candidate_source = f'experiments/radial_bands/guitar_radial_bands_{args.candidate}.v'
    top = f'guitar_radial_bands_{args.candidate}'
    dest = args.destination.resolve()
    dest.relative_to(ROOT / 'build')
    if dest.exists():
        raise SystemExit('Choose a new directory; existing results are preserved')
    original = subprocess.check_output(['git', 'show', f'{BASE}:{SOURCE}'], cwd=ROOT).decode()
    frozen = (ROOT/FROZEN).read_text().replace('module guitar_radial_bands_frozen(',
                                             'module guitar_radial_bands(')
    assert frozen == original, 'Frozen reference is not the declared commit'
    assert (ROOT/SOURCE).read_text() == original, 'Production bands changed'
    candidate = (ROOT/candidate_source).read_text().replace(f'module {top}(',
                                                   'module guitar_radial_bands(')
    # Every sequential statement, map, and attenuation expression is unchanged.
    def without_log(text):
        start = text.index('    function [7:0] log2q3;')
        end = text.index('    endfunction', start) + len('    endfunction')
        return text[:start] + text[end:]
    assert without_log(candidate) == without_log(original), 'Experiment scope changed'
    sources = [SOURCE, FROZEN, candidate_source,
               'sim/tb/tb_radial_bands_equivalence.sv',
               'tools/run_radial_bands_experiment_checks.ps1',
               'tools/prepare_radial_bands_experiment.py',
               'tools/start_radial_bands_experiment.ps1']
    manifest = dict(base_commit=BASE, artifact_scope='standalone frequency-band component only',
                    source_sha256={p:digest(ROOT/p) for p in sources}, variants={}, processes=[])
    protected = ['docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md',
                 'gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json']
    manifest['protected_user_files_sha256'] = {p:digest(ROOT/p) for p in protected}
    for name, text in [('baseline', original), (args.candidate, candidate)]:
        folder = dest/name
        folder.mkdir(parents=True)
        rtl = folder/'bands.v'
        rtl.write_text(text.replace('module guitar_radial_bands(', f'module {top}('))
        sdc = folder/'bands.sdc'
        sdc.write_text('create_clock -name clk -period 20.000 [get_ports {clk}]\n')
        options = f'''set_device -name GW5AT-60B GW5AT-LV60PG484AC1/I0
set_option -synthesis_tool gowinsynthesis
set_option -top_module {top}
set_option -verilog_std v2001
set_option -output_base_name bands
set_option -print_all_synthesis_warning 1
set_option -show_all_warn 1
set_option -place_option 4
set_option -route_option 2
set_option -clock_route_order 1
'''
        prefix = 'set here [file dirname [file normalize [info script]]]\ncd $here\n'
        (folder/'synth.tcl').write_text(prefix +
            'add_file -type verilog [file join $here bands.v]\n' +
            'add_file -type sdc [file join $here bands.sdc]\n' + options + 'run syn\n')
        (folder/'route.tcl').write_text(prefix +
            'add_file [file join $here impl gwsynthesis bands.vg]\n' +
            'add_file -type sdc [file join $here bands.sdc]\n' + options + 'run pnr\n')
        manifest['variants'][name] = {p.name:digest(p) for p in folder.iterdir()}
    (dest/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(dest)


if __name__ == '__main__':
    main()
