# Check routing and solve both frontside PDNs using OpenSTA cell power.
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

# Reading the assembly must reuse the five bumps already saved in each DEF.
set top [[ord::get_db] getChip]
check "Two placed chiplets" { llength [$top getChipInsts] } 2
check "Aligned connected regions" { get_3dblox_connected_errors } 0
foreach chip_name {chipA chipB} {
  set block [[[$top findChipInst $chip_name] getMasterChip] getBlock]
  check "$chip_name: three cells and five bumps" { llength [$block getInsts] } 8

  foreach {port bump_name} {
    VDD bump_vdd VSS bump_vss clk bump_clk d bump_d q bump_q
  } {
    set net [$block findNet $port]
    set bterm [$block findBTerm $port]
    set bump [$block findInst $bump_name]
    check "$chip_name/$port: PAD net" { [$bump findITerm PAD] getNet } $net
    check "$chip_name/$port: mapped bump" { [$bterm getChipBump] getInst } $bump
  }

  foreach name {VDD VSS} {
    set net [$block findNet $name]
    check "$chip_name/$name: power connectivity" {
      psm::check_connectivity_cmd $net false "" false
    } 1
  }

  # RCX orders the routed wires. A disconnected port, bump, or cell pin
  # would leave this flag set; do not clear it to make the test pass.
  foreach name {clk d q n1 n2} {
    set net [$block findNet $name]
    check "$chip_name/$name: routed and connected" { $net isDisconnected } 0
    check "$chip_name/$name: extracted" { expr {[llength [$net getRSegs]] > 0} } 1

    # Inspect actual wire geometry, not just the routing-layer setting.
    # Allow only a final M4-M5 via on nets with a signal bump.
    set decoder [odb::dbWireDecoder]
    $decoder begin [$net getWire]
    set previous_point {}
    set upper_signal_wire false
    set highest_via_layer 0
    set bump_access_vias 0
    while { true } {
      set op [$decoder next]
      if { $op == $odb::dbWireDecoder_END_DECODE } { break }
      if {
        $op in [list $odb::dbWireDecoder_PATH $odb::dbWireDecoder_JUNCTION \
          $odb::dbWireDecoder_SHORT $odb::dbWireDecoder_VWIRE]
      } {
        set previous_point {}
      } elseif { $op in [list $odb::dbWireDecoder_POINT $odb::dbWireDecoder_POINT_EXT] } {
        if { $op == $odb::dbWireDecoder_POINT_EXT } {
          set point [lrange [$decoder getPoint_ext] 0 1]
        } else {
          set point [$decoder getPoint]
        }
        if {
          $previous_point ne {} && $point ne $previous_point
          && [[$decoder getLayer] getRoutingLevel] > 4
        } {
          set upper_signal_wire true
        }
        set previous_point $point
      } elseif { $op == $odb::dbWireDecoder_RECT } {
        if { [[$decoder getLayer] getRoutingLevel] > 4 } { set upper_signal_wire true }
      } elseif { $op in [list $odb::dbWireDecoder_TECH_VIA $odb::dbWireDecoder_VIA] } {
        if { $op == $odb::dbWireDecoder_TECH_VIA } {
          set via [$decoder getTechVia]
        } else {
          set via [$decoder getVia]
        }
        set layer [[$via getTopLayer] getRoutingLevel]
        set highest_via_layer [expr { max($highest_via_layer, $layer) }]
        if { $layer == 5 } { incr bump_access_vias }
      }
    }
    $decoder -delete
    check "$chip_name/$name: no signal wires above M4" { set upper_signal_wire } false
    check "$chip_name/$name: no signal vias above M5" {
      expr {$highest_via_layer <= 5}
    } 1
    check "$chip_name/$name: final bump access via" { set bump_access_vias } \
      [expr { $name in {clk d q} ? 1 : 0 }]
  }
}

