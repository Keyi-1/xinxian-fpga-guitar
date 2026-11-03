"""Adversarial checks for the one-renderer graph boundary exception."""
from pathlib import Path
import tempfile
import unittest
from compare_qing_ge_title_graph import compare

VG = """`timescale 100 ps/100 ps
module neo_guitar_touch_game_top(clk,a,b,y);
input clk; input a; input b; output y; wire z;
LUT2 outside(.I0(a),.I1(b),.F(z));
defparam outside.INIT=4'h6;
touch_game_renderer renderer(.clk(clk),.a(z),.b(b),.y(y));
endmodule
module touch_game_renderer(clk,a,b,y);
input clk; input a; input b; output y;
LUT2 title(.I0(a),.I1(b),.F(y));
defparam title.INIT=4'h8;
endmodule
"""


class TitleGraphGuardTests(unittest.TestCase):
    def check_pair(self, changed, accepted):
        base=Path(__file__).resolve().parent.parent/'build/qing_ge_melody/graph_guard_temp'
        base.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as d:
            a=Path(d)/'before.vg'; b=Path(d)/'after.vg'
            a.write_text(VG); b.write_text(changed)
            if accepted:
                self.assertEqual(compare(a,b)['result'],'PASS')
            else:
                with self.assertRaises(AssertionError): compare(a,b)

    def test_only_renderer_body_may_change(self):
        self.check_pair(VG.replace("title.INIT=4'h8", "title.INIT=4'h7"),True)

    def test_outside_primitive_parameter_must_match(self):
        self.check_pair(VG.replace("outside.INIT=4'h6", "outside.INIT=4'h7"),False)

    def test_renderer_input_boundary_connections_must_match(self):
        self.check_pair(VG.replace('.a(z),.b(b)', '.a(b),.b(z)'),False)

    def test_renderer_port_direction_must_match(self):
        self.check_pair(VG.replace('input clk; input a; input b; output y;\nLUT2 title',
                                  'input clk; output a; input b; output y;\nLUT2 title'),False)

    def test_names_and_comments_are_irrelevant(self):
        self.check_pair(VG.replace('wire z;', 'wire renamed;').replace('.F(z)', '.F(renamed)').replace('.a(z)', '.a(renamed)')+'// harmless comment\n',True)


if __name__=='__main__': unittest.main()
