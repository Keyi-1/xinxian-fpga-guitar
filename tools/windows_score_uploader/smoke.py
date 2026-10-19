"""Frozen-runtime smoke test, using no COM enumeration, port or user settings."""
import json
from pathlib import Path
import tempfile


def run(output):
    from PyQt5.QtCore import QTimer, Qt
    from PyQt5.QtWidgets import QApplication
    from .window import Window, STYLE, configure_fonts
    from .core import load_score
    from .preview_audio import render_preview
    import wave
    import serial
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    app = QApplication([])
    app.setStyle("Fusion")
    app.setStyleSheet(STYLE)
    configure_fonts(app)
    import sys
    examples = (Path(sys.executable).parent/'示例曲谱') if getattr(sys, 'frozen', False) else Path(__file__).parent/'examples'
    with tempfile.TemporaryDirectory(dir=output) as temp:
        window = Window(temp, examples, port_provider=lambda:[])
        score = load_score(examples/'情歌_60BPM.xgscore')
        window.path = examples/'情歌_60BPM.xgscore'
        window.file_name.setText(window.path.name)
        window.loaded(score)
        window.update_guide()
        window.show()

        def done():
            try:
                assert score.crc32 == 'c3451bbc' and len(score.events) == 212
                assert serial.VERSION == '3.5'
                assert window.action.isVisible() and window.export.isEnabled()
                assert window.preview.play.isEnabled() and window.preview.player is None
                small=load_score(examples/'入门示例.csv')
                audio=Path(temp)/'preview.wav'
                render_preview(small,audio)
                with wave.open(str(audio),'rb') as wav:
                    assert (wav.getnframes(),wav.getframerate(),wav.getsampwidth())==(384000,48000,2)
                assert window.grab().save(str(output/'frozen_ui.png'))
                (output/'smoke.json').write_text(json.dumps(dict(
                    passed=True, frozen=bool(getattr(sys, 'frozen', False)),
                    events=len(score.events), crc32=score.crc32,
                    serial_version=serial.VERSION, physical_com_opened=False,
                    preview_samples=384000, audio_device_opened=False,
                    executable=sys.executable), ensure_ascii=False, indent=2), encoding='utf-8')
            except Exception as exc:
                (output/'smoke_error.txt').write_text(repr(exc), encoding='utf-8')
                app.exit(1)
                return
            window.close()
            app.quit()

        QTimer.singleShot(200, done)
        return app.exec_()
