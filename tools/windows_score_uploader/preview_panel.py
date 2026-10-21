"""Audition controls with lazy Windows media backend and no serial access."""
from pathlib import Path

from PyQt5.QtCore import Qt, QUrl, pyqtSignal
from PyQt5.QtMultimedia import QMediaContent, QMediaPlayer
from PyQt5.QtWidgets import QHBoxLayout, QLabel, QPushButton, QSlider, QVBoxLayout, QWidget


def time_text(ms):
    seconds = max(0, int(ms)) // 1000
    return f"{seconds//60}:{seconds%60:02d}"


class PreviewPanel(QWidget):
    render_requested = pyqtSignal()
    cancel_requested = pyqtSignal()
    position_changed = pyqtSignal(int)

    def __init__(self, parent=None, player_factory=None):
        super().__init__(parent)
        self.player_factory = player_factory or (lambda: QMediaPlayer(self))
        self.player = None
        self.score = None
        self.path = None
        self.rendering = False
        self.allowed = True
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(6)
        row = QHBoxLayout()
        self.play = QPushButton("电脑试听")
        self.play.clicked.connect(self.toggle)
        self.stop = QPushButton("停止")
        self.stop.clicked.connect(self.stop_playback)
        self.clock = QLabel("0:00 / 0:00")
        self.clock.setMinimumWidth(86)
        row.addWidget(self.play)
        row.addWidget(self.stop)
        row.addWidget(self.clock)
        row.addStretch(1)
        row.addWidget(QLabel("音量"))
        self.volume = QSlider(Qt.Horizontal)
        self.volume.setRange(0,100)
        self.volume.setValue(35)
        self.volume.setFixedWidth(85)
        self.volume.setToolTip("仅控制电脑试听音量，不修改曲谱或琴上的增益。")
        self.volume.valueChanged.connect(self.set_volume)
        row.addWidget(self.volume)
        lay.addLayout(row)
        self.seek = QSlider(Qt.Horizontal)
        self.seek.setRange(0,0)
        self.seek.sliderReleased.connect(self.seek_to_slider)
        self.seek.setToolTip("拖动可跳转试听位置，不改变曲谱内容或速度。")
        lay.addWidget(self.seek)
        self.hint = QLabel("选择曲谱即可试听，无需连接开发板。电脑参考音，实际音色以琴为准。")
        self.hint.setWordWrap(True)
        self.hint.setObjectName("muted")
        lay.addWidget(self.hint)
        self.update_controls()

    def ensure_player(self):
        if self.player is not None:
            return
        self.player = self.player_factory()
        self.player.setNotifyInterval(50)
        self.player.setVolume(self.volume.value())
        self.player.stateChanged.connect(self.state_changed)
        self.player.positionChanged.connect(self.position)
        self.player.mediaStatusChanged.connect(self.media_status)
        self.player.error.connect(self.audio_error)

    def set_score(self, score):
        self.release()
        self.score = score
        duration = round(score.seconds*1000) if score else 0
        self.seek.setRange(0,duration)
        self.clock.setText(f"0:00 / {time_text(duration)}")
        self.hint.setText("点击“电脑试听”核对旋律与节奏。参考合成音，实际音色以琴为准。" if score else
                          "选择曲谱即可试听，无需连接开发板。电脑参考音，实际音色以琴为准。")
        self.update_controls()

    def set_allowed(self, allowed):
        self.allowed = allowed
        self.update_controls()

    def update_controls(self):
        self.play.setEnabled(bool(self.score) and self.allowed and not self.rendering)
        self.stop.setEnabled(bool(self.score) and (self.allowed or self.rendering))
        self.seek.setEnabled(bool(self.path) and self.allowed and not self.rendering)
        self.volume.setEnabled(self.allowed or self.rendering)
        if self.rendering:
            self.play.setText("正在生成…")
        elif self.player and self.player.state() == QMediaPlayer.PlayingState:
            self.play.setText("暂停")
        elif self.player and self.player.state() == QMediaPlayer.PausedState:
            self.play.setText("继续试听")
        else:
            self.play.setText("电脑试听")

    def toggle(self):
        if not self.score or not self.allowed or self.rendering:
            return
        if self.player and self.player.state() == QMediaPlayer.PlayingState:
            self.player.pause()
        elif self.path:
            if self.player.position() >= self.seek.maximum()-5:
                self.player.setPosition(0)
            self.player.play()
        else:
            self.render_requested.emit()

    def render_started(self):
        self.rendering = True
        self.hint.setText("正在生成电脑参考音，可点击“停止”取消…")
        self.update_controls()

    def render_progress(self, n, total):
        self.hint.setText(f"正在生成电脑参考音 · {round(100*n/total)}% · 可点击“停止”取消")

    def ready(self, path, autoplay=True):
        self.rendering = False
        self.path = Path(path)
        self.ensure_player()
        self.player.setMedia(QMediaContent(QUrl.fromLocalFile(str(self.path.resolve()))))
        self.hint.setText("参考合成音用于核对旋律与节奏；实际音色以琴为准。")
        if autoplay:
            self.player.play()
        self.update_controls()

    def failed(self, message):
        self.rendering = False
        self.hint.setText(message)
        self.update_controls()

    def state_changed(self, state):
        self.update_controls()

    def position(self, ms):
        ms = min(max(0,ms),self.seek.maximum())
        if not self.seek.isSliderDown():
            self.seek.setValue(ms)
        self.clock.setText(f"{time_text(ms)} / {time_text(self.seek.maximum())}")
        self.position_changed.emit(ms)

    def seek_to_slider(self):
        if self.player and self.path:
            self.player.setPosition(self.seek.value())

    def set_volume(self, value):
        if self.player:
            self.player.setVolume(value)

    def stop_playback(self):
        if self.rendering:
            self.cancel_requested.emit()
            self.hint.setText("正在取消生成试听…")
        if self.player:
            self.player.stop()
            self.player.setPosition(0)
        self.position(0)
        self.update_controls()

    def release(self):
        self.stop_playback()
        if self.player:
            self.player.setMedia(QMediaContent())
        old, self.path = self.path, None
        if old:
            try:
                old.unlink(missing_ok=True)
            except OSError:
                pass  # Windows decoder may release asynchronously; cleanup on close.

    def media_status(self, status):
        if status == QMediaPlayer.EndOfMedia:
            self.position(self.seek.maximum())
            self.hint.setText("试听已结束，可再次播放或上传。实际音色以琴为准。")
        elif status == QMediaPlayer.InvalidMedia:
            self.audio_error(QMediaPlayer.FormatError)

    def audio_error(self, code):
        if code != QMediaPlayer.NoError:
            self.hint.setText("电脑音频播放失败。请检查 Windows 输出设备/音量后重试；仍可正常上传曲谱。 " + self.player.errorString())
            self.update_controls()
