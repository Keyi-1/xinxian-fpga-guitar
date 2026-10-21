"""Bind completed P5 exploration evidence; never run hardware or FPGA builds."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone, timedelta

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/p5_bluetooth'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    baseline = read(BUILD / 'baseline.json')
    for relative, expected in {**baseline['files'], **baseline['production_sources']}.items():
        if sha(ROOT / relative) != expected:
            raise ValueError(f'Preserved file changed: {relative}')
    protected = ['gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json',
                 'docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md']
    index = subprocess.check_output(['git', 'ls-files', '--stage', '--', *protected], cwd=ROOT, text=True)
    if index != baseline['protected_index']:
        raise ValueError('Protected staging changed')
    subprocess.run(['git', 'diff', '--exit-code', baseline['baseline'], '--', 'rtl', 'mem', 'scores', 'gowin',
                    'tools/game_score_upload.py', 'tools/upload_game_score.py', 'tools/test_game_score_upload.py'],
                   cwd=ROOT, check=True, capture_output=True)
    host = (BUILD/'host_tests.log').read_text(encoding='utf-8-sig')
    phone = (BUILD/'mobile_tests_final.log').read_text(encoding='utf-8-sig')
    if not re.search(r'Ran 9 tests\b', host) or not re.search(r'\nOK\s*$', host):
        raise ValueError('Native host test evidence missing')
    if not all(re.search(rf'\b{k}\s+{n}\b', phone) for k,n in [('tests',16),('pass',16),('fail',0)]):
        raise ValueError('Mobile shared protocol test evidence missing')
    native = read(BUILD/'host/build.json')
    if native['exit_code'] != 0:
        raise ValueError('Host C build failed')
    for relative, expected in native['source_sha256'].items():
        if sha(ROOT/relative) != expected: raise ValueError(f'C core changed: {relative}')
    rtl_dir = BUILD/'p5_bridge_rtl_02'
    rtl = read(rtl_dir/'verification.json')
    if rtl['status'] != 'PASS': raise ValueError('New RTL replay failed')
    for relative, expected in rtl['sources'].items():
        if sha(ROOT/relative) != expected: raise ValueError(f'RTL evidence source changed: {relative}')
    for relative, expected in rtl['logs'].items():
        if sha(rtl_dir/relative) != expected: raise ValueError(f'RTL evidence changed: {relative}')
    bundle = read(BUILD/'mobile_bundle_final_verification.json')
    if bundle['status'] != 'PASS': raise ValueError('Final JS bundle failed')
    for relative, expected in bundle['sources'].items():
        if sha(ROOT/'mobile/p5-import'/relative) != expected: raise ValueError('Mobile source changed after bundle')
    artifacts = list((BUILD/'mobile-bundle-final').rglob('*.js'))
    if not any('android' in p.parts for p in artifacts) or not any('ios' in p.parts for p in artifacts):
        raise ValueError('Both platform bundles required')
    config = read(BUILD/'mobile_introspect_final.json')['_internal']['modResults']
    manifest = config['android']['manifest']['manifest']
    permissions = {p['$']['android:name']: p['$'] for p in manifest['uses-permission']}
    if permissions['android.permission.BLUETOOTH_SCAN'].get('android:usesPermissionFlags') != 'neverForLocation':
        raise ValueError('Android BLE permission configuration mismatch')
    for name in ['READ_EXTERNAL_STORAGE','WRITE_EXTERNAL_STORAGE']:
        if permissions['android.permission.'+name].get('tools:node') != 'remove':
            raise ValueError('Unexpected broad storage permission')
    if not config['ios']['infoPlist'].get('NSBluetoothAlwaysUsageDescription'):
        raise ValueError('iOS Bluetooth purpose string missing')
    code = list((ROOT/'firmware/p5_bridge').glob('*.?'))
    code += [ROOT/p for p in ['mobile/p5-import/App.jsx','mobile/p5-import/index.js',
        'mobile/p5-import/src/protocol.js','mobile/p5-import/test/protocol.test.js','mobile/p5-import/package.json',
        'mobile/p5-import/pnpm-lock.yaml','mobile/p5-import/app.json','tools/p5_score_package.py',
        'tools/test_p5_bridge.py','tools/p5_rtl_vectors.py','tools/run_p5_rtl.ps1','tools/check_p5_exploration.py',
        'sim/tb/tb_p5_bridge_replay.sv']]
    evidence = [BUILD/'host_tests.log',BUILD/'mobile_tests_final.log',BUILD/'host/build.json',
        BUILD/'host/compile.log',BUILD/'mobile_bundle_final.log',BUILD/'mobile_bundle_final_verification.json',
        BUILD/'mobile_introspect_final.json',rtl_dir/'verification.json',BUILD/'research/downloads.json',
        BUILD/'example/qing_ge.xgscore'] + artifacts
    result = dict(status='PASS_EXPLORATION_ONLY',generated_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
        base_commit=baseline['baseline'],remote_master_checked=baseline['remote_master_checked'],
        branch='experiment/p5-bluetooth-import',source_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in code},
        evidence_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in evidence},
        tests=dict(native_host=9,mobile_protocol_pc_model=16,new_rtl_uart_traces=17,
                   android_ios_js_bundle=True,native_apk_ipa=False,bl616_target_image=False,
                   new_synthesis_pnr_netlist=False,physical_ble=False),
        preserved=dict(production_sources=True,protected_bytes_and_index=True,
            p4_bitstream_sha256='cfda7ead63703142876e10776a38f86237188aeb4a4d910b02aa0927df611a30'),
        target_blockers=['U35/L9/antenna assembly unknown','Installed debugger serial unknown',
            '31005 secondary boot mode and recovery unverified','26MHz BSP/RF adaptation and target SDK/toolchain required',
            'Actual competition rules for onboard auxiliary MCU required'],
        boundary='Host tests, accelerated RTL component replay and JS bundling only. No radio/COM/flash/push/merge. Original P4 certification not extended.')
    (BUILD/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS: preserved P4 production/bitstreams/protected index; C9, JS16, RTL17, Android+iOS JS bundles only')


if __name__ == '__main__': main()
