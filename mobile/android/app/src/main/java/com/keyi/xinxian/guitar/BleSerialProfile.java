package com.keyi.xinxian.guitar;
import java.util.UUID;

/** Only known serial characteristics; JDY FFE2 is a separate GPIO channel. */
public final class BleSerialProfile {
    public static final BleSerialProfile JDY23 = new BleSerialProfile("JDY-23", "0000ffe0-0000-1000-8000-00805f9b34fb", "0000ffe1-0000-1000-8000-00805f9b34fb", "0000ffe1-0000-1000-8000-00805f9b34fb");
    public static final BleSerialProfile NUS = new BleSerialProfile("BL616", "6e400001-b5a3-f393-e0a9-e50e24dcca9e", "6e400002-b5a3-f393-e0a9-e50e24dcca9e", "6e400003-b5a3-f393-e0a9-e50e24dcca9e");
    public final String label;
    public final UUID service, write, notify;
    public static final int CHUNK_BYTES = 20;
    // 20 bytes at 9600/8N1 take 20.84ms; allow module buffering margin.
    public static final int CHUNK_INTERVAL_MS = 35;
    private BleSerialProfile(String label, String service, String write, String notify) {
        this.label=label; this.service=UUID.fromString(service); this.write=UUID.fromString(write); this.notify=UUID.fromString(notify);
    }
    public static BleSerialProfile fromService(UUID uuid) {
        if (JDY23.service.equals(uuid)) return JDY23;
        if (NUS.service.equals(uuid)) return NUS;
        return null;
    }
}
