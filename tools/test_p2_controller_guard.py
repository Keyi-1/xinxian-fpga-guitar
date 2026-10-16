"""Negative tests for the single-module A5 certificate exception; no RTL writes."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import check_game_p2_result as checker

parser=argparse.ArgumentParser()
parser.add_argument('--build-dir',type=Path,required=True)
args=parser.parse_args()
manifest=json.loads(checker.read(args.build_dir/'source_manifest.json'))


class ControllerGuard(unittest.TestCase):
    def setUp(self):
        checker.EQUIVALENT_SOURCE_REPLACEMENTS.clear()
        self.manifest=deepcopy(manifest)

    def test_current_proof(self):
        self.assertEqual(checker.controller_equivalence(self.manifest)['result'],'PASS')

    def test_wrong_baseline_rejected(self):
        self.manifest['controller_optimization']['baseline_commit']='master'
        with self.assertRaises(AssertionError):checker.controller_equivalence(self.manifest)

    def test_other_module_rejected(self):
        self.manifest['controller_optimization']['only_changed_source']='rtl/audio_io/four_string_board_audio_chain.v'
        with self.assertRaises(AssertionError):checker.controller_equivalence(self.manifest)

    def test_wrong_receipt_hash_rejected(self):
        self.manifest['controller_optimization']['equivalence_sha256']='0'*64
        with self.assertRaises(AssertionError):checker.controller_equivalence(self.manifest)

    def test_untested_current_controller_rejected(self):
        original=checker.digest
        def changed(path):
            return '0'*64 if Path(path)==checker.ROOT/'rtl/game/game_p2_window_controller.v' else original(path)
        with patch.object(checker,'digest',side_effect=changed):
            with self.assertRaises(AssertionError):checker.controller_equivalence(self.manifest)

    def test_changed_reference_rejected(self):
        original=Path.read_bytes
        ref=checker.ROOT/'sim/reference/game_p2/game_p2_window_controller_a4.v'
        def changed(path):return original(path)+b'\n' if path==ref else original(path)
        with patch.object(Path,'read_bytes',changed):
            with self.assertRaises(AssertionError):checker.controller_equivalence(self.manifest)

    def test_other_asset_and_unknown_old_controller_hash_rejected(self):
        checker.controller_equivalence(self.manifest)
        with self.assertRaises(AssertionError):checker.verified_source('rtl/audio_io/four_string_board_audio_chain.v','0'*64)
        with self.assertRaises(AssertionError):checker.verified_source('rtl/game/game_p2_window_controller.v','0'*64)

    def test_warning_rejected(self):
        original=checker.read
        log=(checker.ROOT/self.manifest['controller_optimization']['equivalence']).parent/'equivalence.log'
        def changed(path):return original(path)+'\n** Warning: deliberately injected\n' if Path(path)==log else original(path)
        with patch.object(checker,'read',side_effect=changed):
            with self.assertRaises(AssertionError):checker.controller_equivalence(self.manifest)


if __name__=='__main__':unittest.main(argv=[__file__])