# Each bond has exactly two bump endpoints. The input and output are external.
set expected_counts [dict create VDD 2 VSS 2 clk_top 2 bridge 2 in_top 1 out_top 1]
check "Six assembly nets" { llength [$top getChipNets] } 6
foreach net [$top getChipNets] {
  set name [$net getName]
  check "$name: bump count" { $net getNumBumpInsts } [dict get $expected_counts $name]
}
# Exercise the combined network after the layout and extraction checks above.
psm::clear_3d_power_grid_cmd
set supply_bonds [dict create]
foreach net [$top getChipNets] {
  if { [$net getName] ni {VDD VSS} } { continue }
  set segments [psm::get_3d_chip_rsegs $net]
  check "[$net getName]: one RCX bond" { llength $segments } 1
  dict set supply_bonds [$net getName] [lindex $segments 0]
  check "[$net getName]: combined connectivity" {
    check_3d_power_grid -net [$net getName]
  } 1
  check "[$net getName]: conductance matrix" {
    psm::check_3d_g_matrix_cmd [$net getName]
  } 1
}

# Match the Nangate45 typical Liberty voltage for both chips' P/V conversion.
set supply_voltage 1.1
foreach chip {chipA chipB} {
  set_pdnsim_chiplet_voltage -net VDD -chiplet $chip -nominal_voltage $supply_voltage
}

# Only Chip A receives fixed supply voltages. The package is not modeled.
check "Missing source is rejected" {
  catch { analyze_3d_power_grid -net VDD } message
} 1
check "Missing source diagnostic" { set message } PSM-0138
set_pdnsim_chiplet_voltage -net VDD -chiplet chipA -port VDD -voltage $supply_voltage
set_pdnsim_chiplet_voltage -net VSS -chiplet chipA -port VSS -voltage 0.0

# Query OpenSTA independently to check the expected current through the bond.
# These values check the result; PSM obtains its cell loads from OpenSTA itself.
set chip_power [dict create]
foreach chip {chipA chipB} {
  set total_power 0.0
  foreach inst {ff inv buf_inst} {
    set cell [lindex [get_cells $chip/$inst] 0]
    set power [lindex [sta::instance_power $cell [sta::cmd_scene]] 3]
    check "$chip/$inst: positive OpenSTA power" { expr {$power > 0.0} } 1
    set total_power [expr { $total_power + $power }]
  }
  dict set chip_power $chip $total_power
}
set chip_b_current [expr { [dict get $chip_power chipB] / $supply_voltage }]
check "A VSS pin cannot be a VDD voltage source" {
  catch {
    set_pdnsim_chiplet_voltage -net VDD -chiplet chipB -port ff/VSS -voltage $supply_voltage
  } message
} 1
check "Wrong-net diagnostic" { set message } PSM-0118

foreach net {VDD VSS} {
  check "$net: cell current vector" { psm::check_3d_j_vector_cmd $net true } 1
  check "$net: loaded solve" { analyze_3d_power_grid -net $net } 1
}
set vdd_source [psm::get_3d_pdn_voltage_cmd VDD chipA VDD]
set vss_source [psm::get_3d_pdn_voltage_cmd VSS chipA VSS]
check "Chip A VDD remains at the supply voltage" {
  expr {abs($vdd_source - $supply_voltage) < 1e-9}
} 1
check "Chip A VSS is fixed at 0 V" { expr {abs($vss_source) < 1e-9} } 1
foreach chip {chipA chipB} {
  foreach inst {ff inv buf_inst} {
    set vdd [psm::get_3d_pdn_voltage_cmd VDD $chip $inst/VDD]
    set vss [psm::get_3d_pdn_voltage_cmd VSS $chip $inst/VSS]
    check "$chip/$inst: power reaches the M1 cell pins with voltage loss" {
      expr {$vdd < $supply_voltage && $vss > 0.0 && $vdd > $vss}
    } 1
  }
}
# Query the actual bond endpoints. M6 port voltages also include local wiring
# drops and therefore must not be used to measure only the bond resistance.
foreach {net pin sign} {VDD bump_vdd/PAD 1 VSS bump_vss/PAD -1} {
  set a [psm::get_3d_pdn_voltage_cmd $net chipA $pin]
  set b [psm::get_3d_pdn_voltage_cmd $net chipB $pin]
  set resistance [[dict get $supply_bonds $net] getResistance]
  check "$net: bond drop equals Chip B power divided by voltage times resistance" {
    expr {abs($sign * ($a - $b) - $chip_b_current * $resistance) < 1e-11}
  } 1
}
set vdd_b_port [psm::get_3d_pdn_voltage_cmd VDD chipB VDD]
check "Chip B's port is not an independent voltage source" {
  expr {$vdd_b_port < $supply_voltage}
} 1

