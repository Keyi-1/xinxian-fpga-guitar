"""Produce real production-RTL listening samples. Never runs synthesis/P&R."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, wave
import numpy as np
from check_karplus_strong import ROOT, run

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

OFF_CAP = [336,168,112,84,112,84,68,56]
ON_CAP = [336,168,68,50,224,76,56,46]
RATIO = 1571089
FS = 48000

def range_report():
    """Cover every quantization bin of the actual reciprocal RTL, not just notes."""
    table = [(int(a),int(b),int(c)) for a,b,c in re.findall(
        r"6'd(\d+): ks_reciprocal=\{25'd(\d+),18'd(\d+)\}",
        (ROOT/'rtl/config/ks_reciprocal.vh').read_text())]
    assert [x[0] for x in table] == list(range(64))
    base = np.array([x[1] for x in table],dtype=np.int64)
    slope = np.array([x[2] for x in table],dtype=np.int64)
    bins = np.arange(16384,dtype=np.int64)
    reciprocal = base[bins>>8]-((slope[bins>>8]*(bins&255))>>8)
    lo = 13138340-(13138340*380+32767)//32768
    hi = 70152776+(70152776*380)//32768
    result = {'sample_rate':FS,'ratio_q20':RATIO,'ratio':RATIO/(1<<20),
        'root_increment_bounds':[lo,hi],
        'coverage':'D3..G5 plus conservative full +/-380/32768 vibrato; every reciprocal quantization bin intersecting every model frequency interval',
        'delay_bsrams_before':4,'delay_bsrams_after':4,'context_bsrams_before':1,'context_bsrams_after':1}
    for mode,caps in [('off',OFF_CAP),('on',ON_CAP)]:
        rows=[];start=0
        for m,cap in enumerate(caps):
            if mode=='off':
                r=[1,2,3,4,3,4,5,6][m];f_lo,f_hi=lo*r,hi*r
            elif m<4:
                r=[1,2,5,7][m];f_lo,f_hi=lo*r,hi*r
            else:
                r=[1,3,4,5][m-4];f_lo=((lo*RATIO)>>20)*r;f_hi=((hi*RATIO)>>20)*r
            assert f_lo>=8421505 and f_hi<=536870912,(mode,m,'frequency guard')
            max_delay=-1;min_delay=10000;count=0
            for exponent in range(23,30):
                shift=31-exponent
                first=((1<<31)+(bins<<17))>>shift
                last=((1<<31)+(bins<<17)+(1<<17)-1)>>shift
                selected=(last>=f_lo)&(first<=f_hi)
                periods=np.clip(reciprocal[selected]>>(exponent-16),2048,130560)
                if len(periods):
                    delays=(periods-128)>>8
                    max_delay=max(max_delay,int(delays.max()));min_delay=min(min_delay,int(delays.min()))
                    count+=len(periods)
            assert count>0 and max_delay<cap-1,(mode,m,max_delay,cap)
            rows.append({'model':m,'base':start,'capacity':cap,'minimum_required_capacity':max_delay+2,
                'maximum_delay_integer':max_delay,'minimum_delay_integer':min_delay,
                'frequency_hz':[f_lo*FS/(1<<32),f_hi*FS/(1<<32)],'reciprocal_bins_checked':count})
            start+=cap
        assert start<=1024
        result[mode]={'words_per_voice':start,'unused_words':1024-start,'models':rows}
    return result

def write_wav(path, samples):
    samples=np.asarray(samples)
    assert np.isfinite(samples).all() and np.abs(samples).max()<32768
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(FS)
        w.writeframes(np.rint(samples).astype('<i2').tobytes())

def spectral_level(x,freq):
    x=x[960:14400];x=x-x.mean();size=262144
    spec=np.abs(np.fft.rfft(x*np.hanning(len(x)),n=size))
    hz=np.fft.rfftfreq(size,1/FS)
    ids=np.where((hz>freq*.985)&(hz<freq*1.015))[0]
    i=ids[np.argmax(spec[ids])]
    y=np.log(np.maximum(spec[i-1:i+2],1e-30))
    delta=.5*(y[0]-y[2])/(y[0]-2*y[1]+y[2])
    return {'frequency_hz':float((i+delta)*FS/size),'fft_magnitude':float(spec[i])}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('name');ap.add_argument('--fifth-gain',type=int,choices=[80,96],default=80);args=ap.parse_args()
    dest=ROOT/'build/ks_fifth'/args.name;dest.mkdir(parents=True,exist_ok=False)
    manifest={}
    for rel in ['rtl/synth/karplus_strong_voice.v','rtl/config/ks_reciprocal.vh','sim/tb/tb_ks_fifth_audition.sv']:
        manifest[rel]=sha(ROOT/rel)
    report=range_report();(dest/'range_report.json').write_text(json.dumps(report,indent=2))
    old=ROOT/'build/ks_fifth/before/source/rtl/synth/karplus_strong_voice.v'
    expected=json.loads((ROOT/'build/ks_fifth/before/source_manifest.json').read_text())
    assert sha(old)==expected['rtl/synth/karplus_strong_voice.v']
    cfg=(ROOT/'rtl/config').as_posix()+'/'
    source=(ROOT/'rtl/synth/karplus_strong_voice.v').read_text().replace('../config/',cfg)
    assert ('(audio_a<<<6)+(audio_a<<<'+str(4 if args.fifth_gain==80 else 5)+')') in source
    (dest/'candidate.v').write_text(source)
    shutil.copy2(Path(__file__),dest/'generator.py')
    names=['karplus_strong_voice','ks_string_lane','ks_period_pipeline']
    baseline=re.sub(r'\b('+'|'.join(names)+r')\b',lambda m:'baseline_'+m[0],old.read_text())
    (dest/'baseline.v').write_text(baseline.replace('../config/',cfg))
    bench=ROOT/'sim/tb/tb_ks_fifth_audition.sv';shutil.copy2(bench,dest/bench.name)
    notes=[('D3',146.8323839587),('A3',220.0),('A4',440.0),('G5',783.9908719635)]
    increments=[round(f*(1<<32)/FS) for _,f in notes]
    (dest/'notes.mem').write_text('\n'.join(f'{x:08x}' for x in increments)+'\n')
    run('vlib.log',['vlib.exe','work'],dest)
    run('compile.log',['vlog.exe','-sv','S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',
        'candidate.v','baseline.v',bench.name],dest)
    log=run('simulation.log',['vsim.exe','-c','work.tb_ks_fifth_audition','-do','run -all; quit -f'],dest)
    assert 'PASS:' in log
    pcm=np.loadtxt(dest/'audition_pcm.txt',dtype=np.int64)
    assert pcm.shape==(288000,9)
    assert np.array_equal(pcm[:,5],pcm[:,3]+pcm[:,4])
    # All gain arithmetic was executed in Verilog. No host synthesis/mixing,
    # segment normalization, filtering, compression or limiting is performed.
    timeline=[];audio=[];compare=[];cursor=0;metrics={}
    for i,(name,_) in enumerate(notes):
        data=pcm[pcm[:,0]==i];assert len(data)==72000
        for column,label in [(6,'root_only'),(7,'fifth_only'),(8,'together')]:
            x=data[:,column]/256.0
            timeline.append({'note':name,'section':label,'start_seconds':cursor/FS,'end_seconds':(cursor+len(x))/FS})
            audio.extend([x,np.zeros(9600)]);cursor+=len(x)+9600
        compare.extend([data[:,2]/256.0,np.zeros(9600),data[:,8]/256.0,np.zeros(19200)])
        f0=increments[i]*FS/(1<<32);fp=((increments[i]*RATIO)>>20)*FS/(1<<32)
        root=spectral_level(data[:,6]/256,f0);fifth=spectral_level(data[:,7]/256,fp)
        mix_root=spectral_level(data[:,8]/256,f0);mix_fifth=spectral_level(data[:,8]/256,fp)
        metrics[name]={'root':root,'fifth':fifth,'target_root_hz':f0,'target_fifth_hz':fp,
            'fifth_pitch_error_cents':float(1200*np.log2(fifth['frequency_hz']/fp)),
            'mix_fifth_to_root_db':float(20*np.log10(mix_fifth['fft_magnitude']/mix_root['fft_magnitude'])),
            'mixed_peak_pcm16':float(np.abs(data[:,8]/256).max()),
            'root_body_rms':float(np.sqrt(np.mean((data[960:14400,6]/256.0)**2))),
            'fifth_body_rms':float(np.sqrt(np.mean((data[960:14400,7]/256.0)**2)))}
        assert abs(metrics[name]['fifth_pitch_error_cents'])<4
    write_wav(dest/'root_fifth_together.wav',np.concatenate(audio))
    write_wav(dest/'off_vs_new_mix.wav',np.concatenate(compare))
    (dest/'timeline.json').write_text(json.dumps(timeline,indent=2))
    for rel,digest in manifest.items():assert sha(ROOT/rel)==digest,rel
    result={'result':'PASS_AWAITING_LISTENING_CONFIRMATION','source_sha256':manifest,
        'reference_kernel_sha256':sha(old),'sample_rate_hz':FS,'rtl_off_exact_samples':288256,
        'rtl_mix_identity_samples':288256,'notes':metrics,'range_report_sha256':sha(dest/'range_report.json'),
        'audition':'Each note: root-only1.5s,0.2s gap,fifth-only1.5s,0.2s gap,together1.5s,0.2s gap. Identical pluck age and seed across the three sections.',
        'gain':f'Production KS gains roots128,48,8,4;fifths{args.fifth_gain},16,8,4; existing main harmony gain(>>1)+(>>2) executed in RTL. WAV conversion /256 only, same fixed gain for all sections.',
        'scope':'Production KS dry output, not full envelope/effects/DAC recording. No FPGA synthesis/P&R/programming performed; original known-good FS retained.',
        'wav_sha256':{p.name:sha(p) for p in dest.glob('*.wav')}}
    (dest/'verification.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({'result':result['result'],'notes':metrics,'wav':str(dest/'root_fifth_together.wav')},indent=2))

if __name__=='__main__':main()
