# Use OpenSTA cell power to solve both frontside chiplets' VDD and VSS grids.
source "helpers.tcl"
set_thread_count 1
define_corners typical slow
read_3dbx 3dic_frontside.3dbx
read_liberty -corner slow Nangate45/Nangate45_slow.lib
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules
extract_parasitics

# The assembly clock reaches both flip-flops through the existing STA network.
# The library models are loaded by read_3dbx through the .3dbv file.
create_clock -name clk -period 1.0 [get_pins -of_objects [get_nets clk_top]]
proc set_chip_activity { chip activity } {
  set pins {}
  foreach pin {ff/D ff/Q inv/A inv/ZN buf_inst/A buf_inst/Z} {
    lappend pins $chip/$pin
  }
  set_power_activity -pins [get_pins $pins] -activity $activity -duty 0.5
}
foreach chip {chipA chipB} {
  set_chip_activity $chip 0.1
}

# Match the Nangate45 typical Liberty operating voltage. OpenSTA supplies the
# cell powers automatically; no current commands or STA option are needed.
set supply_voltage 1.1
foreach chip {chipA chipB} {
  set_pdnsim_chiplet_voltage -net VDD -chiplet $chip -nominal_voltage $supply_voltage
}
check "Nominal-only settings do not create external sources" {
  catch { analyze_3d_power_grid -net VDD } message
} 1
check "No source after nominal-only settings" { set message } PSM-0138
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD \
  -voltage $supply_voltage -nominal_voltage $supply_voltage
set_pdnsim_chiplet_voltage -net VSS -chiplet chipA -port VSS -voltage 0.0

foreach invalid {0 -1 Inf -Inf} {
  check "Invalid nominal voltage $invalid is rejected" {
    catch {
      set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD \
        -voltage 0.5 -nominal_voltage $invalid
    } message
  } 1
  check "Invalid nominal voltage $invalid diagnostic" { set message } PSM-0161
}
check "Both voltage settings are optional, but one is required" {
  catch { set_pdnsim_chiplet_voltage -net VDD -chiplet chipA } message
} 1
check "Missing voltage diagnostic" { set message } PSM-0164
check "A source voltage requires a port" {
  catch {
    set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -voltage 1.1 -nominal_voltage 1.1
  } message
} 1
check "Missing port diagnostic" { set message } PSM-0134
check "A port requires a source voltage" {
  catch {
    set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -nominal_voltage 1.1
  } message
} 1
check "Missing source voltage diagnostic" { set message } PSM-0134
check "Unknown chiplet is rejected" {
  catch { set_pdnsim_chiplet_voltage -net VDD -chiplet missing -nominal_voltage 1.1 } message
} 1
check "Unknown chiplet diagnostic" { set message } PSM-0162
foreach net {VSS clk_top} {
  check "$net cannot receive a nominal power voltage" {
    catch { set_pdnsim_chiplet_voltage -net $net -chiplet chipA -nominal_voltage 1.1 } message
  } 1
  check "$net nominal voltage diagnostic" { set message } PSM-0163
}
check "The chiplet must belong to the selected assembly net" {
  catch { set_pdnsim_chiplet_voltage -net out_top -chiplet chipA -nominal_voltage 1.1 } message
} 1
check "Unmapped chiplet diagnostic" { set message } PSM-0165
check "Unknown nominal-voltage corner is rejected" {
  catch {
    set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -nominal_voltage 1.1 -corner missing
  } message
} 1
check "Unknown nominal-voltage corner diagnostic" { set message } STA-0106

# Query STA independently so the test checks P/V and the actual bond voltage
# drop, rather than just checking whether PSM returned success.
proc chip_power { chip { corner "" } } {
  if { $corner eq "" } { set corner [sta::cmd_scene] }
  set total 0.0
  foreach name {ff inv buf_inst} {
    set cells [get_cells $chip/$name]
    check "$chip/$name: one STA cell" { llength $cells } 1
    set watts [lindex [sta::instance_power [lindex $cells 0] $corner] 3]
    check "$chip/$name: positive STA power" { expr {$watts > 0.0} } 1
    set total [expr { $total + $watts }]
  }
  return $total
}

