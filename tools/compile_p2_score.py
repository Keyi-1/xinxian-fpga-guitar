"""Compile a user-supplied beat/sample CSV to checked P2 note events."""
import argparse
import hashlib
import json
from pathlib import Path
from game_score_v2 import read_csv, payload_info, SAMPLE_RATE


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('csv', type=Path)
    parser.add_argument('output_prefix', type=Path)
    parser.add_argument('--bpm', type=int, default=60)
    parser.add_argument('--timbre', type=int, choices=[0,1,2], default=1)
    args = parser.parse_args()
    events = read_csv(args.csv, args.bpm)
    outputs = [args.output_prefix.with_suffix(s) for s in ['.mem', '.bin', '.json']]
    if any(p.exists() for p in outputs):
        raise SystemExit('Choose a new output prefix; existing files are preserved')
    payload, crc = payload_info(events)
    outputs[0].parent.mkdir(parents=True, exist_ok=True)
    outputs[0].write_text(''.join(f'{e.word():024x}\n' for e in events), encoding='ascii')
    outputs[1].write_bytes(payload)
    outputs[2].write_text(json.dumps(dict(format_version=2, event_bytes=16,
        sample_rate_hz=SAMPLE_RATE, event_count=len(events),
        duration_samples=max(e.onset+e.duration for e in events), bpm=args.bpm,
        recommended_timbre=args.timbre, crc32=crc,
        source_csv_sha256=hashlib.sha256(args.csv.read_bytes()).hexdigest()),indent=2)+'\n')
    print(f'PASS: {len(events)} events, {args.bpm} BPM, CRC32 {crc}; files only, no device access')


if __name__ == '__main__':
    main()
