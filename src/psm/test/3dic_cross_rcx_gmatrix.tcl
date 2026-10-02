# Verify that OpenRCX creates inter-die resistors from the test assembly
# rules and that PSM uses those ODB objects in the combined G matrix.
set test_name 3dic_cross_rcx_gmatrix
source "helpers.tcl"

read_3dbx "3dic_cross.3dbx"

set initial_resistors 0
foreach net [[[ord::get_db] getChip] getChipNets] {
  incr initial_resistors [llength [psm::get_3d_chip_rsegs $net]]
}
check "Loading the assembly alone creates no resistors" {
  set initial_resistors
} 0

set_extraction_rules_file \
  -tech Nangate45_tech \
  "Nangate45/Nangate45.rcx_rules"
set_extraction_rules_file \
  -assembly "3dic_cross_assembly.rules"
extract_parasitics

check "PSM consumes OpenRCX VDD inter-die resistance" {
  check_3d_g_matrix -net VDD
} 1
check "PSM consumes OpenRCX VSS inter-die resistance" {
  check_3d_g_matrix -net VSS
} 1

# The original RCX implementation creates one resistor for each two-bump net.
set bonds 0
foreach net [[[ord::get_db] getChip] getChipNets] {
  if { [$net getNumBumpInsts] < 2 } { continue }
  incr bonds
  set segments [psm::get_3d_chip_rsegs $net]
  check "[$net getName] has one extracted bond" { llength $segments } 1
  check "[$net getName] has two endpoint nodes" {
    psm::get_3d_chip_cap_node_count $net
  } 2
  check "[$net getName] uses the assembly rules value" {
    expr { abs([[lindex $segments 0] getResistance] - 0.1) < 1e-6 }
  } 1
}
check "Power and signal bonds are both extracted" { set bonds } 4

exit_summary
