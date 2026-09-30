# Use standard OpenRCX extraction to create the inter-die resistors,
# then have PSM read them and stitch the two chiplet PDN graphs.

source "helpers.tcl"
source "3dic_helpers.tcl"

read_3dbx "3dic_cross.3dbx"
set_extraction_rules_file -tech Nangate45_tech "Nangate45/Nangate45.rcx_rules"
set_extraction_rules_file -assembly "3dic_cross_assembly.rules"
extract_parasitics

# RCX reads the 0.1-ohm HBV test value from 3dic_cross_assembly.rules.
# The queries below retrieve the resistors it already stored in ODB.
# The rule value is a test assumption.
set vdd_rseg [get_3dic_rseg VDD]
set vss_rseg [get_3dic_rseg VSS]

set vdd_source_node [$vdd_rseg getSourceCapNode]
set vdd_target_node [$vdd_rseg getTargetCapNode]
set vss_source_node [$vss_rseg getSourceCapNode]
set vss_target_node [$vss_rseg getTargetCapNode]

check "VDD rseg net" { [$vdd_rseg getChipNet] getName } VDD
check "VDD source bump port" { [$vdd_source_node getBTerm] getName } VDD
check "VDD target bump port" { [$vdd_target_node getBTerm] getName } VDD
check "VDD resistance is 0.1 ohm" {
  expr {abs([$vdd_rseg getResistance] - 0.1) < 1.0e-6}
} 1

check "VSS rseg net" { [$vss_rseg getChipNet] getName } VSS
check "VSS source bump port" { [$vss_source_node getBTerm] getName } VSS
check "VSS target bump port" { [$vss_target_node getBTerm] getName } VSS
check "VSS resistance is 0.1 ohm" {
  expr {abs([$vss_rseg getResistance] - 0.1) < 1.0e-6}
} 1

check "PSM stitches the VDD chiplet PDNs" {
  check_3d_power_grid -net VDD
} 1
check "PSM stitches the VSS chiplet PDNs" {
  check_3d_power_grid -net VSS
} 1

exit_summary
