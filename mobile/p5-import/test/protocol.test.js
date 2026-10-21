import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { Client, Frames, OP, packet, decode, crc32, view, parsePackage, slotInfo,
  toBase64, fromBase64, UnknownCommit } from '../src/protocol.js';

const sha256 = async b => createHash('sha256').update(b).digest('hex');
function score(events = [[0, 12000, 79, 0], [24000, 12000, 50, 1]]) {
  const raw = new Uint8Array(events.length * 16), d = view(raw);
  events.forEach(([onset, duration, midi, lane], n) => {
    const i = n * 16; d.setUint32(i, onset, true); d.setUint32(i + 4, duration, true);
    raw[i + 8] = midi; raw[i + 9] = lane; raw[i + 10] = 2; d.setUint16(i + 12, [0xbeef, 0x1234][n] || n, true);
  });
  return { package_format: 'xinxian-score', package_version: 1, title: '测试谱', format_version: 2,
    event_bytes: 16, sample_rate_hz: 48000, event_count: events.length, duration_samples: 48000,
    recommended_timbre: 1, crc32: crc32(raw).toString(16).padStart(8, '0'),
    payload_sha256: createHash('sha256').update(raw).digest('hex'), payload_base64: toBase64(raw), raw };
}
// Explicit PC model. Actual FPGA validation is tested separately by RTL replay.
class ModelLink {
  constructor() {
    this.parser = new Frames(); this.slots = Array(5).fill(null); this.staged = null;
    this.cache = null; this.next = 0; this.session = 0; this.frames = []; this.executed = [];
    this.drop = () => false; this.bad = null; this.busy = false; this.space = false; this.delay = 0;
  }
  async write(bytes) {
    assert.ok(bytes.length <= 20);
    for (const f of this.parser.push(bytes)) {
      this.frames.push(f);
      const wire = packet(f.op, f.session, f.seq, f.payload), key = toBase64(wire);
      let p = new Uint8Array(16), execute = false;
      if (key === this.cache?.key) p = this.cache.p;
      else if (f.op === 1 && f.seq === 0 && !this.staged) {
        this.session = f.session; this.next = 0; execute = true;
      } else if (f.session !== this.session || f.seq !== this.next) p[0] = 13;
      else execute = true;
      if (execute) {
        this.executed.push(f.op);
        const d = view(p);
        if (f.op === OP.HELLO) {
          p.set([2, 5, 32], 1); d.setUint16(4, 703, true); d.setUint16(6, 2048, true);
          p[8] = 50; p[9] = 79; d.setUint32(10, 48000, true); p[14] = 1;
        } else if (f.op === OP.LIST) {
          const slot = f.payload[0], s = this.slots[slot]; p[13] = slot;
          if (s) {
            const w = 100n | (703n << 32n) | (BigInt(s.count) << 43n) | (48000n << 55n) | (1n << 87n);
            for (let i = 0; i < 12; i++) p[i + 1] = Number(w >> BigInt(i * 8) & 255n);
            p[14] = 7;
          }
        } else if (f.op === OP.BEGIN) {
          if (this.busy) p[0] = 1;
          else if (this.space) p[0] = 2;
          else this.staged = { slot: f.payload[0], count: view(f.payload).getUint16(2, true),
            crc: view(f.payload).getUint32(8, true), bytes: [] };
        } else if (f.op === OP.DATA) {
          if (!this.staged) p[0] = 9;
          else this.staged.bytes.push(...f.payload);
        } else if (f.op === OP.COMMIT) {
          if (!this.staged) p[0] = 9;
          else if (this.staged.bytes.length !== this.staged.count * 16) p[0] = 3;
          else if (crc32(this.staged.bytes) !== this.staged.crc || this.bad === 'readback') p[0] = 4;
          else this.slots[this.staged.slot] = this.staged;
          this.staged = null;
        }
        if (!p[0]) { this.next++; this.cache = { key, p }; }
      }
      if (!this.drop(f, this.frames.length)) {
        const reply = packet(f.op | 128, f.session, f.seq, p);
        const deliver = () => { this.onBytes(reply.slice(0, 7)); this.onBytes(reply.slice(7)); };
        if (this.delay) setTimeout(deliver, this.delay); else deliver();
      }
    }
  }
}
const makeClient = link => new Client(link, 17, { timeout: 12, attempts: 3 });

