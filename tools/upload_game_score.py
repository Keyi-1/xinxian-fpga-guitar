"""Explicit user-invoked CLI. Never programs FPGA or updates debugger firmware."""
import argparse
import json
from pathlib import Path
import zlib
from game_score_upload import Client
from game_score_v2 import from_binary,validate


def load_score(binary,metadata):
    raw=binary.read_bytes();info=json.loads(metadata.read_text(encoding='utf-8-sig'))
    if (info.get('format_version'),info.get('event_bytes'),info.get('sample_rate_hz'))!=(2,16,48000):
        raise ValueError('Expected compiled v2/16-byte/48kHz score')
    events=from_binary(raw,profile='game_extended')
    duration=info['duration_samples'];timbre=info['recommended_timbre']
    validate(events,duration,profile='game_extended')
    if len(events)!=info['event_count'] or f'{zlib.crc32(raw):08x}'!=info['crc32'].lower():
        raise ValueError('BIN/JSON count or CRC mismatch')
    if not 0<=timbre<3:raise ValueError('Unsupported timbre')
    return events,duration,timbre


def main():
    parser=argparse.ArgumentParser(description='Import v2 note events over DEBUG-USB2 UART,115200 8N1; keep FPGA powered after unplugging USB')
    parser.add_argument('--port',required=True,help='Explicit Windows COM port, e.g. COM5')
    parser.add_argument('--list',action='store_true')
    parser.add_argument('--slot',type=int,choices=range(1,6),help='Visible slot 1..5; replaces its runtime mapping only')
    parser.add_argument('--bin',type=Path);parser.add_argument('--metadata',type=Path)
    args=parser.parse_args()
    if not args.list and (args.slot is None or args.bin is None or args.metadata is None):
        parser.error('Upload requires --slot, --bin and --metadata')
    score=None if args.list else load_score(args.bin,args.metadata)
    import serial
    with serial.Serial(port=None,baudrate=115200,timeout=0.1,write_timeout=2,rtscts=False,dsrdtr=False) as stream:
        stream.dtr=False;stream.rts=False;stream.port=args.port;stream.open()
        stream.reset_input_buffer();client=Client(stream);caps=client.hello()
        print(json.dumps(caps,ensure_ascii=False))
        if args.list:
            for slot in range(5):print(json.dumps(client.list_slot(slot),ensure_ascii=False))
        else:
            events,duration,timbre=score
            def report(n,total):
                if n==total or n%64==0:print(f'{n}/{total} records acknowledged',flush=True)
            result=client.upload(args.slot-1,events,duration,timbre,report)
            if not result['imported'] or result['event_count']!=len(events):
                raise RuntimeError('Committed directory verification failed')
            print('COMMIT acknowledged; runtime slot:',json.dumps(result))
            print('Keep board powered. Dynamic songs are lost after power-off/reconfiguration/reset.')


if __name__=='__main__':main()
