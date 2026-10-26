package com.keyi.xinxian.guitar;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Queue;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

/** Nordic-UART-compatible BLE link used by the BL616 transparent bridge. */
public final class BleUartClient {
    public static final UUID SERVICE_UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
    public static final UUID RX_UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
    public static final UUID TX_UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
    private static final UUID CCC_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

    public interface Listener {
        void onDeviceFound(BluetoothDevice device, String label);
        void onState(String state, boolean ready);
        void onBytes(byte[] value);
        void onLog(String message);
    }

    private final Context context;
    private final Listener listener;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable stopScanTask = this::stopScan;
    private final BluetoothAdapter adapter;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic rx;
    private int mtu = 23;
    private boolean ready;
    private final Queue<byte[]> chunks = new ArrayDeque<>();
    private CompletableFuture<Void> pendingWrite;

    public BleUartClient(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
        BluetoothManager manager = context.getSystemService(BluetoothManager.class);
        adapter = manager == null ? null : manager.getAdapter();
    }

    public boolean isBluetoothEnabled() { return adapter != null && adapter.isEnabled(); }
    public boolean isReady() { return ready; }

    @SuppressLint("MissingPermission")
    public void startScan() {
        if (!isBluetoothEnabled()) {
            listener.onState("请先打开手机蓝牙", false);
            return;
        }
        stopScan();
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            listener.onState("无法启动 BLE 扫描", false);
            return;
        }
        listener.onState("正在扫描附近 BLE 设备…", false);
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build();
        scanner.startScan(null, settings, scanCallback);
        handler.postDelayed(stopScanTask, 12_000);
    }

    @SuppressLint("MissingPermission")
    public void stopScan() {
        handler.removeCallbacks(stopScanTask);
        if (scanner != null) {
            try { scanner.stopScan(scanCallback); } catch (RuntimeException ignored) {}
        }
        scanner = null;
    }

    @SuppressLint("MissingPermission")
    public void connect(BluetoothDevice device) {
        stopScan();
        disconnect();
        ready = false;
        listener.onState("正在连接 " + safeName(device) + "…", false);
        gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
    }

    @SuppressLint("MissingPermission")
    public void disconnect() {
        ready = false;
        failWrite(new IllegalStateException("BLE 已断开"));
        if (gatt != null) {
            try { gatt.disconnect(); } catch (RuntimeException ignored) {}
            gatt.close();
            gatt = null;
        }
        rx = null;
    }

    public synchronized CompletableFuture<Void> write(byte[] value) {
        if (!ready || gatt == null || rx == null) {
            return failedFuture(new IllegalStateException("BLE 串口尚未就绪"));
        }
        if (pendingWrite != null) {
            return failedFuture(new IllegalStateException("上一次 BLE 写入尚未完成"));
        }
        pendingWrite = new CompletableFuture<>();
        int size = Math.max(20, Math.min(244, mtu - 3));
        for (int offset = 0; offset < value.length; offset += size) {
            chunks.add(Arrays.copyOfRange(value, offset, Math.min(value.length, offset + size)));
        }
        writeNext();
        return pendingWrite;
    }

    @SuppressLint("MissingPermission")
    private synchronized void writeNext() {
        if (gatt == null || rx == null) {
            failWrite(new IllegalStateException("BLE 已断开"));
            return;
        }
        byte[] chunk = chunks.peek();
        if (chunk == null) {
            CompletableFuture<Void> done = pendingWrite;
            pendingWrite = null;
            if (done != null) done.complete(null);
            return;
        }
        int properties = rx.getProperties();
        int type = (properties & BluetoothGattCharacteristic.PROPERTY_WRITE) != 0
                ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        boolean started;
        if (Build.VERSION.SDK_INT >= 33) {
            started = gatt.writeCharacteristic(rx, chunk, type) == BluetoothGatt.GATT_SUCCESS;
        } else {
            rx.setWriteType(type);
            rx.setValue(chunk);
            started = gatt.writeCharacteristic(rx);
        }
        if (!started) failWrite(new IllegalStateException("BLE 写入未启动"));
    }

    private synchronized void failWrite(Throwable error) {
        chunks.clear();
        CompletableFuture<Void> failed = pendingWrite;
        pendingWrite = null;
        if (failed != null) failed.completeExceptionally(error);
    }

    private static CompletableFuture<Void> failedFuture(Throwable error) {
        CompletableFuture<Void> future = new CompletableFuture<>();
        future.completeExceptionally(error);
        return future;
    }

    @SuppressLint("MissingPermission")
    private void enableNotifications(BluetoothGatt activeGatt) {
        BluetoothGattService service = activeGatt.getService(SERVICE_UUID);
        if (service == null) {
            listener.onState("设备没有 NUS 串口服务", false);
            return;
        }
        rx = service.getCharacteristic(RX_UUID);
        BluetoothGattCharacteristic tx = service.getCharacteristic(TX_UUID);
        if (rx == null || tx == null || !activeGatt.setCharacteristicNotification(tx, true)) {
            listener.onState("设备的 NUS 收发特征不完整", false);
            return;
        }
        BluetoothGattDescriptor ccc = tx.getDescriptor(CCC_UUID);
        if (ccc == null) {
            listener.onState("设备缺少通知描述符", false);
            return;
        }
        boolean started;
        if (Build.VERSION.SDK_INT >= 33) {
            started = activeGatt.writeDescriptor(ccc, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    == BluetoothGatt.GATT_SUCCESS;
        } else {
            ccc.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            started = activeGatt.writeDescriptor(ccc);
        }
        if (!started) listener.onState("无法订阅串口通知", false);
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override public void onScanResult(int callbackType, ScanResult result) {
            BluetoothDevice device = result.getDevice();
            // The device cache can still be unnamed (or retain an old firmware
            // name). Prefer the name carried by this advertisement.
            String name = result.getScanRecord() == null
                    ? null : result.getScanRecord().getDeviceName();
            if (name == null || name.trim().isEmpty()) name = safeName(device);
            boolean nus = result.getScanRecord() != null
                    && result.getScanRecord().getServiceUuids() != null
                    && result.getScanRecord().getServiceUuids().stream()
                    .anyMatch(uuid -> SERVICE_UUID.equals(uuid.getUuid()));
            // Keep unnamed/non-NUS devices visible during board diagnosis.
            listener.onDeviceFound(device, name + "  " + device.getAddress()
                    + (nus ? "  [BLE 串口]" : ""));
        }

        @Override public void onScanFailed(int errorCode) {
            listener.onState("BLE 扫描失败：" + errorCode, false);
        }
    };

    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        @Override public void onConnectionStateChange(BluetoothGatt active, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                listener.onState("已连接，正在发现串口服务…", false);
                active.discoverServices();
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                ready = false;
                failWrite(new IllegalStateException("BLE 已断开"));
                listener.onState("连接已断开（状态 " + status + "）", false);
            }
        }

        @SuppressLint("MissingPermission")
        @Override public void onServicesDiscovered(BluetoothGatt active, int status) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                listener.onState("发现服务失败：" + status, false);
            } else if (!active.requestMtu(247)) {
                enableNotifications(active);
            }
        }

        @Override public void onMtuChanged(BluetoothGatt active, int value, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) mtu = value;
            enableNotifications(active);
        }

        @Override public void onDescriptorWrite(BluetoothGatt active, BluetoothGattDescriptor descriptor, int status) {
            if (CCC_UUID.equals(descriptor.getUuid()) && status == BluetoothGatt.GATT_SUCCESS) {
                ready = true;
                listener.onState("BLE 串口已就绪", true);
            } else {
                listener.onState("订阅串口通知失败：" + status, false);
            }
        }

        @Override public void onCharacteristicChanged(BluetoothGatt active, BluetoothGattCharacteristic characteristic) {
            listener.onBytes(characteristic.getValue());
        }

        @Override public void onCharacteristicChanged(BluetoothGatt active,
                                                        BluetoothGattCharacteristic characteristic,
                                                        byte[] value) {
            listener.onBytes(Arrays.copyOf(value, value.length));
        }

        @Override public void onCharacteristicWrite(BluetoothGatt active,
                                                     BluetoothGattCharacteristic characteristic, int status) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failWrite(new IllegalStateException("BLE 写入失败：" + status));
                return;
            }
            synchronized (BleUartClient.this) { chunks.poll(); }
            writeNext();
        }
    };

    @SuppressLint("MissingPermission")
    private static String safeName(BluetoothDevice device) {
        try {
            String name = device.getName();
            return name == null || name.trim().isEmpty() ? "未命名设备" : name;
        } catch (SecurityException ignored) {
            return "未命名设备";
        }
    }
}
