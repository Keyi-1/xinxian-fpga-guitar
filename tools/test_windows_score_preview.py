"""PC synthesis/timeline and playback control regressions; fake audio by default."""
from array import array
import hashlib
import math
import os
from pathlib import Path
import tempfile
import threading
import unittest
import wave

from game_score_v2 import Event,payload_info
from windows_score_uploader.core import Score,Cancelled,load_score
from windows_score_uploader.preview_audio import render_preview,RATE

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/windows_uploader/preview_1_1'
os.environ.setdefault('QT_QPA_PLATFORM','offscreen')


def score(events,duration,timbre=1):
    return Score('试听测试',tuple(events),duration,timbre,payload_info(events)[1],'test')


def samples(path):
    with wave.open(str(path),'rb') as wav:
        assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate())==(1,2,RATE)
        result=array('h',wav.readframes(wav.getnframes()))
        return result


class RenderTests(unittest.TestCase):
    def setUp(self):
        OUT.mkdir(parents=True,exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=OUT)
        self.folder=Path(self.temp.name)

    def tearDown(self):self.temp.cleanup()

    def render(self,s,name='test.wav',**kwargs):
        path=self.folder/name
        render_preview(s,path,**kwargs)
        return samples(path)

    def test_sample_positions_rests_and_declared_trailing_silence(self):
        s=score([Event(123,2400,60,0),Event(4801,1200,64,1)],8000)
        pcm=self.render(s)
        self.assertEqual(len(pcm),8000)
        self.assertFalse(any(pcm[:123]))
        self.assertTrue(any(pcm[124:2522]))
        self.assertFalse(any(pcm[2523:4801]))
        self.assertTrue(any(pcm[4802:6000]))
        self.assertFalse(any(pcm[6001:]))

    def test_known_a440_pitch(self):
        pcm=self.render(score([Event(0,24000,69,0)],24000,0))
        # Independent sinusoidal correlation locates the fundamental in Hz.
        chunk=pcm[2000:10000]
        def energy(hz):
            a=sum(x*math.cos(math.tau*hz*i/RATE) for i,x in enumerate(chunk))
            b=sum(x*math.sin(math.tau*hz*i/RATE) for i,x in enumerate(chunk))
            return a*a+b*b
        best=max(range(430,451),key=energy)
        self.assertLessEqual(abs(best-440),1)

    def test_four_voices_no_overflow_and_velocity_ratios(self):
        group=[Event(0,16000,60+i*4,i,velocity=3) for i in range(4)]
        pcm=self.render(score(group,16000))
        self.assertGreater(max(map(abs,pcm)),1000)
        self.assertLess(max(map(abs,pcm)),32767)
        levels=[]
        for v in range(4):
            pcm=self.render(score([Event(0,8000,60,0,velocity=v)],8000),f'v{v}.wav')
            levels.append(sum(x*x for x in pcm)**.5)
        for i,level in enumerate(levels):
            self.assertAlmostEqual(level/levels[-1],(i+1)/4,delta=.002)

    def test_reference_timbres_differ_and_tie_has_no_retrigger(self):
        results=[]
        for t in range(3):
            pcm=self.render(score([Event(0,48000,64,0)],48000,t),f't{t}.wav')
            self.assertGreater(sum(x*x for x in pcm[23900:24100]),10000)
            results.append(hashlib.sha256(pcm.tobytes()).hexdigest())
        self.assertEqual(len(set(results)),3)

    def test_chunk_boundary_keeps_sample_count_and_event_start(self):
        s=score([Event(8191,9000,79,0),Event(18000,1600,50,1)],22000)
        a=self.render(s,'a.wav',block_size=8192)
        b=self.render(s,'b.wav',block_size=4096)
        self.assertEqual(a,b)

    def test_cancel_cleans_partial_and_never_overwrites(self):
        path=self.folder/'cancel.wav';cancel=threading.Event()
        s=score([Event(0,48000,60,0)],48000)
        with self.assertRaises(Cancelled):
            render_preview(s,path,cancel,lambda n,t:cancel.set())
        self.assertFalse(path.exists())
        path.write_bytes(b'user audio')
        with self.assertRaises(FileExistsError):render_preview(s,path)
        self.assertEqual(path.read_bytes(),b'user audio')

    def test_cancel_before_start_and_invalid_score_do_not_create_file(self):
        path=self.folder/'none.wav';cancel=threading.Event();cancel.set()
        with self.assertRaises(Cancelled):render_preview(score([Event(0,4800,60,0)],4800),path,cancel)
        self.assertFalse(path.exists())
        with self.assertRaises(ValueError):render_preview(score([Event(0,4800,80,0)],4800),path)
        self.assertFalse(path.exists())


from PyQt5.QtCore import QObject,pyqtSignal
from PyQt5.QtMultimedia import QMediaPlayer


