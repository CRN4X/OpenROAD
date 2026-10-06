# Check the two frontside PDNs and extract the chip-to-chip bonds.
source "helpers.tcl"

# Load the two chiplets, their layouts, bumps, and connections.
read_3dbx 3dic_frontside.3dbx

# Rules for wiring inside both Nangate45 chiplets.
set_extraction_rules_file -tech Nangate45_tech ../../../test/Nangate45/Nangate45.rcx_rules

# Rules for the bonds between chiplets.
set_extraction_rules_file -assembly 3dic_frontside_assembly.rules

# Extract parasitics
extract_parasitics

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
exit_summary
