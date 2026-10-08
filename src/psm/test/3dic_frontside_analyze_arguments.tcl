# Check required arguments and reject unsupported analyze_3d_power_grid options.
source "helpers.tcl"
set_thread_count 1
read_3dbx 3dic_frontside.3dbx
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules
extract_parasitics
create_clock -name clk -period 1.0 [get_pins -of_objects [get_nets clk_top]]
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage 1.1

check "Analysis requires a net name" {
  catch { analyze_3d_power_grid } message
} 1
check "Missing net diagnostic" { set message } PSM-0135
check "Unknown assembly net is rejected" {
  catch { analyze_3d_power_grid -net missing } message
} 1
check "Unknown net diagnostic" { set message } PSM-0102
foreach args {
  {-net VDD -vsrc unused}
  {-net VDD -source_type FULL}
  {-net VDD -allow_reuse}
  {-net VDD -use_sta}
  {-net VDD -solve_2d}
  {-net VDD unexpected}
} {
  check "Unsupported arguments are rejected: $args" {
    catch { analyze_3d_power_grid {*}$args }
  } 1
}
check "Valid analysis still works after argument errors" {
  analyze_3d_power_grid -net VDD
} 1
exit_summary
