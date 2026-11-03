package com.keyi.xinxian.guitar;

import org.junit.Test;

import java.util.Arrays;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

public final class Xg3ProtocolTest {
    @Test public void helloFrameMatchesPythonUploaderGoldenVector() {
        byte[] expected = hex("58473321030134120000000000000000000000000000000000000000cfd145b2");
        assertArrayEquals(expected, Xg3Protocol.frame(Xg3Protocol.HELLO, 0x1234, 0, new byte[0]));
        Xg3Protocol.Packet decoded = Xg3Protocol.decode(expected);
        assertEquals(Xg3Protocol.HELLO, decoded.opcode);
        assertEquals(0x1234, decoded.session);
        assertEquals(0, decoded.sequence);
    }

    @Test public void songRecordAndBeginPayloadUseFrozenLittleEndianLayout() {
        byte[] record = new byte[16];
        Xg3Protocol.putU32(record, 0, 12_000);
        Xg3Protocol.putU32(record, 4, 48_000);
        record[8] = 60;
        record[9] = 1;
        record[10] = 2;
        Xg3Protocol.putU16(record, 12, 0x3456);
        Xg3Protocol.Song song = Xg3Protocol.parseSong(record);
        assertEquals(1, song.events.size());
        assertEquals(60_000, song.durationSamples);
        assertEquals(0x04056A55L, song.crc32);

        byte[] begin = Xg3Protocol.beginPayload(4, 2, song);
        assertEquals(4, begin[0]);
        assertEquals(2, begin[1]);
        assertEquals(1, Xg3Protocol.u16(begin, 2));
        assertEquals(60_000, Xg3Protocol.u32(begin, 4));
        assertEquals(song.crc32, Xg3Protocol.u32(begin, 8));
        assertArrayEquals(new byte[4], Arrays.copyOfRange(begin, 12, 16));
    }

    @Test public void decodesCatalogDescriptorAcrossThe64BitBoundary() {
        // progress=123, base=703, count=212, duration=7296000, timbre=1,
        // then slot=3 and valid/playable/imported flags.
        byte[] payload = hex("007b000000bfa20600aa378000030700");
        Xg3Protocol.SlotDescriptor value = Xg3Protocol.descriptor(payload);
        assertEquals(3, value.slot);
        assertEquals(703, value.base);
        assertEquals(212, value.eventCount);
        assertEquals(7_296_000L, value.durationSamples);
        assertEquals(1, value.timbre);
        assertEquals(true, value.valid);
        assertEquals(true, value.playable);
        assertEquals(true, value.imported);
        assertEquals(false, value.testOnly);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsOutOfRangeMidiBeforeBluetoothTransfer() {
        byte[] record = new byte[16];
        Xg3Protocol.putU32(record, 4, 48_000);
        record[8] = 49;
        Xg3Protocol.parseSong(record);
    }

    private static byte[] hex(String value) {
        byte[] out = new byte[value.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16);
        }
        return out;
    }
}
