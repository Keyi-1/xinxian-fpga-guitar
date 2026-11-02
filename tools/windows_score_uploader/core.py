"""Offline score validation and bounded UART jobs; no port opens on import."""
from __future__ import annotations

import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import threading

from game_score_upload import Client, BEGIN, DATA, COMMIT, ABORT
from game_score_v2 import from_binary, payload_info, read_csv, validate

MAX_FILE = 512 * 1024
IMPORT_CAPACITY = 1345
TIMBRES = ("钢琴", "明亮弦音", "哇音")


@dataclass(frozen=True)
class Score:
    title: str
    events: tuple
    duration: int
    timbre: int
    crc32: str
    source: str

    @property
    def seconds(self):
        return self.duration / 48000

    def package(self):
        raw, crc = payload_info(self.events)
        return dict(package_format="xinxian-score", package_version=1,
                    title=self.title[:80], format_version=2, event_bytes=16,
                    sample_rate_hz=48000, event_count=len(self.events),
                    duration_samples=self.duration, recommended_timbre=self.timbre,
                    crc32=crc, payload_sha256=hashlib.sha256(raw).hexdigest(),
                    payload_base64=base64.b64encode(raw).decode("ascii"))


def bounded_read(path):
    with Path(path).open("rb") as stream:
        raw = stream.read(MAX_FILE + 1)
    if not raw or len(raw) > MAX_FILE:
        raise ValueError("曲谱为空或超过 512 KiB。请选择音符事件文件。")
    return raw


