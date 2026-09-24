# Build and validate one combined 3D conductance matrix per power net.
set test_name 3dic_cross_gmatrix
source "helpers.tcl"

read_3dbx "3dic_cross.3dbx"

# Use synthetic resistance until assembly extraction supplies real values.
add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1
add_3d_pdn_connection \
  -net VSS \
  -source_chip chipA \
  -source_port VSS \
  -target_chip chipB \
  -target_port VSS \
  -resistance 0.1

check "PSM builds the combined VDD G matrix" {
  check_3d_g_matrix -net VDD
} 1
check "PSM builds the combined VSS G matrix" {
  check_3d_g_matrix -net VSS
} 1

exit_summary
