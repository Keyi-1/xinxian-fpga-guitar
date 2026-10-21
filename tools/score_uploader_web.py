"""Local browser UI for the existing XG3 UART score uploader.

This tool deliberately reuses the validated P3 event checks and XG3 Client.
It only listens on 127.0.0.1, opens a serial port after an explicit browser
action, and never programs the FPGA.
"""
from __future__ import annotations

import base64
import csv
import io
import json
import sys
import threading
import webbrowser
import zlib
from fractions import Fraction
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from game_score_upload import Client  # noqa: E402
from game_score_v2 import (  # noqa: E402
    SAMPLE_RATE, Event, allocate, from_binary, payload_info, validate,
)

HOST = "127.0.0.1"
PORT = 8765
MAX_FILE_BYTES = 512 * 1024


def fail(message: str) -> ValueError:
    return ValueError(message)


def decode_file(item: dict, expected_suffix: str) -> tuple[str, bytes]:
    """Decode a browser supplied file; do not accept paths from the browser."""
    name = Path(str(item.get("name", ""))).name
    if not name.lower().endswith(expected_suffix):
        raise fail(f"需要 {expected_suffix} 文件，收到：{name or '未命名文件'}")
    try:
        raw = base64.b64decode(str(item["data"]), validate=True)
    except (KeyError, ValueError) as exc:
        raise fail(f"无法读取 {name}") from exc
    if not raw or len(raw) > MAX_FILE_BYTES:
        raise fail(f"{name} 为空或超过 {MAX_FILE_BYTES // 1024} KiB 限制")
    return name, raw


