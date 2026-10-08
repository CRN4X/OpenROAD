# Verify that a 3D solve fails when no package voltage source is defined.
set test_name 3dic_backside_tsv_missing_source
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"
source "3dic_backside_tsv_connections_setup.tcl"
source "3dic_backside_tsv_rc_setup.tcl"

add_3d_pdn_current \
  -net VDD -chip chipB -port VDD -current -0.02

set failed [catch { solve_3d_power_grid -net VDD } error]
check "3D solve rejects a missing package voltage source" {
  set failed
} 1
check "Missing-source failure reports PSM-0138" {
  expr {[string first "PSM-0138" $error] >= 0}
} 1

exit_summary
