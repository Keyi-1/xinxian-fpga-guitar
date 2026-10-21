package com.keyi.xinxian.guitar;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.zip.CRC32;

/** Pure-Java implementation of the FPGA's frozen XG3 v3 wire format. */
public final class Xg3Protocol {
    public static final byte[] MAGIC = {'X', 'G', '3', '!'};
    public static final int VERSION = 3;
    public static final int PACKET_SIZE = 32;
    public static final int HELLO = 1, LIST = 2, BEGIN = 3, DATA = 4,
            COMMIT = 5, ABORT = 6, STATUS = 7;
    private static final long MAX_DURATION = 28_800_000L;

    private Xg3Protocol() {}

    public static byte[] frame(int opcode, int session, int sequence, byte[] payload) {
        if (session <= 0 || session > 0xffff || sequence < 0 || sequence > 0xffff
                || payload.length > 16) {
            throw new IllegalArgumentException("非法会话、序号或 payload 长度");
        }
        byte[] out = new byte[PACKET_SIZE];
        System.arraycopy(MAGIC, 0, out, 0, MAGIC.length);
        out[4] = VERSION;
        out[5] = (byte) opcode;
        putU16(out, 6, session);
        putU16(out, 8, sequence);
        System.arraycopy(payload, 0, out, 10, payload.length);
        putU32(out, 28, crc32(out, 4, 24));
        return out;
    }

    public static Packet decode(byte[] data) {
        if (data.length != PACKET_SIZE || !startsWith(data, MAGIC)) {
            throw new IllegalArgumentException("不是完整 XG3 帧");
        }
        if (u8(data[4]) != VERSION || u16(data, 26) != 0 || u16(data, 6) == 0
                || u32(data, 28) != crc32(data, 4, 24)) {
            throw new IllegalArgumentException("XG3 版本、保留字段或 CRC 错误");
        }
        return new Packet(u8(data[5]), u16(data, 6), u16(data, 8),
                Arrays.copyOfRange(data, 10, 26));
    }

    public static Song parseSong(byte[] binary) {
        if (binary.length == 0 || binary.length % 16 != 0) {
            throw new IllegalArgumentException("曲谱必须由完整的 16 字节事件组成");
        }
        int count = binary.length / 16;
        if (count > 2048) {
            throw new IllegalArgumentException("事件数超过 FPGA 总容量 2048");
        }

        List<byte[]> events = new ArrayList<>(count);
        long previousOnset = -1;
        long duration = 0;
        long[] laneEnd = {-1, -1, -1, -1};
        long[] laneOnset = {-1, -1, -1, -1};
        @SuppressWarnings("unchecked")
        ArrayDeque<Long>[] windows = new ArrayDeque[4];
        for (int i = 0; i < 4; i++) windows[i] = new ArrayDeque<>();

        for (int i = 0; i < count; i++) {
            byte[] event = Arrays.copyOfRange(binary, i * 16, i * 16 + 16);
            long onset = u32(event, 0);
            long length = u32(event, 4);
            int midi = u8(event[8]);
            int lane = u8(event[9]);
            int velocity = u8(event[10]);
            if (length == 0 || onset + length > MAX_DURATION || onset + length < onset) {
                throw bad(i, "时长为零、溢出或超过 10 分钟");
            }
            if (midi < 50 || midi > 79 || lane > 3 || velocity > 3
                    || event[11] != 0 || event[14] != 0 || event[15] != 0) {
                throw bad(i, "音高、轨道、力度或保留字段越界");
            }
            if (onset < previousOnset) throw bad(i, "起音时间没有按升序排列");
            if (laneEnd[lane] > onset) throw bad(i, "同轨事件重叠");
            if (laneOnset[lane] >= 0 && onset - laneOnset[lane] < 12_000) {
                throw bad(i, "同轨相邻起音小于 12000 个采样");
            }
            ArrayDeque<Long> window = windows[lane];
            // RTL rejects the ninth event when onset-oldest <= 108200, so an
            // event leaves the active window only when the difference is greater.
            while (!window.isEmpty() && onset - window.peekFirst() > 108_200) {
                window.removeFirst();
            }
            window.addLast(onset);
            if (window.size() > 8) throw bad(i, "同轨密度超过 108200 采样内 8 个事件");

            previousOnset = onset;
            laneOnset[lane] = onset;
            laneEnd[lane] = onset + length;
            duration = Math.max(duration, onset + length);
            events.add(event);
        }
        return new Song(events, duration, crc32(binary, 0, binary.length));
    }

