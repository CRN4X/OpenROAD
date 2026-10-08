# Check 3D power connectivity and compare the bond voltage drop with I * R.
# PSM calculates load currents as power divided by nominal supply voltage.
source "helpers.tcl"

# Load the two chiplets, their layouts, bumps, and connections.
read_3dbx 3dic_frontside.3dbx

# Rules for wiring inside both Nangate45 chiplets.
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules

# Rules for the bonds between chiplets.
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules

# Extract parasitics
extract_parasitics

# Both flip-flops receive the assembly clock. Set activity for power analysis.
create_clock -name clk -period 1.0 [get_pins -of_objects [get_nets clk_top]]
set_power_activity -global -activity 0.1 -duty 0.5

# Check connectivity inside each chiplet and between the two chiplets.
foreach net {VDD VSS} {
  check "$net: combined connectivity" { check_power_grid -net $net } 1
}

# Match the Nangate45 typical Liberty voltage for both chips' P/V conversion.
set supply_voltage 1.1
foreach chip {chipA chipB} {
  set_pdnsim_net_voltage -net VDD -chiplet $chip -nominal_voltage $supply_voltage
}

# Only Chip A receives fixed supply voltages. The package is not modeled.
set_pdnsim_net_voltage -net VDD -chiplet chipA -port VDD -voltage $supply_voltage
set_pdnsim_net_voltage -net VSS -chiplet chipA -port VSS -voltage 0.0

# All of Chip B's supply current passes through its single VDD/VSS bond pair.
# Calculate that current independently from OpenSTA power: I = P / V.
# PSM obtains its loads from OpenSTA; this value is only used to check the result.
set chip_b_power 0.0
foreach inst {ff inv buf_inst} {
  set cell [lindex [get_cells chipB/$inst] 0]
  set power [lindex [sta::instance_power $cell [sta::cmd_scene]] 3]
  set chip_b_power [expr { $chip_b_power + $power }]
}
set chip_b_current [expr { $chip_b_power / $supply_voltage }]

# RCX loaded the bond resistance from 3dic_frontside_assembly.rules into ODB.
set top [[ord::get_db] getChip]
set bond_resistance [dict create]
foreach net [$top getChipNets] {
  set name [$net getName]
  if { $name ni {VDD VSS} } { continue }
  set bond [lindex [psm::get_3d_chip_rsegs $net] 0]
  dict set bond_resistance $name [$bond getResistance]
}

# Compare only the bond endpoints; cell voltages also include local wiring drop.
# VSS current returns from Chip B to Chip A, so its voltage difference is reversed.
foreach {net pin sign} {VDD bump_vdd/PAD 1 VSS bump_vss/PAD -1} {
  analyze_power_grid -net $net
  set a [psm::get_3d_pdn_voltage_cmd $net chipA $pin]
  set b [psm::get_3d_pdn_voltage_cmd $net chipB $pin]
  set expected_drop [expr { $chip_b_current * [dict get $bond_resistance $net] }]
  set calculated_drop [expr { $sign * ($a - $b) }]
  puts [format "%s bond drop: expected %.4g V, calculated %.4g V" \
    $net $expected_drop $calculated_drop]
  check "$net: bond drop matches I * R" {
    expr {abs($calculated_drop - $expected_drop) < 1e-11}
  } 1
}

exit_summary
