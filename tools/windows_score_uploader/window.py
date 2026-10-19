"""Restrained cream desktop UI; all device IO runs outside the GUI thread."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import threading
import tempfile
import uuid

from PyQt5.QtCore import Qt, QThread, pyqtSignal, QRectF, QTimer
from PyQt5.QtGui import QColor, QFont, QPainter, QPainterPath, QPen
from PyQt5.QtWidgets import (QApplication, QComboBox, QFileDialog, QFrame,
    QGridLayout, QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox,
    QPlainTextEdit, QProgressBar, QPushButton, QScrollArea, QSpinBox,
    QVBoxLayout, QWidget)

from . import VERSION
from .core import (Journal, TIMBRES, Cancelled, CommitUncertain, CommittedUnverified,
                   export_package, friendly_error, load_score, probe, upload)
from .preview_audio import render_preview
from .preview_panel import PreviewPanel


STYLE = """
QWidget { color:#343d38; font-family:'Microsoft YaHei UI','Segoe UI'; font-size:13px; }
QMainWindow, QWidget#paper { background:#f6f3eb; }
QScrollArea { border:0; background:transparent; }
QScrollArea > QWidget > QWidget, QWidget#page { background:transparent; }
QFrame#card { background:rgba(255,253,248,205); border:1px solid #e3ded2; border-radius:14px; }
QLabel { background:transparent; }
QLabel#title { font-size:27px; font-weight:600; color:#293c33; }
QLabel#section { font-size:16px; font-weight:600; }
QLabel#muted { color:#777b72; } QLabel#status { color:#426653; }
QLabel#metric { font-size:20px; font-weight:600; color:#344f40; }
QLabel#guide { font-size:14px; color:#344f40; }
QLabel#notice { color:#795d35; background:#f5eddf; border-radius:8px; padding:10px; }
QPushButton { background:#f0eee6; border:1px solid #d9d6ca; border-radius:7px;
              padding:9px 15px; color:#3f5145; }
QPushButton:hover { background:#e7e9df; border-color:#acb5a2; }
QPushButton:pressed { background:#dbe0d1; }
QPushButton#primary { background:#3d604d; border:1px solid #3d604d; color:#fffdf8; font-weight:600; }
QPushButton#primary:hover { background:#304e3d; }
QPushButton:disabled { background:#efeee8; color:#aaa99d; border-color:#e1ded3; }
QComboBox, QLineEdit, QSpinBox { background:#fffefb; border:1px solid #d7d9ce;
    border-radius:6px; padding:8px; min-height:20px; selection-background-color:#637c64; }
QComboBox:focus, QLineEdit:focus, QSpinBox:focus { border-color:#76917b; }
QComboBox:disabled, QSpinBox:disabled { background:#f1efe8; color:#95998f; }
QComboBox::drop-down { border:0; width:25px; }
QComboBox::down-arrow { image:url(ICON_DIR/down.png); width:12px; height:8px; }
QSpinBox::up-button, QSpinBox::down-button { border:0; width:20px; background:#eeeee5; }
QSpinBox::up-arrow { image:url(ICON_DIR/up.png); width:10px; height:7px; }
QSpinBox::down-arrow { image:url(ICON_DIR/down.png); width:10px; height:7px; }
QComboBox QAbstractItemView { background:#fffdf8; selection-background-color:#e1e7d9; selection-color:#25392b; }
QProgressBar { border:0; background:#e6e8de; border-radius:4px; min-height:9px; max-height:9px; }
QProgressBar::chunk { background:#6e8c73; border-radius:4px; }
QPlainTextEdit { background:#eeece4; border:0; border-radius:7px; color:#586057; padding:8px; font-family:Consolas; font-size:12px; }
QToolTip { background:#fffdf8; color:#343d38; border:1px solid #d7d9ce; padding:6px; }
QSlider::groove:horizontal { background:#dedfd4; height:4px; border-radius:2px; }
QSlider::sub-page:horizontal { background:#82957e; border-radius:2px; }
QSlider::handle:horizontal { background:#526f58; border-radius:6px; width:12px; margin:-4px 0; }
QSlider:disabled::handle:horizontal { background:#bfc4b8; }
"""
STYLE = STYLE.replace("ICON_DIR", (Path(__file__).resolve().parent / "assets").as_posix())


def label(text, kind=None, wrap=True):
    w = QLabel(text)
    w.setWordWrap(wrap)
    if kind:
        w.setObjectName(kind)
    return w


class Paper(QWidget):
    """Low contrast vector guitar, scalable without bitmap/font dependencies."""
    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        # One large horizontal instrument spans the lower window, independently
        # of scrolling. Translucent cards reveal the quiet watermark beneath.
        scale = min(self.width() / 450, self.height() / 290)
        p.translate(self.width() * .5, self.height() - 142 * scale)
        p.rotate(68)
        p.scale(scale, scale)
        p.setPen(QPen(QColor(174, 151, 112, 92), 1.1))
        p.setBrush(Qt.NoBrush)
        path = QPainterPath()
        path.moveTo(-16, -160)
        path.lineTo(-16, 18)
        path.cubicTo(-78, -4, -90, 58, -55, 89)
        path.cubicTo(-125, 133, -77, 220, 0, 211)
        path.cubicTo(77, 220, 125, 133, 55, 89)
        path.cubicTo(90, 58, 78, -4, 16, 18)
        path.lineTo(16, -160)
        path.closeSubpath()
        p.drawPath(path)
        p.drawEllipse(QRectF(-24, 72, 48, 48))
        p.drawRoundedRect(QRectF(-29, -202, 58, 45), 9, 9)
        p.drawRect(QRectF(-32, 151, 64, 9))
        for x in (-10, -6, -2, 2, 6, 10):
            p.drawLine(x, -186, x, 159)
        for y in range(-140, 10, 17):
            p.drawLine(-16, y, 16, y)


class Notes(QWidget):
    def __init__(self):
        super().__init__()
        self.score = None
        self.playhead = None
        self.setMinimumHeight(125)
        self.setToolTip("横轴为全曲时间；每一块来自实际曲谱事件，纵轴为四根弦。此图不播放声音。")

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        area = QRectF(36, 15, max(1, self.width() - 50), self.height() - 43)
        colors = ("#6d8876", "#a39370", "#84969c", "#a78477")
        for lane in range(4):
            y = area.top() + (lane + .5) * area.height() / 4
            p.setPen(QColor("#e3e2d8"))
            p.drawLine(int(area.left()), int(y), int(area.right()), int(y))
            p.setPen(QColor("#85887c"))
            p.drawText(QRectF(0, y - 10, 30, 20), Qt.AlignCenter, f"{lane + 1} 弦")
        if not self.score:
            p.setPen(QColor("#92968a"))
            p.drawText(area, Qt.AlignCenter, "选择曲谱后显示真实音符分布")
            return
        p.setPen(Qt.NoPen)
        for e in self.score.events:
            x = area.left() + e.onset / self.score.duration * area.width()
            width = max(2, e.duration / self.score.duration * area.width())
            y = area.top() + (e.lane + .5) * area.height() / 4
            p.setBrush(QColor(colors[e.lane]))
            p.drawRoundedRect(QRectF(x, y - 4, width, 8), 2, 2)
        p.setPen(QColor("#85887c"))
        p.drawText(QRectF(36, self.height()-24, 80, 20), Qt.AlignLeft, "0:00")
        p.drawText(QRectF(self.width()-95, self.height()-24, 80, 20), Qt.AlignRight, duration_text(self.score.seconds))
        if self.playhead is not None:
            x = area.left() + min(1,max(0,self.playhead))*area.width()
            p.setPen(QPen(QColor("#395e49"), 1.5))
            p.drawLine(int(x), int(area.top()), int(x), int(area.bottom()))


def duration_text(seconds):
    seconds = round(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


class Job(QThread):
    completed = pyqtSignal(object)
    failed = pyqtSignal(object)
    progress = pyqtSignal(int, int)
    stage = pyqtSignal(str, str)

    def __init__(self, fn, parent=None):
        super().__init__(parent)
        self.fn = fn
        self.cancel = threading.Event()

    def run(self):
        try:
            self.completed.emit(self.fn(self))
        except Exception as exc:
            self.failed.emit(exc)


class Window(QMainWindow):
    def __init__(self, data_dir, examples, port_provider=None, probe_fn=probe, upload_fn=upload,
                 player_factory=None):
        super().__init__()
        self.journal = Journal(Path(data_dir) / "pending_commit.json")
        self.examples = Path(examples)
        self.port_provider = port_provider or self._ports
        self.probe_fn, self.upload_fn = probe_fn, upload_fn
        self.score = None
        self.device = None
        self.checked_port = None
        self.path = None
        self.metadata = None
        self.busy = False
        self.phase = ""
        self.worker = None
        self.close_requested = False
        self.completed_target = None
        self.preview_temp = None
        self.setWindowTitle(f"FPGA 吉他 · 曲谱上传 {VERSION}")
        self.resize(1100, 825)
        self.setMinimumSize(900, 650)
        shell = Paper()
        shell.setObjectName("paper")
        outer = QVBoxLayout(shell)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        self.setCentralWidget(shell)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        outer.addWidget(scroll, 1)
        page = QWidget()
        page.setObjectName("page")
        scroll.setWidget(page)
        layout = QVBoxLayout(page)
        layout.setContentsMargins(32, 25, 32, 12)
        layout.setSpacing(17)
        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 8)
        titles = QVBoxLayout()
        titles.addWidget(label("FPGA 吉他 · 曲谱上传", "title"))
        titles.addWidget(label("把音符带到琴上，开始下一首练习。", "muted"))
        header.addLayout(titles, 1)
        help_button = QPushButton("使用说明")
        help_button.clicked.connect(self.help)
        header.addWidget(help_button, 0, Qt.AlignTop)
        layout.addLayout(header)

        columns = QHBoxLayout()
        columns.setSpacing(18)
        left, ll = self.card("01  连接与目标槽位")
        left.setMaximumWidth(365)
        left.setMinimumWidth(305)
        ll.addWidget(label("连接开发板的 DEBUG-USB2，并让琴停留在主页或选曲页。", "muted"))
        ll.addWidget(label("串口"))
        port_row = QHBoxLayout()
        self.port = QComboBox()
        self.port.setMinimumContentsLength(10)
        self.port.setToolTip("可在 Windows 设备管理器的“端口（COM 和 LPT）”中查看。")
        self.refresh = QPushButton("刷新")
        self.refresh.clicked.connect(self.refresh_ports)
        port_row.addWidget(self.port, 1)
        port_row.addWidget(self.refresh)
        ll.addLayout(port_row)
        self.check = QPushButton("检查设备")
        self.check.setObjectName("primary")
        self.check.clicked.connect(self.check_device)
        ll.addWidget(self.check)
        self.connection = label("尚未检查设备", "status")
        ll.addWidget(self.connection)
        ll.addSpacing(7)
        ll.addWidget(label("上传到哪个槽位？"))
        self.slot = QComboBox()
        for i in range(5):
            self.slot.addItem(f"第 {i+1} 槽 · 待查询", i)
        self.slot.setCurrentIndex(1)
        self.slot.setToolTip("推荐先使用第 2 或第 5 槽。上传会替换该槽的运行时曲谱。")
        ll.addWidget(self.slot)
        self.capacity = label("五槽共享最多 1345 条导入事件。\n替换时需先有足够空间存放整首新曲。", "muted")
        ll.addWidget(self.capacity)
        ll.addStretch(1)
        ll.addWidget(label("曲谱保存在 RAM。断电、复位或重新配置 FPGA 后，导入曲会消失。", "notice"))
        right, rl = self.card("02  选择曲谱")
        rl.addWidget(label("支持 XG 曲谱包、CSV，或配对的 BIN + JSON。", "muted"))
        file_row = QHBoxLayout()
        self.file_name = QLineEdit()
        self.file_name.setReadOnly(True)
        self.file_name.setPlaceholderText("选择要上传的曲谱文件")
        self.browse = QPushButton("选择文件…")
        self.browse.clicked.connect(self.choose_file)
        file_row.addWidget(self.file_name, 1)
        file_row.addWidget(self.browse)
        rl.addLayout(file_row)
        options = QHBoxLayout()
        options.addWidget(label("CSV 速度"))
        self.bpm = QSpinBox()
        self.bpm.setRange(20, 240)
        self.bpm.setValue(60)
        self.bpm.setSuffix(" BPM")
        self.bpm.setEnabled(False)
        options.addWidget(self.bpm)
        options.addWidget(label("音色"))
        self.timbre = QComboBox()
        self.timbre.addItems([f"{i+1} · {t}" for i, t in enumerate(TIMBRES)])
        self.timbre.setCurrentIndex(1)
        self.timbre.setEnabled(False)
        options.addWidget(self.timbre, 1)
        rl.addLayout(options)
        self.csv_hint = label("速度和音色仅用于 CSV 编译；曲谱包使用文件内已确认的参数。", "muted")
        rl.addWidget(self.csv_hint)
        metrics = QGridLayout()
        self.metrics = []
        for col, name in enumerate(("音符事件", "曲目时长", "推荐音色")):
            w = label("—", "metric")
            metrics.addWidget(w, 0, col)
            metrics.addWidget(label(name, "muted"), 1, col)
            self.metrics.append(w)
        rl.addLayout(metrics)
        self.notes = Notes()
        rl.addWidget(self.notes, 1)
        self.preview = PreviewPanel(self, player_factory)
        self.preview.render_requested.connect(self.start_preview)
        self.preview.cancel_requested.connect(self.cancel_job)
        self.preview.position_changed.connect(self.preview_position)
        rl.addWidget(self.preview)
        self.score_info = label("曲谱将在本机校验音域、节奏、分弦和文件完整性。", "muted")
        rl.addWidget(self.score_info)
        shortcuts = QHBoxLayout()
        example = QPushButton("示例曲谱")
        example.setToolTip("打开附带的《情歌》和入门示例，先试听再上传。")
        example.clicked.connect(lambda: self.choose_file(str(self.examples)))
        self.export = QPushButton("另存曲谱包…")
        self.export.clicked.connect(self.export_score)
        file_row.addWidget(example)
        shortcuts.addWidget(self.export)
        rl.addLayout(shortcuts)
        self.example = example
        columns.addWidget(left)
        columns.addWidget(right, 1)
        layout.addLayout(columns, 1)

        footer, fl = self.card("03  确认并上传")
        self.guide = label("", "guide")
        fl.addWidget(self.guide)
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setValue(0)
        self.progress.setTextVisible(False)
        fl.addWidget(self.progress)
        row = QHBoxLayout()
        self.message = label("只会在点击上传并确认后写入曲库。", "muted")
        row.addWidget(self.message, 1)
        self.recover = QPushButton("处理上次提交")
        self.recover.clicked.connect(self.resolve_pending)
        row.addWidget(self.recover)
        self.cancel = QPushButton("取消上传")
        self.cancel.clicked.connect(self.cancel_job)
        row.addWidget(self.cancel)
        self.action = QPushButton("开始上传")
        self.action.setObjectName("primary")
        self.action.setMinimumWidth(155)
        self.action.clicked.connect(self.primary_action)
        row.addWidget(self.action)
        fl.addLayout(row)
        footer_wrap = QWidget()
        footer_layout = QVBoxLayout(footer_wrap)
        footer_layout.setContentsMargins(32, 0, 32, 20)
        footer_layout.addWidget(footer)
        outer.addWidget(footer_wrap)

        self.details_button = QPushButton("查看操作记录 ▾")
        self.details_button.setFlat(True)
        self.details_button.clicked.connect(self.toggle_log)
        layout.addWidget(self.details_button, 0, Qt.AlignLeft)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumHeight(115)
        self.log.setMaximumBlockCount(200)
        self.log.hide()
        layout.addWidget(self.log)
        self.port.currentIndexChanged.connect(self.port_changed)
        self.bpm.editingFinished.connect(self.csv_changed)
        self.timbre.currentIndexChanged.connect(self.csv_changed)
        self.slot.currentIndexChanged.connect(self.update_guide)
        self.refresh_ports()

    @staticmethod
    def card(title):
        frame = QFrame()
        frame.setObjectName("card")
        lay = QVBoxLayout(frame)
        lay.setContentsMargins(20, 20, 20, 20)
        lay.setSpacing(10)
        lay.addWidget(label(title, "section"))
        return frame, lay

    @staticmethod
    def _ports():
        from serial.tools import list_ports
        return [(p.device, p.description) for p in list_ports.comports()]

    def refresh_ports(self):
        previous = self.port.currentData()
        self.port.blockSignals(True)
        self.port.clear()
        try:
            ports = self.port_provider()
            for name, description in ports:
                self.port.addItem(f"{name} · {description}", name)
            if not ports:
                self.port.addItem("未发现串口 · 请连接 USB", None)
            index = self.port.findData(previous)
            if index >= 0:
                self.port.setCurrentIndex(index)
        except Exception as exc:
            self.port.addItem("串口枚举失败", None)
            self.show_error(exc)
        self.port.blockSignals(False)
        self.port_changed()

    def port_changed(self):
        self.device = None
        self.checked_port = None
        self.connection.setText("尚未检查设备")
        self.set_slots(None)
        self.update_guide()

    def set_slots(self, slots):
        names = ("茉莉花", "待导入", "Seven Nation Army", "情歌", "诊断槽")
        for i in range(5):
            text = "待查询"
            if slots:
                s = slots[i]
                text = (f"USER {i+1}" if s["imported"] else names[i])
                text += f" · {s['event_count']} 事件" if s["playable"] else " · 未开放"
            self.slot.setItemText(i, f"第 {i+1} 槽 · {text}")

    def run_job(self, fn, complete, kind):
        if self.busy:
            return
        if kind != "render":
            self.preview.stop_playback()
        self.busy = True
        self.phase = kind
        self.worker = Job(fn, self)
        self.worker.completed.connect(complete)
        self.worker.failed.connect(self.show_error)
        self.worker.progress.connect(self.on_progress)
        self.worker.stage.connect(self.on_stage)
        self.worker.finished.connect(self.job_done)
        self.update_guide()
        self.worker.start()

    def job_done(self):
        self.busy = False
        self.phase = ""
        self.worker.deleteLater()
        self.worker = None
        self.update_guide()
        if self.close_requested:
            self.close()

    def check_device(self):
        port = self.port.currentData()
        if not port:
            self.message.setText("请先连接 DEBUG-USB2，再点击“刷新”。若仍没有 COM 口，请检查设备管理器中的串口驱动。")
            return
        self.device = None
        self.connection.setText("正在查询设备，请稍候…")
        self.run_job(lambda job: self.probe_fn(port), lambda data: self.probed(port, data), "probe")

    def probed(self, port, data):
        self.device = data
        self.checked_port = port
        self.connection.setText(f"已识别 FPGA · {port}\n115200 / 8N1 · 五槽曲库")
        self.set_slots(data["slots"])
        self.message.setText("设备检查通过。请选择曲谱和目标槽位；上传时将重新核对设备。")
        self.record(f"设备检查通过：{port}\n" + json.dumps(data, ensure_ascii=False))

    def choose_file(self, directory=None):
        directory = directory if isinstance(directory, str) else str(self.path.parent if self.path else self.examples)
        path, _ = QFileDialog.getOpenFileName(self, "选择曲谱（BIN 与 JSON 请放在同一目录）", directory,
            "支持的曲谱 (*.xgscore *.csv *.bin *.json);;XG 曲谱包 (*.xgscore);;CSV 曲谱 (*.csv);;编译曲谱 (*.bin *.json)")
        if not path:
            return
        metadata = None
        if Path(path).suffix.lower() == ".bin" and not Path(path).with_suffix(".json").exists():
            metadata, _ = QFileDialog.getOpenFileName(self, "请选择此 BIN 对应的 JSON 元数据", str(Path(path).parent), "曲谱信息 (*.json)")
            if not metadata:
                return
        self.load_path(path, metadata)

    def load_path(self, path, metadata=None):
        self.preview.set_score(None)
        self.notes.playhead = None
        self.path = Path(path)
        self.metadata = metadata
        self.score = None
        self.notes.score = None
        self.notes.update()
        for m in self.metrics:
            m.setText("—")
        self.file_name.setText(self.path.name)
        self.file_name.setToolTip(str(self.path))
        self.score_info.setText("正在读取并校验曲谱…")
        self.progress.setValue(0)
        bpm, timbre = self.bpm.value(), self.timbre.currentIndex()
        self.run_job(lambda job: load_score(path, bpm, timbre, metadata), self.loaded, "load")

    def loaded(self, score):
        self.score = score
        self.timbre.blockSignals(True)
        self.timbre.setCurrentIndex(score.timbre)
        self.timbre.blockSignals(False)
        self.metrics[0].setText(str(len(score.events)))
        self.metrics[1].setText(duration_text(score.seconds))
        self.metrics[2].setText(TIMBRES[score.timbre])
        self.notes.score = score
        self.preview.set_score(score)
        self.notes.update()
        low, high = min(e.midi for e in score.events), max(e.midi for e in score.events)
        self.score_info.setText(f"已校验 · {score.title}\n{score.source} · MIDI {low}–{high} · CRC32 {score.crc32.upper()}")
        self.message.setText("曲谱校验通过。请核对曲目、音色和目标槽位。")
        self.record(f"曲谱校验通过：{score.title}，{len(score.events)} 事件，CRC32 {score.crc32}")

    def csv_changed(self):
        if not self.busy and self.path and self.path.suffix.lower() == ".csv":
            self.load_path(self.path)

    def start_preview(self):
        if self.busy or not self.score:
            return
        try:
            if self.preview_temp is None:
                directory = self.journal.path.parent
                directory.mkdir(parents=True,exist_ok=True)
                self.preview_temp = tempfile.TemporaryDirectory(prefix='audio_',dir=directory,
                                                                ignore_cleanup_errors=True)
        except OSError as exc:
            self.preview.failed("无法创建电脑试听缓存，请检查本机应用数据目录的空间和权限。")
            self.record(str(exc))
            return
        path = Path(self.preview_temp.name)/(uuid.uuid4().hex+'.wav')
        score = self.score
        self.preview.render_started()
        self.message.setText("正在生成电脑试听；无需串口，不会修改上传的曲谱。")
        self.run_job(lambda job:render_preview(score,path,job.cancel,job.progress.emit),
                     self.preview_ready,"render")

    def preview_ready(self, path):
        if self.close_requested or self.worker.cancel.is_set():
            Path(path).unlink(missing_ok=True)
            self.preview.failed("已取消生成电脑试听。")
            return
        try:
            self.preview.ready(path)
        except Exception as exc:
            self.preview.failed("电脑播放组件启动失败，请检查 Windows 音频设备。曲谱仍可正常上传。")
            self.record(str(exc))
            return
        self.message.setText("电脑试听已开始。确认节奏后可上传；实际音色以琴为准。")

    def preview_position(self, ms):
        if self.notes.score:
            self.notes.playhead = ms/(self.notes.score.seconds*1000)
            self.notes.update()

    def export_score(self):
        if not self.score:
            return
        path, _ = QFileDialog.getSaveFileName(self, "另存曲谱包（请选择新文件名）", str(self.path.with_suffix(".xgscore")), "XG 曲谱包 (*.xgscore)")
        if not path:
            return
        if not path.lower().endswith(".xgscore"):
            path += ".xgscore"
        try:
            export_package(self.score, path)
            self.message.setText("曲谱包已保存，可在下次直接打开。")
        except Exception as exc:
            self.show_error(exc)

    def primary_action(self):
        if self.journal.read():
            self.resolve_pending()
        elif not self.device:
            self.check_device()
        elif not self.score:
            self.choose_file()
        else:
            self.start_upload()

    def start_upload(self):
        if self.busy or not self.device or not self.score:
            return
        slot, port, score = self.slot.currentIndex(), self.checked_port, self.score
        expected = dict(self.device["slots"][slot])
        choice = QMessageBox.question(self, "确认上传", f"曲目：{score.title}\n音色：{TIMBRES[score.timbre]}\n事件：{len(score.events)} · 时长：{duration_text(score.seconds)}\n\n目标：{self.slot.currentText()}\n该槽的运行时曲谱将被替换。请让琴保持在主页/选曲页，保持供电。\n\n现在上传？", QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if choice != QMessageBox.Yes:
            return
        self.preview.stop_playback()
        self.progress.setValue(0)
        self.run_job(lambda job: self.upload_fn(port, slot, score, self.journal,
            job.progress.emit, job.stage.emit, job.cancel, expected_slot=expected),
            lambda result: self.uploaded(slot, result), "upload")

    def uploaded(self, slot, result):
        self.device["slots"][slot] = result
        self.set_slots(self.device["slots"])
        self.progress.setValue(100)
        self.message.setText(f"上传成功！请在琴上选择 USER {slot+1}，先试听，再开始练习。保持供电可继续使用。")
        self.completed_target = (self.checked_port, slot, self.score.crc32)
        self.record("上传成功：已收到 COMMIT ACK，且槽位/数量/时长/音色目录回读一致。")

    def on_progress(self, n, total):
        if self.phase == "render":
            self.preview.render_progress(n,total)
            return
        self.progress.setValue(round(95 * n / total))
        self.message.setText(f"已确认 {n} / {total} 个事件 · 请保持连接和供电")

    def on_stage(self, phase, text):
        self.phase = phase
        self.message.setText(text)
        self.record(text)
        self.update_guide()

    def cancel_job(self):
        if self.worker and self.phase in ("upload", "connect", "data", "render"):
            self.worker.cancel.set()
            self.cancel.setEnabled(False)
            self.message.setText("正在取消生成电脑试听…" if self.phase == "render" else
                                 "正在停止传输，并请求释放尚未提交的数据…")

    def show_error(self, exc):
        message = friendly_error(exc)
        self.message.setText(message)
        self.record(f"{type(exc).__name__}: {exc}")
        if self.phase == "probe":
            self.connection.setText("设备检查未通过 · 请看下方提示")
        if self.phase == "load":
            self.score_info.setText("曲谱未通过校验 · 请看下方提示")
        if self.phase == "render":
            self.preview.failed(message)
        if self.phase in ("upload", "connect", "data", "commit", "verify"):
            self.device = None
            self.connection.setText("上传未完成 · 请重新检查设备")
        if isinstance(exc, (CommitUncertain, CommittedUnverified)):
            self.device = None
            self.connection.setText("提交待确认 · 请重新检查设备")
        if not isinstance(exc, Cancelled):
            self.log.show()

    def resolve_pending(self):
        pending = self.journal.read()
        if not pending:
            return
        phase = "已收到 FPGA 提交确认，但回读未完成" if pending.get("phase") == "commit_acknowledged" else "提交是否生效尚未确认"
        text = f"{pending.get('port')} · 第 {pending.get('slot')} 槽 · {pending.get('title', '未知曲目')}\n{phase}。\n\n请先点击“检查设备”，并在琴上试听对应 USER 槽，确认曲目是否已生效。目录没有整曲 CRC，单靠数量和时长不能证明内容相同。\n\n如果已核对实物，或已复位清空导入曲，可以清除此记录。软件不会自动重传。"
        box = QMessageBox(self)
        box.setWindowTitle("处理上次提交")
        box.setText(text)
        clear = box.addButton("我已核对，清除记录", QMessageBox.AcceptRole)
        box.addButton("先返回检查", QMessageBox.RejectRole)
        box.exec_()
        if box.clickedButton() == clear:
            try:
                self.journal.clear()
                self.message.setText("已按你的确认清除待确认记录。重新上传前请检查设备。")
                self.device = None
                self.update_guide()
            except Exception as exc:
                self.show_error(exc)

    def update_guide(self):
        pending = bool(self.journal.read())
        self.recover.setVisible(pending)
        self.recover.setEnabled(not self.busy)
        for w in (self.port, self.refresh, self.check, self.browse, self.slot, self.example):
            w.setEnabled(not self.busy)
        csv = bool(self.path and self.path.suffix.lower() == ".csv")
        self.bpm.setEnabled(csv and not self.busy)
        self.timbre.setEnabled(csv and not self.busy)
        self.export.setEnabled(bool(self.score) and not self.busy)
        self.action.setEnabled(not self.busy)
        self.preview.set_allowed(not self.busy)
        self.cancel.setVisible(self.busy and self.phase in ("upload", "connect", "data", "commit", "verify"))
        self.cancel.setEnabled(self.busy and self.phase in ("upload", "connect", "data") and self.worker and not self.worker.cancel.is_set())
        if self.busy:
            self.guide.setText("正在生成电脑试听，可点击“停止”取消。" if self.phase == "render" else
                               "正在处理，请稍候。提交开始后请保持连接，等待最终结果。")
            self.action.setText("处理中…")
        elif pending:
            self.guide.setText("有一笔上次提交待确认。可先检查设备并试听，再处理记录。")
            self.action.setText("处理上次提交")
        elif not self.device:
            self.guide.setText("第 1 步：连接 DEBUG-USB2，选择 COM 口，再检查设备。")
            self.action.setText("检查设备")
        elif not self.score:
            self.guide.setText("第 2 步：选择曲谱。第一次使用可先打开示例文件夹。")
            self.action.setText("选择曲谱…")
        elif self.completed_target == (self.checked_port, self.slot.currentIndex(), self.score.crc32):
            self.guide.setText(f"上传完成：请在琴上选择 USER {self.slot.currentIndex()+1}，试听后开始练习。")
            self.action.setText("再次上传…")
        else:
            self.guide.setText(f"第 3 步：可先电脑试听 · {self.score.title} → 第 {self.slot.currentIndex()+1} 槽")
            self.action.setText("确认并上传…")

    def record(self, text):
        from datetime import datetime
        self.log.appendPlainText(datetime.now().strftime("%H:%M:%S") + "  " + text)

    def toggle_log(self):
        self.log.setVisible(not self.log.isVisible())

    def help(self):
        QMessageBox.information(self, "三步开始练习", "① 连接设备\n将 DEBUG-USB2 连接电脑，在琴上回到主页或选曲页。刷新串口，选择 COM 后点击“检查设备”。如果不确定 COM 号，可拔插 USB 对照列表。\n\n② 选择曲谱\n新手可用“打开示例曲谱”。.xgscore 是单文件包；BIN 与同名 JSON 需放在一起；CSV 是音符表，可设置速度和音色。拍数支持 1/2、1/3 等分数。样本时间 CSV 已含绝对时间，BPM 不改变其节奏。 选好曲谱后可点“电脑试听”，支持暂停、停止、拖动进度和独立音量，无需连接开发板；电脑参考音用于核对节奏，实际音色以琴为准。\n\n③ 上传与试听\n推荐先用第 2 槽。确认替换后等待成功，再在琴上选择 USER 槽试听。传输进度根据 FPGA 的真实确认更新；提交完成前请保持供电。\n\n曲谱限制\nMIDI 50–79（D3–G5）、最长 10 分钟、最多 1345 个导入事件（五槽共享）。同弦不能重叠，也不能过密。不符合要求会提示原因。图片、PDF 和 MP3 需先整理成音符事件。\n\n常见问题\n串口打不开：关闭其他占用串口的软件。BUSY：回主页/选曲页。NO_SPACE：新曲需要额外暂存空间。提交结果未知：先检查设备和实物，再处理记录，勿直接重传。\n\n导入曲仅保存在 RAM，断电、复位或重新配置后丢失。")

    def closeEvent(self, event):
        if self.busy:
            if self.phase in ("commit", "verify"):
                QMessageBox.information(self, "正在等待提交结果", "正在等待 FPGA 的最终确认。请保持连接，结果返回后再关闭窗口。")
            else:
                self.close_requested = True
                self.cancel_job()
                self.message.setText("正在安全结束当前操作，随后关闭窗口…")
            event.ignore()
            return
        self.preview.release()
        if self.preview_temp:
            self.preview_temp.cleanup()
            self.preview_temp = None
        event.accept()


def main():
    from PyQt5.QtCore import QLockFile, QStandardPaths
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps, True)
    app = QApplication(sys.argv)
    app.setApplicationName("FPGAGuitarUploader")
    app.setOrganizationName("Xinxian")
    app.setStyle("Fusion")
    app.setStyleSheet(STYLE)
    configure_fonts(app)
    from PyQt5.QtGui import QIcon
    app.setWindowIcon(QIcon(str(Path(__file__).resolve().parent/'assets/guitar.ico')))
    data = Path(QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation))
    data.mkdir(parents=True, exist_ok=True)
    lock = QLockFile(str(data / "uploader.lock"))
    lock.setStaleLockTime(0)
    if not lock.tryLock():
        QMessageBox.information(None, "软件已运行", "已有曲谱上传窗口正在运行，请切换到原窗口。")
        return 1
    if getattr(sys, "frozen", False):
        examples = Path(sys.executable).parent / "示例曲谱"
    else:
        examples = Path(__file__).resolve().parent / "examples"
    window = Window(data, examples)
    window.show()
    result = app.exec_()
    lock.unlock()
    return result


def configure_fonts(app):
    # Offscreen Windows tests expose an empty system font database. Load a local
    # Windows font for the same Chinese rendering; no system font is distributed.
    from PyQt5.QtGui import QFontDatabase
    if not QFontDatabase().families():
        fonts = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
        for name in ("msyh.ttc", "segoeui.ttf", "seguisym.ttf"):
            font_id = QFontDatabase.addApplicationFont(str(fonts / name))
            if font_id >= 0 and name == "msyh.ttc":
                families = QFontDatabase.applicationFontFamilies(font_id)
                if families:
                    app.setFont(QFont(families[0], 9))