def compiled_score(body: dict) -> tuple[list, int, int, dict]:
    """Load the exact .bin/.json pair accepted by the command line uploader."""
    bin_name, raw = decode_file(body.get("bin", {}), ".bin")
    meta_name, meta_raw = decode_file(body.get("metadata", {}), ".json")
    try:
        metadata = json.loads(meta_raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise fail(f"{meta_name} 不是有效 JSON") from exc
    if (metadata.get("format_version"), metadata.get("event_bytes"),
            metadata.get("sample_rate_hz")) != (2, 16, 48000):
        raise fail("曲谱必须是 v2 / 16-byte / 48 kHz 的编译结果")
    events = from_binary(raw, profile="game_extended")
    duration = int(metadata.get("duration_samples", 0))
    timbre = int(metadata.get("recommended_timbre", -1))
    validate(events, duration, profile="game_extended")
    if len(events) != metadata.get("event_count"):
        raise fail("BIN 与 JSON 的事件数量不一致")
    actual_crc = f"{zlib.crc32(raw):08x}"
    if actual_crc != str(metadata.get("crc32", "")).lower():
        raise fail("BIN 与 JSON 的 CRC32 不一致")
    if timbre not in (0, 1, 2):
        raise fail("推荐音色必须为 0、1 或 2")
    return events, duration, timbre, {
        "name": Path(bin_name).stem,
        "event_count": len(events),
        "duration_samples": duration,
        "timbre": timbre,
        "crc32": actual_crc,
        "source": "已编译 BIN + JSON",
    }


def csv_score(body: dict) -> tuple[list, int, int, dict]:
    """Compile a supplied CSV in memory using the same rules as read_csv()."""
    name, raw = decode_file(body.get("csv", {}), ".csv")
    bpm = int(body.get("bpm", 60))
    timbre = int(body.get("timbre", 1))
    if not 30 <= bpm <= 240:
        raise fail("BPM 仅允许 30–240")
    if timbre not in (0, 1, 2):
        raise fail("推荐音色必须为 0、1 或 2")
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise fail("CSV 必须是 UTF-8 编码") from exc
    events, lanes = [], []
    try:
        for row in csv.DictReader(io.StringIO(text)):
            if "onset_beats" in row:
                onset = round(Fraction(row["onset_beats"]) * SAMPLE_RATE * 60 / bpm)
                duration = round(Fraction(row["duration_beats"]) * SAMPLE_RATE * 60 / bpm)
            else:
                onset, duration = int(row["t_on_samples"]), int(row["duration_samples"])
            lane = row.get("lane", "").strip()
            lanes.append(lane)
            events.append(Event(onset, duration, int(row["midi_note"]), int(lane) if lane else 0,
                                int(row.get("velocity_hint", "") or 2),
                                int(row.get("flags", "") or 0),
                                int(row.get("group_id", "") or 0)))
    except (KeyError, TypeError, ValueError, ZeroDivisionError) as exc:
        raise fail("CSV 列或数值无效；需要拍数列，或 t_on_samples/duration_samples 列") from exc
    if not events:
        raise fail("CSV 中没有可导入的音符")
    if any(lanes) and not all(lanes):
        raise fail("CSV 必须为所有事件都填写 lane，或全部留空以自动分弦")
    events = validate(events, profile="game_extended") if all(lanes) else allocate(events, profile="game_extended")
    duration = max(event.onset + event.duration for event in events)
    validate(events, duration, profile="game_extended")
    payload, crc = payload_info(events)
    return events, duration, timbre, {
        "name": Path(name).stem,
        "event_count": len(events),
        "duration_samples": duration,
        "timbre": timbre,
        "crc32": crc,
        "source": "CSV（本地临时编译）",
        "payload_bytes": len(payload),
    }


def load_from_request(body: dict) -> tuple[list, int, int, dict]:
    mode = body.get("mode")
    if mode == "compiled":
        return compiled_score(body)
    if mode == "csv":
        return csv_score(body)
    raise fail("请选择“编译后的 BIN + JSON”或“CSV 曲谱”")


def serial_module():
    try:
        import serial
        from serial.tools import list_ports
    except ImportError as exc:
        raise RuntimeError("缺少 pyserial。请按使用说明安装：python -m pip install pyserial") from exc
    return serial, list_ports


def open_client(port: str):
    serial, _ = serial_module()
    if not port or not port.upper().startswith("COM"):
        raise fail("请选择有效的 Windows COM 串口")
    stream = serial.Serial(port=None, baudrate=115200, timeout=0.1,
                           write_timeout=2, rtscts=False, dsrdtr=False)
    stream.dtr = False
    stream.rts = False
    stream.port = port
    stream.open()
    stream.reset_input_buffer()
    return stream, Client(stream)


def probe(port: str) -> dict:
    stream, client = open_client(port)
    try:
        caps = client.hello()
        slots = [client.list_slot(index) for index in range(5)]
        return {"capabilities": caps, "slots": slots}
    finally:
        stream.close()


def upload(port: str, visible_slot: int, body: dict) -> dict:
    if visible_slot not in range(1, 6):
        raise fail("目标槽位必须为 1–5")
    events, duration, timbre, summary = load_from_request(body)
    stream, client = open_client(port)
    try:
        capabilities = client.hello()
        if capabilities["slots"] != 5:
            raise RuntimeError("连接到的设备不是兼容的五槽 P3 曲库")
        result = client.upload(visible_slot - 1, events, duration, timbre)
        if not result["imported"] or result["event_count"] != len(events):
            raise RuntimeError("提交后的目录回读验证失败")
        return {"summary": summary, "slot": result}
    finally:
        stream.close()


PAGE = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FPGA Guitar · 曲谱导入</title><style>
:root{--navy:#0b1736;--navy2:#142551;--blue:#2563eb;--cyan:#16c6dd;--orange:#ff8052;--ink:#17213e;--muted:#72809c;--line:#e5eaf3;--paper:#f6f8fc;--green:#12a978;--danger:#d74b5c}*{box-sizing:border-box}body{margin:0;background:var(--paper);font-family:"Microsoft YaHei","Segoe UI",sans-serif;color:var(--ink)}.app{min-height:100vh;display:grid;grid-template-columns:250px 1fr}.side{background:linear-gradient(160deg,var(--navy),#11265b);color:#d9e5ff;padding:30px 20px}.brand{font-size:21px;font-weight:800;display:flex;gap:10px;align-items:center;color:#fff}.brand i{font-style:normal;background:var(--orange);border-radius:11px;padding:6px 10px}.side p{font-size:12px;line-height:1.7;color:#9fb5e8;margin:10px 4px 36px}.nav{padding:13px 14px;margin:8px 0;border-radius:10px;color:#a9bee9}.nav.active{background:#2b559d;color:#fff;font-weight:700}.foot{position:fixed;bottom:28px;font-size:12px;color:#91a9da;line-height:1.8}.main{max-width:1250px;width:100%;margin:0 auto;padding:38px 42px 30px}.top{display:flex;align-items:flex-start;justify-content:space-between}.eyebrow{font-size:12px;color:var(--blue);font-weight:800;letter-spacing:.1em}.top h1{font-size:32px;margin:5px 0 8px}.top p{margin:0;color:var(--muted)}.device{background:#effbf6;border:1px solid #c8efdf;color:#08785a;padding:13px 17px;border-radius:12px;font-size:14px;font-weight:700}.steps{display:flex;gap:34px;margin:32px 0 23px;color:#8793ad;font-size:14px}.step{display:flex;align-items:center;gap:9px}.dot{width:26px;height:26px;border-radius:50%;display:grid;place-items:center;background:#dbe4f6;font-weight:800}.step.active{color:var(--blue);font-weight:700}.step.active .dot{background:var(--blue);color:white}.layout{display:grid;grid-template-columns:minmax(500px,1.3fr) minmax(320px,.7fr);gap:22px}.card{background:#fff;border:1px solid var(--line);border-radius:17px;padding:23px;box-shadow:0 8px 24px #29456b0a}.card h2{font-size:16px;margin:0 0 17px}.row{display:flex;gap:12px;align-items:center}.field{flex:1}.field label{display:block;font-size:12px;font-weight:700;color:#697793;margin:0 0 7px}select,input{width:100%;border:1px solid #d8dfec;border-radius:9px;padding:11px 12px;font:inherit;color:var(--ink);background:#fff}.btn{border:0;border-radius:9px;padding:11px 14px;font:inherit;font-weight:700;cursor:pointer;background:#edf3ff;color:#1f58c9;white-space:nowrap}.btn:hover{filter:brightness(.97)}.btn.primary{background:var(--blue);color:white;padding:13px 21px;box-shadow:0 7px 15px #2563eb42}.status{margin:15px 0 2px;background:#effbf6;color:#08785a;border-radius:9px;padding:10px 12px;font-size:13px}.muted{color:var(--muted);font-size:13px;line-height:1.6}.mode{display:flex;gap:9px;margin:12px 0 16px}.mode button{border:1px solid #dce4f2;background:white;border-radius:9px;padding:8px 12px;color:#687795;cursor:pointer}.mode button.sel{background:#edf3ff;color:#205cd0;border-color:#a9c5ff;font-weight:700}.drop{border:2px dashed #bed0f3;background:#f9fbff;border-radius:13px;text-align:center;padding:26px 16px;cursor:pointer}.drop strong{display:block;font-size:15px;margin:7px 0}.drop span{font-size:12px;color:var(--muted)}.drop.drag{background:#edf4ff;border-color:var(--blue)}.fileline{margin-top:13px;background:#f5f8fd;border-radius:10px;padding:10px 12px;color:#4b5b7b;font-size:13px;display:flex;justify-content:space-between}.fileline b{color:var(--ink)}.checks{display:grid;gap:10px;margin-top:17px}.check{color:#098367;font-size:13px}.check:before{content:"✓";display:inline-grid;place-items:center;width:18px;height:18px;border-radius:50%;background:#dcf7ed;margin-right:8px;font-weight:bold}.hidden{display:none}.preview{background:linear-gradient(150deg,#142551,#1a3472);color:white;min-height:320px;overflow:hidden}.preview h2{color:#fff}.piano{height:205px;border-radius:11px;background:repeating-linear-gradient(90deg,#ffffff18 0 1px,transparent 1px 38px),repeating-linear-gradient(0deg,#ffffff1c 0 1px,transparent 1px 31px);position:relative;overflow:hidden}.note{position:absolute;height:16px;border-radius:4px;background:var(--cyan);box-shadow:0 2px 8px #16c6dd66}.note.o{background:var(--orange);box-shadow:0 2px 8px #ff805266}.note:nth-child(1){top:22px;left:8%;width:36%}.note:nth-child(2){top:53px;left:30%;width:44%}.note:nth-child(3){top:84px;left:17%;width:26%}.note:nth-child(4){top:116px;left:55%;width:35%}.note:nth-child(5){top:147px;left:9%;width:57%}.note:nth-child(6){top:178px;left:66%;width:22%}.metrics{display:flex;gap:10px;margin-top:16px}.metric{background:#ffffff14;border:1px solid #ffffff20;border-radius:9px;padding:9px 11px;font-size:12px}.metric b{display:block;font-size:15px;margin-top:3px}.warn{margin-top:22px;background:#fff8ec;border:1px solid #ffe0a4;border-radius:12px;padding:13px 15px;font-size:13px;color:#805312}.action{margin-top:22px;background:var(--navy);border-radius:16px;padding:19px 21px;display:flex;align-items:center;justify-content:space-between;color:#dbe8ff}.action b{display:block;color:#fff;margin-bottom:4px}.action span{font-size:12px;color:#aabfe8}.log{margin-top:16px;display:none;white-space:pre-wrap;font-family:Consolas,monospace;font-size:12px;background:#101827;color:#c4f5e7;border-radius:9px;padding:13px;max-height:180px;overflow:auto}.log.show{display:block}.result{margin-top:14px;border-radius:10px;padding:12px;font-size:13px}.result.ok{color:#08785a;background:#ecfaf4}.result.err{color:#ad2940;background:#fff0f2}@media(max-width:850px){.app{grid-template-columns:1fr}.side{display:none}.main{padding:24px 18px}.layout{grid-template-columns:1fr}.top{gap:16px}.device{display:none}.action{display:block}.action .btn{margin-top:14px;width:100%}}
</style></head><body><div class="app"><aside class="side"><div class="brand"><i>♫</i> FPGA Guitar</div><p>曲谱管理与安全导入<br>本机页面 · 不上传到云端</p><div class="nav">概览</div><div class="nav active">曲谱导入</div><div class="nav">曲库状态</div><div class="nav">设备说明</div><div class="foot">P3 · XG3 串口协议<br>115200 · 8N1</div></aside><main class="main"><header class="top"><div><div class="eyebrow">SCORE LIBRARY</div><h1>曲谱导入</h1><p>通过串口将练习曲谱安全写入 FPGA 吉他曲库。</p></div><div class="device" id="device">● 未连接设备</div></header><div class="steps"><div class="step active"><span class="dot">1</span>连接设备</div><div class="step active"><span class="dot">2</span>选择曲谱</div><div class="step active"><span class="dot">3</span>校验与上传</div></div><section class="layout"><div><section class="card"><h2>连接设备</h2><div class="row"><div class="field"><label for="port">DEBUG-USB2 串口</label><select id="port"><option>正在搜索串口…</option></select></div><button class="btn" id="refresh">刷新端口</button><button class="btn primary" id="connect">检查设备</button></div><div class="status" id="connection">尚未连接。请先将 DEBUG-USB2 接到电脑，并在 FPGA 上进入主页或选曲页。</div></section><section class="card" style="margin-top:22px"><h2>选择曲谱</h2><div class="mode"><button class="sel" data-mode="compiled">已编译 BIN + JSON</button><button data-mode="csv">CSV 曲谱</button></div><div id="compiled"><div class="drop" id="dropCompiled"><strong>拖入 <span style="color:#2563eb">.bin</span> 与 <span style="color:#2563eb">.json</span> 文件</strong><span>或点击此处选择两个配对的编译结果</span><input class="hidden" id="bin" type="file" accept=".bin"><input class="hidden" id="metadata" type="file" accept=".json"></div><div class="fileline"><b id="binName">尚未选择 BIN</b><span id="jsonName">尚未选择 JSON</span></div></div><div id="csv" class="hidden"><div class="drop" id="dropCsv"><strong>拖入 CSV 曲谱，或点击选择</strong><span>网页仅在临时目录编译，不覆盖你的原文件</span><input class="hidden" id="csvFile" type="file" accept=".csv"></div><div class="row" style="margin-top:13px"><div class="field"><label>BPM（30–240）</label><input id="bpm" type="number" min="30" max="240" value="60"></div><div class="field"><label>推荐音色</label><select id="timbre"><option value="0">音色 1</option><option value="1" selected>音色 2</option><option value="2">音色 3</option></select></div></div><div class="fileline"><b id="csvName">尚未选择 CSV</b><span>游戏音域 D3–G5</span></div></div><div class="checks"><div class="check">上传前将检查事件格式、音域、时长和同轨冲突</div><div class="check">上传时逐条等待 FPGA ACK；提交后再次读回目录</div><div class="check">曲谱仅保存在运行时 RAM，断电、复位或重新配置后会丢失</div></div></section></div><section class="card preview"><h2>演奏预览</h2><div class="piano"><i class="note"></i><i class="note o"></i><i class="note"></i><i class="note o"></i><i class="note"></i><i class="note o"></i></div><div class="metrics"><div class="metric">当前曲谱<b id="scoreTitle">未选择</b></div><div class="metric">事件数<b id="eventCount">—</b></div><div class="metric">推荐音色<b id="timbreInfo">—</b></div></div><div class="warn">提示：导入操作只允许在 FPGA 的主页或选曲页进行；演奏、试听和游戏中会返回 BUSY。</div></section></section><section class="action"><div><b id="readyTitle">准备上传</b><span id="readyText">先选择曲谱，再点击“检查设备”；上传前不会写入 FPGA。</span></div><div><label style="font-size:12px;margin-right:9px">目标槽位</label><select id="slot" style="width:125px;margin-right:10px"><option value="1">第 1 槽</option><option value="2" selected>第 2 槽</option><option value="3">第 3 槽</option><option value="4">第 4 槽</option><option value="5">第 5 槽</option></select><button class="btn primary" id="upload">开始安全上传</button></div></section><div class="result" id="result">请选择曲谱文件。</div><pre class="log" id="log"></pre></main></div><script>
const $=id=>document.getElementById(id);let mode='compiled',lastSummary=null;
function jsonFile(file){return new Promise((resolve,reject)=>{let r=new FileReader;r.onload=()=>resolve({name:file.name,data:btoa(String.fromCharCode(...new Uint8Array(r.result)))});r.onerror=reject;r.readAsArrayBuffer(file)})}
function message(text,ok=false){let e=$('result');e.textContent=text;e.className='result '+(ok?'ok':'err')}
function log(text){$('log').classList.add('show');$('log').textContent=text}
async function call(path,data){let r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data||{})});let j=await r.json();if(!r.ok)throw Error(j.error||'未知错误');return j}
async function ports(){try{let data=await call('/api/ports');let select=$('port');select.innerHTML='';if(!data.ports.length)select.innerHTML='<option value="">未发现可用 COM 口</option>';data.ports.forEach(p=>{let o=document.createElement('option');o.value=p.name;o.textContent=p.name+(p.description?' · '+p.description:'');select.appendChild(o)});message('已刷新串口列表。请选中 DEBUG-USB2 对应的 COM 口。',true)}catch(e){message(e.message)}}
function activePayload(){if(mode==='compiled'){if(!$('bin').files[0]||!$('metadata').files[0])throw Error('请同时选择 .bin 与 .json 文件');return Promise.all([jsonFile($('bin').files[0]),jsonFile($('metadata').files[0])]).then(([bin,metadata])=>({mode,bin,metadata}))}if(!$('csvFile').files[0])throw Error('请选择 CSV 文件');return jsonFile($('csvFile').files[0]).then(csv=>({mode,csv,bpm:+$('bpm').value,timbre:+$('timbre').value}))}
async function inspect(){try{let data=await call('/api/inspect',await activePayload());lastSummary=data.summary;$('scoreTitle').textContent=data.summary.name;$('eventCount').textContent=data.summary.event_count+' 个';$('timbreInfo').textContent='音色 '+(data.summary.timbre+1);$('readyTitle').textContent='曲谱校验通过';$('readyText').textContent=data.summary.source+' · CRC32 '+data.summary.crc32.toUpperCase();message('曲谱本地校验通过；尚未向 FPGA 写入任何数据。',true)}catch(e){lastSummary=null;message(e.message)}}
document.querySelectorAll('.mode button').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;document.querySelectorAll('.mode button').forEach(x=>x.classList.toggle('sel',x===b));$('compiled').classList.toggle('hidden',mode!=='compiled');$('csv').classList.toggle('hidden',mode!=='csv');lastSummary=null;message('请选择曲谱文件。')});
$('dropCompiled').onclick=()=>$('bin').click();$('bin').onchange=()=>{$('binName').textContent=$('bin').files[0]?.name||'尚未选择 BIN';setTimeout(()=>$('metadata').click(),50)};$('metadata').onchange=()=>{$('jsonName').textContent=$('metadata').files[0]?.name||'尚未选择 JSON';inspect()};$('dropCsv').onclick=()=>$('csvFile').click();$('csvFile').onchange=()=>{$('csvName').textContent=$('csvFile').files[0]?.name||'尚未选择 CSV';inspect()};
['dropCompiled','dropCsv'].forEach(id=>{let e=$(id);['dragenter','dragover'].forEach(n=>e.addEventListener(n,x=>{x.preventDefault();e.classList.add('drag')}));['dragleave','drop'].forEach(n=>e.addEventListener(n,x=>{x.preventDefault();e.classList.remove('drag')}));e.addEventListener('drop',x=>{let f=[...x.dataTransfer.files];if(id==='dropCompiled'){let b=f.find(q=>q.name.toLowerCase().endsWith('.bin')),j=f.find(q=>q.name.toLowerCase().endsWith('.json'));if(b&&j){let dt=new DataTransfer;dt.items.add(b);$('bin').files=dt.files;dt=new DataTransfer;dt.items.add(j);$('metadata').files=dt.files;$('binName').textContent=b.name;$('jsonName').textContent=j.name;inspect()}else message('请一次拖入配对的 .bin 与 .json 文件')}else{let c=f.find(q=>q.name.toLowerCase().endsWith('.csv'));if(c){let dt=new DataTransfer;dt.items.add(c);$('csvFile').files=dt.files;$('csvName').textContent=c.name;inspect()}else message('请选择 .csv 文件')}})});
$('refresh').onclick=ports;$('connect').onclick=async()=>{try{$('connection').textContent='正在查询 FPGA 能力与五个曲目槽位…';let d=await call('/api/probe',{port:$('port').value});$('device').textContent='● Tang Mega 60K · 已连接';$('connection').textContent='设备已就绪：P3 五槽曲库，'+d.capabilities.capacity+' 条总事件容量。';log(JSON.stringify(d.slots,null,2));message('设备检查通过。现在可以安全上传。',true)}catch(e){$('device').textContent='● 未连接设备';$('connection').textContent='设备检查失败：'+e.message;message(e.message)}};
$('upload').onclick=async()=>{try{if(!lastSummary)await inspect();if(!lastSummary)return;let slot=+$('slot').value;if(!confirm('确认将“'+lastSummary.name+'”导入第 '+slot+' 槽？运行时原槽位映射会被替换。'))return;$('upload').disabled=true;$('upload').textContent='正在上传…';$('readyTitle').textContent='正在安全上传';$('readyText').textContent='逐条等待 ACK；请勿拔掉 USB 或给 FPGA 断电。';let data=await call('/api/upload',{...(await activePayload()),port:$('port').value,slot});$('readyTitle').textContent='上传完成';$('readyText').textContent='COMMIT 与目录回读验证均成功。';message('已成功导入第 '+slot+' 槽：'+data.summary.event_count+' 个事件。',true);log(JSON.stringify(data,null,2))}catch(e){message(e.message);$('readyTitle').textContent='上传未完成';$('readyText').textContent='若错误涉及 COMMIT 超时，请重新查询设备，勿假定已回滚。'}finally{$('upload').disabled=false;$('upload').textContent='开始安全上传'}};
ports();
</script></body></html>'''


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def reply(self, status: int, payload: dict) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if urlparse(self.path).path != "/":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        encoded = PAGE.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_POST(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 2 * MAX_FILE_BYTES:
                raise fail("请求为空或文件总大小超过限制")
            body = json.loads(self.rfile.read(size).decode("utf-8"))
            path = urlparse(self.path).path
            if path == "/api/ports":
                _, list_ports = serial_module()
                ports = [{"name": item.device, "description": item.description}
                         for item in list_ports.comports()]
                result = {"ports": ports}
            elif path == "/api/inspect":
                _events, _duration, _timbre, summary = load_from_request(body)
                result = {"summary": summary}
            elif path == "/api/probe":
                result = probe(str(body.get("port", "")))
            elif path == "/api/upload":
                result = upload(str(body.get("port", "")), int(body.get("slot", 0)), body)
            else:
                self.reply(HTTPStatus.NOT_FOUND, {"error": "未知接口"})
                return
            self.reply(HTTPStatus.OK, result)
        except Exception as exc:  # Return an actionable local error to the UI.
            self.reply(HTTPStatus.BAD_REQUEST, {"error": str(exc)})


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    address = f"http://{HOST}:{PORT}/"
    print(f"曲谱上传页面已启动：{address}")
    print("仅监听本机；按 Ctrl+C 结束。浏览器操作前不会打开串口。")
    threading.Timer(0.2, lambda: webbrowser.open(address)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止本地曲谱上传页面。")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
