"""Fixed dry piano triad from RTL: test linear mixing and export fair listening AB."""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
SIM=ROOT/'sim/temp/procedural_static'
OUT=ROOT/'build/procedural_piano/static_triad'
FS=48000


def read(name):
    rows=np.loadtxt(SIM/name,dtype=str)
    run=rows[:,0].astype(int)
    data=np.array([[int(v,16) for v in row] for row in rows[:,1:]],dtype=np.int64)
    for c,bits in enumerate([16,16,24,24]):
        data[data[:,c]>=(1<<(bits-1)),c]-=1<<bits
    clips=[data[run==n] for n in range(4)]
    assert [len(x) for x in clips]==[48000,48000,48000,96000]
    return clips


def save(name,data):
    with wave.open(str(OUT/name),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(FS)
        f.writeframes(data[:,:2].astype('<i2').tobytes())


def main():
    evidence=json.loads((SIM/'verification.json').read_text(encoding='utf-8-sig'))
    assert evidence['result']=='PASS'
    for path,digest in evidence['source_sha256'].items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path
    assert hashlib.sha256((SIM/'run.log').read_bytes()).hexdigest()==evidence['log_sha256']
    OUT.mkdir(parents=True,exist_ok=True)
    versions=[read('static_triad_legacy.txt'),read('static_triad_procedural.txt')]
    checks=[]
    for label,clips in zip(['legacy','procedural'],versions):
        linear_delta=clips[3][:48000]-sum(clips[:3])
        pre_peak=int(np.abs(linear_delta[:,2:]).max())
        pcm_peak=int(np.abs(linear_delta[:,:2]).max())
        assert pre_peak<=2 and pcm_peak<=3,(label,pre_peak,pcm_peak)
        assert all(np.abs(x[:,:2]).max()<32767 for x in clips)
        checks.append(dict(version=label,pre_fx_superposition_error_pcm24=pre_peak,
                           final_superposition_error_pcm16=pcm_peak,
                           chord_peak_pcm16=int(np.abs(clips[3][:,:2]).max())))
        save(f'piano_C4_E4_G4_dry_{label}.wav',clips[3])
        for voice,note in enumerate(['G4','E4','C4']):
            save(f'piano_{note}_dry_{label}.wav',clips[voice])
    # No effects are enabled, so after the intentional hammer transient the
    # complete final stereo stream must be identical, including rounding.
    for before,after in zip(*versions):
        assert np.array_equal(before[2112:],after[2112:]),'Changed post-attack dry body'
    parts=[]
    gap=np.zeros((7200,4),dtype=np.int64)
    for n in [2,1,0,3]:  # C, E, G solos; fixed triad last
        parts.extend([versions[0][n],gap,versions[1][n],gap])
    save('piano_fixed_notes_dry_ab.wav',np.concatenate(parts))
    save('piano_C4_E4_G4_dry_ab.wav',np.concatenate([versions[0][3],gap,versions[1][3]]))
    result=dict(result='PASS',sample_rate_hz=FS,velocity_level=2,
        notes_hz=[261.625565,329.627557,391.995436],voices=3,
        fret_changes=False,harmony=False,chorus=False,room=False,retrigger=False,
        gain='Unmodified original full-chain gain; no normalisation, EQ or added fades',
        checks=checks,post_attack_stereo_exact_from_frame=2112,
        explanation='Earlier stress preview deliberately used four voices, changed to open-string pitches at chord+0.292s, enabled FX at +0.375s and restruck at +0.417/+0.425s. This separate diagnostic holds all three notes constant.',
        rtl_evidence=evidence,
        input_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
            [SIM/'static_triad_legacy.txt',SIM/'static_triad_procedural.txt']},
        wav_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.wav')})
    (OUT/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['result','checks','post_attack_stereo_exact_from_frame']},indent=2))


if __name__=='__main__':main()
