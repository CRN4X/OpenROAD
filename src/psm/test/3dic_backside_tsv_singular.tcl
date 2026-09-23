# Verify that every disconnected component needs a fixed-voltage source.
set test_name 3dic_backside_tsv_singular
source "helpers.tcl"

read_3dbx "3dic_backside_tsv_broken.3dbx"

add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD_FRONT \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1

add_3d_pdn_current \
  -net VDD -chip chipB -port VDD -current -0.02
set_3d_pdn_voltage_source \
  -net VDD -chip chipA -port VDD_BACK -voltage 1.0

# Chip B's VDD_ISLAND component has no source, so the constrained matrix is
# singular even though the main component has the package source above.
set failed [catch { solve_3d_power_grid -net VDD } error]
check "3D solve rejects an unsourced disconnected component" {
  set failed
} 1
check "Singular-matrix failure reports PSM-0139" {
  expr {[string first "PSM-0139" $error] >= 0}
} 1

exit_summary