test('Python golden frame/CRC and all bit corruptions', () => {
  assert.equal(crc32(new TextEncoder().encode('123456789')), 0xcbf43926);
  const b = packet(1, 17, 0);
  assert.equal(Buffer.from(b).toString('hex'), '584733210301110000000000000000000000000000000000000000005da773de');
  for (let i = 0; i < 32; i++) { const x = b.slice(); x[i] ^= 1; assert.throws(() => decode(x)); }
  for (let n = 0; n < 32; n++) assert.throws(() => decode(b.slice(0, n)));
});
test('bounded parser accepts every split, coalescing and rejects noise/CRC', () => {
  const b = packet(1, 17, 0);
  for (let n = 1; n < 32; n++) {
    const p = new Frames(); assert.deepEqual(p.push(b.slice(0, n)), []);
    assert.equal(p.push(b.slice(n)).length, 1);
  }
  const p = new Frames(), noise = Uint8Array.from([...b.slice(0, 18), ...b, ...b]);
  assert.equal(p.push(noise).length, 2); assert.ok(p.bytes.length <= 31);
});
test('base64 canonical checks and binary roundtrip', () => {
  for (let n = 0; n < 130; n++) { const b = Uint8Array.from({ length: n }, (_, i) => i); assert.deepEqual(fromBase64(toBase64(b)), b); }
  for (const s of ['A', 'ab==', '====', 'aaa', 'a\n==']) assert.throws(() => fromBase64(s));
});
test('current formal Qing Ge package matches Python bytes and metadata', async () => {
  const text = await readFile(new URL('../../../build/p5_bluetooth/example/qing_ge.xgscore', import.meta.url), 'utf8');
  const p = await parsePackage(text, sha256); assert.equal(p.event_count, 212); assert.equal(p.duration_samples, 7296000);
  assert.equal(p.crc32, 'c3451bbc'); // Current accepted 10/18-bar rhythm; never old upload example.
});
test('package bounds/hash/CRC/metadata strictness', async () => {
  const p = score(); assert.equal(crc32(p.raw), 0x62885540); await parsePackage(JSON.stringify(p), sha256);
  for (const patch of [{ event_count: 0 }, { event_count: 1346 }, { event_count: '2' }, { duration_samples: 1 },
    { recommended_timbre: 3 }, { title: '' }, { payload_sha256: '0'.repeat(64) }, { crc32: '00000000' }])
    await assert.rejects(parsePackage(JSON.stringify({ ...p, ...patch }), sha256));
  await assert.rejects(parsePackage(' '.repeat(65537), sha256));
});
test('package event ranges, ordering, lane conflicts, spacing and density', async () => {
  for (const events of [ [[0, 12000, 80, 0]], [[0, 0, 60, 0]], [[0, 12000, 60, 4]],
    [[24000, 12000, 60, 0], [0, 12000, 60, 1]], [[0, 24000, 60, 0], [12000, 12000, 60, 0]],
    [[0, 100, 60, 0], [11999, 100, 60, 0]] ]) await assert.rejects(parsePackage(JSON.stringify(score(events)), sha256));
  const p = score(Array.from({ length: 9 }, (_, i) => [i * 12000, 100, 60, 0])); p.duration_samples = 120000;
  await assert.rejects(parsePackage(JSON.stringify(p), sha256), /密度/);
});
test('five slots, successful commit, progress and durable marker order', async () => {
  const link = new ModelLink(), c = makeClient(link), progress = []; await c.hello();
  const result = await c.upload(1, score(), () => assert.fail('empty slot confirmation'),
    (n, total) => progress.push([n, total]), async () => { assert.ok(!link.executed.includes(5)); });
  assert.ok(result.committed); assert.equal(result.slots.length, 5); assert.equal(result.slots[1].count, 2);
  assert.deepEqual(progress, [[1, 2], [2, 2]]); assert.equal(link.executed.filter(op => op === 5).length, 1);
});
test('lost ACK retries exact request; duplicate COMMIT executes once', async () => {
  const link = new ModelLink(); let lost = false;
  link.drop = f => f.op === 5 && !lost ? (lost = true) : false;
  const c = makeClient(link); await c.hello(); assert.ok((await c.upload(4, score(), () => true)).committed);
  assert.equal(link.frames.filter(f => f.op === 5).length, 2); assert.equal(link.executed.filter(op => op === 5).length, 1);
});
test('all final ACKs lost means unknown; no ABORT or assumed rollback', async () => {
  const link = new ModelLink(); link.drop = f => f.op === 5; const c = makeClient(link); await c.hello();
  await assert.rejects(c.upload(0, score(), () => true), UnknownCommit);
  assert.ok(link.slots[0]); assert.equal(link.executed.filter(op => op === 5).length, 1);
  assert.ok(!link.frames.some(f => f.op === 6));
});
test('disconnect during COMMIT means unknown, old session ACK ignored on reconnect', async () => {
  const link = new ModelLink(); link.drop = f => { if (f.op === 5) link.onClose(); return f.op === 5; };
  const c = makeClient(link); await c.hello(); await assert.rejects(c.upload(0, score(), () => true), UnknownCommit);
  const fresh = new ModelLink(), next = new Client(fresh, 18, { timeout: 12 });
  fresh.onBytes(packet(129, 17, 0)); await next.hello(); assert.equal(next.seq, 1);
});
test('BUSY and NO_SPACE preserve replacement; explicit confirmation required', async () => {
  for (const property of ['busy', 'space']) {
    const link = new ModelLink(), old = { count: 99 }; link.slots[0] = old; link[property] = true;
    const c = makeClient(link); await c.hello(); let confirms = 0;
    await assert.rejects(c.upload(0, score(), () => { confirms++; return true; }), property === 'busy' ? /BUSY/ : /NO_SPACE/);
    assert.equal(confirms, 1); assert.equal(link.slots[0], old); assert.ok(!link.frames.some(f => f.op === 4));
  }
  const link = new ModelLink(); link.slots[0] = { count: 3 }; const c = makeClient(link); await c.hello();
  await assert.rejects(c.upload(0, score(), () => false), /取消/); assert.ok(!link.frames.some(f => f.op === 3));
});
test('readback CRC rejection preserves old slot and never reports success', async () => {
  const link = new ModelLink(), old = { count: 99 }; link.slots[0] = old; link.bad = 'readback';
  const c = makeClient(link); await c.hello(); await assert.rejects(c.upload(0, score(), () => true), /SONG_CRC/);
  assert.equal(link.slots[0], old);
});
test('COMMIT confirmed with later directory failure remains success', async () => {
  const link = new ModelLink(); link.drop = f => f.op === 2 && link.slots[0];
  const c = makeClient(link); await c.hello(); const result = await c.upload(0, score(), () => true);
  assert.ok(result.committed); assert.equal(result.slots, null); assert.ok(result.refreshError);
});
test('reset after COMMIT ACK warns when volatile directory no longer matches', async () => {
  const link = new ModelLink();
  link.drop = f => { if (f.op === 5) link.slots[0] = null; return false; };
  const c = makeClient(link); await c.hello(); const result = await c.upload(0, score(), () => true);
  assert.ok(result.committed); assert.ok(result.catalogWarning);
});
test('write rejection during COMMIT is unknown and never retries a half write', async () => {
  const link = new ModelLink(), write = link.write.bind(link);
  link.write = bytes => { if (bytes[5] === 5) throw new Error('write disconnected'); return write(bytes); };
  const c = makeClient(link); await c.hello(); await assert.rejects(c.upload(0, score(), () => true), UnknownCommit);
  assert.ok(!link.frames.some(f => f.op === 5));
});
test('delayed replies, one active request and journal failure before COMMIT', async () => {
  const link = new ModelLink(); link.delay = 2; const c = makeClient(link);
  const pending = c.hello(); await assert.rejects(c.request(2), /传输忙/); await pending;
  await assert.rejects(c.upload(0, score(), () => true, () => {}, async () => { throw new Error('journal write'); }), /journal/);
  assert.ok(!link.frames.some(f => f.op === 5)); assert.equal(link.slots[0], null);
});
