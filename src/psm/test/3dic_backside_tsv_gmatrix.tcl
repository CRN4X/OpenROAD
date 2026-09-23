# Validate a 3D PDN path from Chip A's package-facing backside, through a
# TSV-like B1-to-M1 bridge, and across the front-to-front bond into Chip B.
set test_name 3dic_backside_tsv_gmatrix
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"

set db [ord::get_db]
set top_chip [$db getChip]
set chip_a [[$top_chip findChipInst chipA] getMasterChip]
set chip_b [[$top_chip findChipInst chipB] getMasterChip]

check "Chip A declares TSV support" { $chip_a isTsv } 1
check "Chip B does not declare TSV support" { $chip_b isTsv } 0

# Synthetic bond resistance until assembly extraction supplies real values.
add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD_FRONT \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1
add_3d_pdn_connection \
  -net VSS \
  -source_chip chipA \
  -source_port VSS_FRONT \
  -target_chip chipB \
  -target_port VSS \
  -resistance 0.1

# -require_tsv prevents this regression from passing with only the inter-die
# bond. PSM must also find and stamp Chip A's backside BridgeConnection.
check "VDD G matrix contains the backside TSV and inter-die bond" {
  check_3d_g_matrix -net VDD -require_tsv
} 1
check "VSS G matrix contains the backside TSV and inter-die bond" {
  check_3d_g_matrix -net VSS -require_tsv
} 1

exit_summary
