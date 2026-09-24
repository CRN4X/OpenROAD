# Verify the production handoff: OpenRCX creates inter-die dbChipRSeg objects
# from assembly rules, and PSM consumes them in the combined G matrix.
set test_name 3dic_cross_rcx_gmatrix
source "helpers.tcl"

read_3dbx "3dic_cross.3dbx"

set_extraction_rules_file \
  -tech Nangate45_tech \
  "../../odb/test/Nangate45/Nangate45.rcx_rules"
set_extraction_rules_file \
  -assembly "3dic_cross_assembly.rules"
extract_parasitics

check "PSM consumes OpenRCX VDD inter-die resistance" {
  check_3d_g_matrix -net VDD
} 1
check "PSM consumes OpenRCX VSS inter-die resistance" {
  check_3d_g_matrix -net VSS
} 1

exit_summary
