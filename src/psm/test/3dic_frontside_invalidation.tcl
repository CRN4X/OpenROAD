# A saved voltage must not survive an edit to the network that produced it.
source "helpers.tcl"
set_thread_count 1
read_3dbx 3dic_frontside.3dbx
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules
extract_parasitics
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage 1.1
psm::add_3d_pdn_current_cmd VDD chipB buf_inst/VDD -0.001

proc solve { } {
  psm::analyze_3d_power_grid_cmd VDD [sta::cmd_scene] false
}
proc no_saved_voltage { description } {
  check $description { catch { psm::get_3d_pdn_voltage_cmd VDD chipB VDD } message } 1
  check "$description: diagnostic" { set message } PSM-0130
}
set top [[ord::get_db] getChip]
foreach name {chipA chipB} {
  set block($name) [[[$top findChipInst $name] getMasterChip] getBlock]
}
foreach net [$top getChipNets] {
  if { [$net getName] eq "VDD" } { break }
}
set bond [lindex [psm::get_3d_chip_rsegs $net] 0]
set source [$bond getSourceCapNode]
set target [$bond getTargetCapNode]
set resistance [$bond getResistance]
check "Initial solve" { solve } 1
set before [psm::get_3d_pdn_voltage_cmd VDD chipB VDD]
check "An unchanged network retains its result" {
  expr {[psm::get_3d_pdn_voltage_cmd VDD chipB VDD] == $before}
} 1

# ODB has no callback for resistor edits; compare live bond data with the solve.
$bond setResistance [expr { 2 * $resistance }]
no_saved_voltage "Changing bond resistance invalidates the saved result"
$bond setResistance $resistance
no_saved_voltage "Restoring resistance does not revive an invalidated result"
check "Solve after restoring resistance" { solve } 1
set bump [$target getChipBumpInst]
$target setChipBumpInst [$source getChipBumpInst]
no_saved_voltage "Changing a bond endpoint invalidates the saved result"
$target setChipBumpInst $bump
check "Solve after restoring the endpoint" { solve } 1
odb::dbChipRSeg_destroy $bond
# Query before check_power_grid: the query must itself reject the old result.
no_saved_voltage "Deleting the only VDD bond invalidates the saved result"
check "Connectivity still rejects the missing bond" {
  catch { check_3d_power_grid -net VDD } message
} 1
check "Missing bond diagnostic" { set message } PSM-0103
set bond [odb::dbChipRSeg_create $net $source $target]
$bond setResistance $resistance
no_saved_voltage "Recreating the bond still requires a new solve"
check "Solve after recreating the bond" { solve } 1
set extra_bond [odb::dbChipRSeg_create $net $source $target]
$extra_bond setResistance $resistance
no_saved_voltage "Adding a bond invalidates the saved result"
odb::dbChipRSeg_destroy $extra_bond
check "Solve after removing the extra bond" { solve } 1

# Each chiplet needs an observer. Watching only the last block misses Chip A.
foreach name {chipA chipB} {
  set inst [$block($name) findInst ff]
  lassign [$inst getOrigin] x y
  $inst setOrigin $x [expr { $y + 10000 }]
  no_saved_voltage "$name: moving a cell invalidates the saved result"
  $inst setOrigin $x $y
  check "$name: solve after restoring placement" { solve } 1

  set pin [$inst findITerm VDD]
  set local_net [$pin getNet]
  $pin disconnect
  no_saved_voltage "$name: disconnecting a power pin invalidates the saved result"
  $pin connect $local_net
  check "$name: solve after reconnecting the pin" { solve } 1

  psm::set_inst_power $inst [sta::cmd_scene] 0.011
  no_saved_voltage "$name: changing saved power invalidates the saved result"
  check "$name: solve after changing power" { solve } 1
  set_pdnsim_chiplet_voltage -net VDD -chiplet $name -nominal_voltage 1.1
  no_saved_voltage "$name: changing nominal voltage invalidates the saved result"
  check "$name: solve after changing nominal voltage" { solve } 1
}
# Deleting the source chip's cell must also clear that cell's saved power.
foreach name {chipA chipB} {
  odb::dbInst_destroy [$block($name) findInst ff]
  no_saved_voltage "$name: deleting a cell invalidates the saved result"
  check "$name: solve the remaining grid after deleting the cell" { solve } 1
}
exit_summary
