package com.keyi.xinxian.guitar;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothDevice;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.ArrayAdapter;
import android.widget.Toast;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity implements BleUartClient.Listener {
    private static final int REQUEST_BLE=20, PICK_SONG=21;
    private CompanionUi ui;
    private ArrayAdapter<String> deviceAdapter;
    private final Map<String,BluetoothDevice> devices=new LinkedHashMap<>();
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private BleUartClient ble;
    private volatile Xg3Client client;
    private Xg3Protocol.Song song;
    private Xg3Client.Capabilities capabilities;
    private final Xg3Protocol.SlotDescriptor[] descriptors=new Xg3Protocol.SlotDescriptor[5];
    private int selectedSlot=3, selectedTimbre=1, selectedBuiltin=-1;
    private String songTitle="", selectedUri;
    private boolean protocolReady, busy, pickingFile, closed;
    private volatile boolean needsReview;
    private SharedPreferences commitJournal, preferences;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        ui=new CompanionUi(this);installSafeArea();
        preferences=getSharedPreferences("companion_ui",MODE_PRIVATE);
        commitJournal=getSharedPreferences("jdy23_commit_journal",MODE_PRIVATE);
        needsReview=commitJournal.contains("pending");ble=new BleUartClient(this,this);
        deviceAdapter=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,new ArrayList<>());
        ui.devices.setAdapter(deviceAdapter);
        ui.scan.setOnClickListener(v->ensurePermissionAndScan());ui.connect.setOnClickListener(v->connectSelected());
        ui.disconnect.setOnClickListener(v->ble.disconnect());ui.query.setOnClickListener(v->querySlots());
        ui.pick.setOnClickListener(v->pickSong());ui.upload.setOnClickListener(v->confirmUpload());
        for(int i=0;i<3;i++) { final int index=i;
            ui.songs[i].setOnClickListener(v->loadBuiltin(index));
            ui.timbres[i].setOnClickListener(v->{ selectedTimbre=index;refreshActions(); });
        }
        for(int i=0;i<5;i++) { final int index=i;ui.slots[i].setOnClickListener(v->{ selectedSlot=index;refreshActions(); }); }
        ui.animation.setChecked(preferences.getBoolean("notes",true));
        ui.animation.setOnCheckedChangeListener((button,value)->{ preferences.edit().putBoolean("notes",value).apply();refreshActions(); });
        ui.review.setOnClickListener(v->new AlertDialog.Builder(this).setTitle("核对上次提交")
            .setMessage("请先连接并刷新槽位，在乐器上试听确认曲目。目录条数一致不能证明内容相同。")
            .setNegativeButton("返回",null).setPositiveButton("我已核对",(dialog,which)->{
                if(commitJournal.edit().remove("pending").commit()) { needsReview=false;append("已核对上次提交");refreshActions(); }
                else toast("未能保存核对结果，请重试");
            }).show());
        if(state!=null) {
            selectedSlot=Math.max(0,Math.min(4,state.getInt("slot",3)));selectedTimbre=Math.max(0,Math.min(2,state.getInt("timbre",1)));
            ui.show(Math.max(0,Math.min(3,state.getInt("page",0))));
            int builtin=state.getInt("builtin",-1);String uri=state.getString("uri");
            if(builtin>=0&&builtin<3)loadBuiltin(builtin);else if(uri!=null)loadPhone(Uri.parse(uri));
        }
        refreshActions();
    }
    private void installSafeArea() {
        if(Build.VERSION.SDK_INT>=30)getWindow().setDecorFitsSystemWindows(false);
        else getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        getWindow().setStatusBarColor(android.graphics.Color.TRANSPARENT);getWindow().setNavigationBarColor(android.graphics.Color.TRANSPARENT);
        if(Build.VERSION.SDK_INT>=29)getWindow().setNavigationBarContrastEnforced(false);
        if(Build.VERSION.SDK_INT>=30&&getWindow().getInsetsController()!=null)
            getWindow().getInsetsController().setSystemBarsAppearance(0,WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        ui.safe.setOnApplyWindowInsetsListener((view,insets)->{
            int left,top,right,bottom;
            if(Build.VERSION.SDK_INT>=30) {
                Insets bars=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
                left=bars.left;top=bars.top;right=bars.right;bottom=bars.bottom;
            } else {
                left=insets.getSystemWindowInsetLeft();top=insets.getSystemWindowInsetTop();right=insets.getSystemWindowInsetRight();bottom=insets.getSystemWindowInsetBottom();
                if(Build.VERSION.SDK_INT>=28&&insets.getDisplayCutout()!=null) {
                    left=Math.max(left,insets.getDisplayCutout().getSafeInsetLeft());top=Math.max(top,insets.getDisplayCutout().getSafeInsetTop());
                    right=Math.max(right,insets.getDisplayCutout().getSafeInsetRight());bottom=Math.max(bottom,insets.getDisplayCutout().getSafeInsetBottom());
                }
            }
            view.setPadding(left,top,right,bottom);return insets;
        });ui.safe.requestApplyInsets();
    }
    private void ensurePermissionAndScan() {
        String[] wanted=Build.VERSION.SDK_INT>=31?new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
        List<String> missing=new ArrayList<>();for(String permission:wanted)if(checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)missing.add(permission);
        if(!missing.isEmpty()) { requestPermissions(missing.toArray(new String[0]),REQUEST_BLE);return; }
        devices.clear();deviceAdapter.clear();append("正在扫描附近的蓝牙乐器…");ble.startScan();
    }
    @Override public void onRequestPermissionsResult(int code,String[] permissions,int[] results) {
        super.onRequestPermissionsResult(code,permissions,results);if(code!=REQUEST_BLE||results.length==0)return;
        for(int result:results)if(result!=PackageManager.PERMISSION_GRANTED) { toast("连接乐器需要蓝牙权限");return; }ensurePermissionAndScan();
    }
    private void connectSelected() {
        Object selected=ui.devices.getSelectedItem();if(selected==null||!devices.containsKey(selected.toString())) { toast("请先扫描并选择乐器");return; }
        protocolReady=false;refreshActions();ble.connect(devices.get(selected.toString()));
    }
    private void pickSong() {
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);pickingFile=true;startActivityForResult(intent,PICK_SONG);
    }
    @Override protected void onActivityResult(int request,int result,Intent data) {
        super.onActivityResult(request,result,data);if(request==PICK_SONG)pickingFile=false;
        if(request!=PICK_SONG||result!=RESULT_OK||data==null||data.getData()==null)return;Uri uri=data.getData();
        try { getContentResolver().takePersistableUriPermission(uri,data.getFlags()&Intent.FLAG_GRANT_READ_URI_PERMISSION); }catch(SecurityException ignored) {}
        loadPhone(uri);
    }
    private interface SongReader { Xg3Protocol.Song read() throws Exception; }
    private void loadBuiltin(int index) {
        ScoreLibrary.Entry entry=ScoreLibrary.ENTRIES[index];
        loadSong(entry.title,index,null,()->{ try(InputStream in=getAssets().open("scores/"+entry.file)) { return entry.read(in); } });
    }
    private void loadPhone(Uri uri) {
        loadSong("手机曲谱.bin",-1,uri.toString(),()->{ try(InputStream in=getContentResolver().openInputStream(uri)) { return ScoreLibrary.read(in); } });
    }
    private void loadSong(String title,int builtin,String uri,SongReader reader) {
        if(busy)return;setBusy(true);
        worker.execute(()->{
            try {
                Xg3Protocol.Song parsed=reader.read();String resolvedTitle=uri==null?title:displayName(Uri.parse(uri));runOnUiThread(()->{
                    if(closed)return;song=parsed;songTitle=resolvedTitle;selectedBuiltin=builtin;selectedUri=uri;
                    String subtitle=(builtin>=0?ScoreLibrary.ENTRIES[builtin].bpm+" BPM · ":"")+ScoreLibrary.duration(parsed.durationSamples)+" · "+parsed.events.size()+"个音符事件";
                    ui.fileName.setText(resolvedTitle+"\n"+subtitle);ui.uploadSong.setText(resolvedTitle+"\n"+subtitle);ui.setResult("");append("曲谱校验通过："+resolvedTitle);setBusy(false);
                });
            } catch(Exception error) { runOnUiThread(()->{
                if(closed)return;song=null;selectedBuiltin=-1;selectedUri=null;songTitle="";
                ui.fileName.setText("曲谱不可用："+message(error));ui.uploadSong.setText("请重新选择曲谱");append("曲谱读取失败："+message(error));setBusy(false);toast("曲谱格式或内容不符合要求");
            }); }
        });
    }
    private void querySlots() {
        Xg3Client active=client;if(!protocolReady||active==null||busy)return;setBusy(true);
        worker.execute(()->{
            try {
                Xg3Protocol.SlotDescriptor[] values=new Xg3Protocol.SlotDescriptor[5];for(int i=0;i<5;i++)values[i]=active.listSlot(i);
                runOnUiThread(()->{ if(!closed&&client==active) { System.arraycopy(values,0,descriptors,0,5);append("五个槽位已刷新");refreshActions(); } });
            } catch(Exception error) { appendFromWorker("查询失败："+message(error)); }
            finally { runOnUiThread(()->{ if(!closed)setBusy(false); }); }
        });
    }
    private void confirmUpload() {
        if(!protocolReady||song==null||busy||needsReview)return;
        final int slot=selectedSlot,timbre=selectedTimbre;final Xg3Protocol.Song selected=song;
        new AlertDialog.Builder(this).setTitle("确认上传")
            .setMessage(songTitle+"\n第"+(slot+1)+"槽 · "+ScoreLibrary.timbre(timbre)+"\n\n将替换该槽的运行时曲谱。请让乐器停留在主页或选曲页，并保持供电。")
            .setNegativeButton("取消",null).setPositiveButton("上传",(dialog,which)->uploadSong(slot,timbre,selected)).show();
    }
    private void uploadSong(int slot,int timbre,Xg3Protocol.Song selected) {
        Xg3Client active=client;if(!protocolReady||active==null||busy||needsReview)return;
        if(capabilities!=null&&selected.events.size()>capabilities.capacity-capabilities.reservedRecords) { ui.setResult("曲谱超过设备可导入容量");return; }
        setBusy(true);ui.progress.setVisibility(View.VISIBLE);ui.progressText.setVisibility(View.VISIBLE);ui.progress.setProgress(0);ui.progressText.setText("准备上传…");ui.setResult("");
        worker.execute(()->{
            try {
                Xg3Protocol.SlotDescriptor result=active.upload(slot,timbre,selected,
                    (done,total)->runOnUiThread(()->{ if(!closed) { ui.progress.setProgress(done*100/total);ui.progressText.setText(done+" / "+total+" 个事件"); } }),
                    new Xg3Client.CommitJournal() {
                        @Override public void beforeCommit(int target,Xg3Protocol.Song value) throws Exception {
                            String record="第"+(target+1)+"槽，"+value.events.size()+"事件，CRC32 "+Long.toHexString(value.crc32);needsReview=true;
                            if(!commitJournal.edit().putString("pending",record).commit())throw new IllegalStateException("未能保存提交标记，尚未发送 COMMIT");
                        }
                        @Override public void confirmed() throws Exception {
                            if(!commitJournal.edit().remove("pending").commit())throw new IllegalStateException("无法清除提交标记");needsReview=false;
                        }
                    });
                runOnUiThread(()->{ if(!closed) { if(client==active)descriptors[slot]=result;ui.setResult("上传成功，请在乐器上选择 USER "+(slot+1));append("上传完成，已核对设备返回的曲谱信息"); } });
            } catch(Exception error) { runOnUiThread(()->{ if(!closed) { ui.setResult(message(error));append("上传状态："+message(error)); } }); }
            finally { runOnUiThread(()->{ if(!closed)setBusy(false); }); }
        });
    }
    private void setBusy(boolean value) { busy=value;refreshActions(); }
    private void refreshActions() {
        if(closed)return;ui.query.setEnabled(protocolReady&&!busy);ui.upload.setEnabled(protocolReady&&song!=null&&!busy&&!needsReview);
        ui.configure.setEnabled(song!=null&&!busy);ui.pick.setEnabled(!busy);ui.scan.setEnabled(!busy&&!ble.isReady());ui.connect.setEnabled(!busy&&!ble.isReady());
        ui.disconnect.setEnabled(ble.isReady()||client!=null);ui.devices.setEnabled(!busy&&!ble.isReady());ui.review.setEnabled(needsReview&&!busy);
        ui.pending.setText(needsReview?"上次提交结果待核对："+commitJournal.getString("pending",""):"没有待核对的上传");
        for(android.widget.Button button:ui.songs)button.setEnabled(!busy);for(android.widget.Button button:ui.slots)button.setEnabled(!busy);for(android.widget.Button button:ui.timbres)button.setEnabled(!busy);
        ui.upload.setAlpha(ui.upload.isEnabled()?1f:.45f);ui.configure.setAlpha(ui.configure.isEnabled()?1f:.45f);
        ui.selected(selectedBuiltin,selectedSlot,selectedTimbre,descriptors);ui.backdrop.animateNotes(ui.animation.isChecked()&&!busy);
        if(needsReview&&ui.page()==CompanionUi.UPLOAD)ui.setResult("上次提交结果待核对，请到设置页面处理。");
    }
    private String displayName(Uri uri) {
        try(android.database.Cursor cursor=getContentResolver().query(uri,null,null,null,null)) {
            if(cursor!=null&&cursor.moveToFirst()) { int index=cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(index>=0)return cursor.getString(index); }
        } catch(Exception ignored) {}return "手机曲谱.bin";
    }
    @Override public void onDeviceFound(BluetoothDevice device,String label) { runOnUiThread(()->{ if(!closed&&!devices.containsKey(label)) { devices.put(label,device);deviceAdapter.add(label); } }); }
    @Override public void onState(String text,boolean ready) {
        runOnUiThread(()->{
            if(closed)return;ui.connection.setText(text);ui.status.setText(ready?"○ 正在握手":"○ 未连接");append(text);protocolReady=false;capabilities=null;
            for(int i=0;i<descriptors.length;i++)descriptors[i]=null;if(ready)beginProtocolSession();else client=null;refreshActions();
        });
    }
    private void beginProtocolSession() {
        Xg3Client next=new Xg3Client(ble);client=next;
        worker.execute(()->{
            try {
                Xg3Client.Capabilities caps=next.hello();runOnUiThread(()->{
                    if(closed||client!=next||!ble.isReady())return;capabilities=caps;protocolReady=true;ui.status.setText("● 蓝牙已连接");
                    ui.capacity.setText("五槽共享 "+(caps.capacity-caps.reservedRecords)+" 个导入事件\n连接后曲谱仅保存在设备 RAM 中");append("乐器已就绪");refreshActions();querySlots();
                });
            } catch(Exception error) { runOnUiThread(()->{ if(!closed&&client==next) { ui.status.setText("○ 握手失败");append("设备握手失败："+message(error)); } }); }
        });
    }
    @Override public void onBytes(byte[] value) { Xg3Client active=client;if(active!=null)active.accept(value); }
    @Override public void onLog(String message) { appendFromWorker(message); }
    private void appendFromWorker(String message) { runOnUiThread(()->{ if(!closed)append(message); }); }
    private void append(String message) {
        String previous=ui.log.getText().toString();if(previous.equals("等待操作…"))previous="";String next=(previous.isEmpty()?"":previous+"\n")+message;
        ui.log.setText(next.length()>10000?next.substring(next.length()-10000):next);
    }
    private void toast(String message) { Toast.makeText(this,message,Toast.LENGTH_SHORT).show(); }
    private static String message(Throwable error) { return error.getMessage()==null?error.getClass().getSimpleName():error.getMessage(); }
    @Override protected void onSaveInstanceState(Bundle state) {
        state.putInt("slot",selectedSlot);state.putInt("timbre",selectedTimbre);state.putInt("page",ui.page());state.putInt("builtin",selectedBuiltin);state.putString("uri",selectedUri);super.onSaveInstanceState(state);
    }
    @Override protected void onResume() { super.onResume();if(ui!=null)ui.backdrop.setActive(true); }
    @Override protected void onStop() { if(ui!=null)ui.backdrop.setActive(false);super.onStop();if(!isChangingConfigurations()&&!pickingFile)ble.disconnect(); }
    @Override protected void onDestroy() { closed=true;ble.disconnect();worker.shutdownNow();super.onDestroy(); }
    @Override public void onBackPressed() { if(ui.page()!=CompanionUi.LIBRARY)ui.show(CompanionUi.LIBRARY);else super.onBackPressed(); }
}
