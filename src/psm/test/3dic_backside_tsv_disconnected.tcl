# Verify that both 3D connectivity checks reject a disconnected chiplet PDN.
set test_name 3dic_backside_tsv_disconnected
source "helpers.tcl"

read_3dbx "3dic_backside_tsv_broken.3dbx"

add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD_FRONT \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1

set failed [catch { check_3d_power_grid -net VDD } error]
check "3D power-grid check rejects a disconnected PDN" {
  set failed
} 1
check "Disconnected power-grid failure reports PSM-0140" {
  expr {[string first "PSM-0140" $error] >= 0}
} 1

set failed [catch { check_3d_g_matrix -net VDD } error]
check "3D G-matrix check rejects a disconnected PDN" {
  set failed
} 1
check "Disconnected-PDN failure reports PSM-0137" {
  expr {[string first "PSM-0137" $error] >= 0}
} 1

exit_summary
