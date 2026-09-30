# Build and validate one combined 3D conductance matrix per power net.
set test_name 3dic_cross_gmatrix
source "helpers.tcl"

read_3dbx "3dic_cross.3dbx"
set_extraction_rules_file -tech Nangate45_tech "Nangate45/Nangate45.rcx_rules"
set_extraction_rules_file -assembly "3dic_cross_assembly.rules"
extract_parasitics

check "PSM builds the combined VDD G matrix" {
  check_3d_g_matrix -net VDD
} 1
check "PSM builds the combined VSS G matrix" {
  check_3d_g_matrix -net VSS
} 1

exit_summary
