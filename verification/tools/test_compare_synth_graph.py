"""Sensitivity checks for the exact structural comparison, including port splits."""
import unittest
from compare_synth_graph import Graph,parse

BEFORE="""`timescale 100 ps/100 ps
module inner (clk,d,q);
input clk;
input [1:0] d;
output [1:0] q;
DFFRE a (.Q(q[1]),.D(d[1]),.CLK(clk),.RESET(1'b0),.CE(1'b1));
defparam a.INIT=1'b0;
DFFRE b (.Q(q[0]),.D(d[0]),.CLK(clk),.RESET(1'b0),.CE(1'b1));
defparam b.INIT=1'b0;
endmodule
module top (clk,d,q);
input clk;
input [1:0] d;
output [1:0] q;
inner pair (.clk(clk),.d(d[1:0]),.q(q[1:0]));
endmodule
"""
SPLIT="""`timescale 100 ps/100 ps
module inner (clock,high,low,one,zero);
input clock;
input high;
input low;
output one;
output zero;
DFFRE renamed_a (.Q(one),.D(high),.CLK(clock),.RESET(1'b0),.CE(1'b1));
defparam renamed_a.INIT=1'b0;
DFFRE renamed_b (.Q(zero),.D(low),.CLK(clock),.RESET(1'b0),.CE(1'b1));
defparam renamed_b.INIT=1'b0;
endmodule
module top (clk,d,q);
input clk;
input [1:0] d;
output [1:0] q;
inner renamed_pair (.clock(clk),.high(d[1]),.low(d[0]),.one(q[1]),.zero(q[0]));
endmodule
"""


def signature(text):return Graph(parse(text),'top').signature()


class StructuralTests(unittest.TestCase):
    def test_renaming_and_port_split_are_equivalent(self):
        self.assertEqual(signature(BEFORE),signature(SPLIT))

    def test_pin_and_primitive_mutations_are_detected(self):
        for old,new in [('.D(d[1])','.D(d[0])'),('.CLK(clk)','.CLK(d[0])'),
                        ("a.INIT=1'b0","a.INIT=1'b1"),('DFFRE a','DFFSE a'),
                        ('.RESET(1\'b0)','.RESET(1\'b1)'),('.q(q[1:0])','.q({q[0],q[1]})')]:
            with self.subTest(new=new):
                self.assertNotEqual(signature(BEFORE),signature(BEFORE.replace(old,new,1)))

    def test_primitive_deletion_is_detected(self):
        text=BEFORE.replace("DFFRE b (.Q(q[0]),.D(d[0]),.CLK(clk),.RESET(1'b0),.CE(1'b1));\ndefparam b.INIT=1'b0;",'')
        self.assertNotEqual(signature(BEFORE),signature(text))

    def test_ram_init_and_mode_parameters_are_preserved(self):
        text=BEFORE.replace('DFFRE a','DPB a').replace("a.INIT=1'b0","a.INIT_RAM_00=256'h1234;\ndefparam a.READ_MODE=1'b0")
        self.assertNotEqual(signature(text),signature(text.replace("256'h1234","256'h1235")))
        self.assertNotEqual(signature(text),signature(text.replace("a.READ_MODE=1'b0","a.READ_MODE=1'b1")))

    def test_literal_parameter_strings_preserve_spaces(self):
        text=BEFORE.replace("a.INIT=1'b0",'a.MODE="a b"')
        self.assertNotEqual(signature(text),signature(text.replace('"a b"','"ab"')))

    def test_unsupported_syntax_and_bad_aliases_fail_closed(self):
        for text in [BEFORE.replace('wire absent;','')+'`include "unexpected.v"\n',
                     BEFORE.replace('endmodule','assign q=d;\nendmodule',1),
                     BEFORE.replace('.d(d[1:0])','.d(d[0])'),
                     BEFORE.replace(".RESET(1'b0)",".RESET(1'bx)"),
                     BEFORE.replace('100 ps/100 ps','1 ns/1 ps'),
                     BEFORE.replace('module top (clk,d,q)','module top (clk,d)')]:
            with self.subTest(text=text):
                with self.assertRaises(AssertionError):signature(text)


if __name__=='__main__':unittest.main()
