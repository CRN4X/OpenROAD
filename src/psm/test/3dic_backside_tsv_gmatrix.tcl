# Validate a 3D PDN path from Chip A's package-facing backside, through a
# custom BRDL-to-RDL bridge model, and across the front-to-front bond into Chip B.
set test_name 3dic_backside_tsv_gmatrix
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"
source "3dic_backside_tsv_connections_setup.tcl"
source "3dic_backside_tsv_rc_setup.tcl"

set db [ord::get_db]
set top_chip [$db getChip]
set chip_a [[$top_chip findChipInst chipA] getMasterChip]
set chip_b [[$top_chip findChipInst chipB] getMasterChip]

check "Chip A declares TSV support" { $chip_a isTsv } 1
check "Chip B declares TSV support" { $chip_b isTsv } 1

# Both chiplets contain backside bridge models. The -require_tsv option
# checks that bridge connections are present in the combined G matrix;
# the connectivity test separately checks each supply's bridge path.
check "VDD G matrix contains the backside TSV and inter-die bond" {
  check_3d_g_matrix -net VDD -require_tsv
} 1
check "VSS G matrix contains the backside TSV and inter-die bond" {
  check_3d_g_matrix -net VSS -require_tsv
} 1

exit_summary
