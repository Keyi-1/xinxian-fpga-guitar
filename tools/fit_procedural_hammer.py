"""Fit a few noise-filter parameters, never an audio waveform or state trajectory.

The simulation-only old residual supplies spectral/RMS targets. This optional
offline analysis writes coefficients and scalars; HDL generates every sample.
Run with the scientific Python environment (NumPy + SciPy).
"""
from pathlib import Path
import hashlib
import json
import numpy as np
from scipy import signal, optimize

ROOT = Path(__file__).resolve().parents[1]
FS = 48000


def main():
    reference = ROOT / 'sim/reference/piano_legacy/piano_hammer.mem'
    raw = np.array([int(x, 16) for x in reference.read_text().split()])
    raw[raw >= 32768] -= 65536
    raw = raw.reshape(3, 2048)
    w = np.linspace(2*np.pi*600/FS, 2*np.pi*7500/FS, 80)
    z = np.exp(-1j*w)
    noise_power=np.abs(.25/(1-.75*z))**8
    banks = []
    for bank, target in enumerate(raw):
        f, p = signal.welch(target.astype(float), FS, nperseg=512)
        target_psd = np.interp(w*FS/(2*np.pi), f, p)
        target_psd /= target_psd.max()
        def spectrum(v):
            centers, radii, gains = v[:3], v[3:6], v[6:9]
            h = [(1-z*z)/(1-2*r*np.cos(2*np.pi*c/FS)*z+r*r*z*z)
                 for c, r in zip(centers, radii)]
            return noise_power*sum(g*g*np.abs(x)**2 for g, x in zip(gains, h))
        def objective(v):
            p = spectrum(v)
            p /= p.max()
            return np.log(np.maximum(p, .0001))-np.log(np.maximum(target_psd, .0001))
        fit = optimize.least_squares(objective,
            [1100, 3000, 5800, .93, .91, .87, .6, 1., .5],
            bounds=([650, 1800, 3800, .72, .72, .72, .08, .08, .08],
                    [1800, 4400, 7500, .985, .985, .985, 3., 3., 3.]),
            max_nfev=3000)
        v = fit.x
        # Only shift weights in HDL. Overall level is a single envelope scalar.
        shifts = np.clip(np.rint(5-np.log2(v[6:9]/max(v[6:9]))), 5, 10).astype(int)
        a1 = np.rint(-2*v[3:6]*np.cos(2*np.pi*v[:3]/FS)*16384).astype(int)
        a2 = np.rint(v[3:6]**2*16384).astype(int)
        banks.append(dict(a1_q14=a1.tolist(), a2_q14=a2.tolist(),
                          noise_shifts=shifts.tolist(), envelope_start_q24=0x800000,
                          fitted_centers_hz=v[:3].tolist(), fitted_radii=v[3:6].tolist(),
                          target_rms_pcm16=float(np.sqrt(np.mean(target.astype(float)**2)))))
    out = dict(sample_rate_hz=FS, duration_samples=2048, seed=0x6d2b79f5,
               algorithm='xorshift32 innovations; four shift-only lowpass poles; three parallel damped bandpass resonators; difference of exponential envelopes',
               innovation_lowpass_poles=4,innovation_lowpass_shift=2,
               coefficients_fraction_bits=14, filter_state_bits=18, profiles=banks,
               reference_usage='Spectral shape and RMS only; no recorded PCM or per-sample trajectory emitted',
               reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest())
    path = ROOT/'mem/piano_hammer_model.json'
    path.write_text(json.dumps(out, indent=2)+'\n')
    # Calibrate the analytic envelope's scalar against long independent strikes.
    from procedural_hammer import HammerModel
    for bank in range(3):
        # Search using the actual clipped/floor-rounded model. A single scale
        # estimate from a clipped loud reference would overstate attack energy.
        lower,upper=0,0xffffff
        target=out['profiles'][bank]['target_rms_pcm16']**2
        # Make enough excitation headroom before searching the bounded Q15
        # envelope scalar. Keep relative band weights and the 2048 output cap.
        for _ in range(6):
            out['profiles'][bank]['envelope_start_q24']=0xffffff
            energies=[]
            for seed in (0x6d2b79f5,0x9e3779b9,0xa341316c,0xc8013ea4):
                model=HammerModel(seed,out)
                wave=np.array([model.sample(n==0,True,n,bank) for n in range(2048)],dtype=float)
                energies.append(np.mean(wave*wave))
            if np.mean(energies)>=target:break
            shifts=out['profiles'][bank]['noise_shifts']
            if min(shifts)<=0:raise ValueError('Cannot calibrate hammer energy within fixed-point limits')
            out['profiles'][bank]['noise_shifts']=[s-1 for s in shifts]
        else:raise ValueError('Insufficient excitation headroom')
        for _ in range(16):
            candidate=(lower+upper)//2
            out['profiles'][bank]['envelope_start_q24']=candidate
            energies=[]
            for seed in (0x6d2b79f5, 0x9e3779b9, 0xa341316c, 0xc8013ea4):
                model=HammerModel(seed, out)
                wave=[model.sample(n==0, True, n, bank) for n in range(2048)]
                energies.append(np.mean(np.array(wave,dtype=float)**2))
            if np.mean(energies)<target:lower=candidate
            else:upper=candidate
        out['profiles'][bank]['envelope_start_q24']=(lower+upper)//2
    path.write_text(json.dumps(out, indent=2)+'\n')
    lines=['// Spectral/RMS parameters only. No sampled audio or filter-state table.\n']
    for field, name, width in [('a1_q14','hammer_a1',17),('a2_q14','hammer_a2',17),('noise_shifts','hammer_noise_shift',4)]:
        signed=' signed' if width==17 else ''
        lines += [f'function{signed} [{width-1}:0] {name};\n',
                  '    input [1:0] bank; input [1:0] band;\n    begin\n        case ({bank,band})\n']
        for bank, profile in enumerate(out['profiles']):
            for band, value in enumerate(profile[field]):
                literal=(f"-17'sd{-value}" if value<0 else f"17'sd{value}") if width==17 else f"4'd{value}"
                lines.append(f"            4'd{bank*4+band}: {name}={literal};\n")
        lines += [f"            default: {name}=0;\n        endcase\n    end\nendfunction\n"]
    lines += ['function [23:0] hammer_envelope_start;\n    input [1:0] bank;\n    begin\n        case(bank)\n']
    for bank, profile in enumerate(out['profiles']):
        lines.append(f"            2'd{bank}: hammer_envelope_start=24'd{profile['envelope_start_q24']};\n")
    lines += ["            default: hammer_envelope_start=0;\n        endcase\n    end\nendfunction\n"]
    (ROOT/'rtl/config/piano_hammer_coeffs.vh').write_text(''.join(lines))
    print(json.dumps(out, indent=2))


if __name__=='__main__': main()
