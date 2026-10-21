import React, { useEffect, useRef, useState } from 'react';
import { Alert, AppState, Button, PermissionsAndroid, Platform, ScrollView, Text, View } from 'react-native';
import { BleManager } from 'react-native-ble-plx';
import * as DocumentPicker from 'expo-document-picker';
import * as Crypto from 'expo-crypto';
import { File, Paths } from 'expo-file-system';
import { Client, FpgaRejected, SERVICE, RX, TX, parsePackage, toBase64, fromBase64 } from './src/protocol.js';

const journal = () => new File(Paths.document, 'p5_pending_commit.json');
const confirm = message => new Promise(resolve => Alert.alert('确认替换', message, [
  { text: '取消', onPress: () => resolve(false), style: 'cancel' },
  { text: '确认替换', onPress: () => resolve(true), style: 'destructive' },
], { cancelable: false }));
const sha256 = async bytes => Array.from(new Uint8Array(await Crypto.digest(Crypto.CryptoDigestAlgorithm.SHA256, bytes)))
  .map(v => v.toString(16).padStart(2, '0')).join('');

async function permissions() {
  if (Platform.OS !== 'android') return;
  const p = PermissionsAndroid.PERMISSIONS;
  const needed = Number(Platform.Version) >= 31 ? [p.BLUETOOTH_SCAN, p.BLUETOOTH_CONNECT] : [p.ACCESS_FINE_LOCATION];
  const granted = await PermissionsAndroid.requestMultiple(needed);
  if (!needed.every(k => granted[k] === PermissionsAndroid.RESULTS.GRANTED)) throw new Error('需要蓝牙连接权限');
}

