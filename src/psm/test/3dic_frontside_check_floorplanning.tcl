# Check check_3d_power_grid -floorplanning for placed cells and fixed bumps.
source "helpers.tcl"
set_thread_count 1
read_3dbx 3dic_frontside.3dbx
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules
extract_parasitics

set top [[ord::get_db] getChip]
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set cell [$block findInst ff]
lassign [$cell getOrigin] x y
$cell setOrigin $x [expr { $y + 10000 }]
check "Default check detects a detached placed cell" {
  catch { check_3d_power_grid -net VDD } message
} 1
check "Disconnected cell error" { set message } PSM-0140
check "Floorplanning ignores non-fixed cells" {
  check_3d_power_grid -net VDD -floorplanning
} 1
$cell setOrigin $x $y
check "Restored cell passes" { check_3d_power_grid -net VDD } 1
set bump [$block findInst bump_vdd]
lassign [$bump getOrigin] bump_x bump_y
set status [$bump getPlacementStatus]
$bump setPlacementStatus PLACED
$bump setOrigin $bump_x [expr { $bump_y + 60000 }]
$bump setPlacementStatus FIRM
check "Floorplanning still rejects a disconnected fixed bump" {
  catch { check_3d_power_grid -net VDD -floorplanning } message
} 1
check "Floorplanning disconnected bump diagnostic" { set message } PSM-0140
$bump setPlacementStatus PLACED
$bump setOrigin $bump_x $bump_y
$bump setPlacementStatus $status
check "Restored fixed bump passes floorplanning" {
  check_3d_power_grid -net VDD -floorplanning
} 1
exit_summary
