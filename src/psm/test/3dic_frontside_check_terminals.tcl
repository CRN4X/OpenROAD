# Check check_3d_power_grid -dont_require_terminals without hiding open connections.
source "helpers.tcl"
set test_name 3dic_frontside_check_terminals
set_thread_count 1
read_3dbx 3dic_frontside.3dbx
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules
extract_parasitics

proc contents { filename } {
  set stream [open $filename r]
  set data [read $stream]
  close $stream
  return $data
}

set top [[ord::get_db] getChip]
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set errors [make_result_file ${test_name}.errors]
set bpin [lindex [[$block findBTerm VDD] getBPins] 0]
set status [$bpin getPlacementStatus]
$bpin setPlacementStatus UNPLACED
check "Default check requires a placed boundary pin on each chiplet" {
  catch { check_3d_power_grid -net VDD -error_file $errors } message
} 1
check "Boundary-pin failure diagnostic" { set message } PSM-0153
check "Missing terminal is written to the error file" {
  expr {[string first PSM-0025 [contents $errors]] >= 0}
} 1
check "The terminal requirement can be disabled" {
  check_3d_power_grid -net VDD -dont_require_terminals
} 1
set cell [$block findInst ff]
lassign [$cell getOrigin] x y
$cell setOrigin $x [expr { $y + 10000 }]
check "Disabling the terminal requirement still detects disconnected cells" {
  catch { check_3d_power_grid -net VDD -dont_require_terminals } message
} 1
check "Disconnected cell diagnostic" { set message } PSM-0140
$cell setOrigin $x $y
$bpin setPlacementStatus $status
check "Restored boundary pin passes the default check" {
  check_3d_power_grid -net VDD
} 1
exit_summary
