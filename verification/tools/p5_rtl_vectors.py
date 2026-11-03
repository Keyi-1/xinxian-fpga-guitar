"""Generate UART stimuli THROUGH the host-compiled C BLE transport core."""
from pathlib import Path
import json
import struct
from test_p5_bridge import NativeBridge, ROOT
from game_score_upload import packet


def generate(output):
    output.mkdir(parents=True, exist_ok=False)
    one = struct.pack('<IIBBBBHH', 0, 12000, 79, 0, 2, 0, 0xbeef, 0)
    two = struct.pack('<IIBBBBHH', 24000, 12000, 50, 1, 2, 0, 0x1234, 0)
    begin = lambda count, crc: struct.pack('<BBHIII', 4, 1, count, 48000, crc, 0)
    rows = [(1, 0, b'', 0, 1), (3, 1, begin(2, 0x62885540), 0, 1),
            (4, 2, one, 0, 1), (4, 2, one, 0, 1), (4, 3, two, 0, 1),
            (5, 4, b'', 0, 1), (5, 4, b'', 0, 1), (2, 5, b'\4', 0, 1),
            (3, 6, begin(1345, 0), 2, 1), (3, 6, begin(1, 0), 0, 1),
            (4, 7, one, 0, 1), (5, 8, b'', 4, 1), (2, 8, b'\4', 0, 1),
            (3, 9, begin(1, 0), 1, 0), (3, 9, begin(1, 0), 0, 1),
            (6, 10, b'', 0, 1), (2, 11, b'\4', 0, 1)]
    bridge = NativeBridge(); assert bridge.open() == 0
    wires = []
    for i, (op, seq, payload, code, allowed) in enumerate(rows):
        wire = packet(op, 17, seq, payload)
        # Alternate MTU23 fragments and byte-by-byte writes; all are C inputs.
        chunk = 20 if i % 2 else 1
        for start in range(0, 32, chunk):
            assert bridge.host(wire[start:start+chunk], now=i*10) == 0
        forwarded = bridge.take(); assert forwarded == wire; wires.append(forwarded)
        # Stimulus preparation only. Actual RTL responses replace these in replay.
        bridge.uart(packet(op | 128, 17, seq, bytes([code])))
        assert bridge.take(True)
    (output/'requests.hex').write_text(''.join(f'{v:02x}\n' for w in wires for v in w))
    (output/'expected.hex').write_text(''.join(f'{r[3]:02x}\n' for r in rows))
    (output/'allowed.hex').write_text(''.join(f'{r[4]:02x}\n' for r in rows))
    (output/'vectors.json').write_text(json.dumps(dict(frames=len(rows),
        scope='Host C transport forwarded stimuli, NOT hardware/BLE acceptance',
        rows=[dict(op=r[0],sequence=r[1],status=r[3],allowed=r[4]) for r in rows]),indent=2))


def check_responses(output):
    from game_score_upload import decode_packet
    requests = bytes.fromhex((output/'requests.hex').read_text())
    replies = bytes.fromhex((output/'responses.hex').read_text())
    expected = bytes.fromhex((output/'expected.hex').read_text())
    assert len(requests) == len(replies) == len(expected)*32
    bridge = NativeBridge(); assert bridge.open() == 0
    for i, code in enumerate(expected):
        req, ack = requests[i*32:i*32+32], replies[i*32:i*32+32]
        bridge.host(req[:20]); bridge.host(req[20:]); assert bridge.take() == req
        bridge.uart(ack[:11]); bridge.uart(ack[11:]); returned = bridge.take(True)
        assert returned == ack
        op, session, seq, body = decode_packet(returned)
        a, b, c, _ = decode_packet(req)
        assert (op, session, seq, body[0]) == (a | 128, b, c, code)
    print(f'PASS: {len(expected)} actual RTL UART responses returned unchanged through C core')


if __name__ == '__main__':
    import sys
    directory = Path(sys.argv[2])
    if sys.argv[1] == 'generate': generate(directory)
    elif sys.argv[1] == 'check': check_responses(directory)
    else: raise ValueError('generate/check required')