# Override M1 resistance through the same EstimateParasitics API used by
# set_layer_rc. Keep the LEF unchanged, so this tests the corner override.
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set layer [[$block getTech] findLayer metal1]
set width_m [expr { double([$layer getWidth]) / [$block getDbUnitsPerMicron] * 1e-6 }]
set scene [lindex [sta::scenes] 0]
set before [psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD]
est::set_layer_rc_cmd $layer $scene [expr { 2.0 * [$layer getResistance] / $width_m }] 0.0
check "3D solve accepts the existing corner resistance override" {
  analyze_3d_power_grid -net VDD
} 1
set after [psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD]
check "Higher M1 resistance increases cell voltage loss" { expr {$after < $before - 1e-6} } 1
est::set_layer_rc_cmd $layer $scene 0.0 0.0
check "Restoring LEF resistance succeeds" {
  analyze_3d_power_grid -net VDD
} 1
set restored [psm::get_3d_pdn_voltage_cmd VDD chipB ff/VDD]
check "Restoring LEF resistance restores cell voltage" { expr {abs($restored - $before) < 1e-8} } 1

# Changing an ODB resistor must affect the next solve; extraction is not rerun.
set bond [dict get $supply_bonds VDD]
set resistance [$bond getResistance]
$bond setResistance [expr { 2.0 * $resistance }]
check "Re-solve with doubled bond resistance" {
  analyze_3d_power_grid -net VDD
} 1
set a [psm::get_3d_pdn_voltage_cmd VDD chipA bump_vdd/PAD]
set b [psm::get_3d_pdn_voltage_cmd VDD chipB bump_vdd/PAD]
check "Doubled bond resistance doubles its voltage drop" {
  expr {abs(($a - $b) - $chip_b_current * 2.0 * $resistance) < 1e-11}
} 1
$bond setResistance 0.0
check "Zero bond resistance is rejected" {
  catch { analyze_3d_power_grid -net VDD } message
} 1
check "Invalid resistance diagnostic" { set message } PSM-0096
check "Failed re-solve leaves no stale result" {
  catch { psm::get_3d_pdn_voltage_cmd VDD chipA VDD } message
} 1
check "No stale solution diagnostic" { set message } PSM-0130
$bond setResistance $resistance
check "Solve after restoring the bond resistance" {
  analyze_3d_power_grid -net VDD
} 1

# Move the bump off its M5 landing. The M6 port remains connected, so this
# specifically catches implementations that incorrectly attach the bond there.
set block [[[$top findChipInst chipB] getMasterChip] getBlock]
set bump [$block findInst bump_vdd]
set placement_status [$bump getPlacementStatus]
$bump setPlacementStatus PLACED
lassign [$bump getOrigin] x y
$bump setOrigin $x [expr { $y + 60000 }]
check "A detached M5 bump fails combined connectivity" {
  catch { check_3d_power_grid -net VDD } message
} 1
check "Disconnected bump diagnostic" { set message } PSM-0153
$bump setOrigin $x $y
$bump setPlacementStatus $placement_status
check "Restored M5 bump reconnects the assembly" { check_3d_power_grid -net VDD } 1

# The local connectivity check must catch a disconnected cell inside a chiplet.
set inst [$block findInst ff]
lassign [$inst getOrigin] x y
$inst setOrigin $x [expr { $y + 10000 }]
check "A detached M1 cell fails combined connectivity" {
  catch { check_3d_power_grid -net VDD } message
} 1
check "Disconnected cell diagnostic" { set message } PSM-0153
$inst setOrigin $x $y
check "Restored cell reconnects the assembly" { check_3d_power_grid -net VDD } 1

# Delete only the bond: each local PDN is still intact, but the assembly is open.
odb::dbChipRSeg_destroy $bond
check "Missing bond fails combined connectivity" {
  catch { check_3d_power_grid -net VDD } message
} 1
check "Missing bond diagnostic" { set message } PSM-0103
psm::clear_3d_power_grid_cmd

exit_summary
