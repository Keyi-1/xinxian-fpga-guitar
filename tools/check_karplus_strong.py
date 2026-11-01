"""Run production RTL in ModelSim and measure its audio, never a software substitute."""
from pathlib import Path
import subprocess, sys, json, hashlib, wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
BIN=Path('S:/BaiduNetdiskDownload/modelsim/win64')

def run(name, args, cwd):
    result=subprocess.run([str(BIN/args[0]),*args[1:]],cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (cwd/name).write_text(result.stdout)
    if result.returncode or '** Error' in result.stdout or '** Fatal' in result.stdout:
        raise RuntimeError(result.stdout[-6000:])
    return result.stdout

def main():
    dest=ROOT/'build/karplus_strong'/sys.argv[1]
    dest.mkdir(parents=True,exist_ok=False)
    source=(ROOT/'rtl/synth/karplus_strong_voice.v').read_text().replace('../config/ks_reciprocal.vh',(ROOT/'rtl/config/ks_reciprocal.vh').as_posix())
    (dest/'karplus_strong_voice.v').write_text(source)
    run('vlib.log',['vlib.exe','work'],dest)
    run('compile.log',['vlog.exe','-sv','S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v','karplus_strong_voice.v',str(ROOT/'sim/tb/tb_karplus_strong.sv')],dest)
    log=run('simulation.log',['vsim.exe','-c','work.tb_karplus_strong','-do','run -all; quit -f'],dest)
    assert 'PASS:' in log
    data=np.loadtxt(dest/'ks_pcm.txt')/256
    assert data.shape==(144000,4) and np.isfinite(data).all()
    def rms(a): return float(np.sqrt(np.mean(a*a)))
    results={}
    for v,freq in [(0,146.8324),(1,146.8324),(2,440.278),(3,784.0)]:
        x=data[1000:16000,v];x=x-x.mean();size=262144
        spec=abs(np.fft.rfft(x*np.hanning(len(x)),n=size));hz=np.fft.rfftfreq(size,1/48000)
        ids=np.where((hz>freq*.97)&(hz<freq*1.03))[0];i=ids[np.argmax(spec[ids])]
        y=np.log(spec[i-1:i+2]);delta=.5*(y[0]-y[2])/(y[0]-2*y[1]+y[2]);estimate=(i+delta)*48000/size
        cents=float(1200*np.log2(estimate/freq))
        assert abs(cents)<4,(v,cents)
        results[str(v)]={'frequency_hz':float(estimate),'pitch_error_cents':cents,'peak':float(abs(data[:,v]).max()),'early_rms':rms(data[4000:16000,v]),'late_rms':rms(data[48000:65000,v])}
        assert results[str(v)]['peak']<32768
    assert rms(data[48000:65000,1])>rms(data[48000:65000,0])*1.1
    # Stereo normal/sustain and simultaneous harmony from actual RTL samples.
    for name,channels in [('normal_vs_sustain',(0,1)),('harmony_and_slide',(2,3))]:
        a=np.clip(data[:,channels],-32768,32767).astype('<i2')
        with wave.open(str(dest/(name+'.wav')),'wb') as w:
            w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(a.tobytes())
    results['source_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'rtl/synth/karplus_strong_voice.v',ROOT/'rtl/config/ks_reciprocal.vh',ROOT/'sim/tb/tb_karplus_strong.sv']}
    (dest/'verification.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results,indent=2))

if __name__=='__main__':main()