export default function App() {
  const manager = useRef(null), device = useRef(null), client = useRef(null), subs = useRef([]), scanning = useRef(null);
  const [devices, setDevices] = useState([]), [slots, setSlots] = useState([]), [score, setScore] = useState(null);
  const [slot, setSlot] = useState(1), [busy, setBusy] = useState(false), [connected, setConnected] = useState(false);
  const [status, setStatus] = useState('板载 BLE 固件尚未实物验证'), [pending, setPending] = useState(false);
  const [progress, setProgress] = useState('');
  const stopScan = () => { clearTimeout(scanning.current); scanning.current = null; manager.current?.stopDeviceScan(); };
  const disconnect = async () => {
    stopScan();
    const link = client.current?.link;
    if (link) link.onClose?.();
    client.current = null;
    for (const s of subs.current) s.remove();
    subs.current = [];
    const d = device.current; device.current = null; setConnected(false);
    if (d) await d.cancelConnection().catch(() => {});
  };
  useEffect(() => {
    manager.current = new BleManager();
    setPending(journal().exists);
    const s = AppState.addEventListener('change', state => { if (state !== 'active') void disconnect(); });
    return () => { s.remove(); void disconnect().finally(() => manager.current?.destroy()); };
  }, []);
  const run = async fn => {
    if (busy) return;
    setBusy(true);
    try { await fn(); }
    catch (e) { setStatus(String(e.message || e)); }
    finally { setBusy(false); }
  };
  const scan = async () => {
    await disconnect(); await permissions();
    if (await manager.current.state() !== 'PoweredOn') throw new Error('请在系统设置开启蓝牙后重试');
    setDevices([]); setStatus('选择下方吉他设备');
    manager.current.startDeviceScan([SERVICE], null, (error, found) => {
      if (error) { stopScan(); setStatus(error.message); return; }
      if (found) setDevices(old => old.some(d => d.id === found.id) ? old : [...old, found]);
    });
    scanning.current = setTimeout(stopScan, 10000);
  };
  const connect = async candidate => {
    stopScan(); await disconnect();
    try {
      const d = await candidate.connect({ timeout: 10000 }); device.current = d;
      await d.discoverAllServicesAndCharacteristics();
      const characteristics = await d.characteristicsForService(SERVICE);
      if (!characteristics.some(c => c.uuid.toLowerCase() === RX && c.isWritableWithResponse) ||
          !characteristics.some(c => c.uuid.toLowerCase() === TX && c.isNotifiable))
        throw new Error('设备未提供此版本所需的 BLE 服务');
      const link = {
        write: async bytes => {
          let timer;
          try {
            await Promise.race([
              d.writeCharacteristicWithResponseForService(SERVICE, RX, toBase64(bytes)),
              new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('BLE 写入超时')), 2000); }),
            ]);
          } catch (e) { void disconnect(); throw e; }
          finally { clearTimeout(timer); }
        },
      };
      const bytes = Crypto.getRandomBytes(2), session = (bytes[0] | bytes[1] << 8) || 1;
      const c = new Client(link, session); client.current = c;
      subs.current.push(d.monitorCharacteristicForService(SERVICE, TX, (error, value) => {
        if (error) { link.onClose(); setConnected(false); setStatus('蓝牙连接中断，重新连接前请等待至少 6 秒'); }
        else if (value?.value) link.onBytes(fromBase64(value.value));
      }));
      subs.current.push(d.onDisconnected(() => { link.onClose(); setConnected(false); }));
      await c.hello(); setSlots(await c.list()); setConnected(true); setStatus('已连接，五槽目录来自 FPGA');
    } catch (e) { await disconnect(); throw e; }
  };
  const pick = async () => {
    const result = await DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true });
    if (result.canceled) return;
    const asset = result.assets[0], file = new File(asset.uri);
    if (file.size > 65536) throw new Error('曲谱包超过 64 KiB');
    const p = await parsePackage(await file.text(), sha256); setScore(p); setProgress('');
    setStatus(`已选择「${p.title}」，${p.event_count} 个音符`);
  };
  const upload = async () => {
    if (!client.current || !score || pending) throw new Error('请先连接、选择曲谱并处理待确认提交');
    let commitStarted = false;
    try {
      const result = await client.current.upload(slot, score,
        old => confirm(`槽位 ${old.slot + 1} 已有曲谱（${old.count} 个音符）。上传失败时由 FPGA 保留旧曲。`),
        (n, total) => setProgress(`${n} / ${total} 个音符已获 FPGA 确认`),
        async record => { journal().write(JSON.stringify(record)); commitStarted = true; setPending(true); });
      // Only Client's matching successful COMMIT ACK authorizes this text.
      journal().delete(); setPending(false);
      if (result.slots) setSlots(result.slots);
      setStatus(result.catalogWarning ? 'FPGA 曾确认提交，但当前目录不匹配，请检查吉他是否复位' :
        result.slots ? 'FPGA 已确认提交成功，可断开手机继续演奏' : 'FPGA 已确认提交成功；目录刷新失败，请重新连接查询');
    } catch (e) {
      if (commitStarted && e instanceof FpgaRejected) { journal().delete(); setPending(false); }
      throw e;
    }
  };
  return <ScrollView contentContainerStyle={{ padding: 24, gap: 16 }}>
    <Text style={{ fontSize: 27, fontWeight: '700', marginTop: 24 }}>弦芯 · 曲谱导入</Text>
    <Text>{status}</Text>
    <Button title="扫描吉他" disabled={busy || connected} onPress={() => run(scan)} />
    {!connected && devices.map(d => <Button key={d.id} title={d.name || d.id} disabled={busy} onPress={() => run(() => connect(d))} />)}
    <Button title="选择曲谱包" disabled={busy} onPress={() => run(pick)} />
    {score && <Text>「{score.title}」 · {score.event_count} 音符 · {(score.duration_samples / 48000).toFixed(1)} 秒{ '\n' }吉他屏幕显示 USER {slot + 1}</Text>}
    {slots.map(s => <View key={s.slot} style={{ padding: 10, borderWidth: slot === s.slot ? 2 : 1, borderColor: '#63817e' }}>
      <Button title={`槽 ${s.slot + 1} · ${!s.valid ? '空闲' : s.imported ? '已导入' : s.testOnly ? '诊断保留' : '内置'} · ${s.count} 音符`}
        disabled={busy} onPress={() => setSlot(s.slot)} />
    </View>)}
    <Text>{progress}</Text>
    <Button title={`上传到槽 ${slot + 1}`} disabled={busy || !connected || !score || pending} onPress={() => run(upload)} />
    <Button title="刷新目录" disabled={busy || !connected} onPress={() => run(async () => setSlots(await client.current.list()))} />
    <Button title="断开手机" disabled={busy || !connected} onPress={() => run(disconnect)} />
    {pending && <View style={{ padding: 12, backgroundColor: '#fff0d2', gap: 8 }}>
      <Text>存在待确认提交。请保持吉他供电，重新连接并查询目录、试听检查；相同数量和时长不能证明内容相同。不会自动重传或声称回滚。</Text>
      <Button title="我已人工核对，清除待确认标记" disabled={busy} onPress={() => run(async () => {
        if (await confirm('确认已人工核对提交结果？清除标记不改变吉他曲库。')) { journal().delete(); setPending(false); }
      })} />
    </View>}
    <Text>导入曲保存在 RAM，吉他须持续供电。复位、断电或重新配置后丢失。上传期间请保持应用在前台。</Text>
  </ScrollView>;
}
