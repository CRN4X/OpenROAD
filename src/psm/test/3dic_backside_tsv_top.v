// Structural connectivity for the power-only 3D regression.
module backside_tsv_chip_a (VDD_FRONT, VSS_FRONT, VDD_BACK, VSS_BACK);
  inout VDD_FRONT, VSS_FRONT, VDD_BACK, VSS_BACK;
endmodule

module backside_tsv_chip_b (VDD, VSS);
  inout VDD, VSS;
endmodule

module backside_tsv_top (VDD, VSS);
  inout VDD, VSS;

  backside_tsv_chip_a chipA (
    .VDD_FRONT(VDD),
    .VSS_FRONT(VSS),
    .VDD_BACK(VDD),
    .VSS_BACK(VSS)
  );

  backside_tsv_chip_b chipB (
    .VDD(VDD),
    .VSS(VSS)
  );
endmodule

