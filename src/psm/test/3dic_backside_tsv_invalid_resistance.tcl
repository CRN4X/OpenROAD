# Verify that a nonpositive inter-die resistance is rejected while building G.
set test_name 3dic_backside_tsv_invalid_resistance
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"

# Create a valid dbChipRSeg first, then corrupt it to exercise the database
# validation in IRNetwork3D rather than Tcl argument validation.
set rseg [add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD_FRONT \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1]
$rseg setResistance 0.0

set failed [catch { check_3d_g_matrix -net VDD } error]
check "3D G-matrix build rejects a zero resistance" {
  set failed
} 1
check "Invalid-resistance failure reports PSM-0096" {
  expr {[string first "PSM-0096" $error] >= 0}
} 1

exit_summary
