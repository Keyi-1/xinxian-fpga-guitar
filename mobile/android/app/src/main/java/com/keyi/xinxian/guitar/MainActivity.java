package com.keyi.xinxian.guitar;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothDevice;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity implements BleUartClient.Listener {
    private static final int REQUEST_BLE = 20;
    private static final int PICK_SONG = 21;

    private TextView status, fileName, log;
    private Spinner deviceSpinner, slotSpinner, timbreSpinner;
    private Button queryButton, uploadButton;
    private ProgressBar progress;
    private ArrayAdapter<String> deviceAdapter;
    private final Map<String, BluetoothDevice> devices = new LinkedHashMap<>();
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private BleUartClient ble;
    private volatile Xg3Client client;
    private Xg3Protocol.Song song;
    private boolean protocolReady;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_main);
        status = findViewById(R.id.status);
        fileName = findViewById(R.id.fileName);
        log = findViewById(R.id.log);
        deviceSpinner = findViewById(R.id.devices);
        slotSpinner = findViewById(R.id.slot);
        timbreSpinner = findViewById(R.id.timbre);
        queryButton = findViewById(R.id.query);
        uploadButton = findViewById(R.id.upload);
        progress = findViewById(R.id.progress);

        deviceAdapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
                new ArrayList<>());
        deviceSpinner.setAdapter(deviceAdapter);
        slotSpinner.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
                new String[]{"USER 1", "USER 2（推荐先试）", "USER 3", "USER 4", "USER 5（推荐先试）"}));
        slotSpinner.setSelection(1);
        timbreSpinner.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
                new String[]{"音色 0", "音色 1", "音色 2"}));
        timbreSpinner.setSelection(1);

        ble = new BleUartClient(this, this);
        findViewById(R.id.scan).setOnClickListener(v -> ensurePermissionAndScan());
        findViewById(R.id.connect).setOnClickListener(v -> connectSelected());
        findViewById(R.id.pickFile).setOnClickListener(v -> pickSong());
        queryButton.setOnClickListener(v -> querySlots());
        uploadButton.setOnClickListener(v -> uploadSong());
    }

    private void ensurePermissionAndScan() {
        String[] wanted = Build.VERSION.SDK_INT >= 31
                ? new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT}
                : new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
        List<String> missing = new ArrayList<>();
        for (String permission : wanted) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) missing.add(permission);
        }
        if (!missing.isEmpty()) {
            requestPermissions(missing.toArray(new String[0]), REQUEST_BLE);
            return;
        }
        devices.clear();
        deviceAdapter.clear();
        append("开始扫描；优先选择名称含 XINXIAN 或标有 [BLE 串口] 的设备。");
        ble.startScan();
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode != REQUEST_BLE) return;
        for (int result : results) {
            if (result != PackageManager.PERMISSION_GRANTED) {
                toast("需要蓝牙权限才能连接开发板");
                return;
            }
        }
        ensurePermissionAndScan();
    }

    private void connectSelected() {
        Object selected = deviceSpinner.getSelectedItem();
        if (selected == null || !devices.containsKey(selected.toString())) {
            toast("请先扫描并选择设备");
            return;
        }
        setProtocolReady(false);
        ble.connect(devices.get(selected.toString()));
    }

    private void pickSong() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/octet-stream");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"application/octet-stream", "*/*"});
        startActivityForResult(intent, PICK_SONG);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICK_SONG || resultCode != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        worker.execute(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri)) {
                if (input == null) throw new IllegalArgumentException("无法打开所选文件");
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                byte[] block = new byte[4096];
                int count;
                while ((count = input.read(block)) != -1) {
                    bytes.write(block, 0, count);
                    if (bytes.size() > 2048 * 16) {
                        throw new IllegalArgumentException("曲谱超过 FPGA 的 2048 条事件上限");
                    }
                }
                Xg3Protocol.Song parsed = Xg3Protocol.parseSong(bytes.toByteArray());
                song = parsed;
                String name = displayName(uri);
                runOnUiThread(() -> {
                    fileName.setText(name + "\n" + parsed.events.size() + " 条事件，"
                            + String.format("%.2f 秒，CRC32 %08X", parsed.durationSamples / 48000.0, parsed.crc32));
                    append("曲谱本地校验通过：" + name);
                    refreshActions();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    song = null;
                    fileName.setText("曲谱不可用：" + message(error));
                    refreshActions();
                });
            }
        });
    }

    private void querySlots() {
        Xg3Client active = client;
        if (!protocolReady || active == null) return;
        setBusy(true);
        worker.execute(() -> {
            try {
                for (int i = 0; i < 5; i++) {
                    Xg3Protocol.SlotDescriptor value = active.listSlot(i);
                    appendFromWorker(String.format("USER %d: %s，%d 条，%.2f 秒，音色 %d%s",
                            i + 1, value.playable ? "可演奏" : "空/不可演奏", value.eventCount,
                            value.durationSamples / 48000.0, value.timbre,
                            value.imported ? "，RAM 导入" : ""));
                }
            } catch (Exception error) {
                appendFromWorker("查询失败：" + message(error));
            } finally {
                runOnUiThread(() -> setBusy(false));
            }
        });
    }

    private void uploadSong() {
        Xg3Client active = client;
        Xg3Protocol.Song selectedSong = song;
        if (!protocolReady || active == null || selectedSong == null) return;
        int slot = slotSpinner.getSelectedItemPosition();
        int timbre = timbreSpinner.getSelectedItemPosition();
        setBusy(true);
        progress.setProgress(0);
        append("开始上传到 USER " + (slot + 1) + "；上传期间请停留在开发板主页/选曲页。");
        worker.execute(() -> {
            try {
                Xg3Protocol.SlotDescriptor result = active.upload(slot, timbre, selectedSong,
                        (done, total) -> runOnUiThread(() -> progress.setProgress(done * 100 / total)));
                appendFromWorker("上传完成并经 FPGA RAM 读回校验：USER " + (result.slot + 1)
                        + "，" + result.eventCount + " 条事件。");
            } catch (Xg3Client.CommitUnknown unknown) {
                appendFromWorker("警告：" + unknown.getMessage());
            } catch (Exception error) {
                appendFromWorker("上传失败：" + message(error));
            } finally {
                runOnUiThread(() -> setBusy(false));
            }
        });
    }

    private void setBusy(boolean busy) {
        queryButton.setEnabled(protocolReady && !busy);
        uploadButton.setEnabled(protocolReady && song != null && !busy);
        findViewById(R.id.pickFile).setEnabled(!busy);
    }

    private void setProtocolReady(boolean value) {
        protocolReady = value;
        refreshActions();
    }

    private void refreshActions() {
        queryButton.setEnabled(protocolReady);
        uploadButton.setEnabled(protocolReady && song != null);
    }

    private String displayName(Uri uri) {
        try (android.database.Cursor cursor = getContentResolver().query(uri, null, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) return cursor.getString(index);
            }
        }
        return "所选曲谱.bin";
    }

    @Override public void onDeviceFound(BluetoothDevice device, String label) {
        runOnUiThread(() -> {
            if (!devices.containsKey(label)) {
                devices.put(label, device);
                deviceAdapter.add(label);
            }
        });
    }

    @Override public void onState(String text, boolean ready) {
        runOnUiThread(() -> {
            status.setText(text);
            append(text);
            setProtocolReady(false);
            if (ready) beginProtocolSession();
        });
    }

    private void beginProtocolSession() {
        Xg3Client next = new Xg3Client(ble);
        client = next;
        worker.execute(() -> {
            try {
                Xg3Client.Capabilities caps = next.hello();
                appendFromWorker("XG3 握手成功：" + caps.slots + " 槽，容量 " + caps.capacity
                        + "，MIDI " + caps.midiMin + "–" + caps.midiMax + "。");
                runOnUiThread(() -> setProtocolReady(true));
            } catch (Exception error) {
                appendFromWorker("BLE 已连接，但 XG3 握手失败：" + message(error));
            }
        });
    }

    @Override public void onBytes(byte[] value) {
        Xg3Client active = client;
        if (active != null) active.accept(value);
    }

    @Override public void onLog(String message) { appendFromWorker(message); }

    private void appendFromWorker(String message) { runOnUiThread(() -> append(message)); }
    private void append(String message) {
        String previous = log.getText().toString();
        if ("等待操作…".equals(previous)) previous = "";
        log.setText((previous.isEmpty() ? "" : previous + "\n") + message);
    }
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_SHORT).show(); }
    private static String message(Throwable error) {
        Throwable current = error;
        while (current.getCause() != null && current.getMessage() == null) current = current.getCause();
        return current.getMessage() == null ? current.getClass().getSimpleName() : current.getMessage();
    }

    @Override protected void onDestroy() {
        ble.disconnect();
        worker.shutdownNow();
        super.onDestroy();
    }
}
