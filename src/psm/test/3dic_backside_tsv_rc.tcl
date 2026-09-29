# Run AFTER read_3dbx. Set this example's routing sheet and via resistance
# in memory; the technology LEF has no resistance values and is unchanged.
# BRDL: gt2n_data/setRC.tcl specifies 0.01 ohm/um at nominal width 1.6 um.
# RDL: use the same 0.01 ohm/um as an explicit TEST ASSUMPTION; the existing
# GT2N RC file does not characterize RDL. This is not a signoff RC model.
# Sheet resistance = resistance per length * nominal width = 0.016 ohm/sq.
# BPR/BM1..BM4 and BV0..BV4 values also follow gt2n_data/setRC.tcl.
# IRSolver3D reads dbTechLayer::getResistance directly.
foreach _gt2n_chip_name { chipA chipB } {
  set _gt2n_top [odb::dbDatabase_getChip [ord::get_db]]
  set _gt2n_inst [odb::dbChip_findChipInst $_gt2n_top $_gt2n_chip_name]
  set _gt2n_chip [odb::dbChipInst_getMasterChip $_gt2n_inst]
  set _gt2n_tech [odb::dbChip_getTech $_gt2n_chip]
  set _gt2n_dbu [odb::dbTech_getDbUnitsPerMicron $_gt2n_tech]
  foreach { _gt2n_layer_name _gt2n_res_per_um } {
    RDL 0.01 BRDL 0.01 BPR 24.31 BM1 7.48 BM2 7.48 BM3 0.64 BM4 0.64
  } {
    set _gt2n_layer [odb::dbTech_findLayer $_gt2n_tech $_gt2n_layer_name]
    set _gt2n_width [expr { double([odb::dbTechLayer_getWidth $_gt2n_layer]) / $_gt2n_dbu }]
    odb::dbTechLayer_setResistance $_gt2n_layer [expr { $_gt2n_res_per_um * $_gt2n_width }]
  }
  foreach { _gt2n_layer_name _gt2n_via_res } {
    BV0 25.10 BV1 6.08 BV2 6.08 BV3 0.95 BV4 0.15
  } {
    set _gt2n_layer [odb::dbTech_findLayer $_gt2n_tech $_gt2n_layer_name]
    odb::dbTechLayer_setResistance $_gt2n_layer $_gt2n_via_res
  }
}
unset _gt2n_chip_name _gt2n_top _gt2n_inst _gt2n_chip _gt2n_tech _gt2n_dbu
unset _gt2n_layer_name _gt2n_layer _gt2n_width
unset _gt2n_res_per_um _gt2n_via_res
