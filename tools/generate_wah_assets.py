"""Prepare timbre 3 only from the new dry C4/E4/G4 wah references."""
from pathlib import Path
import hashlib
import json
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
FS=48000
STEP=1024
FRAMES=32
CUTOFF=28800


def hex_file(path,values,bits):
    path.write_text(''.join(f'{int(v)&((1<<bits)-1):0{(bits+3)//4}X}\n' for v in values.flat),encoding='ascii')


def quantize_gains(weights):
    raw=weights/weights.sum()*32760
    values=np.floor(raw).astype(np.int64)
    remaining=32760-int(values.sum())
    if remaining:values[np.argsort(raw-values)[-remaining:]]+=1
    assert values.sum()==32760
    return values


def main():
    source=ROOT/'build/wah_reference'
    data=json.loads((source/'analysis.json').read_text(encoding='utf-8'))
    if [m['label'] for m in data['metadata']]!=['C4','E4','G4','chord']:
        raise ValueError('New dry reference set required')
    for m in data['metadata']:
        if hashlib.sha256(Path(m['path']).read_bytes()).hexdigest()!=m['sha256']:
            raise ValueError('Reference changed: '+m['label'])
    measured=np.load(source/'modal_curves.npz')
    times=measured['times'];curves=measured['curves'];ratios=measured['ratios']
    grid=np.arange(FRAMES)*STEP/FS
    gain_rows=[];envelope_rows=[];phase_rows=[]
    for profile in range(3):
        two=curves[profile*2:profile*2+2].copy()
        # One scalar per strike compensates velocity, retaining the measured
        # formant/amplitude motion. Held keys adapt to finite right-hand plucks;
        # all modes have a common decay so the high-frequency buzz survives.
        early=(times>=.05)&(times<=.25)
        scale=np.linalg.norm(two[:,:,early],axis=1).mean(axis=1)
        two/=scale[:,None,None]
        curve=np.median(two,axis=0)
        body=np.array([np.interp(grid+.02,times,part) for part in curve])
        body*=np.exp(-grid/.25)*np.clip((.60-grid)/.15,0,1)
        peaks=body.max(axis=1)
        gains=quantize_gains(peaks)
        levels=np.rint(4095*body/np.maximum(peaks[:,None],1e-12)).astype(np.int64)
        levels[gains==0]=0
        assert np.all((levels>=0)&(levels<=4095)) and np.all(levels[:,-1]==0)
        following=np.c_[levels[:,1:],levels[:,-1]]
        delta=following-levels
        # Unsigned base + signed delta; multiply ABS(delta), apply its sign
        # outside the DSP to avoid the Gowin signed pre-adder narrowing issue.
        packed=(levels<<13)|(delta&0x1fff)
        phase=measured['phases'][profile*2]
        seeds=np.rint((phase/(2*np.pi)%1)*2**32).astype(np.int64)&0xffffffff
        seeds[0]=0
        gain_rows.append(gains);envelope_rows.append(packed);phase_rows.append(seeds)
    gains=np.array(gain_rows);envelopes=np.array(envelope_rows);seeds=np.array(phase_rows)
    ratio_q20=np.rint(ratios*2**20).astype(np.int64)
    assert ratio_q20[0]==2**20 and len(np.unique(ratio_q20))==32
    mem=ROOT/'mem'
    hex_file(mem/'rock_gain.mem',gains,16)
    hex_file(mem/'rock_envelope.mem',envelopes,25)
    hex_file(mem/'rock_phase.mem',seeds,32)
    hex_file(mem/'rock_ratio.mem',ratio_q20,26)
    lines=['// Generated exclusively from dry C4/E4/G4 wah references.',
        "localparam [16:0] ROCK_DRY_CUTOFF=17'd28800;",
        'function [15:0] rock_gain_for;','    input [1:0] sound_profile;','    input [4:0] mode;',
        '    begin case({sound_profile,mode})']
    lines += [f"        7'd{p*32+n}: rock_gain_for=16'd{gains[p,n]};" for p in range(3) for n in range(32)]
    lines += ['        default: rock_gain_for=0;','    endcase end','endfunction',
        'function [31:0] rock_phase_for;','    input [1:0] sound_profile;','    input [4:0] mode;',
        '    begin case({sound_profile,mode})']
    lines += [f"        7'd{p*32+n}: rock_phase_for=32'h{seeds[p,n]:08X};" for p in range(3) for n in range(32)]
    lines += ['        default: rock_phase_for=0;','    endcase end','endfunction',
        'function [25:0] rock_ratio_for;','    input [4:0] mode;','    begin case(mode)']
    lines += [f"        5'd{n}: rock_ratio_for=26'd{r};" for n,r in enumerate(ratio_q20)]
    lines += ["        default: rock_ratio_for=26'd1048576;",'    endcase end','endfunction','']
    (ROOT/'rtl/config/rock_coeffs.vh').write_text('\n'.join(lines),encoding='ascii')
    profile=dict(version='dry_wah_reference_v4_long_decay',sample_rate_hz=FS,
        source_files=data['metadata'],source_settings=data['settings'],
        harmonics=32,modal_ratios=ratios.tolist(),profiles=['C4','E4','G4'],
        gain_sum_q15_per_profile=[int(g.sum()) for g in gains],
        nonzero_components_per_profile=[int(np.count_nonzero(g)) for g in gains],
        envelope_words=3072,envelope_word_bits=25,envelope_level_bits=12,envelope_delta_bits=13,
        envelope_frames_per_component=FRAMES,envelope_step_samples=STEP,
        interpolation='floor-rounded linear, unsigned abs-delta multiplication',attack_samples=32,
        virtual_dry_cutoff_samples=CUTOFF,virtual_dry_cutoff_s=CUTOFF/FS,virtual_pluck_tau_s=.25,
        playback_initial_unscaled_samples=2048,playback_envelope_rate_after_initial=.5,
        dry_cutoff_samples=2*CUTOFF-2048,dry_cutoff_s=(2*CUTOFF-2048)/FS,
        sustain_cutoff_samples=4*(2*CUTOFF-2048)-3*2048,
        sustain_cutoff_s=(4*(2*CUTOFF-2048)-3*2048)/FS,
        pluck_tau_s_after_initial=.5,
        amplitude_sum_bound_pcm16=16380,
        selected_half_grid_power_fractions=data['selected_grid_power_fractions'],
        synthesis='Three measured moving modal profiles with half-integer ratios; no old metal references or invented overdrive/low-pass profile',
        limitations=['Only three recorded keys; nearest register profile between them.',
            'Manual held-key duration adapted to a finite right-hand pluck.',
            '32 strongest modes approximate source; residual detuning and low-level non-modal energy not copied.'])
    for name in ('rock_gain.mem','rock_envelope.mem','rock_phase.mem','rock_ratio.mem'):
        profile[name+'_sha256']=hashlib.sha256((mem/name).read_bytes()).hexdigest()
    (mem/'rock_profile.json').write_text(json.dumps(profile,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(profile,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
