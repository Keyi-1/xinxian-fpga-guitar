"""XG3 reliable note-event transport; importing this module never opens a port."""
from dataclasses import dataclass
import secrets
import struct
import time
import zlib

MAGIC=b'XG3!'
VERSION=3
PACKET_SIZE=32
HELLO, LIST, BEGIN, DATA, COMMIT, ABORT, STATUS=range(1,8)
ERRORS={1:'BUSY',2:'NO_SPACE',3:'BAD_LENGTH',4:'SONG_CRC',5:'ORDER_OR_LANE_CONFLICT',
        6:'RANGE_OR_METADATA',7:'DENSITY',8:'TIMEOUT',9:'NO_TRANSACTION',
        10:'BAD_COMMAND',11:'BAD_FORMAT',12:'PACKET_CRC',13:'SESSION_OR_SEQUENCE'}


def packet(op, session, sequence, payload=b''):
    if not 0<session<65536 or not 0<=sequence<65536 or len(payload)>16:
        raise ValueError('Invalid session, sequence or payload length')
    header=struct.pack('<BBHH16sH',VERSION,op,session,sequence,payload,0)
    return MAGIC+header+struct.pack('<I',zlib.crc32(header))


def decode_packet(data):
    if len(data)!=32 or data[:4]!=MAGIC:
        raise ValueError('Not an XG3 packet')
    version,op,session,sequence,payload,reserved=struct.unpack('<BBHH16sH',data[4:28])
    if version!=3 or reserved or not session or zlib.crc32(data[4:28])!=struct.unpack('<I',data[28:])[0]:
        raise ValueError('Bad XG3 version, reserved field or CRC')
    return op,session,sequence,payload


def descriptor(data):
    if len(data)!=12:
        raise ValueError('Descriptor must be 96 bits')
    word=int.from_bytes(data,'little')
    return dict(progress_step=word&0xffffffff,base=word>>32&2047,
                event_count=word>>43&4095,duration_samples=word>>55&0xffffffff,
                recommended_timbre=word>>87&3)


@dataclass
class Client:
    stream: object
    session: int=0
    sequence: int=0
    timeout: float=1.0
    attempts: int=4

    def __post_init__(self):
        self.session=self.session or secrets.randbelow(65535)+1
        self.buffer=bytearray()

    def _read_reply(self,op):
        deadline=time.monotonic()+self.timeout
        while time.monotonic()<deadline:
            start=self.buffer.find(MAGIC)
            if start<0:
                self.buffer[:]=self.buffer[-3:]
            elif start:
                del self.buffer[:start]
            if self.buffer.startswith(MAGIC) and len(self.buffer)>=32:
                candidate=bytes(self.buffer[:32])
                try:
                    rop,session,seq,payload=decode_packet(candidate)
                except ValueError:
                    del self.buffer[0]
                    continue
                del self.buffer[:32]
                if (rop,session,seq)==(op|0x80,self.session,self.sequence):
                    return payload
                continue
            block=self.stream.read(32)
            if block:self.buffer.extend(block)
        raise TimeoutError('No valid matching ACK')

    def request(self,op,payload=b''):
        wire=packet(op,self.session,self.sequence,payload)
        for attempt in range(self.attempts):
            pending=memoryview(wire)
            while pending:
                written=self.stream.write(pending)
                if not written:raise TimeoutError('Serial write did not advance')
                pending=pending[written:]
            try:reply=self._read_reply(op)
            except TimeoutError:
                if attempt+1==self.attempts:raise
                continue
            if reply[0]==12 and attempt+1<self.attempts:
                continue
            if reply[0]:
                raise RuntimeError(f'FPGA rejected command {op}: {ERRORS.get(reply[0],reply[0])}')
            self.sequence=(self.sequence+1)&65535
            return reply
        raise TimeoutError('ACK retry limit reached')

    def hello(self):
        if self.sequence:
            raise ValueError('HELLO must start a new client session')
        reply=self.request(HELLO)
        version,slots,size,reserved,capacity,low,high,rate,features=struct.unpack('<BBBHHBBIH',reply[1:])
        if (version,slots,size,rate)!=(2,5,32,48000):
            raise ValueError('Incompatible FPGA capabilities')
        return dict(event_format=version,slots=slots,packet_bytes=size,
                    reserved_records=reserved,capacity=capacity,midi_min=low,midi_max=high,
                    sample_rate_hz=rate,features=features)

    def list_slot(self,slot):
        reply=self.request(LIST,bytes([slot]))
        result=descriptor(reply[1:13]);flags=reply[14]
        result.update(slot=reply[13],valid=bool(flags&1),playable=bool(flags&2),
                      imported=bool(flags&4),test_only=bool(flags&8))
        return result

    def upload(self,slot,events,duration,timbre,progress=None):
        from game_score_v2 import validate,payload_info
        validate(events,duration,profile='game_extended')
        if not 0<=slot<5 or not 0<=timbre<3:
            raise ValueError('Invalid slot/timbre')
        payload,crc=payload_info(events)
        self.request(BEGIN,struct.pack('<BBHIII',slot,timbre,len(events),duration,int(crc,16),0))
        # If DATA fails, tentative space remains unpublished and times out;
        # an explicit ABORT is attempted. A lost COMMIT ACK is ambiguous and
        # must never be reported as a definitive failed/rolled-back commit.
        try:
            for i,event in enumerate(events):
                self.request(DATA,event.binary())
                if progress:progress(i+1,len(events))
        except Exception:
            try:self.request(ABORT)
            except Exception:pass
            raise
        try:self.request(COMMIT)
        except TimeoutError as exc:
            raise TimeoutError('COMMIT result unknown: ACK retries exhausted; do not assume rollback. Query/reconnect before replacing the song.') from exc
        return self.list_slot(slot)
