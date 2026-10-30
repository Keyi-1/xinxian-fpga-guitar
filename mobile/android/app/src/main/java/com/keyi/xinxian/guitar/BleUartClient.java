package com.keyi.xinxian.guitar;

import android.annotation.SuppressLint;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Queue;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

/** Main-looper-owned serial state; worker threads receive stable futures. */
@SuppressLint("MissingPermission")
public final class BleUartClient {
    public static final UUID SERVICE_UUID=BleSerialProfile.NUS.service;
    public static final UUID RX_UUID=BleSerialProfile.NUS.write;
    public static final UUID TX_UUID=BleSerialProfile.NUS.notify;
    private static final UUID CCC_UUID=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    public interface Listener {
        void onDeviceFound(BluetoothDevice device,String label);
        void onState(String state,boolean ready);
        void onBytes(byte[] value);
        void onLog(String message);
    }
    private final Context context;
    private final Listener listener;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final BluetoothAdapter adapter;
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic rx,tx;
    private BleSerialProfile profile;
    private volatile boolean ready;
    private volatile int generation;
    private long reconnectAfter,writeStarted;
    private boolean waitingWrite;
    private final Queue<byte[]> chunks=new ArrayDeque<>();
    private CompletableFuture<Void> pendingWrite;
    private final Runnable stopScanTask=this::stopScan;

    public BleUartClient(Context context,Listener listener) {
        this.context=context.getApplicationContext();this.listener=listener;
        BluetoothManager manager=context.getSystemService(BluetoothManager.class);
        adapter=manager==null?null:manager.getAdapter();
    }
    private void onMain(Runnable action) {
        if(Looper.myLooper()==handler.getLooper())action.run();else handler.post(action);
    }
    public boolean isBluetoothEnabled(){return adapter!=null&&adapter.isEnabled();}
    public boolean isReady(){return ready;}
    public int connectionGeneration(){return generation;}
    public void startScan(){onMain(()->{
        if(!isBluetoothEnabled()){listener.onState("请先打开手机蓝牙",false);return;}
        if(gatt!=null){listener.onLog("请先断开当前设备再扫描");return;}
        stopScan();scanner=adapter.getBluetoothLeScanner();
        if(scanner==null){listener.onState("无法启动 BLE 扫描",false);return;}
        listener.onState("正在扫描，选择 JDY-23 或 XINXIAN-JDY23…",false);
        try {
            scanner.startScan(null,new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scanCallback);
            handler.postDelayed(stopScanTask,12000);
        }catch(RuntimeException e){stopScan();listener.onState("扫描失败："+e.getMessage(),false);}
    });}
    public void stopScan(){onMain(()->{
        handler.removeCallbacks(stopScanTask);
        if(scanner!=null)try{scanner.stopScan(scanCallback);}catch(RuntimeException ignored){}
        scanner=null;
    });}
    public void connect(BluetoothDevice device){onMain(()->{
        stopScan();closeLink();int expected=generation;
        long delay=Math.max(0,reconnectAfter-SystemClock.elapsedRealtime());
        listener.onState(delay>0?"等待旧串口事务结束，再连接…":"正在连接 "+safeName(device)+"…",false);
        handler.postDelayed(()->{
            if(expected!=generation)return;
            try {
                gatt=device.connectGatt(context,false,callback,BluetoothDevice.TRANSPORT_LE);
                if(gatt==null){failLink("无法创建 BLE 连接");return;}
                BluetoothGatt active=gatt;
                handler.postDelayed(()->{if(active==gatt&&!ready)failLink("连接或订阅超时，请确认模块未被其他手机占用");},12000);
            }catch(RuntimeException e){failLink("连接失败："+e.getMessage());}
        },delay);
    });}
    public void disconnect(){onMain(()->{stopScan();closeLink();listener.onState("已断开蓝牙",false);});}
    private void closeLink(){
        generation++;ready=false;failWrite(new IllegalStateException("BLE 已断开"));
        BluetoothGatt old=gatt;gatt=null;rx=tx=null;profile=null;
        if(old!=null){
            reconnectAfter=SystemClock.elapsedRealtime()+6000;
            try{old.disconnect();}catch(RuntimeException ignored){}
            old.close();
        }
    }
    private void failLink(String message){closeLink();listener.onState(message,false);}

