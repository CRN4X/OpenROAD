# Check analyze_3d_power_grid -enable_em and -em_outfile against solved currents.
source "helpers.tcl"
set test_name 3dic_frontside_analyze_em
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

set currents [make_result_file ${test_name}.csv]
check "EM reporting works without an output file" {
  analyze_3d_power_grid -net VDD -enable_em
} 1
check "Write EM current CSV" {
  analyze_3d_power_grid -net VDD -enable_em -em_outfile $currents
} 1
set rows [split [string trim [contents $currents]] \n]
set em_columns [list "Node0 Layer" "Node0 X location" "Node0 Y location" \
  "Node1 Layer" "Node1 X location" "Node1 Y location" "Current"]
check "EM CSV uses the 2D columns" { lindex $rows 0 } [join $em_columns ,]
set bonds 0
set local_resistors 0
set top [[ord::get_db] getChip]
foreach net [$top getChipNets] {
  if { [$net getName] eq "VDD" } { break }
}
set resistance [[lindex [psm::get_3d_chip_rsegs $net] 0] getResistance]
set expected [expr {
  abs([psm::get_3d_pdn_voltage_cmd VDD chipA bump_vdd/PAD]
    - [psm::get_3d_pdn_voltage_cmd VDD chipB bump_vdd/PAD]) / $resistance
}]
foreach row [lrange $rows 1 end] {
  lassign [split $row ,] layer0 x0 y0 layer1 x1 y1 current
  if { [lindex [split $layer0 /] 0] ne [lindex [split $layer1 /] 0] } {
    incr bonds
    check "Bond current agrees with voltage drop divided by resistance" {
      expr {abs($current - $expected) < $expected * 0.00051}
    } 1
  } else {
    incr local_resistors
  }
}
check "EM CSV contains the inter-chip bond" { set bonds } 1
check "EM CSV also contains wiring inside the chiplets" { expr {$local_resistors > 0} } 1
check "EM outfile requires enable_em" {
  catch { analyze_3d_power_grid -net VDD -em_outfile $currents } message
} 1
check "EM option diagnostic" { set message } PSM-0154

# A regular input file cannot be used as a report directory.
check "An unwritable EM report is rejected" {
  catch {
    analyze_3d_power_grid -net VDD -enable_em -em_outfile 3dic_frontside.3dbx/report.csv
  } message
} 1
check "EM file error" { set message } PSM-0156
exit_summary
