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
    // Package bumps stay on Chip A's local DEF power nets. Leave their
    // ports unbound here so each assembly net contains only the two
    // facing front bumps. PSM applies sources at these local back ports.
    .VDD_BACK(),
    .VSS_BACK()
  );

  backside_tsv_chip_b chipB (
    .VDD(VDD),
    .VSS(VSS)
  );
endmodule