def json_object(raw):
    data = json.loads(raw.decode("utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError("JSON 顶层必须为曲谱信息对象。")
    return data


def integer(data, key):
    value = data.get(key)
    if type(value) is not int:
        raise ValueError(f"曲谱字段 {key} 必须是整数。")
    return value


def compiled(raw, info, title, source):
    for key, value in (("format_version", 2), ("event_bytes", 16), ("sample_rate_hz", 48000)):
        if integer(info, key) != value:
            raise ValueError("需要 v2 / 16 字节 / 48 kHz 曲谱。")
    duration = integer(info, "duration_samples")
    timbre = integer(info, "recommended_timbre")
    if timbre not in range(3):
        raise ValueError("音色必须为钢琴、明亮弦音或哇音。")
    events = from_binary(raw, profile="game_extended")
    validate(events, duration, profile="game_extended")
    _, crc = payload_info(events)
    if integer(info, "event_count") != len(events) or str(info.get("crc32", "")).lower() != crc:
        raise ValueError("事件数量或 CRC32 不匹配，请重新选择配对的曲谱文件。")
    return finish(title, events, duration, timbre, source)


def finish(title, events, duration, timbre, source):
    if len(events) > IMPORT_CAPACITY:
        raise ValueError("导入曲谱最多 1345 个事件；这是五槽共享空间。请先整理曲谱。")
    _, crc = payload_info(events)
    return Score(str(title)[:80], tuple(events), duration, timbre, crc, source)


def load_score(path, bpm=60, timbre=1, metadata=None):
    """BIN/JSON pair, P5-compatible single package, or exact-beat CSV."""
    path = Path(path)
    raw = bounded_read(path)
    suffix = path.suffix.lower()
    if suffix == ".csv":
        if type(bpm) is not int or not 20 <= bpm <= 240 or type(timbre) is not int or timbre not in range(3):
            raise ValueError("CSV 速度需为 20–240 BPM，音色需为 0、1 或 2。")
        # Use the accepted allocator; never silently delete/transpose/shorten notes.
        events = read_csv(path, bpm, profile="game_extended")
        duration = max(event.onset + event.duration for event in events)
        validate(events, duration, profile="game_extended")
        return finish(path.stem, events, duration, timbre, "CSV · 本地编译")
    if suffix in (".json", ".xgscore"):
        info = json_object(raw)
        if info.get("package_format") == "xinxian-score":
            if integer(info, "package_version") != 1 or len(raw) > 65536:
                raise ValueError("曲谱包版本不支持或超过 64 KiB。")
            if not isinstance(info.get("title"), str) or not 1 <= len(info["title"]) <= 80:
                raise ValueError("曲谱包名称长度需为 1–80 字符。")
            payload = base64.b64decode(info["payload_base64"], validate=True)
            if hashlib.sha256(payload).hexdigest() != info.get("payload_sha256"):
                raise ValueError("曲谱包 SHA256 不匹配，文件可能已损坏。")
            return compiled(payload, info, info["title"], "XG 曲谱包")
        if suffix == ".xgscore":
            raise ValueError("这不是 xinxian-score 曲谱包。")
        return compiled(bounded_read(path.with_suffix(".bin")), info, path.stem, "BIN + JSON")
    if suffix == ".bin":
        info = json_object(bounded_read(metadata or path.with_suffix(".json")))
        return compiled(raw, info, path.stem, "BIN + JSON")
    raise ValueError("请选择 .xgscore、.csv，或同名配对的 .bin / .json 文件。图片、PDF、MP3 需先整理成音符事件。")


def export_package(score, path):
    # UI requires a new filename; a race cannot silently replace an existing file.
    with Path(path).open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(score.package(), stream, ensure_ascii=False, indent=2)
        stream.write("\n")


class Journal:
    """Durable marker written BEFORE any COMMIT bytes; survives app restarts."""
    def __init__(self, path):
        self.path = Path(path)

    def read(self):
        if not self.path.exists():
            return None
        try:
            return json_object(bounded_read(self.path))
        except (ValueError, OSError):
            return {"phase": "unreadable", "port": "未知", "slot": "?"}

    def write(self, data):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temp = self.path.with_suffix(".tmp")
        with temp.open("w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, self.path)

    def clear(self):
        self.path.unlink(missing_ok=True)


class Cancelled(Exception):
    pass


class CommitUncertain(Exception):
    pass


class CommittedUnverified(Exception):
    pass


def open_serial(port):
    if not re.fullmatch(r"COM[1-9][0-9]*", port, re.IGNORECASE):
        raise ValueError("请选择 Windows COM 串口，例如 COM5。")
    import serial
    stream = serial.Serial(port=None, baudrate=115200, timeout=0.1,
                           write_timeout=2, rtscts=False, dsrdtr=False)
    stream.dtr = False
    stream.rts = False
    stream.port = port
    try:
        stream.open()
        stream.reset_input_buffer()
        return stream
    except Exception:
        stream.close()
        raise


def check_device(client):
    caps = client.hello()
    if (caps["reserved_records"], caps["capacity"], caps["midi_min"], caps["midi_max"]) != (703, 2048, 50, 79) or not caps["features"] & 1:
        raise ValueError("设备曲库能力与本软件不兼容，请使用当前 P3/P4 曲库位流。")
    slots = [client.list_slot(i) for i in range(5)]
    if any(slot["slot"] != i for i, slot in enumerate(slots)):
        raise ValueError("设备返回了不一致的槽位目录，请重新检查设备。")
    return {"capabilities": caps, "slots": slots}


def probe(port, factory=open_serial):
    stream = factory(port)
    try:
        return check_device(Client(stream))
    finally:
        stream.close()


def upload(port, slot, score, journal, progress, stage, cancel=None,
           expected_slot=None, factory=open_serial, timeout=1.0):
    """Frontend policy around the unchanged certified Client and its retry logic."""
    if journal.read():
        raise ValueError("有一笔上次提交尚待确认，请先点击“处理上次提交”。")
    if type(slot) is not int or slot not in range(5):
        raise ValueError("目标槽位必须为 1–5。")
    validate(score.events, score.duration, profile="game_extended")
    if score.timbre not in range(3) or len(score.events) > IMPORT_CAPACITY:
        raise ValueError("曲谱容量或音色无效。")
    cancel = cancel or threading.Event()
    state = {"phase": "before_begin", "begun": False}

    class ObservedClient(Client):
        def request(self, op, payload=b""):
            if op in (BEGIN, DATA, COMMIT) and cancel.is_set():
                raise Cancelled("已停止发送；未提交的新曲会撤销或在 FPGA 端超时释放。")
            if op == COMMIT:
                journal.write(dict(phase="commit_pending", port=port, slot=slot + 1,
                                   title=score.title, crc32=score.crc32,
                                   event_count=len(score.events), duration_samples=score.duration,
                                   recommended_timbre=score.timbre))
                state["phase"] = "commit_pending"
                stage("commit", "音符已传输，正在等待 FPGA 校验并提交…")
            try:
                reply = super().request(op, payload)
            except RuntimeError:
                # Explicit matching NACK means FPGA rejected COMMIT, not ACK loss.
                if op == COMMIT:
                    journal.clear()
                    state["phase"] = "rejected"
                raise
            if op == BEGIN:
                state["begun"] = True
                state["phase"] = "data"
            if op == ABORT:
                state["begun"] = False
            if op == COMMIT:
                state["phase"] = "acknowledged"
                data = journal.read()
                data["phase"] = "commit_acknowledged"
                journal.write(data)
                stage("verify", "FPGA 已确认提交，正在回读曲库目录…")
            return reply

    stage("connect", "正在重新连接并核对设备曲库…")
    stream = factory(port)
    client = ObservedClient(stream, timeout=timeout)
    try:
        device = check_device(client)
        if expected_slot is not None and device["slots"][slot] != expected_slot:
            raise ValueError("设备曲库在上次检查后发生变化。请重新检查设备，再确认目标槽位。")
        stage("data", "正在发送音符事件，逐条等待 FPGA 确认…")

        def acknowledged(n, total):
            progress(n, total)
            if cancel.is_set():
                raise Cancelled("已停止发送；未提交的新曲会撤销或在 FPGA 端超时释放。")

        result = client.upload(slot, score.events, score.duration, score.timbre, acknowledged)
        if not (result["slot"] == slot and result["valid"] and result["playable"] and
                result["imported"] and result["event_count"] == len(score.events) and
                result["duration_samples"] == score.duration and
                result["recommended_timbre"] == score.timbre):
            raise ValueError("提交后的目录字段与待上传曲谱不一致。")
        journal.clear()
        state["phase"] = "verified"
        return result
    except Exception as exc:
        if state["phase"] == "commit_pending":
            raise CommitUncertain("提交结果未知：最终确认未收到。新曲可能已经生效，请重新检查设备并在琴上核对，不能直接重传。") from exc
        if state["phase"] == "acknowledged":
            raise CommittedUnverified("FPGA 已确认提交，但目录回读未完成。请重新检查设备并在琴上核对，不能把它当作未上传。") from exc
        if state["begun"] and state["phase"] != "verified":
            try:
                client.request(ABORT)
            except Exception:
                pass
        raise
    finally:
        stream.close()


def friendly_error(exc):
    text = str(exc)
    for token, message in (
        ("BUSY", "FPGA 正忙。请退出演奏、试听或游戏，回到主页/选曲页后重试。"),
        ("NO_SPACE", "曲库空闲连续空间不足。旧导入曲在提交前仍占空间，可减少新曲事件数；复位会清空全部导入曲。"),
        ("ORDER_OR_LANE_CONFLICT", "音符排序或同弦时长冲突。请检查 CSV 的起音、时长和轨道。"),
        ("DENSITY", "音符过密，超过当前游戏的显示/判定限制。请整理曲谱。"),
        ("SONG_CRC", "FPGA 整曲校验失败，未发布新曲。请检查文件与连接后重试。"),
        ("RANGE_OR_METADATA", "FPGA 拒绝曲谱的音域或元数据。请重新检查事件范围、时长和音色。"),
        ("SESSION_OR_SEQUENCE", "串口会话或序号不一致。请重新检查设备，关闭其他串口工具后重试。"),
        ("NO_TRANSACTION", "FPGA 的上传事务已经结束或超时。请回到主页，重新检查设备。"),
        ("unsupported lane/pitch", "音符超出 D3–G5（MIDI 50–79），或轨道不在 0–3 范围。请检查曲谱。"),
        ("invalid declared song duration", "曲目总时长不能短于最后一个音符的结束，且最长为 10 分钟。"),
        ("No valid matching ACK", "没有收到 FPGA 响应。请核对 COM 口、当前位流和 DEBUG-USB2 连接，并关闭其他串口工具。"),
        ("overlapping", "同一根弦的音符时长重叠。请调整 lane 或让 CSV 自动分弦。"),
        ("same-string onsets", "同一根弦起音间隔不足 250 毫秒。请调整分弦或节奏。"),
        ("outside", "存在超出 D3–G5（MIDI 50–79）的音符。请先确认需要怎样移调。"),
        ("visible blocks", "部分轨道音符过密，超过同时可见的八个音符块。请整理曲谱。"),
        ("no legal allocation", "这些音符无法在四根弦上合法分配。请检查同时发音数、时长和分弦。"),
        ("simultaneous notes", "同时起音超过四个，超出四根弦可演奏的范围。请先整理曲谱。"),
        ("invalid literal", "曲谱数值格式无效。CSV 的音高/轨道需为整数，拍数可写为 1/2、1/3。请参考 CSV 格式说明。"),
    ):
        if token in text:
            return message
    if isinstance(exc, PermissionError) or "Access is denied" in text or "拒绝访问" in text:
        return "串口无法打开或文件无法访问。请关闭串口助手/Gowin 中占用串口的窗口，并检查文件权限。"
    if isinstance(exc, FileNotFoundError):
        return "找不到文件或 COM 口。BIN 和 JSON 需同名并放在同一文件夹；设备拔插后请刷新串口。"
    if isinstance(exc, (json.JSONDecodeError, UnicodeError)):
        return "文件编码或 JSON 格式无效。请使用 UTF-8 编码的曲谱文件。"
    if isinstance(exc, KeyError):
        return f"曲谱缺少必要字段 {text}。请参考示例文件夹中的 CSV 格式说明，或重新编译配对的 BIN/JSON。"
    return text or type(exc).__name__
