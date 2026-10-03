// Use cells from Nangate45 library
module flop_chip_a (clk, d, q, VDD, VSS);
  input clk;
  input d;
  output q;
  inout VDD, VSS;

  wire n1, n2;

  DFF_X1 ff       (.D(d),  .CK(clk), .Q(n1), .QN());
  INV_X1 inv      (.A(n1), .ZN(n2));
  BUF_X1 buf_inst (.A(n2), .Z(q));
endmodule


module flop_chip_b (clk, d, q, VDD, VSS);
  input clk;
  input d;
  output q;
  inout VDD, VSS;

  wire n1, n2;

  DFF_X1 ff       (.D(d),  .CK(clk), .Q(n1), .QN());
  INV_X1 inv      (.A(n1), .ZN(n2));
  BUF_X1 buf_inst (.A(n2), .Z(q));
endmodule


module top (clk_top, in_top, out_top, VDD, VSS);
  // so _top indicated the module name and not physical location of port
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
