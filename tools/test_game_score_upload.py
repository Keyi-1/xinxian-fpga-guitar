import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from game_score_upload import *
from game_score_v2 import Event,payload_info
from upload_game_score import load_score


class Transport:
    """Small transport fault injector; no serial port or FPGA side effects."""
    def __init__(self,drop=(),partial=7,noise=False,reject=None):
        self.partial=partial;self.pending=bytearray();self.replies=bytearray()
        self.frames=[];self.drop=set(drop);self.cache={};self.executed=[];self.noise=noise;self.reject=reject
    def write(self,data):
        part=bytes(data[:self.partial]);self.pending.extend(part)
        if len(self.pending)>=32:
            raw=bytes(self.pending[:32]);del self.pending[:32]
            op,session,seq,payload=decode_packet(raw);self.frames.append(raw)
            key=(session,seq)
            if key not in self.cache:
                self.executed.append(op)
                body=bytearray(16)
                if op==HELLO:body[1:]=struct.pack('<BBBHHBBIH',2,5,32,703,2048,50,79,48000,1)
                if op==LIST:
                    d=(100|(703<<32)|(2<<43)|(48000<<55)|(1<<87))
                    body[1:13]=d.to_bytes(12,'little');body[13]=payload[0];body[14]=7
                if self.reject and op==self.reject:body[0]=1
                self.cache[key]=packet(op|0x80,session,seq,body)
            if len(self.frames) not in self.drop:
                if self.noise:self.replies.extend(b'junkXGXG3!'+b'\0'*28)
                self.replies.extend(self.cache[key])
        return len(part)
    def read(self,n):
        data=bytes(self.replies[:min(n,5)]);del self.replies[:len(data)];return data


class UploadTests(unittest.TestCase):
    def test_golden_and_round_trip(self):
        self.assertEqual(zlib.crc32(b'123456789'),0xcbf43926)
        self.assertEqual(packet(HELLO,17,0).hex(),'584733210301110000000000000000000000000000000000000000005da773de')
        for op in range(1,8):
            for seq in [0,1,65535]:
                for payload in [b'',bytes(range(16)),b'XG3!'*4]:
                    self.assertEqual(decode_packet(packet(op,19,seq,payload)),(op,19,seq,payload.ljust(16,b'\0')))
    def test_corruption_rejected(self):
        wire=packet(DATA,99,12,bytes(range(16)))
        for i in range(32):
            damaged=bytearray(wire);damaged[i]^=1
            with self.assertRaises(ValueError):decode_packet(damaged)
        for n in range(32):
            with self.assertRaises(ValueError):decode_packet(wire[:n])
    def test_partial_writes_noise_and_lost_ack(self):
        t=Transport(drop=[1,3],noise=True)
        c=Client(t,session=17,timeout=0.002)
        self.assertEqual(c.hello()['midi_max'],79)
        slot=c.list_slot(4)
        self.assertTrue(slot['imported']);self.assertEqual(slot['duration_samples'],48000)
        self.assertEqual(t.frames[0],t.frames[1]);self.assertEqual(t.frames[2],t.frames[3])
        self.assertEqual(t.executed,[HELLO,LIST])
    def test_upload_and_lost_commit_ack(self):
        t=Transport(drop=[5]);c=Client(t,session=8,timeout=0.002);c.hello()
        events=[Event(0,12000,79,0,group=0xbeef),Event(24000,12000,50,1,group=0x1234)]
        self.assertEqual(payload_info(events)[1],'62885540')
        result=c.upload(4,events,48000,1)
        self.assertEqual(result['event_count'],2)
        self.assertEqual(t.executed,[HELLO,BEGIN,DATA,DATA,COMMIT,LIST])
        self.assertEqual(t.frames[4],t.frames[5])
    def test_explicit_nack_does_not_advance(self):
        t=Transport(reject=BEGIN);c=Client(t,session=9);c.hello()
        with self.assertRaisesRegex(RuntimeError,'BUSY'):c.request(BEGIN)
        self.assertEqual(c.sequence,1)
    def test_lost_commit_is_unknown(self):
        t=Transport(drop=[4,5,6,7]);c=Client(t,session=5,timeout=0.001);c.hello()
        with self.assertRaisesRegex(TimeoutError,'result unknown'):
            c.upload(0,[Event(0,12000,60,0)],48000,0)
        self.assertNotIn(ABORT,t.executed)
    def test_validate_before_device_write(self):
        t=Transport();c=Client(t,session=5)
        with self.assertRaises(ValueError):c.upload(0,[Event(0,12000,80,0)],48000,0)
        self.assertFalse(t.frames)
    def test_compiled_pair(self):
        temp_root=Path(__file__).resolve().parent.parent/'sim/temp'
        temp_root.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='p3_upload_',dir=temp_root) as temp:
            root=Path(temp);events=[Event(0,12000,79,0)];raw,crc=payload_info(events)
            assert root.resolve().is_relative_to(temp_root.resolve())
            b=root/'test.bin';j=root/'test.json';b.write_bytes(raw)
            metadata=dict(format_version=2,event_bytes=16,sample_rate_hz=48000,event_count=1,
                          duration_samples=48000,recommended_timbre=1,crc32=crc)
            j.write_text(json.dumps(metadata));self.assertEqual(load_score(b,j)[0],events)
            b.write_bytes(bytes(len(raw)))
            with self.assertRaises(ValueError):load_score(b,j)


if __name__=='__main__':unittest.main()
