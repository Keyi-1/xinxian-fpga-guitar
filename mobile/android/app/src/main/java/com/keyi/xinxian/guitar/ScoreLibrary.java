package com.keyi.xinxian.guitar;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Locale;

/** Local event files, never recorded audio. Both import paths use the same parser. */
public final class ScoreLibrary {
    public static final String[] TIMBRES = {"钢琴", "明亮弦音", "哇音"};
    public static final Entry[] ENTRIES = {
        new Entry("生日快乐歌", "happy_birthday_60bpm.bin", 60, 25, 1152000L, 0xf08df358L),
        new Entry("我不难过", "wo_bu_nan_guo_64bpm_v2.bin", 64, 564, 14220000L, 0x5d01057fL),
        new Entry("City of Stars", "city_of_stars_100bpm_poly_v2.bin", 100, 491, 6451200L, 0x1dd77241L)
    };

    public static Xg3Protocol.Song read(InputStream input) throws IOException {
        if (input == null) throw new IOException("无法打开曲谱");
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        byte[] block = new byte[4096];
        int count;
        while ((count = input.read(block)) != -1) {
            if (bytes.size() + count > 2048 * 16) throw new IOException("曲谱超过设备事件上限");
            bytes.write(block, 0, count);
        }
        return Xg3Protocol.parseSong(bytes.toByteArray());
    }

    public static String timbre(int index) {
        return index >= 0 && index < TIMBRES.length ? TIMBRES[index] : "未知音色";
    }

    public static String duration(long samples) {
        long seconds = samples / 48000;
        return seconds < 60 ? seconds + "秒" : String.format(Locale.CHINA, "%d分%02d秒", seconds / 60, seconds % 60);
    }

    public static String slotTitle(int index, Xg3Protocol.SlotDescriptor value) {
        if (value == null) return new String[]{"茉莉花", "Seven Nation Army", "情歌", "待导入", "待导入"}[index];
        if (value.imported) return "USER " + (index + 1);
        if (!value.playable) return "待导入";
        // Recognize the actual descriptor, not an assumed slot order on an older bitstream.
        if (value.eventCount == 67 && value.durationSamples == 1620000L && value.timbre == 0) return "茉莉花";
        if (value.eventCount == 168 && value.durationSamples == 9216000L && value.timbre == 2) return "Seven Nation Army";
        if (value.eventCount == 212 && value.durationSamples == 7296000L && value.timbre == 1) return "情歌";
        return "设备曲谱";
    }

    public static final class Entry {
        public final String title, file;
        public final int bpm, count;
        public final long samples, crc;
        Entry(String title, String file, int bpm, int count, long samples, long crc) {
            this.title = title; this.file = file; this.bpm = bpm; this.count = count; this.samples = samples; this.crc = crc;
        }
        public Xg3Protocol.Song read(InputStream input) throws IOException {
            Xg3Protocol.Song result = ScoreLibrary.read(input);
            if (result.crc32 != crc || result.events.size() != count || result.durationSamples != samples)
                throw new IOException("内置曲谱校验失败：" + title);
            return result;
        }
    }
    private ScoreLibrary() {}
}
