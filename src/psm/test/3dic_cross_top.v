// Stub flop_chip_a / flop_chip_b modules so STA's verilog reader doesn't
// black-box them when buildChipNetsFromVerilog parses this file. The real
// bodies are loaded separately from each chiplet's DEF.
module flop_chip_a (clk, d, q, VDD, VSS);
  input clk;
  input d;
  output q;
  inout VDD, VSS;
endmodule

module flop_chip_b (clk, d, q, VDD, VSS);
  input clk;
  input d;
  output q;
  inout VDD, VSS;
endmodule

module top (clk_top, in_top, out_top, VDD, VSS);
  input clk_top;
  input in_top;
  output out_top;
  inout VDD, VSS;
  wire bridge;
  flop_chip_a chipA (
    .clk(clk_top), .d(in_top), .q(bridge),
    .VDD(VDD), .VSS(VSS)
  );

  flop_chip_b chipB (
    .clk(clk_top), .d(bridge), .q(out_top),
    .VDD(VDD), .VSS(VSS)
  );
endmodule
