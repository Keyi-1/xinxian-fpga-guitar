"""Execute actual BLE client with deterministic Android doubles, then XG3 journal failures."""
from pathlib import Path
import hashlib
import json
import subprocess

R=Path(__file__).resolve().parents[1]
E=R/'build/jdy23/v1/android_test'
APP=R/'mobile/android/app/src/main/java/com/keyi/xinxian/guitar'
J=Path('S:/AndroidSoftWare/JDK_Version/bin')
STUBS={
'android/annotation/SuppressLint.java':'package android.annotation; public @interface SuppressLint {String[] value();}',
'android/os/Looper.java':'package android.os; public class Looper {static final Looper MAIN=new Looper(); public static Looper getMainLooper(){return MAIN;} public static Looper myLooper(){return MAIN;}}',
'android/os/SystemClock.java':'package android.os; public class SystemClock {public static long elapsedRealtime(){return Handler.now;}}',
'android/os/Build.java':'package android.os; public class Build {public static class VERSION {public static int SDK_INT=35;}}',
'android/os/ParcelUuid.java':'package android.os; import java.util.UUID; public class ParcelUuid {UUID u;public ParcelUuid(UUID u){this.u=u;}public UUID getUuid(){return u;}}',
'android/os/Handler.java':'''package android.os; import java.util.*;
public class Handler {
 public static long now;static long serial;
 static class Job {long time,id;Runnable r;Job(long t,Runnable r){time=t;this.r=r;id=serial++;}}
 static PriorityQueue<Job> jobs=new PriorityQueue<>(Comparator.<Job>comparingLong(j->j.time).thenComparingLong(j->j.id));
 public Handler(Looper l){}public Looper getLooper(){return Looper.getMainLooper();}
 public boolean post(Runnable r){return postDelayed(r,0);}public boolean postDelayed(Runnable r,long delay){jobs.add(new Job(now+delay,r));return true;}
 public void removeCallbacks(Runnable r){jobs.removeIf(j->j.r==r);}
 public static void advance(long ms){long end=now+ms;while(!jobs.isEmpty()&&jobs.peek().time<=end){Job j=jobs.poll();now=j.time;j.r.run();}now=end;}
}''',
'android/content/Context.java':'''package android.content; import android.bluetooth.*;public class Context {
 public Context getApplicationContext(){return this;}public <T>T getSystemService(Class<T> c){return c.cast(new BluetoothManager());}}''',
'android/bluetooth/BluetoothManager.java':'package android.bluetooth;public class BluetoothManager {public BluetoothAdapter getAdapter(){return new BluetoothAdapter();}}',
'android/bluetooth/BluetoothAdapter.java':'package android.bluetooth;import android.bluetooth.le.*;public class BluetoothAdapter {public boolean isEnabled(){return true;}public BluetoothLeScanner getBluetoothLeScanner(){return new BluetoothLeScanner();}}',
'android/bluetooth/BluetoothProfile.java':'package android.bluetooth;public interface BluetoothProfile {int STATE_CONNECTED=2,STATE_DISCONNECTED=0;}',
'android/bluetooth/BluetoothDevice.java':'''package android.bluetooth; import android.content.Context;public class BluetoothDevice {
 public static final int TRANSPORT_LE=2;public BluetoothGatt last;public String kind="jdy";
 public String getName(){return "JDY-23";}public String getAddress(){return "01:02:03:04:05:06";}
 public BluetoothGatt connectGatt(Context c,boolean a,BluetoothGattCallback b,int t){last=new BluetoothGatt(b,kind);return last;}}''',
'android/bluetooth/BluetoothGattCharacteristic.java':'''package android.bluetooth;import java.util.*;public class BluetoothGattCharacteristic {
 public static final int PROPERTY_WRITE=8,PROPERTY_WRITE_NO_RESPONSE=4,PROPERTY_NOTIFY=16,WRITE_TYPE_DEFAULT=2,WRITE_TYPE_NO_RESPONSE=1;
 public UUID uuid;public int properties=24;public BluetoothGattDescriptor ccc=new BluetoothGattDescriptor();byte[] value;
 public BluetoothGattCharacteristic(UUID u){uuid=u;}public UUID getUuid(){return uuid;}public int getProperties(){return properties;}
 public BluetoothGattDescriptor getDescriptor(UUID u){return ccc;}public boolean setValue(byte[] v){value=v;return true;}public byte[] getValue(){return value;}
 public void setWriteType(int type){}
}''',
'android/bluetooth/BluetoothGattDescriptor.java':'package android.bluetooth;import java.util.*;public class BluetoothGattDescriptor {public static final byte[] ENABLE_NOTIFICATION_VALUE={1,0};public UUID getUuid(){return UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");}public boolean setValue(byte[] v){return true;}}',
'android/bluetooth/BluetoothGattService.java':'package android.bluetooth;import java.util.*;public class BluetoothGattService {public Map<UUID,BluetoothGattCharacteristic> chars=new HashMap<>();public BluetoothGattCharacteristic getCharacteristic(UUID u){return chars.get(u);}}',
'android/bluetooth/BluetoothGatt.java':'''package android.bluetooth;import java.util.*;import android.os.SystemClock;import com.keyi.xinxian.guitar.BleSerialProfile;
public class BluetoothGatt {
 public static final int GATT_SUCCESS=0;public BluetoothGattCallback cb;public boolean closed,reject,discoverReject;public int descriptorStatus;
 public List<byte[]> writes=new ArrayList<>();public List<Long> times=new ArrayList<>();public Map<UUID,BluetoothGattService> services=new HashMap<>();
 public BluetoothGattCharacteristic rx,tx;
 public BluetoothGatt(BluetoothGattCallback cb,String kind){this.cb=cb;if(kind.equals("none"))return;
  BleSerialProfile p=kind.equals("nus")?BleSerialProfile.NUS:BleSerialProfile.JDY23;
  BluetoothGattService s=new BluetoothGattService();rx=new BluetoothGattCharacteristic(p.write);
  tx=p.write.equals(p.notify)?rx:new BluetoothGattCharacteristic(p.notify);s.chars.put(p.write,rx);s.chars.put(p.notify,tx);services.put(p.service,s);
 }
 public void disconnect(){}public void close(){closed=true;}public boolean discoverServices(){return !discoverReject;}
 public BluetoothGattService getService(UUID u){return services.get(u);}public boolean setCharacteristicNotification(BluetoothGattCharacteristic c,boolean b){return true;}
 public int writeDescriptor(BluetoothGattDescriptor d,byte[] v){return descriptorStatus;}public boolean writeDescriptor(BluetoothGattDescriptor d){return descriptorStatus==0;}
 public int writeCharacteristic(BluetoothGattCharacteristic c,byte[] v,int t){if(reject)return 1;writes.add(Arrays.copyOf(v,v.length));times.add(SystemClock.elapsedRealtime());return 0;}
 public boolean writeCharacteristic(BluetoothGattCharacteristic c){return writeCharacteristic(c,c.getValue(),0)==0;}
}''',
'android/bluetooth/BluetoothGattCallback.java':'''package android.bluetooth;public class BluetoothGattCallback {
 public void onConnectionStateChange(BluetoothGatt g,int s,int n){}public void onServicesDiscovered(BluetoothGatt g,int s){}
 public void onDescriptorWrite(BluetoothGatt g,BluetoothGattDescriptor d,int s){}public void onCharacteristicWrite(BluetoothGatt g,BluetoothGattCharacteristic c,int s){}
 public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c){}public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c,byte[] b){}
}''',
'android/bluetooth/le/BluetoothLeScanner.java':'package android.bluetooth.le;public class BluetoothLeScanner {public void startScan(Object o,ScanSettings s,ScanCallback c){}public void stopScan(ScanCallback c){}}',
'android/bluetooth/le/ScanSettings.java':'package android.bluetooth.le;public class ScanSettings {public static final int SCAN_MODE_LOW_LATENCY=2;public static class Builder {public Builder setScanMode(int m){return this;}public ScanSettings build(){return new ScanSettings();}}}',
'android/bluetooth/le/ScanCallback.java':'package android.bluetooth.le;public class ScanCallback {public void onScanResult(int t,ScanResult r){}public void onScanFailed(int c){}}',
'android/bluetooth/le/ScanRecord.java':'package android.bluetooth.le;import java.util.*;import android.os.ParcelUuid;public class ScanRecord {public String getDeviceName(){return null;}public List<ParcelUuid> getServiceUuids(){return null;}}',
'android/bluetooth/le/ScanResult.java':'package android.bluetooth.le;import android.bluetooth.*;public class ScanResult {public BluetoothDevice getDevice(){return new BluetoothDevice();}public ScanRecord getScanRecord(){return null;}}',
}
BLE_TEST=r'''package com.keyi.xinxian.guitar;
import android.bluetooth.*;import android.content.Context;import android.os.*;import java.util.*;import java.util.concurrent.*;
public class BleProbe {
 static int bytes,readyCount;
 static BleUartClient client(){return new BleUartClient(new Context(),new BleUartClient.Listener(){
  public void onDeviceFound(BluetoothDevice d,String s){}public void onState(String s,boolean r){if(r)readyCount++;}
  public void onBytes(byte[] b){bytes+=b.length;}public void onLog(String s){}
 });}
 static BluetoothGatt setup(BleUartClient c,String kind){BluetoothDevice d=new BluetoothDevice();d.kind=kind;c.connect(d);Handler.advance(6000);
  BluetoothGatt g=d.last;g.cb.onConnectionStateChange(g,0,2);g.cb.onServicesDiscovered(g,0);
  assert !c.isReady();if(g.tx!=null)g.cb.onDescriptorWrite(g,g.tx.ccc,0);return g;
 }
 static void finish(BluetoothGatt g){g.cb.onCharacteristicWrite(g,g.rx,0);Handler.advance(35);g.cb.onCharacteristicWrite(g,g.rx,0);Handler.advance(35);}
 public static void main(String[] a)throws Exception {
  assert BleSerialProfile.JDY23.write.equals(BleSerialProfile.JDY23.notify);
  assert BleSerialProfile.fromService(UUID.fromString("0000ffe2-0000-1000-8000-00805f9b34fb"))==null;
  byte[] frame=new byte[32];for(int i=0;i<32;i++)frame[i]=(byte)(i*7);
  BleUartClient c=client();BluetoothGatt g=setup(c,"jdy");assert c.isReady();
  CompletableFuture<Void> f=c.write(frame);assert f!=null&&!f.isDone()&&g.writes.size()==1&&g.writes.get(0).length==20;
  g.cb.onCharacteristicWrite(g,g.rx,0);Handler.advance(34);assert g.writes.size()==1;
  Handler.advance(1);assert g.writes.size()==2&&g.writes.get(1).length==12&&g.times.get(1)-g.times.get(0)>=35;
  g.cb.onCharacteristicWrite(g,g.rx,0);Handler.advance(35);f.get();
  byte[] joined=new byte[32];System.arraycopy(g.writes.get(0),0,joined,0,20);System.arraycopy(g.writes.get(1),0,joined,20,12);assert Arrays.equals(joined,frame);
  g.cb.onCharacteristicChanged(g,new BluetoothGattCharacteristic(UUID.randomUUID()),frame);assert bytes==0;
  g.cb.onCharacteristicChanged(g,g.tx,Arrays.copyOf(frame,20));g.cb.onCharacteristicChanged(g,g.tx,new byte[12]);assert bytes==32;
  BluetoothGatt old=g;g=setup(c,"jdy");assert c.isReady();f=c.write(frame);
  old.cb.onConnectionStateChange(old,0,0);old.cb.onDescriptorWrite(old,old.tx.ccc,0);old.cb.onCharacteristicWrite(old,old.rx,0);old.cb.onCharacteristicChanged(old,old.tx,frame);
  assert c.isReady()&&!f.isDone()&&g.writes.size()==1&&bytes==32;finish(g);f.get();
  g.reject=true;f=c.write(frame);assert f!=null&&f.isCompletedExceptionally()&&g.closed&&!c.isReady();
  f=c.write(frame);assert f!=null&&f.isCompletedExceptionally();
  c=client();g=setup(c,"jdy");f=c.write(frame);Handler.advance(2500);assert f.isCompletedExceptionally()&&g.closed&&!c.isReady();
  Build.VERSION.SDK_INT=30;c=client();g=setup(c,"nus");assert c.isReady()&&g.rx!=g.tx;f=c.write(frame);finish(g);f.get();Build.VERSION.SDK_INT=35;
  assert c.write(new byte[0]).isCompletedExceptionally();c.disconnect();
  c=client();g=setup(c,"none");assert g.closed&&!c.isReady();
  c=client();BluetoothDevice d=new BluetoothDevice();c.connect(d);Handler.advance(0);g=d.last;Handler.advance(12000);assert g.closed&&!c.isReady();
  c=client();d=new BluetoothDevice();c.connect(d);Handler.advance(0);g=d.last;g.rx.properties=16;g.cb.onServicesDiscovered(g,0);assert g.closed;
  c=client();d=new BluetoothDevice();c.connect(d);Handler.advance(0);g=d.last;g.tx.ccc=null;g.cb.onServicesDiscovered(g,0);assert g.closed;
  System.out.println("PASS: actual BLE class; JDY/NUS discovery, CCC readiness, 20+12 bytes/35ms pacing, notification filtering, stale callbacks, stable failed futures, write/setup watchdogs, legacy Android API, unsupported service/properties");
 }
}'''
FAKE_LINK=r'''package com.keyi.xinxian.guitar;
import java.math.BigInteger;import java.util.*;import java.util.concurrent.*;
public class BleUartClient {
 Xg3Client client;int generation=1,writes,commits,lists,mode;boolean marker;Xg3Protocol.Song song;
 public int connectionGeneration(){return generation;}public boolean isReady(){return true;}
 public CompletableFuture<Void> write(byte[] bytes){
  Xg3Protocol.Packet p=Xg3Protocol.decode(bytes);writes++;
  if(p.opcode==Xg3Protocol.COMMIT){commits++;assert marker:"COMMIT before durable journal";if(mode==1)return CompletableFuture.failedFuture(new IllegalStateException("remote accepted; link lost"));}
  if(p.opcode==Xg3Protocol.LIST){lists++;if(mode==2)return CompletableFuture.failedFuture(new IllegalStateException("LIST lost"));}
  if(p.opcode==Xg3Protocol.DATA&&mode==3)return CompletableFuture.failedFuture(new IllegalStateException("DATA lost"));
  byte[] payload=new byte[16];
  if(p.opcode==Xg3Protocol.HELLO){payload[1]=2;payload[2]=5;payload[3]=32;Xg3Protocol.putU32(payload,10,48000);}
  if(p.opcode==Xg3Protocol.LIST){
   BigInteger bits=BigInteger.valueOf(703).shiftLeft(32).or(BigInteger.valueOf(song.events.size()).shiftLeft(43))
    .or(BigInteger.valueOf(song.durationSamples).shiftLeft(55)).or(BigInteger.ONE.shiftLeft(87));
   for(int i=0;i<12;i++)payload[i+1]=bits.shiftRight(8*i).byteValue();payload[13]=4;payload[14]=7;
  }
  byte[] ack=Xg3Protocol.frame(p.opcode|128,p.session,p.sequence,payload);
  byte[] bad=ack.clone();bad[10]^=1;client.accept(bad);
  client.accept(Arrays.copyOf(ack,20));client.accept(Arrays.copyOfRange(ack,20,32));
  return CompletableFuture.completedFuture(null);
 }
}'''
COMMIT_TEST=r'''package com.keyi.xinxian.guitar;
public class CommitProbe {
 static BleUartClient make(int mode){BleUartClient b=new BleUartClient();b.mode=mode;b.client=new Xg3Client(b);
  byte[] note=new byte[16];note[8]=60;note[10]=2;Xg3Protocol.putU32(note,4,24000);b.song=Xg3Protocol.parseSong(note);return b;}
 static Xg3Client.CommitJournal journal(BleUartClient b,boolean beforeFail,boolean confirmFail){return new Xg3Client.CommitJournal(){
  public void beforeCommit(int s,Xg3Protocol.Song song)throws Exception{if(beforeFail)throw new Exception("disk full");b.marker=true;}
  public void confirmed()throws Exception{if(confirmFail)throw new Exception("cannot clear journal");b.marker=false;}
 };}
 public static void main(String[] a)throws Exception{
  BleUartClient b=make(0);b.client.hello();assert b.client.upload(4,1,b.song,null,journal(b,false,false)).eventCount==1;assert !b.marker&&b.commits==1;
  b=make(1);try{b.client.upload(4,1,b.song,null,journal(b,false,false));throw new AssertionError();}catch(Xg3Client.CommitUnknown expected){}assert b.marker&&b.commits==1;
  b=make(0);try{b.client.upload(4,1,b.song,null,journal(b,true,false));throw new AssertionError();}catch(Exception expected){}assert b.commits==0;
  b=make(0);try{b.client.upload(4,1,b.song,null,journal(b,false,true));throw new AssertionError();}catch(Xg3Client.CommitConfirmed expected){}assert b.marker&&b.commits==1&&b.lists==0;
  b=make(2);try{b.client.upload(4,1,b.song,null,journal(b,false,false));throw new AssertionError();}catch(Xg3Client.CommitConfirmed expected){}assert !b.marker&&b.commits==1;
  b=make(3);try{b.client.upload(4,1,b.song,null,journal(b,false,false));throw new AssertionError();}catch(Exception expected){}assert b.commits==0&&!b.marker;
  b=make(0);b.generation++;try{b.client.hello();throw new AssertionError();}catch(IllegalStateException expected){}assert b.writes==0;
  System.out.println("PASS: actual XG3 class; fragmented/CRC-filtered ACK; durable journal precedes COMMIT; link loss => unknown; journal failure blocks send; confirmed commit vs LIST failure; DATA failure; connection generation binding");
 }
}'''

