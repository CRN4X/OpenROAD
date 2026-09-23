# Create fixed inter-die resistance segments with PDN, then have PSM read
# those ODB objects and stitch the two chiplet PDN graphs.

source "helpers.tcl"

read_3dbx "3dic_cross.3dbx"

# Use a synthetic 0.1 ohm resistance for both power connections.  This value
# is for solver development only; a real value must come from assembly rules
# or foundry/OSAT characterization.
set vdd_rseg [add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1]
set vss_rseg [add_3d_pdn_connection \
  -net VSS \
  -source_chip chipA \
  -source_port VSS \
  -target_chip chipB \
  -target_port VSS \
  -resistance 0.1]

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
