# Check analyze_3d_power_grid -voltage_file terminal names, units, and voltages.
source "helpers.tcl"
set test_name 3dic_frontside_analyze_voltage_file
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

set voltages [make_result_file ${test_name}.csv]
check "Write terminal voltage CSV" {
  analyze_3d_power_grid -net VDD -voltage_file $voltages
} 1
set rows [split [string trim [contents $voltages]] \n]
check "Voltage CSV uses the 2D columns" { lindex $rows 0 } \
  {Instance,Terminal,Layer,X location,Y location,Voltage}
check "Voltage CSV contains six cells and two supply bumps" { llength $rows } 9
set names {}
foreach row [lrange $rows 1 end] {
  lassign [split $row ,] instance terminal layer x y voltage
  lappend names $instance
  lassign [split $instance /] chip cell
  set solved [psm::get_3d_pdn_voltage_cmd VDD $chip $cell/$terminal]
  check "$instance/$terminal: CSV voltage matches the solve" {
    expr {abs($voltage - $solved) < 0.00000051}
  } 1
  check "$instance/$terminal: coordinates are local microns" {
    expr {$x >= 0 && $x <= 130 && $y >= 0 && $y <= 130}
  } 1
}
check "Both chiplets are identified in voltage CSV" { lsort $names } \
  [list chipA/buf_inst chipA/bump_vdd chipA/ff chipA/inv \
    chipB/buf_inst chipB/bump_vdd chipB/ff chipB/inv]

# A regular input file cannot be used as a report directory.
check "An unwritable voltage report is rejected" {
  catch {
    analyze_3d_power_grid -net VDD -voltage_file 3dic_frontside.3dbx/report.csv
  } message
} 1
check "Voltage file error" { set message } PSM-0155
exit_summary
