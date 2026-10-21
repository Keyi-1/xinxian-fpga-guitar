"""One bounded JSON file for native phone pickers; no port/network access."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
from upload_game_score import load_score
from game_score_v2 import payload_info

MAX_FILE_BYTES = 65536


def make_package(binary, metadata, title):
    if not isinstance(title, str) or not 1 <= len(title) <= 80:
        raise ValueError('Title must have 1..80 characters')
    events, duration, timbre = load_score(binary, metadata)
    raw, crc = payload_info(events)
    if len(events) > 1345:
        raise ValueError('P5 import space is at most 1345 events shared by five slots')
    return dict(package_format='xinxian-score', package_version=1, title=title,
                format_version=2, event_bytes=16, sample_rate_hz=48000,
                event_count=len(events), duration_samples=duration,
                recommended_timbre=timbre, crc32=crc,
                payload_sha256=hashlib.sha256(raw).hexdigest(),
                payload_base64=base64.b64encode(raw).decode('ascii'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--title', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = make_package(args.bin, args.metadata, args.title)
    encoded = (json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    if len(encoded) > MAX_FILE_BYTES:
        raise ValueError('Package exceeds 64 KiB')
    # No accidental replacement of a user's score package.
    with args.out.open('xb') as stream:
        stream.write(encoded)
    print(f'{args.out}: {result["event_count"]} events, CRC32 {result["crc32"]}')


if __name__ == '__main__':
    main()
