# Verify that a nonpositive inter-die resistance is rejected while building G.
set test_name 3dic_backside_tsv_invalid_resistance
source "helpers.tcl"
source "3dic_helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"
source "3dic_backside_tsv_connections.tcl"
source "3dic_backside_tsv_rc.tcl"

# Set a test dbChipRSeg to zero to exercise IRNetwork3D validation.
set rseg [get_3dic_rseg VDD]
$rseg setResistance 0.0

set failed [catch { check_3d_g_matrix -net VDD } error]
check "3D G-matrix build rejects a zero resistance" {
  set failed
} 1
check "Invalid-resistance failure reports PSM-0096" {
  expr {[string first "PSM-0096" $error] >= 0}
} 1

exit_summary
