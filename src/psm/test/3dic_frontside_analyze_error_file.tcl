# Check analyze_3d_power_grid -error_file rejects shorts and reports opens.
source "helpers.tcl"
set test_name 3dic_frontside_analyze_error_file
set_thread_count 1
read_3dbx 3dic_frontside.3dbx
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules
extract_parasitics
create_clock -name clk -period 1.0 [get_pins -of_objects [get_nets clk_top]]
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage 1.1

proc contents { filename } {
  set stream [open $filename r]
  set data [read $stream]
  close $stream
  return $data
}

set top [[ord::get_db] getChip]
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set errors [make_result_file ${test_name}.errors]
set voltages [make_result_file ${test_name}.voltages]
set currents [make_result_file ${test_name}.currents]
# Bridge the M1 VDD and VSS rails at x = 40 um in Chip B.
set wire [odb::dbSWire_create [$block findNet VDD] ROUTED]
set layer [[$block getTech] findLayer metal1]
odb::dbSBox_create $wire $layer 79800 39000 80140 42200 STRIPE
check "Analysis rejects a local supply short" {
  catch { analyze_3d_power_grid -net VDD -error_file $errors } message
} 1
check "Analysis short error" { set message } PSM-0153
check "Analysis writes the chiplet and shorted net into the report" {
  expr {[string first chipB [contents $errors]] >= 0
    && [string first VSS [contents $errors]] >= 0}
} 1
odb::dbSWire_destroy $wire
check "All report options work together after removing the short" {
  analyze_3d_power_grid -net VDD -error_file $errors -voltage_file $voltages \
    -enable_em -em_outfile $currents
} 1
check "Voltage and EM reports contain results" {
  expr {[llength [split [string trim [contents $voltages]] \n]] > 1
    && [llength [split [string trim [contents $currents]] \n]] > 1}
} 1
check "The successful report no longer contains the earlier short" {
  expr {[string first "Short" [contents $errors]] < 0
    && [string first VSS [contents $errors]] < 0}
} 1
set cell [$block findInst ff]
lassign [$cell getOrigin] x y
$cell setOrigin $x [expr { $y + 10000 }]
check "Analysis rejects a detached cell" {
  catch { analyze_3d_power_grid -net VDD -error_file $errors } message
} 1
check "Analysis open error" { set message } PSM-0153
check "Analysis open report identifies the disconnected cell" {
  expr {[string first chipB/ [contents $errors]] >= 0
    && [string first ff [contents $errors]] >= 0}
} 1
$cell setOrigin $x $y
check "An unwritable analysis error report is rejected" {
  catch {
    analyze_3d_power_grid -net VDD -error_file 3dic_frontside.3dbx/report.txt
  } message
} 1
check "Analysis error file diagnostic" { set message } PSM-0152
exit_summary
