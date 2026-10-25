"""Export the actual RTL piano comparison, using identical PCM gain."""
import hashlib
import json
import wave
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
def main():
    source=ROOT/'sim/temp/piano_hold_audio_v3_01/piano_decay_ab.txt'
    rows=[tuple(map(int,line.split())) for line in source.read_text().splitlines()]
    assert len(rows)==131076 and all(len(r)==2 for r in rows),len(rows)
    folder=ROOT/'build/piano_short/audio';folder.mkdir(exist_ok=True)
    def write(name,samples):
        data=b''.join((value&0xffffff).to_bytes(3,'little') for value in samples)
        with wave.open(str(folder/name),'wb') as output:
            output.setnchannels(1);output.setsampwidth(3);output.setframerate(48000);output.writeframes(data)
        return hashlib.sha256((folder/name).read_bytes()).hexdigest()
    old=[r[0] for r in rows];new=[r[1] for r in rows]
    artifacts={
        'piano_before.wav':write('piano_before.wav',old),
        'piano_half_duration.wav':write('piano_half_duration.wav',new),
        'piano_before_then_after.wav':write('piano_before_then_after.wav',old+[0]*14400+new[:65540])}
    record={'result':'PASS','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'sample_rate':48000,'bits':24,'gain':'Identical raw mono voice PCM, unity gain; no normalization/time stretch',
        'source':'Actual ModelSim RTL, E4/profile1/velocity3, no effects, old then short piano',
        'artifacts_sha256':artifacts}
    (folder/'verification.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))

if __name__=='__main__':main()
