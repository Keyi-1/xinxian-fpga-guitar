"""Host-compiled C transport tests. No hardware/COM or target firmware execution."""
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import unittest
from game_score_upload import packet, decode_packet, HELLO, LIST, BEGIN, DATA, COMMIT
from p5_score_package import make_package

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/p5_bluetooth/host'


class State(C.Structure):
    _fields_ = [('epoch', C.c_uint32), ('until', C.c_uint32), ('last_byte', C.c_uint32),
                ('session', C.c_uint16), ('retired_session', C.c_uint16)] + [
        (n, C.c_uint8) for n in ['mode', 'live', 'quarantine', 'host_n', 'uart_n',
                               'pending', 'tx_ready', 'reply_ready']] + [
        (n, C.c_uint8 * 32) for n in ['host', 'uart', 'request', 'reply']]


class NativeBridge:
    def __init__(self, mode=2):
        self.state = State()
        self.lib = C.CDLL(str(OUT / 'p5_bridge.dll'))
        self.lib.p5_init(C.byref(self.state), mode)

    def open(self, channel=2, epoch=1, now=0):
        return self.lib.p5_open(C.byref(self.state), channel, C.c_uint32(epoch), C.c_uint32(now))

    def close(self, epoch=1, now=1):
        self.lib.p5_close(C.byref(self.state), C.c_uint32(epoch), C.c_uint32(now))

    def host(self, data, channel=2, epoch=1, now=0):
        raw = C.create_string_buffer(bytes(data))
        return self.lib.p5_host_bytes(C.byref(self.state), channel, C.c_uint32(epoch), raw, C.c_size_t(len(data)), C.c_uint32(now))

    def uart(self, data):
        raw = C.create_string_buffer(bytes(data))
        self.lib.p5_uart_bytes(C.byref(self.state), raw, C.c_size_t(len(data)))

    def take(self, reply=False, channel=2, epoch=1):
        raw = (C.c_uint8 * 32)()
        n = (self.lib.p5_take_reply(C.byref(self.state), channel, C.c_uint32(epoch), raw)
             if reply else self.lib.p5_take_uart(C.byref(self.state), raw))
        return bytes(raw[:n])


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    cmd = ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-shared',
           '-o', str(OUT / 'p5_bridge.dll'), str(ROOT / 'firmware/p5_bridge/p5_bridge.c')]
    result = subprocess.run(cmd, capture_output=True, text=True)
    (OUT / 'compile.log').write_text(result.stdout + result.stderr)
    (OUT / 'build.json').write_text(json.dumps(dict(command=cmd, pid=os.getpid(),
        exit_code=result.returncode, compiler=subprocess.check_output(['gcc', '--version'], text=True).splitlines()[0],
        source_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in (ROOT / 'firmware/p5_bridge').glob('*.?')}), indent=2))
    result.check_returncode()


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        build()

    def test_every_fragment_split_and_ack_split(self):
        req = packet(HELLO, 17, 0)
        ack = packet(HELLO | 128, 17, 0)
        for n in range(1, 33):
            b = NativeBridge(); self.assertEqual(b.open(), 0)
            for i in range(0, 32, n): b.host(req[i:i+n])
            self.assertEqual(b.take(), req)
            for i in range(0, 32, n): b.uart(ack[i:i+n])
            self.assertEqual(b.take(True), ack)

    def test_exclusive_modes_and_epoch(self):
        for mode in [1, 2]:
            b = NativeBridge(mode); self.assertEqual(b.open(3-mode), -1)
            self.assertEqual(b.open(mode, epoch=12), 0)
            self.assertEqual(b.open(mode, epoch=13), -1)
            self.assertEqual(b.host(packet(HELLO, 1, 0), 3-mode, 12), -1)
            self.assertEqual(b.host(packet(HELLO, 1, 0), mode, 11), -1)
            self.assertFalse(b.take())

    def test_disconnect_quarantine_and_stale_callbacks(self):
        b = NativeBridge(); b.open(); req = packet(HELLO, 17, 0)
        b.host(req[:20]); b.close(now=100)
        self.assertEqual(b.host(req[20:]), -1)
        self.assertEqual(b.open(epoch=2, now=6099), -1)
        self.assertEqual(b.open(epoch=2, now=6100), 0)
        self.assertEqual(b.host(req, epoch=1), -1)
        self.assertFalse(b.take())
        b.host(req, epoch=2); b.take(); b.close(epoch=2, now=6200)
        b.uart(packet(129, 17, 0))
        self.assertEqual(b.open(epoch=3, now=12200), 0)
        self.assertEqual(b.host(req, epoch=3), -1)
        self.assertEqual(b.host(packet(LIST, 18, 1), epoch=3), -1)
        b.host(packet(HELLO, 18, 0), epoch=3)
        self.assertEqual(b.take(), packet(HELLO, 18, 0))
        b.uart(packet(129, 17, 0)); self.assertFalse(b.take(True, epoch=3))

    def test_half_frame_timeout_crc_noise_and_resync(self):
        req = packet(HELLO, 25, 0)
        for cut in range(1, 32):
            b = NativeBridge(); b.open(); b.host(req[:cut], now=1)
            b.host(req, now=1001); self.assertEqual(b.take(), req)
        for i in range(32):
            b = NativeBridge(); b.open(); bad = bytearray(req); bad[i] ^= 1
            b.host(bad); self.assertFalse(b.take())
            b.host(b'noise' + req); self.assertEqual(b.take(), req)

    def test_stop_wait_lost_ack_exact_replay_and_no_synthetic_success(self):
        b = NativeBridge(); b.open(); req = packet(HELLO, 17, 0)
        b.host(req); self.assertEqual(b.take(), req)
        self.assertEqual(b.host(packet(LIST, 17, 1)), -2)
        self.assertFalse(b.take(True))
        b.host(req); self.assertEqual(b.take(), req)
        b.uart(packet(129, 17, 1)); self.assertFalse(b.take(True))
        b.uart(packet(129, 18, 0)); self.assertFalse(b.take(True))
        b.uart(packet(129, 17, 0)); self.assertFalse(b.take(True, channel=1))
        self.assertEqual(b.take(True), packet(129, 17, 0))

    def test_coalesced_requests_cannot_pipeline(self):
        b = NativeBridge(); b.open()
        self.assertEqual(b.host(packet(HELLO, 17, 0) + packet(LIST, 17, 1)), -2)
        self.assertEqual(b.take(), packet(HELLO, 17, 0)); self.assertFalse(b.take())

    def test_timer_wraparound(self):
        b = NativeBridge(); b.open(now=0xffffff00); b.close(now=0xffffff10)
        self.assertEqual(b.open(epoch=2, now=0xffffff11), -1)
        self.assertEqual(b.open(epoch=2, now=(0xffffff10 + 6000) & 0xffffffff), 0)

    def test_fragment_duplicates_are_not_forwarded_as_valid_frames(self):
        req = packet(HELLO, 17, 0)
        b = NativeBridge(); b.open()
        b.host(req[:20]); b.host(req[:20]); b.host(req[20:])
        self.assertEqual(b.take(), req)
        # A complete request replay is allowed for FPGA deduplication.
        b.host(req); self.assertEqual(b.take(), req)
        b.uart(packet(129, 17, 0)); self.assertEqual(b.take(True), packet(129, 17, 0))
        b.uart(packet(129, 17, 0)); self.assertFalse(b.take(True))

    def test_real_score_package_and_old_score_unchanged(self):
        # Generate from the current formal score compiler output supplied by runner.
        binary = ROOT/'build/p5_bluetooth/example/qing_ge.bin'
        metadata = binary.with_suffix('.json')
        p = make_package(binary, metadata, '情歌')
        self.assertEqual(p['event_count'], 212)
        self.assertEqual(p['duration_samples'], 7296000)
        import base64
        self.assertEqual(base64.b64decode(p['payload_base64']), binary.read_bytes())
        for title in ['', 'x' * 81]:
            with self.assertRaises(ValueError): make_package(binary, metadata, title)


if __name__ == '__main__': unittest.main()