class FakePlayer(QObject):
    stateChanged=pyqtSignal(int)
    positionChanged=pyqtSignal(int)
    mediaStatusChanged=pyqtSignal(int)
    error=pyqtSignal(int)

    def __init__(self):
        super().__init__();self.status=QMediaPlayer.StoppedState;self.ms=0;self.level=0;self.calls=[]
    def setNotifyInterval(self,value):pass
    def setVolume(self,value):self.level=value
    def setMedia(self,content):self.calls.append(('media',content.isNull()))
    def state(self):return self.status
    def position(self):return self.ms
    def setPosition(self,ms):self.ms=ms;self.positionChanged.emit(ms)
    def play(self):self.status=QMediaPlayer.PlayingState;self.calls.append('play');self.stateChanged.emit(self.status)
    def pause(self):self.status=QMediaPlayer.PausedState;self.calls.append('pause');self.stateChanged.emit(self.status)
    def stop(self):self.status=QMediaPlayer.StoppedState;self.calls.append('stop');self.stateChanged.emit(self.status)
    def errorString(self):return '模拟音频设备不可用'


class PlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PyQt5.QtWidgets import QApplication
        from windows_score_uploader.window import STYLE,configure_fonts
        cls.app=QApplication.instance() or QApplication([])
        cls.app.setStyle('Fusion');cls.app.setStyleSheet(STYLE);configure_fonts(cls.app)
        OUT.mkdir(parents=True,exist_ok=True)

    def test_play_pause_resume_seek_volume_end_and_stop(self):
        from windows_score_uploader.preview_panel import PreviewPanel
        with tempfile.TemporaryDirectory(dir=OUT) as temp:
            player=FakePlayer();panel=PreviewPanel(player_factory=lambda:player)
            s=score([Event(0,48000,60,0)],48000)
            panel.set_score(s)
            path=Path(temp)/'test.wav';render_preview(s,path)
            panel.ready(path)
            self.assertEqual(player.state(),QMediaPlayer.PlayingState)
            self.assertEqual(player.level,35)
            panel.toggle();self.assertEqual(player.state(),QMediaPlayer.PausedState)
            panel.toggle();self.assertEqual(player.state(),QMediaPlayer.PlayingState)
            panel.seek.setValue(500);panel.seek_to_slider();self.assertEqual(player.ms,500)
            panel.volume.setValue(12);self.assertEqual(player.level,12)
            panel.media_status(QMediaPlayer.EndOfMedia);self.assertIn('已结束',panel.hint.text())
            panel.stop_playback();self.assertEqual(player.ms,0)
            panel.set_score(None);self.assertIsNone(panel.path)
            self.assertFalse(panel.play.isEnabled());self.assertFalse(path.exists())
            panel.close()

    def test_no_autoplay_on_import_and_error_does_not_touch_score(self):
        from windows_score_uploader.preview_panel import PreviewPanel
        made=[]
        def factory():made.append(True);return FakePlayer()
        panel=PreviewPanel(player_factory=factory)
        s=score([Event(0,48000,60,0)],48000)
        panel.set_score(s);self.assertFalse(made)
        panel.ensure_player();panel.audio_error(QMediaPlayer.ResourceError)
        self.assertIn('Windows',panel.hint.text())
        self.assertIs(panel.score,s);self.assertTrue(panel.play.isEnabled())
        panel.close()

    def test_window_offline_preview_render_change_and_close(self):
        from PyQt5.QtTest import QTest
        from windows_score_uploader.window import Window
        import time
        with tempfile.TemporaryDirectory(dir=OUT) as temp:
            player=FakePlayer()
            w=Window(temp,ROOT/'tools/windows_score_uploader/examples',port_provider=lambda:[],player_factory=lambda:player)
            w.show()
            def wait():
                deadline=time.monotonic()+15
                while w.busy and time.monotonic()<deadline:QTest.qWait(10)
                self.assertFalse(w.busy)
            w.load_path(ROOT/'tools/windows_score_uploader/examples/入门示例.csv');wait()
            self.assertIsNone(w.device)
            before=w.score.package()
            w.preview.toggle();wait()
            self.assertEqual(player.state(),QMediaPlayer.PlayingState)
            self.assertEqual(w.score.package(),before)
            player.setPosition(2000)
            self.assertEqual(w.notes.playhead,.25)
            QTest.qWait(30)
            w.grab().save(str(OUT/'ui_preview_playing.png'))
            w.bpm.setValue(120);w.csv_changed();wait()
            self.assertEqual(w.score.seconds,4)
            self.assertEqual(player.state(),QMediaPlayer.StoppedState)
            self.assertIsNone(w.preview.path)
            w.load_path(ROOT/'tools/windows_score_uploader/examples/情歌_60BPM.xgscore');wait()
            self.assertEqual(player.state(),QMediaPlayer.StoppedState)
            self.assertIsNone(w.preview.path)
            w.close()
            self.assertIsNone(w.preview_temp)

    def test_cancelled_render_never_starts_audio(self):
        from PyQt5.QtTest import QTest
        from windows_score_uploader.window import Window
        import time
        with tempfile.TemporaryDirectory(dir=OUT) as temp:
            player=FakePlayer()
            w=Window(temp,OUT,port_provider=lambda:[],player_factory=lambda:player)
            w.loaded(score([Event(0,RATE*30,60,0)],RATE*30))
            w.start_preview();w.preview.stop_playback()
            deadline=time.monotonic()+10
            while w.busy and time.monotonic()<deadline:QTest.qWait(10)
            self.assertFalse(w.busy)
            self.assertNotIn('play',player.calls)
            self.assertFalse(list(Path(w.preview_temp.name).glob('*.wav')))
            w.close()


if __name__=='__main__':unittest.main()
