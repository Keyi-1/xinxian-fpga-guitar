"""Compare FULL v1/v2 effects using actual RTL stereo PCM16 samples.

Run sim/run_main_regression.ps1 -Benches tb_full_effects_pcm_export first.
No gain normalization, resampling, or software effects are applied to WAVs.
All variants use one C4 open-string pluck with no note-off, a real 256-clock
audio budget, and the board's panning, clip, effects and PCM16 conversion.
"""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'piano' / 'effects_v2'
FS = 48000
PLUCK = .15
TONES = ('piano', 'bright')
EFFECTS = ('dry', 'chorus', 'room', 'sustain')


def load(index):
    path = ROOT / 'sim' / 'temp' / f'full_effects_{index}_pcm16.txt'
    values = np.fromiter((int(v, 16) for v in path.read_text().split()),
                         dtype=np.int32)
    if values.size != 192000 * 2:
        raise ValueError(f'Incomplete export {path}: {values.size} values')
    values[values >= 32768] -= 65536
    return values.reshape(-1, 2).astype(np.int16)


def save(name, pcm):
    path = OUT / name
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(FS)
        wav.writeframes(pcm.astype('<i2').tobytes())
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rms_window(pcm, start, end):
    window = pcm[round((PLUCK + start) * FS):round((PLUCK + end) * FS)].astype(float)
    return float(np.sqrt(np.mean(window ** 2)))


def db_ratio(a, b):
    # An exactly silent PCM16 reference has no finite dB ratio.
    return None if b == 0 else float(20 * np.log10(max(a, 1e-12) / b))


def fundamental(pcm):
    window = pcm[round((PLUCK + .15) * FS):round((PLUCK + .55) * FS)].astype(float)
    spectrum = np.fft.rfft(window * np.hanning(len(window))[:, None],
                           n=262144, axis=0)
    frequencies = np.fft.rfftfreq(262144, 1 / FS)
    region = np.flatnonzero((frequencies > 256) & (frequencies < 267))
    power = np.mean(abs(spectrum) ** 2, axis=1)
    peak = region[np.argmax(power[region])]
    return float(frequencies[peak])