proc bond_drop { net } {
  set bump [expr { $net eq "VDD" ? "bump_vdd" : "bump_vss" }]
  set va [psm::get_3d_pdn_voltage_cmd $net chipA $bump/PAD]
  set vb [psm::get_3d_pdn_voltage_cmd $net chipB $bump/PAD]
  return [expr { $va - $vb }]
}

set top [[ord::get_db] getChip]
foreach net [$top getChipNets] {
  if { [$net getName] in {VDD VSS} } {
    set bond([$net getName]) [lindex [psm::get_3d_chip_rsegs $net] 0]
  }
}
set power_a [chip_power chipA]
set power_b [chip_power chipB]
foreach net {VDD VSS} {
  check "$net: STA current vector" { psm::check_3d_j_vector_cmd $net true } 1
  check "$net: solve with STA loads" { analyze_3d_power_grid -net $net } 1
  set sign [expr { $net eq "VDD" ? 1.0 : -1.0 }]
  set expected [expr { $sign * $power_b / $supply_voltage * [$bond($net) getResistance] }]
  check "$net: bond drop agrees with Chip B's STA power divided by voltage" {
    expr {abs([bond_drop $net] - $expected) < 1e-11}
  } 1
}
foreach chip {chipA chipB} {
  foreach name {ff inv buf_inst} {
    set vdd [psm::get_3d_pdn_voltage_cmd VDD $chip $name/VDD]
    set vss [psm::get_3d_pdn_voltage_cmd VSS $chip $name/VSS]
    check "$chip/$name: STA loads cause supply drop and ground rise" {
      expr {$vdd < $supply_voltage && $vss > 0.0 && $vdd > $vss}
    } 1
  }
}
check "Chip A VDD source remains fixed" {
  expr {abs([psm::get_3d_pdn_voltage_cmd VDD chipA VDD] - $supply_voltage) < 1e-12}
} 1
set initial_drop [bond_drop VDD]
set initial_a [psm::get_3d_pdn_voltage_cmd VDD chipA ff/VDD]

# Change only Chip B's data activity. Its flip-flop still sees the same clock.
# This also exercises refreshing power after a previous successful solve.
set_chip_activity chipB 0.8
set more_power_b [chip_power chipB]
check "More Chip B activity increases its STA power" { expr {$more_power_b > $power_b} } 1
foreach net {VDD VSS} {
  check "$net: solve again after activity changes" { analyze_3d_power_grid -net $net } 1
  set sign [expr { $net eq "VDD" ? 1.0 : -1.0 }]
  set expected [expr { $sign * $more_power_b / $supply_voltage * [$bond($net) getResistance] }]
  check "$net: updated bond current agrees with updated STA power" {
    expr {abs([bond_drop $net] - $expected) < 1e-11}
  } 1
}
check "More Chip B activity increases the bond drop" { expr {[bond_drop VDD] > $initial_drop} } 1
check "More Chip B load also affects Chip A's shared power path" {
  expr {[psm::get_3d_pdn_voltage_cmd VDD chipA ff/VDD] < $initial_a}
} 1

# Changing only Chip A's loads must not be mistaken for a Chip B load merely
# because the two chiplets use identical cell names and local coordinates.
set b_drop_before [bond_drop VDD]
set a_before [psm::get_3d_pdn_voltage_cmd VDD chipA ff/VDD]
set_chip_activity chipA 0.8
set more_power_a [chip_power chipA]
check "More Chip A activity increases its STA power" { expr {$more_power_a > $power_a} } 1
check "Solve after changing Chip A activity" { analyze_3d_power_grid -net VDD } 1
check "Chip A's own load changes its cell voltage" {
  expr {[psm::get_3d_pdn_voltage_cmd VDD chipA ff/VDD] < $a_before}
} 1
check "Chip A's load is not counted as current crossing to Chip B" {
  expr {abs([bond_drop VDD] - $b_drop_before) < 1e-11}
} 1

