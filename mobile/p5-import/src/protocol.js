// Shared by the native phone app and Node fault tests. No BLE/serial side effects.
export const SERVICE = '7ad10001-6e85-4cba-a0b6-d607ce2d3105';
export const RX = '7ad10002-6e85-4cba-a0b6-d607ce2d3105';
export const TX = '7ad10003-6e85-4cba-a0b6-d607ce2d3105';
export const OP = { HELLO: 1, LIST: 2, BEGIN: 3, DATA: 4, COMMIT: 5, ABORT: 6, STATUS: 7 };
const MAGIC = [88, 71, 51, 33];
const ERRORS = ['', 'BUSY', 'NO_SPACE', 'BAD_LENGTH', 'SONG_CRC', 'ORDER_OR_LANE_CONFLICT',
  'RANGE_OR_METADATA', 'DENSITY', 'TIMEOUT', 'NO_TRANSACTION', 'BAD_COMMAND',
  'BAD_FORMAT', 'PACKET_CRC', 'SESSION_OR_SEQUENCE'];
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
export function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const n = bytes[i] * 65536 + (bytes[i + 1] || 0) * 256 + (bytes[i + 2] || 0);
    s += alphabet[n >>> 18] + alphabet[n >>> 12 & 63] +
      (i + 1 < bytes.length ? alphabet[n >>> 6 & 63] : '=') +
      (i + 2 < bytes.length ? alphabet[n & 63] : '=');
  }
  return s;
}
export function fromBase64(s) {
  if (typeof s !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(s))
    throw new Error('无效 Base64');
  const out = [];
  for (let i = 0; i < s.length; i += 4) {
    const n = alphabet.indexOf(s[i]) * 262144 + alphabet.indexOf(s[i + 1]) * 4096 +
      Math.max(0, alphabet.indexOf(s[i + 2])) * 64 + Math.max(0, alphabet.indexOf(s[i + 3]));
    out.push(n >>> 16);
    if (s[i + 2] !== '=') out.push(n >>> 8 & 255);
    if (s[i + 3] !== '=') out.push(n & 255);
  }
  const bytes = Uint8Array.from(out);
  if (toBase64(bytes) !== s) throw new Error('非规范 Base64');
  return bytes;
}
export function crc32(bytes) {
  let c = 0xffffffff;
  for (const byte of bytes) {
    c ^= byte;
    for (let i = 0; i < 8; i++) c = (c >>> 1) ^ ((c & 1) ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
export const view = b => new DataView(b.buffer, b.byteOffset, b.byteLength);
export function packet(op, session, seq, payload = new Uint8Array()) {
  if (!Number.isInteger(session) || session < 1 || session > 65535 ||
      !Number.isInteger(seq) || seq < 0 || seq > 65535 || payload.length > 16) throw new Error('帧参数错误');
  const b = new Uint8Array(32), d = view(b);
  b.set(MAGIC); b[4] = 3; b[5] = op;
  d.setUint16(6, session, true); d.setUint16(8, seq, true); b.set(payload, 10);
  d.setUint32(28, crc32(b.subarray(4, 28)), true);
  return b;
}
export function decode(b) {
  const d = view(b);
  if (b.length !== 32 || !MAGIC.every((v, i) => b[i] === v) || b[4] !== 3 ||
      !d.getUint16(6, true) || d.getUint16(26, true) || crc32(b.subarray(4, 28)) !== d.getUint32(28, true))
    throw new Error('帧格式或 CRC 错误');
  return { op: b[5], session: d.getUint16(6, true), seq: d.getUint16(8, true), payload: b.slice(10, 26) };
}
export class Frames {
  constructor() { this.bytes = []; }
  push(bytes) {
    const frames = [];
    for (const byte of bytes) {
      this.bytes.push(byte);
      if (this.bytes.length < 32) continue;
      try { frames.push(decode(Uint8Array.from(this.bytes))); this.bytes = []; }
      catch { this.bytes.shift(); }
    }
    return frames;
  }
}
export async function parsePackage(text, sha256) {
  if (typeof text !== 'string' || text.length > 65536) throw new Error('曲谱包超过 64 KiB');
  const p = JSON.parse(text);
  if (p.package_format !== 'xinxian-score' || p.package_version !== 1 || p.format_version !== 2 ||
      p.event_bytes !== 16 || p.sample_rate_hz !== 48000 || typeof p.title !== 'string' ||
      [...p.title].length < 1 || [...p.title].length > 80) throw new Error('不支持的曲谱包');
  for (const k of ['event_count', 'duration_samples', 'recommended_timbre'])
    if (!Number.isSafeInteger(p[k])) throw new Error('曲谱元数据必须为整数');
  if (p.event_count < 1 || p.event_count > 1345 || p.duration_samples < 1 ||
      p.duration_samples > 28800000 || p.recommended_timbre < 0 || p.recommended_timbre > 2)
    throw new Error('曲谱超出当前曲库范围');
  const raw = fromBase64(p.payload_base64);
  if (raw.length !== p.event_count * 16 ||
      crc32(raw).toString(16).padStart(8, '0') !== p.crc32 ||
      typeof sha256 !== 'function' || await sha256(raw) !== p.payload_sha256)
    throw new Error('曲谱包长度或校验错误');
  const d = view(raw), ends = [-1, -1, -1, -1], lanes = [[], [], [], []];
  let last = -1;
  for (let i = 0; i < raw.length; i += 16) {
    const onset = d.getUint32(i, true), duration = d.getUint32(i + 4, true);
    const midi = raw[i + 8], lane = raw[i + 9], velocity = raw[i + 10];
    if (onset < last || !duration || onset + duration > p.duration_samples || midi < 50 || midi > 79 ||
        lane > 3 || velocity > 3 || raw[i + 11] || d.getUint16(i + 14, true) || ends[lane] > onset ||
        (lanes[lane].length && onset - lanes[lane].at(-1) < 12000)) throw new Error('音符范围、排序或同轨冲突');
    lanes[lane].push(onset); ends[lane] = onset + duration; last = onset;
  }
  for (const onsets of lanes) {
    let first = 0;
    for (let i = 0; i < onsets.length; i++) {
      while (onsets[i] - onsets[first] > 108200) first++;
      if (i - first + 1 > 8) throw new Error('谱面局部密度过高');
    }
  }
  return { ...p, raw };
}
export function slotInfo(payload) {
  const d = view(payload), b = payload.subarray(1, 13);
  // Descriptor bitfields cross bytes; extract arithmetically without signed truncation.
  const bits = (offset, n) => {
    let v = 0;
    for (let i = 0; i < n; i++) v += ((b[(offset + i) >>> 3] >>> ((offset + i) & 7)) & 1) * 2 ** i;
    return v;
  };
  return { slot: payload[13], valid: !!(payload[14] & 1), playable: !!(payload[14] & 2),
    imported: !!(payload[14] & 4), testOnly: !!(payload[14] & 8), base: bits(32, 11),
    count: bits(43, 12), duration: bits(55, 32), timbre: bits(87, 2), step: d.getUint32(1, true) };
}
export class UnknownCommit extends Error {
  constructor(cause) { super('提交结果待确认：未收到 FPGA 最终确认，请勿假定回滚。', { cause }); }
}
export class FpgaRejected extends Error {
  constructor(code) { super(`FPGA: ${ERRORS[code] || code}`); this.code = code; }
}
export class AckTimeout extends Error {}
export class Client {
  constructor(link, session, { timeout = 3000, attempts = 4 } = {}) {
    this.link = link; this.session = session; this.seq = 0; this.timeout = timeout; this.attempts = attempts;
    this.parser = new Frames(); this.waiter = null; this.active = false; this.closed = false;
    link.onBytes = bytes => {
      for (const f of this.parser.push(bytes))
        if (this.waiter && f.session === this.session && f.seq === this.seq && f.op === (this.waiter.op | 128))
          this.waiter.resolve(f.payload);
    };
    link.onClose = () => { this.closed = true; this.waiter?.reject(new Error('蓝牙连接已断开')); };
  }
  async request(op, payload = new Uint8Array()) {
    if (this.active || this.closed) throw new Error('传输忙或连接已断开');
    this.active = true;
    const wire = packet(op, this.session, this.seq, payload);
    try {
      for (let attempt = 0; attempt < this.attempts; attempt++) {
        let timer;
        const reply = new Promise((resolve, reject) => {
          this.waiter = { op, resolve, reject };
          timer = setTimeout(() => reject(new AckTimeout('等待 FPGA ACK 超时')), this.timeout);
        });
        // A write error may leave a half packet; close instead of overlapping writes.
        let sendError;
        const send = (async () => {
          try { for (let i = 0; i < 32; i += 20) await this.link.write(wire.slice(i, i + 20)); }
          catch (error) { sendError = error; this.closed = true; this.waiter?.reject(error); }
        })();
        try {
          const body = await reply;
          await send;
          if (sendError) throw sendError;
          if (body[0] === 12 && attempt + 1 < this.attempts) continue;
          if (body[0]) throw new FpgaRejected(body[0]);
          this.seq = (this.seq + 1) & 65535;
          return body;
        } catch (error) {
          if (!(error instanceof AckTimeout) || attempt + 1 === this.attempts) {
            if (!(error instanceof FpgaRejected)) this.closed = true;
            throw error;
          }
          // Never begin another write while a native write is still pending.
          // Adapter must finish/cancel writes within the ACK deadline.
          await send;
          if (this.closed) throw sendError || new Error('连接已失效');
        } finally { clearTimeout(timer); this.waiter = null; }
      }
    } finally { this.active = false; }
  }
  async hello() {
    const p = await this.request(OP.HELLO), d = view(p);
    if (p[1] !== 2 || p[2] !== 5 || p[3] !== 32 || d.getUint16(4, true) !== 703 ||
        d.getUint16(6, true) !== 2048 || p[8] !== 50 || p[9] !== 79 || d.getUint32(10, true) !== 48000)
      throw new Error('FPGA 能力与此版本不兼容');
  }
  async list() {
    const slots = [];
    for (let i = 0; i < 5; i++) {
      const p = await this.request(OP.LIST, Uint8Array.of(i)), slot = slotInfo(p);
      if (slot.slot !== i) throw new Error('目录槽号不匹配');
      slots.push(slot);
    }
    return slots;
  }
  async upload(slot, score, confirmReplace, progress = () => {}, beforeCommit = async () => {}) {
    if (!Number.isInteger(slot) || slot < 0 || slot > 4) throw new Error('槽号错误');
    const slots = await this.list();
    if (slots[slot].valid && !await confirmReplace(slots[slot])) throw new Error('已取消替换');
    const p = new Uint8Array(16), d = view(p);
    p[0] = slot; p[1] = score.recommended_timbre;
    d.setUint16(2, score.event_count, true); d.setUint32(4, score.duration_samples, true);
    d.setUint32(8, crc32(score.raw), true);
    await this.request(OP.BEGIN, p);
    for (let i = 0; i < score.event_count; i++) {
      await this.request(OP.DATA, score.raw.slice(i * 16, i * 16 + 16)); progress(i + 1, score.event_count);
    }
    // Durable phone-side marker must be saved BEFORE sending COMMIT.
    await beforeCommit({ slot, session: this.session, sequence: this.seq, crc32: score.crc32, title: score.title });
    try { await this.request(OP.COMMIT); }
    catch (error) { if (error instanceof FpgaRejected) throw error; throw new UnknownCommit(error); }
    try {
      const slots = await this.list(), current = slots[slot];
      return { committed: true, slots, catalogWarning: !current.imported || current.count !== score.event_count ||
        current.duration !== score.duration_samples || current.timbre !== score.recommended_timbre };
    }
    catch (error) { return { committed: true, slots: null, refreshError: String(error) }; }
  }
}