def effect_difference(dry, effected):
    # Remove the best-fit volume difference when measuring timbral change.
    # This gain is for evidence only; WAV samples remain unmodified.
    lo, hi = round((PLUCK + .1) * FS), round((PLUCK + 1.5) * FS)
    x, y = dry[lo:hi].astype(float), effected[lo:hi].astype(float)
    gain = float(np.sum(x * y) / np.sum(x * x))
    residual = float(np.sqrt(np.mean((y - gain * x) ** 2)))
    reference = float(np.sqrt(np.mean(y ** 2)))
    return {'best_fit_dry_gain': gain,
            'residual_percent_of_effected_rms': 100 * residual / reference,
            'stereo_correlation': float(np.corrcoef(y.T)[0, 1])}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    clips = {}
    evidence = {'sample_rate_hz': FS, 'frames_per_variant': 192000,
                'channels': 2, 'pluck_time_seconds': PLUCK,
                'input': 'One C4 open-string pluck, velocity 2, no note-off',
                'gain': 'Actual RTL PCM16; no WAV gain normalization or extra effects',
                'sample_budget_clocks': 256, 'variants': {}, 'comparisons': {}}
    for edition in (1, 2):
        for tone_index, tone in enumerate(TONES):
            for fx_index, effect in enumerate(EFFECTS):
                name = f'v{edition}_{tone}_{effect}'
                pcm = load((edition - 1) * 8 + tone_index * 4 + fx_index)
                clips[name] = pcm
                peak = int(np.max(np.abs(pcm.astype(np.int32))))
                assert peak < 32767, name
                metrics = {'peak_pcm16': peak, 'fundamental_hz': fundamental(pcm),
                           'rms_0p1_0p3_seconds': rms_window(pcm, .1, .3),
                           'rms_0p8_1p2_seconds': rms_window(pcm, .8, 1.2),
                           'rms_1p5_2p0_seconds': rms_window(pcm, 1.5, 2),
                           'rms_2p5_3p3_seconds': rms_window(pcm, 2.5, 3.3),
                           'sha256': save(f'{name}.wav', pcm)}
                evidence['variants'][name] = metrics

    # The open-string bug in v1 and exact preservation of accepted dry piano.
    for tone in TONES:
        assert np.array_equal(clips[f'v1_{tone}_dry'], clips[f'v1_{tone}_sustain'])
    assert np.array_equal(clips['v1_piano_dry'], clips['v2_piano_dry'])
    evidence['v1_open_string_sustain_identical_to_dry'] = True
    evidence['v2_dry_piano_identical_to_v1'] = True
    gap = np.zeros((round(.35 * FS), 2), dtype=np.int16)
    for tone in TONES:
        for edition in (1, 2):
            dry = clips[f'v{edition}_{tone}_dry']
            for effect in ('chorus', 'room'):
                name = f'v{edition}_{tone}_{effect}'
                evidence['variants'][name]['difference_from_dry'] = effect_difference(dry, clips[name])
        dry_rms = rms_window(clips[f'v2_{tone}_dry'], 2.5, 3.3)
        sustain_rms = rms_window(clips[f'v2_{tone}_sustain'], 2.5, 3.3)
        evidence['comparisons'][tone] = {
            'v2_sustain_over_dry_0p8_1p2_seconds_db': db_ratio(
                rms_window(clips[f'v2_{tone}_sustain'], .8, 1.2),
                rms_window(clips[f'v2_{tone}_dry'], .8, 1.2)),
            'v2_sustain_over_dry_1p5_2p0_seconds_db': db_ratio(
                rms_window(clips[f'v2_{tone}_sustain'], 1.5, 2),
                rms_window(clips[f'v2_{tone}_dry'], 1.5, 2)),
            'v2_sustain_over_dry_late_tail_db': db_ratio(sustain_rms, dry_rms),
            'v2_dry_late_tail_is_exact_pcm16_silence': dry_rms == 0,
            'effect_order': 'dry 4s, gap .35s, chorus 4s, gap .35s, room 4s, gap .35s, sustain 4s',
            'effect_starts_seconds': [0, 4.35, 8.7, 13.05]}
        assert sustain_rms > 20, f'{tone}: missing open-string sustain tail'
        sequence = []
        for effect in EFFECTS:
            if sequence:
                sequence.append(gap)
            sequence.append(clips[f'v2_{tone}_{effect}'])
        save(f'v2_{tone}_effects_comparison.wav', np.concatenate(sequence))
        save(f'{tone}_sustain_v1_v2.wav', np.concatenate([
            clips[f'v1_{tone}_sustain'], gap, clips[f'v2_{tone}_sustain']]))
        for effect in ('dry', 'sustain'):
            assert abs(evidence['variants'][f'v2_{tone}_{effect}']['fundamental_hz'] - 261.625565) < .5

    fig, axes = plt.subplots(2, 2, figsize=(12, 7), layout='constrained')
    colors = {'dry': '#606060', 'chorus': '#2166ac', 'room': '#9c4dcc', 'sustain': '#16855b'}
    block = 480  # 10 ms RMS, common absolute scale.
    for row, tone in enumerate(TONES):
        for col, edition in enumerate((1, 2)):
            ax = axes[row, col]
            for effect in EFFECTS:
                pcm = clips[f'v{edition}_{tone}_{effect}'].astype(float) / 32768
                rms = np.sqrt(np.mean(pcm.reshape(-1, block, 2) ** 2, axis=(1, 2)))
                ax.plot(np.arange(len(rms)) * block / FS - PLUCK,
                        20 * np.log10(np.maximum(rms, 1e-6)), color=colors[effect],
                        linestyle='--' if effect == 'sustain' else '-', label=effect)
            ax.set(title=f'v{edition}: {tone}', xlabel='Time after open-string pluck (s)',
                   ylabel='10 ms RMS (dBFS)', xlim=(0, 3.7), ylim=(-100, -10))
            ax.legend()
            ax.grid(alpha=.2)
    fig.savefig(OUT / 'open_string_effects_comparison.png', dpi=160)
    plt.close(fig)
    (OUT / 'effects_metrics.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'checks': {k: v for k, v in evidence.items() if k.startswith('v1_') or k.startswith('v2_')},
                      'comparisons': evidence['comparisons'],
                      'differences': {k: v['difference_from_dry'] for k, v in evidence['variants'].items()
                                      if 'difference_from_dry' in v}}, indent=2))


if __name__ == '__main__':
    main()