# Reuse the existing PSM per-net nominal voltage settings. The ground grid
# must use the power voltage of its own chiplet, never 0 V or the other chip's
# voltage. These change P/V conversion; they do not change the Liberty model.
foreach {chip volts} {chipA 1.1 chipB 1.0} {
  set_pdnsim_chiplet_voltage -net VDD -chiplet $chip -nominal_voltage $volts
}
foreach net {VDD VSS} {
  check "$net: solve with chiplet-specific nominal voltages" {
    analyze_3d_power_grid -net $net
  } 1
  set sign [expr { $net eq "VDD" ? 1.0 : -1.0 }]
  set expected [expr { $sign * $more_power_b / 1.0 * [$bond($net) getResistance] }]
  check "$net: Chip B uses its own nominal supply in P/V" {
    expr {abs([bond_drop $net] - $expected) < 1e-11}
  } 1
}
set b_drop_at_1v [bond_drop VSS]
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -nominal_voltage 1.2
check "Changing Chip A nominal voltage leaves Chip B ground current unchanged" {
  analyze_3d_power_grid -net VSS
  expr {abs([bond_drop VSS] - $b_drop_at_1v) < 1e-11}
} 1

check "The 3D setter rejects zero nominal voltage" {
  catch {
    set_pdnsim_chiplet_voltage -net VDD -chiplet chipB -nominal_voltage 0.0
  } message
} 1
check "Invalid nominal-voltage error" { set message } PSM-0161
foreach chip {chipA chipB} {
  set_pdnsim_chiplet_voltage -net VDD -chiplet $chip -nominal_voltage $supply_voltage
}

# Do not silently count both manual and STA currents on the same supply net.
psm::add_3d_pdn_current_cmd VDD chipB ff/VDD -0.001
check "Mixed STA and explicit current modes are rejected" {
  catch { analyze_3d_power_grid -net VDD } message
} 1
check "Mixed-current error" { set message } PSM-0150
check "Failed STA solve leaves no old voltage result" {
  catch { psm::get_3d_pdn_voltage_cmd VDD chipA VDD } message
} 1
check "No stale solution error" { set message } PSM-0130

psm::clear_3d_power_grid_cmd
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage $supply_voltage
check "Clearing manual loads allows STA analysis again" { analyze_3d_power_grid -net VDD } 1
# The small public interface must not expose internal solver-test commands.
foreach command {
  clear_3d_power_grid check_3d_g_matrix check_3d_j_vector
  add_3d_pdn_current get_3d_pdn_voltage
} {
  check "$command is not a public command" { info commands ::$command } {}
}

# Select another corner without changing the current OpenSTA scene. The
# chosen corner must supply both the power model and layer resistance.
set slow [sta::find_scene slow]
check "A source from another corner is not silently reused" {
  catch { analyze_3d_power_grid -net VDD -corner slow } message
} 1
check "Missing corner source diagnostic" { set message } PSM-0138
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage 1.0 -corner slow
set slow_power_b [chip_power chipB $slow]
foreach chip {chipA chipB} {
  set_pdnsim_chiplet_voltage -net VDD -chiplet $chip -nominal_voltage $supply_voltage -corner slow
}
check "Slow corner uses a different Liberty power model" {
  expr {abs($slow_power_b - $more_power_b) > 1e-9}
} 1
check "Analyze the selected slow corner" {
  analyze_3d_power_grid -net VDD -corner slow
} 1
check "Selected corner has its own fixed source voltage" {
  expr {abs([psm::get_3d_pdn_voltage_cmd VDD chipA VDD] - 1.0) < 1e-12}
} 1
set expected [expr { $slow_power_b / $supply_voltage * [$bond(VDD) getResistance] }]
check "Selected corner supplies the cell currents" {
  expr {abs([bond_drop VDD] - $expected) < 1e-11}
} 1
set_pdnsim_chiplet_voltage -net VDD -chiplet chipB -nominal_voltage 1.0 -corner slow
check "Analyze the selected corner after changing its nominal voltage" {
  analyze_3d_power_grid -net VDD -corner slow
} 1
set expected [expr { $slow_power_b / 1.0 * [$bond(VDD) getResistance] }]
check "Selected corner supplies the nominal P/V voltage" {
  expr {abs([bond_drop VDD] - $expected) < 1e-11}
} 1
set before [psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD]
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set layer [[$block getTech] findLayer metal1]
set width_m [expr { double([$layer getWidth]) / [$block getDbUnitsPerMicron] * 1e-6 }]
est::set_layer_rc_cmd $layer $slow [expr { 2.0 * [$layer getResistance] / $width_m }] 0.0
check "Analyze the selected corner after changing its resistance" {
  analyze_3d_power_grid -net VDD -corner slow
} 1
check "Selected corner supplies the layer resistance" {
  expr {[psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD] < $before - 1e-6}
} 1
check "The default corner is unchanged" {
  expr {[sta::cmd_scene] eq [sta::find_scene typical]}
} 1
check "Typical source is unchanged by the slow corner setting" {
  analyze_3d_power_grid -net VDD -corner typical
  expr {abs([psm::get_3d_pdn_voltage_cmd VDD chipA VDD] - $supply_voltage) < 1e-12}
} 1
check "Unknown source corner is rejected" {
  catch {
    set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage 1.0 -corner missing
  } message
} 1
check "Unknown source corner diagnostic" { set message } STA-0106
check "Unknown analysis corner is rejected" {
  catch { analyze_3d_power_grid -net VDD -corner missing } message
} 1
check "Unknown corner diagnostic" { set message } STA-0106