def run():
    E.mkdir(parents=True,exist_ok=True)
    assert not (E/'verification.json').exists(),'Completed verification must not be repeated'
    logs=[]
    def execute(args):
        result=subprocess.run(list(map(str,args)),capture_output=True,text=True,encoding='utf-8',errors='replace')
        logs.append(result.stdout+result.stderr)
        (E/'tests.log').write_text('\n'.join(logs),encoding='utf-8')
        assert result.returncode==0,logs[-1]
        return result.stdout
    for group,files,actual,probe in [('ble',STUBS,('BleUartClient.java','BleSerialProfile.java'),('BleProbe',BLE_TEST)),
        ('commit',{'com/keyi/xinxian/guitar/BleUartClient.java':FAKE_LINK},('Xg3Client.java','Xg3Protocol.java'),('CommitProbe',COMMIT_TEST))]:
        src=E/group/'src';classes=E/group/'classes';classes.mkdir(parents=True,exist_ok=True)
        bodies=dict(files);bodies['com/keyi/xinxian/guitar/'+probe[0]+'.java']=probe[1]
        for name in actual:bodies['com/keyi/xinxian/guitar/'+name]=(APP/name).read_text(encoding='utf-8')
        for name,body in bodies.items():
            p=src/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(body,encoding='utf-8')
        execute([J/'javac.exe','--release','17','-encoding','UTF-8','-d',classes,*sorted(src.rglob('*.java'))])
        print(execute([J/'java.exe','-ea','-cp',classes,'com.keyi.xinxian.guitar.'+probe[0]]).strip())
    record={'result':'PASS','hardware_tested':False,'android_os_tested':False,
        'actual_source_sha256':{n:hashlib.sha256((APP/n).read_bytes()).hexdigest() for n in ('BleUartClient.java','BleSerialProfile.java','Xg3Client.java','Xg3Protocol.java')},
        'log_sha256':hashlib.sha256((E/'tests.log').read_bytes()).hexdigest()}
    (E/'verification.json').write_text(json.dumps(record,indent=2))

if __name__=='__main__':run()
