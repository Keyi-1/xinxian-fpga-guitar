package com.keyi.xinxian.guitar;

import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/** Stop-and-wait XG3 client. All public request methods must run off the UI thread. */
public final class Xg3Client {
    public interface Progress { void onProgress(int completed, int total); }

    private static final Map<Integer, String> ERRORS = new HashMap<>();
    static {
        ERRORS.put(1, "设备忙"); ERRORS.put(2, "曲库存储空间不足");
        ERRORS.put(3, "长度错误"); ERRORS.put(4, "整曲或读回 CRC 错误");
        ERRORS.put(5, "顺序或同轨冲突"); ERRORS.put(6, "范围或元数据错误");
        ERRORS.put(7, "事件密度过高"); ERRORS.put(8, "事务超时");
        ERRORS.put(9, "没有上传事务"); ERRORS.put(10, "不支持的命令");
        ERRORS.put(11, "帧格式错误"); ERRORS.put(12, "帧 CRC 错误");
        ERRORS.put(13, "会话或序号错误");
    }

    private final BleUartClient transport;
    private final int session = new SecureRandom().nextInt(0xffff) + 1;
    private final Object requestLock = new Object();
    private byte[] rxBuffer = new byte[0];
    private int sequence;
    private int pendingOpcode = -1, pendingSequence = -1;
    private byte[] pendingReply;

    public Xg3Client(BleUartClient transport) { this.transport = transport; }

    public void accept(byte[] bytes) {
        synchronized (this) {
            byte[] joined = Arrays.copyOf(rxBuffer, rxBuffer.length + bytes.length);
            System.arraycopy(bytes, 0, joined, rxBuffer.length, bytes.length);
            rxBuffer = joined;
            while (true) {
                int start = Xg3Protocol.findMagic(rxBuffer);
                if (start < 0) {
                    rxBuffer = Arrays.copyOfRange(rxBuffer, Math.max(0, rxBuffer.length - 3), rxBuffer.length);
                    return;
                }
                if (start > 0) rxBuffer = Arrays.copyOfRange(rxBuffer, start, rxBuffer.length);
                if (rxBuffer.length < Xg3Protocol.PACKET_SIZE) return;
                byte[] candidate = Arrays.copyOf(rxBuffer, Xg3Protocol.PACKET_SIZE);
                Xg3Protocol.Packet packet;
                try {
                    packet = Xg3Protocol.decode(candidate);
                } catch (IllegalArgumentException error) {
                    rxBuffer = Arrays.copyOfRange(rxBuffer, 1, rxBuffer.length);
                    continue;
                }
                rxBuffer = Arrays.copyOfRange(rxBuffer, Xg3Protocol.PACKET_SIZE, rxBuffer.length);
                if (packet.opcode == (pendingOpcode | 0x80) && packet.session == session
                        && packet.sequence == pendingSequence) {
                    pendingReply = packet.payload;
                    notifyAll();
                }
            }
        }
    }

    public Capabilities hello() throws Exception {
        if (sequence != 0) throw new IllegalStateException("HELLO 只能开始新会话");
        byte[] reply = request(Xg3Protocol.HELLO, new byte[0]);
        int format = Xg3Protocol.u8(reply[1]);
        int slots = Xg3Protocol.u8(reply[2]);
        int packetBytes = Xg3Protocol.u8(reply[3]);
        int reserved = Xg3Protocol.u16(reply, 4);
        int capacity = Xg3Protocol.u16(reply, 6);
        int midiMin = Xg3Protocol.u8(reply[8]), midiMax = Xg3Protocol.u8(reply[9]);
        long rate = Xg3Protocol.u32(reply, 10);
        int features = Xg3Protocol.u16(reply, 14);
        if (format != 2 || slots != 5 || packetBytes != 32 || rate != 48_000) {
            throw new IllegalStateException("FPGA 能力与手机端不兼容");
        }
        return new Capabilities(format, slots, reserved, capacity, midiMin, midiMax, rate, features);
    }

    public Xg3Protocol.SlotDescriptor listSlot(int slot) throws Exception {
        return Xg3Protocol.descriptor(request(Xg3Protocol.LIST, new byte[]{(byte) slot}));
    }

    public Xg3Protocol.SlotDescriptor upload(int slot, int timbre, Xg3Protocol.Song song,
                                              Progress progress) throws Exception {
        request(Xg3Protocol.BEGIN, Xg3Protocol.beginPayload(slot, timbre, song));
        try {
            for (int i = 0; i < song.events.size(); i++) {
                request(Xg3Protocol.DATA, song.events.get(i));
                if (progress != null) progress.onProgress(i + 1, song.events.size());
            }
        } catch (Exception dataError) {
            try { request(Xg3Protocol.ABORT, new byte[0]); } catch (Exception ignored) {}
            throw dataError;
        }
        try {
            request(Xg3Protocol.COMMIT, new byte[0]);
        } catch (RequestTimeout timeout) {
            throw new CommitUnknown("COMMIT 的确认包多次丢失，提交结果未知；请重新连接并查询槽位，不能假定已经回滚。", timeout);
        }
        return listSlot(slot);
    }

    private byte[] request(int opcode, byte[] payload) throws Exception {
        synchronized (requestLock) {
            byte[] wire = Xg3Protocol.frame(opcode, session, sequence, payload);
            for (int attempt = 0; attempt < 4; attempt++) {
                synchronized (this) {
                    pendingOpcode = opcode;
                    pendingSequence = sequence;
                    pendingReply = null;
                }
                transport.write(wire).get(3, TimeUnit.SECONDS);
                byte[] reply;
                synchronized (this) {
                    long deadline = System.currentTimeMillis() + 1800;
                    while (pendingReply == null) {
                        long remaining = deadline - System.currentTimeMillis();
                        if (remaining <= 0) break;
                        wait(remaining);
                    }
                    reply = pendingReply;
                    pendingOpcode = pendingSequence = -1;
                    pendingReply = null;
                }
                if (reply == null) {
                    if (attempt == 3) throw new RequestTimeout("等待 FPGA 回包超时");
                    continue;
                }
                int status = Xg3Protocol.u8(reply[0]);
                if (status == 12 && attempt < 3) continue;
                if (status != 0) {
                    String meaning = ERRORS.containsKey(status) ? ERRORS.get(status) : "未知错误 " + status;
                    throw new DeviceRejected("FPGA 拒绝命令 " + opcode + "：" + meaning, status);
                }
                sequence = (sequence + 1) & 0xffff;
                return reply;
            }
            throw new RequestTimeout("已达到重试上限");
        }
    }

    public static final class Capabilities {
        public final int eventFormat, slots, reservedRecords, capacity, midiMin, midiMax, features;
        public final long sampleRate;
        Capabilities(int eventFormat, int slots, int reservedRecords, int capacity,
                     int midiMin, int midiMax, long sampleRate, int features) {
            this.eventFormat = eventFormat; this.slots = slots; this.reservedRecords = reservedRecords;
            this.capacity = capacity; this.midiMin = midiMin; this.midiMax = midiMax;
            this.sampleRate = sampleRate; this.features = features;
        }
    }

    public static class RequestTimeout extends Exception {
        private static final long serialVersionUID = 1L;
        RequestTimeout(String message) { super(message); }
    }
    public static final class CommitUnknown extends Exception {
        private static final long serialVersionUID = 1L;
        CommitUnknown(String message, Throwable cause) { super(message, cause); }
    }
    public static final class DeviceRejected extends Exception {
        private static final long serialVersionUID = 1L;
        public final int status;
        DeviceRejected(String message, int status) { super(message); this.status = status; }
    }
}
