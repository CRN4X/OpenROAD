# Check check_3d_power_grid -error_file for opens, shorts, and missing bonds.
source "helpers.tcl"
set test_name 3dic_frontside_check_error_file
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
set cell [$block findInst ff]
lassign [$cell getOrigin] x y
$cell setOrigin $x [expr { $y + 10000 }]
check "A detached cell fails and writes an error report" {
  catch { check_3d_power_grid -net VDD -error_file $errors } message
} 1
check "Disconnected cell error" { set message } PSM-0140
check "Open report names the affected chiplet and cell" {
  expr {[string first chipB/ [contents $errors]] >= 0
    && [string first ff [contents $errors]] >= 0}
} 1
$cell setOrigin $x $y

# Bridge the M1 VDD and VSS rails at x = 40 um in Chip B.
set wire [odb::dbSWire_create [$block findNet VDD] ROUTED]
set layer [[$block getTech] findLayer metal1]
odb::dbSBox_create $wire $layer 79800 39000 80140 42200 STRIPE
check "Combined check rejects a local supply short" {
  catch { check_3d_power_grid -net VDD -error_file $errors } message
} 1
check "Local short error" { set message } PSM-0153
check "Short report identifies the chiplet and the other net" {
  expr {[string first chipB [contents $errors]] >= 0
    && [string first VSS [contents $errors]] >= 0}
} 1
odb::dbSWire_destroy $wire
check "Check succeeds after removing the short" { check_3d_power_grid -net VDD } 1
check "An unwritable check report is rejected" {
  catch {
    check_3d_power_grid -net VDD -error_file 3dic_frontside.3dbx/report.txt
  } message
} 1
check "Error file diagnostic" { set message } PSM-0152
foreach net [$top getChipNets] {
  if { [$net getName] eq "VDD" } { break }
}
odb::dbChipRSeg_destroy [lindex [psm::get_3d_chip_rsegs $net] 0]
check "Missing bond fails and writes an assembly-level error" {
  catch { check_3d_power_grid -net VDD -error_file $errors } message
} 1
check "Missing bond error" { set message } PSM-0103
check "Missing bond report" {
  expr {[string first "0 inter-die connections" [contents $errors]] >= 0}
} 1
exit_summary