# Saved cell power replaces the STA estimate, independently for each corner.
# Chip B's whole current crosses the bond, so its drop gives an independent
# numerical check of the power used by the solver.
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set ff [$block findInst ff]
set sta_ff [lindex [get_cells chipB/ff] 0]
set typical [sta::find_scene typical]
set ff_typical [lindex [sta::instance_power $sta_ff $typical] 3]
set ff_slow [lindex [sta::instance_power $sta_ff $slow] 3]
set other_typical [expr { [chip_power chipB $typical] - $ff_typical }]
set other_slow [expr { [chip_power chipB $slow] - $ff_slow }]
set before [psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD]
set_pdnsim_chiplet_voltage -net VSS -chiplet chipA -port VSS -voltage 0.0 -corner typical
psm::set_inst_power $ff $typical 0.011
check "Saved power invalidates the previous voltage result" {
  catch { psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD } message
} 1
check "Changed-power diagnostic" { set message } PSM-0130
foreach net {VDD VSS} {
  check "$net: solve with the 0.011 W cell power setting" {
    analyze_3d_power_grid -net $net -corner typical
  } 1
  set sign [expr { $net eq "VDD" ? 1.0 : -1.0 }]
  set expected [expr {
    $sign * ($other_typical + 0.011) / $supply_voltage
    * [$bond($net) getResistance]
  }]
  check "$net: saved power replaces STA power exactly once" {
    expr {abs([bond_drop $net] - $expected) < 5e-10}
  } 1
}
check "Setting 0.011 W causes a substantial additional voltage drop" {
  expr {[psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD] < $before - 0.01}
} 1

psm::set_inst_power $ff NULL 0.008
check "Slow corner uses the default saved power" {
  analyze_3d_power_grid -net VDD -corner slow
  # Chip B's slow-corner nominal P/V voltage was set to 1.0 V above.
  set expected [expr {($other_slow + 0.008) / 1.0 * [$bond(VDD) getResistance]}]
  expr {abs([bond_drop VDD] - $expected) < 5e-10}
} 1
check "Typical corner retains its explicit power instead of the default" {
  analyze_3d_power_grid -net VDD -corner typical
  set expected [expr {($other_typical + 0.011) / $supply_voltage
    * [$bond(VDD) getResistance]}]
  expr {abs([bond_drop VDD] - $expected) < 5e-10}
} 1
psm::set_inst_power $ff $slow 0.005
check "Slow-corner power takes precedence over the default" {
  analyze_3d_power_grid -net VDD -corner slow
  set expected [expr {($other_slow + 0.005) / 1.0 * [$bond(VDD) getResistance]}]
  expr {abs([bond_drop VDD] - $expected) < 5e-10}
} 1
psm::set_inst_power $ff $typical 0.0
check "An explicit zero power replaces the STA estimate" {
  analyze_3d_power_grid -net VDD -corner typical
  set expected [expr {$other_typical / $supply_voltage * [$bond(VDD) getResistance]}]
  expr {abs([bond_drop VDD] - $expected) < 5e-10}
} 1
exit_summary