    public CompletableFuture<Void> write(byte[] value){
        CompletableFuture<Void> result=new CompletableFuture<>();
        if(value==null||value.length!=32){
            result.completeExceptionally(new IllegalArgumentException("仅接受完整的32字节 XG3 帧"));return result;
        }
        byte[] copy=Arrays.copyOf(value,value.length);
        onMain(()->{
            if(!ready||gatt==null||rx==null){result.completeExceptionally(new IllegalStateException("BLE 串口尚未就绪"));return;}
            if(pendingWrite!=null){result.completeExceptionally(new IllegalStateException("上一次 BLE 写入尚未完成"));return;}
            pendingWrite=result;
            for(int offset=0;offset<copy.length;offset+=BleSerialProfile.CHUNK_BYTES)
                chunks.add(Arrays.copyOfRange(copy,offset,Math.min(copy.length,offset+BleSerialProfile.CHUNK_BYTES)));
            handler.postDelayed(()->{if(pendingWrite==result)failLink("BLE 写入超时，连接已关闭");},2500);
            writeNext();
        });
        return result;
    }
    private void writeNext(){
        if(gatt==null||rx==null||pendingWrite==null||waitingWrite)return;
        byte[] chunk=chunks.peek();
        if(chunk==null){CompletableFuture<Void> done=pendingWrite;pendingWrite=null;done.complete(null);return;}
        waitingWrite=true;writeStarted=SystemClock.elapsedRealtime();
        int type=(rx.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE)!=0
            ?BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT:BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        try{
            boolean started;
            if(Build.VERSION.SDK_INT>=33)started=gatt.writeCharacteristic(rx,chunk,type)==BluetoothGatt.GATT_SUCCESS;
            else{rx.setWriteType(type);rx.setValue(chunk);started=gatt.writeCharacteristic(rx);}
            if(!started)failLink("BLE 写入未启动，连接已关闭");
        }catch(RuntimeException e){failLink("BLE 写入失败："+e.getMessage());}
    }
    private void failWrite(Throwable error){
        waitingWrite=false;chunks.clear();CompletableFuture<Void> failed=pendingWrite;pendingWrite=null;
        if(failed!=null)failed.completeExceptionally(error);
    }
    private void enableNotifications(BluetoothGatt active){
        BluetoothGattService service=active.getService(BleSerialProfile.JDY23.service);
        profile=service==null?BleSerialProfile.NUS:BleSerialProfile.JDY23;
        if(service==null)service=active.getService(profile.service);
        if(service==null){failLink("设备没有 JDY-23 FFE0 或兼容串口服务");return;}
        rx=service.getCharacteristic(profile.write);tx=service.getCharacteristic(profile.notify);
        int writes=BluetoothGattCharacteristic.PROPERTY_WRITE|BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE;
        if(rx==null||tx==null||(rx.getProperties()&writes)==0||(tx.getProperties()&BluetoothGattCharacteristic.PROPERTY_NOTIFY)==0){
            failLink("设备的串口读写/通知特征不完整");return;
        }
        BluetoothGattDescriptor ccc=tx.getDescriptor(CCC_UUID);
        if(ccc==null||!active.setCharacteristicNotification(tx,true)){failLink("无法订阅串口通知");return;}
        boolean started;
        if(Build.VERSION.SDK_INT>=33)started=active.writeDescriptor(ccc,BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)==BluetoothGatt.GATT_SUCCESS;
        else{ccc.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);started=active.writeDescriptor(ccc);}
        if(!started)failLink("通知订阅未启动");
    }
    private final ScanCallback scanCallback=new ScanCallback(){
        @Override public void onScanResult(int type,ScanResult result){onMain(()->{
            if(scanner==null)return;
            BluetoothDevice device=result.getDevice();
            String name=result.getScanRecord()==null?null:result.getScanRecord().getDeviceName();
            if(name==null||name.trim().isEmpty())name=safeName(device);
            String label="";
            if(result.getScanRecord()!=null&&result.getScanRecord().getServiceUuids()!=null)
                for(android.os.ParcelUuid uuid:result.getScanRecord().getServiceUuids()){
                    BleSerialProfile found=BleSerialProfile.fromService(uuid.getUuid());
                    if(found!=null){label="  ["+found.label+" 串口]";break;}
                }
            listener.onDeviceFound(device,name+"  "+device.getAddress()+label);
        });}
        @Override public void onScanFailed(int code){onMain(()->{stopScan();listener.onState("BLE 扫描失败："+code,false);});}
    };
    private final BluetoothGattCallback callback=new BluetoothGattCallback(){
        @Override public void onConnectionStateChange(BluetoothGatt active,int status,int state){onMain(()->{
            if(active!=gatt)return;
            if(status!=BluetoothGatt.GATT_SUCCESS||state==BluetoothProfile.STATE_DISCONNECTED){failLink("连接已断开（状态 "+status+"）");return;}
            if(state==BluetoothProfile.STATE_CONNECTED){
                listener.onState("已连接，正在发现串口服务…",false);
                if(!active.discoverServices())failLink("服务发现未启动");
            }
        });}
        @Override public void onServicesDiscovered(BluetoothGatt active,int status){onMain(()->{
            if(active!=gatt)return;
            if(status!=BluetoothGatt.GATT_SUCCESS){failLink("发现服务失败："+status);return;}
            // Fixed 20-byte chunks need no MTU exchange and fit JDY defaults.
            try{enableNotifications(active);}catch(RuntimeException e){failLink("服务订阅失败："+e.getMessage());}
        });}
        @Override public void onDescriptorWrite(BluetoothGatt active,BluetoothGattDescriptor descriptor,int status){onMain(()->{
            if(active!=gatt||tx==null||descriptor!=tx.getDescriptor(CCC_UUID))return;
            if(status!=BluetoothGatt.GATT_SUCCESS){failLink("订阅串口通知失败："+status);return;}
            if(!ready){ready=true;listener.onState(profile.label+" 串口已就绪",true);}
        });}
        @Override public void onCharacteristicChanged(BluetoothGatt active,BluetoothGattCharacteristic characteristic){
            byte[] value=characteristic.getValue();
            deliver(active,characteristic,value==null?new byte[0]:Arrays.copyOf(value,value.length));
        }
        @Override public void onCharacteristicChanged(BluetoothGatt active,BluetoothGattCharacteristic characteristic,byte[] value){
            deliver(active,characteristic,Arrays.copyOf(value,value.length));
        }
        @Override public void onCharacteristicWrite(BluetoothGatt active,BluetoothGattCharacteristic characteristic,int status){onMain(()->{
            if(active!=gatt||characteristic!=rx||pendingWrite==null||!waitingWrite)return;
            if(status!=BluetoothGatt.GATT_SUCCESS){failLink("BLE 写入失败："+status);return;}
            waitingWrite=false;chunks.poll();CompletableFuture<Void> expected=pendingWrite;
            handler.postDelayed(()->{if(active==gatt&&expected==pendingWrite)writeNext();},
                Math.max(0,BleSerialProfile.CHUNK_INTERVAL_MS-(SystemClock.elapsedRealtime()-writeStarted)));
        });}
    };
    private void deliver(BluetoothGatt active,BluetoothGattCharacteristic characteristic,byte[] value){
        onMain(()->{if(active==gatt&&characteristic==tx&&ready&&value.length>0)listener.onBytes(value);});
    }
    private static String safeName(BluetoothDevice device){
        try{String name=device.getName();return name==null||name.trim().isEmpty()?"未命名设备":name;}
        catch(SecurityException ignored){return "未命名设备";}
    }
}
