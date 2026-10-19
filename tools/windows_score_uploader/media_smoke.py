"""Real Windows Qt/DirectShow playback test at volume zero, no UART access."""
import json
from pathlib import Path


def run(output):
    from PyQt5.QtCore import QTimer,QUrl
    from PyQt5.QtWidgets import QApplication
    from PyQt5.QtMultimedia import QMediaPlayer,QMediaContent
    from game_score_v2 import Event,payload_info
    from .core import Score
    from .preview_audio import render_preview
    output=Path(output).resolve();output.mkdir(parents=True,exist_ok=True)
    event=(Event(0,48000*3,69,0),)
    s=Score('静音播放测试',event,48000*3,0,payload_info(event)[1],'smoke')
    path=output/'media_smoke.wav'
    if not path.exists():render_preview(s,path)
    app=QApplication([])
    player=QMediaPlayer()
    player.setVolume(0)
    player.setNotifyInterval(30)
    report=dict(volume=0,physical_com_opened=False,backend='Qt5 Windows media service',states=[],positions=[])
    done=[False]
    def finish(ok,error=None):
        if done[0]:return
        done[0]=True
        player.stop();player.setMedia(QMediaContent())
        report.update(passed=ok,error=error)
        (output/'media_smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        app.exit(0 if ok else 1)
    def verify_pause():
        if player.state()!=QMediaPlayer.PausedState:
            finish(False,'pause did not hold');return
        player.setPosition(1200)
        player.play()
        QTimer.singleShot(180,verify_resume)
    def verify_resume():
        if player.state()!=QMediaPlayer.PlayingState or player.position()<1100:
            finish(False,'resume/seek failed');return
        report['resumed_position']=player.position()
        player.stop()
        report['stopped']=player.state()==QMediaPlayer.StoppedState
        finish(report['stopped'])
    def position(ms):
        report['positions'].append(ms)
        if ms>80 and not report.get('pause_requested'):
            report['pause_requested']=True
            player.pause()
            QTimer.singleShot(80,verify_pause)
    player.stateChanged.connect(lambda state:report['states'].append(int(state)))
    player.positionChanged.connect(position)
    def error(code):
        if code:
            report['error_code']=int(code)
            finish(False,player.errorString())
    player.error.connect(error)
    player.setMedia(QMediaContent(QUrl.fromLocalFile(str(path))))
    QTimer.singleShot(0,player.play)
    QTimer.singleShot(8000,lambda:finish(False,'playback timeout'))
    return app.exec_()
