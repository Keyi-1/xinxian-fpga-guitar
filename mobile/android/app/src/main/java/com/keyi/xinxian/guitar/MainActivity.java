package com.keyi.xinxian.guitar;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothDevice;
import android.content.Intent;
import android.content.SharedPreferences;
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
    private boolean busy;
    private boolean pickingFile;
    private volatile boolean needsReview;
    private SharedPreferences commitJournal;

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
        commitJournal = getSharedPreferences("jdy23_commit_journal", MODE_PRIVATE);
        needsReview = commitJournal.contains("pending");
        if (needsReview) append("上次提交结果待核对：" + commitJournal.getString("pending", ""));
        findViewById(R.id.scan).setOnClickListener(v -> ensurePermissionAndScan());
        findViewById(R.id.connect).setOnClickListener(v -> connectSelected());
        findViewById(R.id.pickFile).setOnClickListener(v -> pickSong());
        queryButton.setOnClickListener(v -> querySlots());
        uploadButton.setOnClickListener(v -> uploadSong());
        findViewById(R.id.disconnect).setOnClickListener(v -> ble.disconnect());
        findViewById(R.id.clearPending).setOnClickListener(v -> new AlertDialog.Builder(this)
                .setTitle("确认已核对曲目")
                .setMessage("请先读取槽位并在开发板试听。目录条数一致不能证明内容相同。确认后解除重传限制。")
                .setNegativeButton("继续核对", null)
                .setPositiveButton("我已核对", (dialog, which) -> {
                    if (commitJournal.edit().remove("pending").commit()) {
                        needsReview = false; append("已人工核对并清除待确认标记"); refreshActions();
                    } else toast("未能保存核对结果，请重试");
                }).show());
        refreshActions();
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
        append("开始扫描；选择 JDY-23 或 XINXIAN-JDY23。未改名的模块也可以连接。");
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
        pickingFile = true;
        startActivityForResult(intent, PICK_SONG);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == PICK_SONG) pickingFile = false;
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
        if (!protocolReady || active == null || selectedSong == null || needsReview || busy) return;
        int slot = slotSpinner.getSelectedItemPosition();
        int timbre = timbreSpinner.getSelectedItemPosition();
        setBusy(true);
        progress.setProgress(0);
        append("开始上传到 USER " + (slot + 1) + "；上传期间请停留在开发板主页/选曲页。");
        worker.execute(() -> {
            try {
                Xg3Protocol.SlotDescriptor result = active.upload(slot, timbre, selectedSong,
                        (done, total) -> runOnUiThread(() -> progress.setProgress(done * 100 / total)),
                        new Xg3Client.CommitJournal() {
                            @Override public void beforeCommit(int target, Xg3Protocol.Song value) throws Exception {
                                String record = String.format("USER %d，%d条，CRC32 %08X", target + 1, value.events.size(), value.crc32);
                                needsReview = true;
                                if (!commitJournal.edit().putString("pending", record).commit())
                                    throw new IllegalStateException("未能保存提交标记，尚未发送 COMMIT");
                            }
                            @Override public void confirmed() throws Exception {
                                if (!commitJournal.edit().remove("pending").commit())
                                    throw new IllegalStateException("无法清除提交标记");
                                needsReview = false;
                            }
                        });
                appendFromWorker("上传完成并经 FPGA RAM 读回校验：USER " + (result.slot + 1)
                        + "，" + result.eventCount + " 条事件。");
            } catch (Xg3Client.CommitUnknown unknown) {
                appendFromWorker("警告：" + unknown.getMessage());
            } catch (Xg3Client.CommitConfirmed confirmed) {
                appendFromWorker(confirmed.getMessage());
            } catch (Exception error) {
                appendFromWorker("上传失败：" + message(error));
            } finally {
                runOnUiThread(() -> setBusy(false));
            }
        });
    }

    private void setBusy(boolean busy) {
        this.busy = busy;
        refreshActions();
    }

    private void setProtocolReady(boolean value) {
        protocolReady = value;
        refreshActions();
    }

    private void refreshActions() {
        queryButton.setEnabled(protocolReady && !busy);
        uploadButton.setEnabled(protocolReady && song != null && !busy && !needsReview);
        findViewById(R.id.pickFile).setEnabled(!busy);
        findViewById(R.id.scan).setEnabled(!busy && !ble.isReady());
        findViewById(R.id.connect).setEnabled(!busy && !ble.isReady());
        findViewById(R.id.clearPending).setEnabled(needsReview && !busy);
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
            else client = null;
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
                runOnUiThread(() -> { if (client == next && ble.isReady()) setProtocolReady(true); });
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
    @Override protected void onStop() {
        super.onStop();
        // Keep a system file picker usable; other background exits disconnect.
        if (!isChangingConfigurations() && !pickingFile) ble.disconnect();
    }
}
