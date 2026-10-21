"""PC frontend fault tests; no physical COM port or FPGA programming."""
import base64
import json
import os
from pathlib import Path
import struct
import tempfile
import threading
import unittest
from unittest.mock import patch

from game_score_upload import packet, decode_packet, HELLO, LIST, BEGIN, DATA, COMMIT, ABORT
from game_score_v2 import Event, payload_info
from windows_score_uploader.core import (Journal, Score, Cancelled, CommitUncertain,
    CommittedUnverified, load_score, export_package, upload, probe, friendly_error)

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")


class Board:
    """Stateful framed device double: replay cache, partial IO, actual descriptor."""
    def __init__(self, reject=None, drop=None, mismatch=False, disconnect=None):
        self.pending = bytearray()
        self.reply = bytearray()
        self.cache = {}
        self.executed = []
        self.writes = []
        self.closed = False
        self.slots = [dict(slot=i, valid=True, playable=False, imported=False,
                          test_only=False, base=703, event_count=0,
                          duration_samples=0, progress_step=0, recommended_timbre=0) for i in range(5)]
        self.reject = reject or {}
        self.drop = drop or {}
        self.disconnect = disconnect
        self.mismatch = mismatch
        self.staging = []
        self.committed = False

    def write(self, data):
        part = bytes(data[:7])
        self.pending.extend(part)
        if len(self.pending) < 32:
            return len(part)
        wire = bytes(self.pending[:32])
        del self.pending[:32]
        op, session, seq, body = decode_packet(wire)
        self.writes.append(wire)
        if self.disconnect == op:
            raise OSError("Cable disconnected during command")
        key = (session, seq)
        if key not in self.cache:
            self.executed.append(op)
            reply = bytearray(16)
            if op in self.reject:
                reply[0] = self.reject[op]
            elif op == HELLO:
                reply[1:] = struct.pack('<BBBHHBBIH', 2, 5, 32, 703, 2048, 50, 79, 48000, 1)
            elif op == LIST:
                d = self.slots[body[0]]
                word = (d['progress_step'] | d['base'] << 32 | d['event_count'] << 43 |
                        d['duration_samples'] << 55 | d['recommended_timbre'] << 87)
                reply[1:13] = word.to_bytes(12, 'little')
                reply[13] = body[0]
                reply[14] = int(d['valid']) | int(d['playable']) << 1 | int(d['imported']) << 2 | int(d['test_only']) << 3
            elif op == BEGIN:
                self.target, self.timbre, self.count, self.duration, self.crc, _ = struct.unpack('<BBHIII', body)
                self.staging = []
            elif op == DATA:
                self.staging.append(body)
            elif op == COMMIT:
                assert len(self.staging) == self.count
                import zlib
                assert zlib.crc32(b''.join(self.staging)) == self.crc
                self.committed = True
                self.slots[self.target].update(playable=True, imported=True,
                    event_count=self.count + int(self.mismatch), duration_samples=self.duration,
                    recommended_timbre=self.timbre, progress_step=(self.duration + 479)//480)
            self.cache[key] = packet(op | 0x80, session, seq, reply)
        n = self.drop.get(op, 0)
        if n:
            self.drop[op] = n-1
        else:
            self.reply.extend(b"noise")
            self.reply.extend(self.cache[key])
        return len(part)

    def read(self, n):
        data = bytes(self.reply[:min(5, n)])
        del self.reply[:len(data)]
        return data

    def close(self):
        self.closed = True


class DesktopTests(unittest.TestCase):
    def setUp(self):
        root = ROOT / 'build/windows_uploader/tests'
        root.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=root)
        self.folder = Path(self.temp.name)
        self.journal = Journal(self.folder / 'pending.json')
        events = (Event(0, 12000, 60, 0), Event(24000, 12000, 62, 1))
        self.score = Score('测试曲', events, 48000, 1, payload_info(events)[1], 'test')

    def tearDown(self):
        self.temp.cleanup()

    def run_upload(self, board, **kwargs):
        return upload('COM9', 1, self.score, self.journal, kwargs.pop('progress', lambda n,t:None),
            kwargs.pop('stage', lambda p,t:None), factory=lambda port:board, timeout=.001, **kwargs)

    def save_package(self):
        p = self.folder / '曲谱.xgscore'
        export_package(self.score, p)
        return p

    def test_package_roundtrip_and_exclusive_export(self):
        path = self.save_package()
        self.assertEqual(load_score(path).events, self.score.events)
        with self.assertRaises(FileExistsError): export_package(self.score, path)

    def test_tampered_packages_and_metadata_types(self):
        path = self.save_package()
        for key, value in [('event_count', 3), ('duration_samples', '48000'),
                           ('recommended_timbre', True), ('crc32', '00000000'),
                           ('payload_sha256', '0'*64), ('payload_base64', '%%%'),
                           ('format_version', 1), ('title', ''), ('package_version', 2)]:
            data = self.score.package()
            data[key] = value
            path.write_text(json.dumps(data), encoding='utf-8')
            with self.subTest(key=key), self.assertRaises((ValueError, TypeError)):
                load_score(path)

    def test_bin_json_pair(self):
        data = self.score.package()
        path = self.folder / 'test.bin'
        path.write_bytes(payload_info(self.score.events)[0])
        path.with_suffix('.json').write_text(json.dumps(data | {'package_format': ''}), encoding='utf-8')
        self.assertEqual(load_score(path).events, self.score.events)
        self.assertEqual(load_score(path.with_suffix('.json')).crc32, self.score.crc32)
        path.write_bytes(bytes(len(path.read_bytes())))
        with self.assertRaises(ValueError): load_score(path)

    def test_exact_fraction_csv_and_sample_time(self):
        path = self.folder / 'test.csv'
        path.write_text('onset_beats,duration_beats,midi_note,lane\n0,1/3,60,\n1/3,2/3,62,\n', encoding='utf-8-sig')
        score = load_score(path)
        self.assertEqual([e.onset for e in score.events], [0,16000])
        self.assertEqual([e.duration for e in score.events], [16000,32000])
        self.assertNotEqual(score.events[0].lane, score.events[1].lane)
        self.assertEqual(load_score(path, 120).duration, 24000)
        path.write_text('t_on_samples,duration_samples,midi_note,lane\n0,12000,60,0\n', encoding='utf-8')
        self.assertEqual(load_score(path, 120).duration, load_score(path, 60).duration)

    def test_range_conflict_capacity_and_empty(self):
        path = self.folder / 'test.csv'
        for content in ['onset_beats,duration_beats,midi_note,lane\n0,2,60,0\n1,1,62,0\n',
                        'onset_beats,duration_beats,midi_note,lane\n0,1,80,\n', '',
                        'onset_beats,duration_beats,midi_note,lane\n' + ''.join(f'{i/4},1/4,60,{i%4}\n' for i in range(1346))]:
            path.write_text(content, encoding='utf-8')
            with self.assertRaises(ValueError): load_score(path)

    def test_oversized_and_non_object(self):
        path = self.folder / 'test.json'
        path.write_text('[]', encoding='utf-8')
        with self.assertRaises(ValueError): load_score(path)
        path.write_bytes(b'x'*(512*1024+1))
        with self.assertRaises(ValueError): load_score(path)

    def test_official_revised_qing_ge(self):
        path = ROOT / 'tools/windows_score_uploader/examples/情歌_60BPM.xgscore'
        score = load_score(path)
        self.assertEqual((len(score.events), score.duration, score.timbre, score.crc32), (212,7296000,1,'c3451bbc'))

    def test_probe_closes_without_begin(self):
        board = Board()
        self.assertEqual(len(probe('COM9', lambda port:board)['slots']), 5)
        self.assertNotIn(BEGIN, board.executed)
        self.assertTrue(board.closed)

    def test_upload_partial_io_replay_and_real_progress(self):
        board = Board(drop={DATA:1, COMMIT:1})
        progress, stages = [], []
        result = self.run_upload(board, progress=lambda n,t:progress.append((n,t)), stage=lambda p,t:stages.append(p))
        self.assertEqual(result['event_count'], 2)
        self.assertEqual(progress, [(1,2),(2,2)])
        self.assertEqual(board.executed.count(DATA), 2)
        self.assertEqual(board.executed.count(COMMIT), 1)
        self.assertFalse(self.journal.read())
        self.assertTrue(board.closed)
        self.assertEqual(stages, ['connect','data','commit','verify'])

    def test_busy_and_full_do_not_publish(self):
        for status in [1,2]:
            board = Board(reject={BEGIN:status})
            with self.assertRaises(RuntimeError): self.run_upload(board)
            self.assertFalse(board.committed)
            self.assertNotIn(DATA, board.executed)
            self.assertTrue(board.closed)

    def test_cancel_after_data_sends_abort_not_commit(self):
        cancel = threading.Event()
        board = Board()
        with self.assertRaises(Cancelled):
            self.run_upload(board, cancel=cancel, progress=lambda n,t:cancel.set())
        self.assertIn(ABORT, board.executed)
        self.assertNotIn(COMMIT, board.executed)
        self.assertIsNone(self.journal.read())

    def test_cancel_before_begin(self):
        cancel = threading.Event()
        cancel.set()
        board = Board()
        with self.assertRaises(Cancelled): self.run_upload(board, cancel=cancel)
        self.assertNotIn(BEGIN, board.executed)

    def test_data_disconnect_aborts_without_commit_marker(self):
        board = Board(disconnect=DATA)
        with self.assertRaises(OSError): self.run_upload(board)
        self.assertNotIn(COMMIT, board.executed)
        self.assertIn(ABORT, board.executed)
        self.assertIsNone(self.journal.read())

    def test_commit_lost_ack_survives_restart_and_blocks_reupload(self):
        board = Board(drop={COMMIT:99})
        with self.assertRaises(CommitUncertain): self.run_upload(board)
        self.assertTrue(board.committed)
        self.assertEqual(Journal(self.journal.path).read()['phase'], 'commit_pending')
        self.assertNotIn(ABORT, board.executed)
        board2 = Board()
        with self.assertRaises(ValueError): self.run_upload(board2)
        self.assertFalse(board2.writes)

    def test_commit_disconnect_is_also_unknown(self):
        board = Board(disconnect=COMMIT)
        with self.assertRaises(CommitUncertain): self.run_upload(board)
        self.assertIsNotNone(self.journal.read())

    def test_commit_nack_is_definite_and_readback_mismatch_is_committed(self):
        board = Board(reject={COMMIT:4})
        with self.assertRaises(RuntimeError): self.run_upload(board)
        self.assertIsNone(self.journal.read())
        board = Board(mismatch=True)
        with self.assertRaises(CommittedUnverified): self.run_upload(board)
        self.assertEqual(self.journal.read()['phase'], 'commit_acknowledged')

    def test_changed_slot_rejected_before_begin(self):
        board = Board()
        expected = dict(board.slots[1], event_count=2)
        with self.assertRaisesRegex(ValueError, '发生变化'): self.run_upload(board, expected_slot=expected)
        self.assertNotIn(BEGIN, board.executed)

    def test_journal_must_be_writable_before_commit(self):
        board = Board()
        with patch.object(self.journal, 'write', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.run_upload(board)
        self.assertNotIn(COMMIT, board.executed)
        self.assertIn(ABORT, board.executed)

    def test_error_guidance(self):
        self.assertIn('主页', friendly_error(RuntimeError('BUSY')))
        self.assertIn('空间', friendly_error(RuntimeError('NO_SPACE')))
        self.assertIn('占用', friendly_error(PermissionError('blocked')))


class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PyQt5.QtWidgets import QApplication
        from windows_score_uploader.window import STYLE, configure_fonts
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setStyle('Fusion')
        cls.app.setStyleSheet(STYLE)
        configure_fonts(cls.app)

    def test_guided_workflow_worker_upload_and_screenshots(self):
        from PyQt5.QtWidgets import QMessageBox
        from PyQt5.QtTest import QTest
        from windows_score_uploader.window import Window
        root = ROOT / 'build/windows_uploader'
        root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as temp:
            board = Board()
            w = Window(temp, ROOT/'tools/windows_score_uploader/examples',
                       port_provider=lambda:[('COM9','模拟 FPGA · 非实物')],
                       probe_fn=lambda port:probe(port, lambda p:board),
                       upload_fn=lambda *a,**kw:upload(*a,**kw,factory=lambda p:board,timeout=.001))
            w.show()
            QTest.qWait(80)
            self.assertIn('第 1 步', w.guide.text())
            w.grab().save(str(root/'ui_empty.png'))
            w.check_device()
            self.wait_job(w)
            self.assertIn('第 2 步', w.guide.text())
            w.load_path(ROOT/'tools/windows_score_uploader/examples/情歌_60BPM.xgscore')
            self.wait_job(w)
            self.assertEqual(w.metrics[0].text(), '212')
            self.assertIn('第 3 步', w.guide.text())
            self.assertFalse(w.timbre.isEnabled())
            w.grab().save(str(root/'ui_ready.png'))
            w.resize(900, 650)
            QTest.qWait(30)
            from PyQt5.QtCore import QPoint
            self.assertTrue(w.rect().contains(w.action.mapTo(w, QPoint(w.action.width()//2, w.action.height()//2))))
            w.grab().save(str(root/'ui_compact.png'))
            w.resize(1100, 825)
            QTest.qWait(30)
            with patch.object(QMessageBox, 'question', return_value=QMessageBox.Yes):
                w.start_upload()
            self.wait_job(w)
            self.assertIn('上传成功', w.message.text())
            self.assertEqual(w.progress.value(), 100)
            w.grab().save(str(root/'ui_success.png'))
            w.port_changed()
            self.assertIsNone(w.device)
            w.close()

    def test_no_port_and_bad_file_remove_ready_state(self):
        from windows_score_uploader.window import Window
        root = ROOT/'build/windows_uploader'
        with tempfile.TemporaryDirectory(dir=root) as temp:
            w = Window(temp, root, port_provider=lambda:[])
            w.check_device()
            self.assertIn('驱动', w.message.text())
            w.load_path(root/'does_not_exist.xgscore')
            self.wait_job(w)
            self.assertIsNone(w.score)
            self.assertFalse(w.export.isEnabled())
            w.close()

    def test_file_timbre_is_reflected_in_disabled_selector(self):
        from windows_score_uploader.window import Window
        root = ROOT/'build/windows_uploader'
        with tempfile.TemporaryDirectory(dir=root) as temp:
            events = (Event(0, 12000, 60, 0),)
            score = Score('钢琴例子', events, 48000, 0, payload_info(events)[1], 'test')
            path = Path(temp)/'piano.xgscore'
            export_package(score, path)
            w = Window(temp, root, port_provider=lambda:[])
            w.load_path(path)
            self.wait_job(w)
            self.assertEqual(w.timbre.currentIndex(), 0)
            self.assertEqual(w.metrics[2].text(), '钢琴')
            self.assertFalse(w.timbre.isEnabled())
            w.close()

    @classmethod
    def wait_job(cls, window):
        from PyQt5.QtTest import QTest
        import time
        deadline = time.monotonic()+10
        while window.busy and time.monotonic()<deadline:
            QTest.qWait(10)
        cls().assertFalse(window.busy, 'GUI worker did not finish')


if __name__ == '__main__':
    unittest.main()