    public static byte[] beginPayload(int slot, int timbre, Song song) {
        if (slot < 0 || slot >= 5 || timbre < 0 || timbre >= 3) {
            throw new IllegalArgumentException("槽号或音色越界");
        }
        byte[] payload = new byte[16];
        payload[0] = (byte) slot;
        payload[1] = (byte) timbre;
        putU16(payload, 2, song.events.size());
        putU32(payload, 4, song.durationSamples);
        putU32(payload, 8, song.crc32);
        return payload;
    }

    public static SlotDescriptor descriptor(byte[] payload) {
        if (payload.length != 16) throw new IllegalArgumentException("响应 payload 长度错误");
        byte[] descriptor = Arrays.copyOfRange(payload, 1, 13);
        long bits0 = u64le(descriptor, 0);
        long bits1 = u32(descriptor, 8);
        int base = (int) ((bits0 >>> 32) & 0x7ff);
        int count = (int) ((bits0 >>> 43) & 0xfff);
        long duration = ((bits0 >>> 55) | (bits1 << 9)) & 0xffffffffL;
        int timbre = (int) ((bits1 >>> 23) & 0x3);
        int flags = u8(payload[14]);
        return new SlotDescriptor(u8(payload[13]), base, count, duration, timbre,
                (flags & 1) != 0, (flags & 2) != 0, (flags & 4) != 0,
                (flags & 8) != 0);
    }

    public static long crc32(byte[] data, int offset, int length) {
        CRC32 crc = new CRC32();
        crc.update(data, offset, length);
        return crc.getValue();
    }

    public static int findMagic(byte[] data) {
        outer: for (int i = 0; i <= data.length - MAGIC.length; i++) {
            for (int j = 0; j < MAGIC.length; j++) if (data[i + j] != MAGIC[j]) continue outer;
            return i;
        }
        return -1;
    }

    private static boolean startsWith(byte[] data, byte[] prefix) {
        if (data.length < prefix.length) return false;
        for (int i = 0; i < prefix.length; i++) if (data[i] != prefix[i]) return false;
        return true;
    }

    private static IllegalArgumentException bad(int index, String message) {
        return new IllegalArgumentException("第 " + (index + 1) + " 条事件：" + message);
    }

    static int u8(byte value) { return value & 0xff; }
    static int u16(byte[] value, int offset) {
        return u8(value[offset]) | (u8(value[offset + 1]) << 8);
    }
    static long u32(byte[] value, int offset) {
        return (u8(value[offset]) | ((long) u8(value[offset + 1]) << 8)
                | ((long) u8(value[offset + 2]) << 16) | ((long) u8(value[offset + 3]) << 24));
    }
    private static long u64le(byte[] value, int offset) {
        long out = 0;
        for (int i = 7; i >= 0; i--) out = (out << 8) | u8(value[offset + i]);
        return out;
    }
    static void putU16(byte[] value, int offset, long number) {
        value[offset] = (byte) number;
        value[offset + 1] = (byte) (number >>> 8);
    }
    static void putU32(byte[] value, int offset, long number) {
        for (int i = 0; i < 4; i++) value[offset + i] = (byte) (number >>> (8 * i));
    }

    public static final class Packet {
        public final int opcode, session, sequence;
        public final byte[] payload;
        Packet(int opcode, int session, int sequence, byte[] payload) {
            this.opcode = opcode; this.session = session; this.sequence = sequence; this.payload = payload;
        }
    }

    public static final class Song {
        public final List<byte[]> events;
        public final long durationSamples, crc32;
        Song(List<byte[]> events, long durationSamples, long crc32) {
            this.events = events; this.durationSamples = durationSamples; this.crc32 = crc32;
        }
    }

    public static final class SlotDescriptor {
        public final int slot, base, eventCount, timbre;
        public final long durationSamples;
        public final boolean valid, playable, imported, testOnly;
        SlotDescriptor(int slot, int base, int eventCount, long durationSamples, int timbre,
                       boolean valid, boolean playable, boolean imported, boolean testOnly) {
            this.slot = slot; this.base = base; this.eventCount = eventCount;
            this.durationSamples = durationSamples; this.timbre = timbre;
            this.valid = valid; this.playable = playable; this.imported = imported; this.testOnly = testOnly;
        }
    }
}
