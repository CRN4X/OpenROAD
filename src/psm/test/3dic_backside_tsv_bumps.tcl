# Verify real GT2N layers, custom bump geometry and physical PDN contacts.
set test_name 3dic_backside_tsv_bumps
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"

proc rect_bounds { rect } {
  return [list [odb::Rect_xMin $rect] [odb::Rect_yMin $rect] \
    [odb::Rect_xMax $rect] [odb::Rect_yMax $rect]]
}

proc box_bounds { box } {
  return [list [$box xMin] [$box yMin] [$box xMax] [$box yMax]]
}

proc overlaps { a b } {
  lassign $a ax0 ay0 ax1 ay1
  lassign $b bx0 by0 bx1 by1
  return [expr { $ax0 < $bx1 && $bx0 < $ax1 && $ay0 < $by1 && $by0 < $ay1 }]
}

set top [odb::dbDatabase_getChip [ord::get_db]]
set bump_count 0
foreach chip_name { chipA chipB } {
  set chip_inst [odb::dbChip_findChipInst $top $chip_name]
  set chip [odb::dbChipInst_getMasterChip $chip_inst]
  set tech [odb::dbChip_getTech $chip]
  set block [odb::dbChip_getBlock $chip]
  set transform [odb::dbChipInst_getTransform $chip_inst]
  check "$chip_name preserves bump x/y orientation" {
    odb::dbTransform_getOrient $transform
  } R0
  set mirror_z [expr { $chip_name eq "chipB" }]
  check "$chip_name has the intended z reflection" {
    odb::dbTransform_isMirrorZ $transform
  } $mirror_z
  check "$chip_name has no assembly x/y translation" {
    rect_bounds [odb::dbChipInst_getBBox $chip_inst]
  } {0 0 40000 40000}
  set dbu [odb::dbTech_getDbUnitsPerMicron $tech]
  check "$chip_name uses GT2N" { $tech getName } gt2_tech
  check "$chip_name uses 2000 DBU/um" { set dbu } 2000
  check "$chip_name has a 20 um die" {
    expr {[$chip getWidth] == 20*$dbu && [$chip getHeight] == 20*$dbu}
  } 1
  set core_count 0
  foreach instance [$block getInsts] {
    if { [[$instance getMaster] getType] eq "CORE" } { incr core_count }
  }
  check "$chip_name contains three logic standard cells" { set core_count } 3
  set bridge_boxes {}
  set bridge_count 0
  foreach instance [$block getInsts] {
    if { [[$instance getMaster] isBacksideBridge] } { incr bridge_count }
  }
  check "$chip_name has two separate bridge instances" { set bridge_count } 2
  foreach { net center use } { VDD 5 POWER VSS 15 GROUND } {
    set name tsv_[string tolower $net]
    set bridge [$block findInst $name]
    set master [$bridge getMaster]
    check "$chip_name/$name uses its own supply-specific master" {
      $master getName
    } GT2N_TEST_TSV_$net
    check "$chip_name/$name is marked as a backside bridge" { $master isBacksideBridge } 1
    check "$chip_name/$name has exactly one electrical terminal" { llength [$bridge getITerms] } 1
    set pin [$bridge findITerm $net]
    check "$chip_name/$name terminal is on $net only" { [$pin getNet] getName } $net
    check "$chip_name/$name terminal has the correct supply type" {
      [$pin getMTerm] getSigType
    } $use
    set bounds [box_bounds [$bridge getBBox]]
    set low [expr { ($center - 1) * $dbu }]
    set high [expr { ($center + 1) * $dbu }]
    check "$chip_name/$name has a separate 2 um square boundary" {
      set bounds
    } [list $low $low $high $high]
    lappend bridge_boxes $bounds
    set expected_contact [list [expr { int(($center - 0.8) * $dbu) }] \
      [expr { int(($center - 0.8) * $dbu) }] [expr { int(($center + 0.8) * $dbu) }] \
      [expr { int(($center + 0.8) * $dbu) }]]
    set contact_layers {}
    foreach geometry [$pin getGeometries] {
      lassign $geometry layer rect
      lappend contact_layers [$layer getName]
      check "$chip_name/$name contact stays at its original position" {
        rect_bounds $rect
      } $expected_contact
      set rail_overlap 0
      set opposite_overlap 0
      foreach supply { VDD VSS } {
        foreach swire [[$block findNet $supply] getSWires] {
          foreach shape [$swire getWires] {
            if {
              ![$shape isVia] && [$shape getTechLayer] eq $layer
              && [overlaps [rect_bounds $rect] [box_bounds $shape]]
            } {
              if { $supply eq $net } {
                set rail_overlap 1
              } else {
                set opposite_overlap 1
              }
            }
          }
        }
      }
      check "$chip_name/$name contact touches its $net rail" { set rail_overlap } 1
      check "$chip_name/$name contact avoids the other supply" { set opposite_overlap } 0
    }
    check "$chip_name/$name joins exactly RDL and BRDL" {
      lsort $contact_layers
    } {BRDL RDL}
  }
  check "$chip_name VDD/VSS bridge boundaries do not overlap" {
    expr {![overlaps [lindex $bridge_boxes 0] [lindex $bridge_boxes 1]]}
  } 1
  set logic_boxes {}
  foreach { name master_name } {
    ff gt2_6t_dffasync_x1_w31_svt
    inv gt2_6t_inv_x1_w31_svt
    buf gt2_6t_buf_x1_w31_svt
  } {
    set cell [$block findInst $name]
    check "$chip_name/$name uses its existing GT2N cell" {
      [$cell getMaster] getName
    } $master_name
    set bounds [box_bounds [$cell getBBox]]
    lassign $bounds x0 y0 x1 y1
    check "$chip_name/$name is placed inside the die" {
      expr {[$cell isPlaced] && $x0 >= 0 && $y0 >= 0 && $x1 <= 20*$dbu && $y1 <= 20*$dbu}
    } 1
    foreach bridge_box $bridge_boxes {
      check "$chip_name/$name does not overlap a supply bridge" {
        expr {![overlaps $bounds $bridge_box]}
      } 1
    }
    foreach previous $logic_boxes {
      check "$chip_name/$name does not overlap the preceding logic cell" {
        expr {![overlaps $bounds $previous]}
      } 1
    }
    lappend logic_boxes $bounds
    foreach { pin_name net_name } { vdd VDD vss VSS } {
      set pin [$cell findITerm $pin_name]
      check "$chip_name/$name/$pin_name is assigned to $net_name" {
        [$pin getNet] getName
      } $net_name
      set expected_shapes [expr { $name eq "ff" && $pin_name eq "vss" ? 2 : 1 }]
      check "$chip_name/$name/$pin_name includes every library contact" {
        llength [$pin getGeometries]
      } $expected_shapes
      foreach geometry [$pin getGeometries] {
        lassign $geometry pin_layer pin_rect
        check "$chip_name/$name/$pin_name uses BPR" { $pin_layer getName } BPR
        set supply_overlap 0
        set other_overlap 0
        foreach supply { VDD VSS } {
          foreach swire [[$block findNet $supply] getSWires] {
            foreach shape [$swire getWires] {
              if {
                ![$shape isVia] && [$shape getTechLayer] eq $pin_layer
                && [overlaps [rect_bounds $pin_rect] [box_bounds $shape]]
              } {
                if { $supply eq $net_name } {
                  set supply_overlap 1
                } else {
                  set other_overlap 1
                }
              }
            }
          }
        }
        check "$chip_name/$name/$pin_name physically touches its rail" { set supply_overlap } 1
        check "$chip_name/$name/$pin_name avoids the opposite supply" { set other_overlap } 0
      }
    }
  }
  foreach { first pin1 second pin2 signal } { ff Q inv A n1 inv Y buf A n2 } {
    check "$chip_name has the $first to $second logical connection" {
      expr {[[[$block findInst $first] findITerm $pin1] getNet] eq [$block findNet $signal]
        && [[[$block findInst $second] findITerm $pin2] getNet] eq [$block findNet $signal]}
    } 1
  }
  foreach region [$chip getChipRegions] {
    set back [expr { [$region getName] eq "back_reg" }]
    set expected_layer [expr { $back ? "BRDL" : "RDL" }]
    set layer [$region getLayer]
    check "$chip_name region uses $expected_layer" { $layer getName } $expected_layer
    check "$expected_layer backside flag" { $layer isBackside } $back
    check "$chip_name region has two bumps" { llength [$region getChipBumps] } 2
    foreach bump [$region getChipBumps] {
      incr bump_count
      set inst [$bump getInst]
      set label "$chip_name/[$inst getName]"
      set net [$bump getNet]
      set net_name [$net getName]
      set port [$bump getBTerm]
      set pad [$inst findITerm PAD]
      set master [$inst getMaster]
      check "$label uses a bump master in its chip technology" {
        expr {[$master getType] eq "COVER_BUMP" && [[$master getLib] getTech] eq $tech}
      } 1
      set expected_port $net_name
      if { $chip_name eq "chipA" } {
        append expected_port [expr { $back ? "_BACK" : "_FRONT" }]
      }
      check "$label port assignment" { $port getName } $expected_port
      check "$label PAD, port and bump have the same supply net" {
        expr {$net_name in {VDD VSS} && [$pad getNet] eq $net && [$port getNet] eq $net}
      } 1
      set geometries [$pad getGeometries]
      check "$label has exactly one contact rectangle" { llength $geometries } 1
      lassign [lindex $geometries 0] pad_layer rect
      check "$label PAD is on the region layer" { expr {$pad_layer eq $layer} } 1
      set bounds [rect_bounds $rect]
      set coord [expr { $net_name eq "VDD" ? 5 : 15 }]
      set x [expr { ($back ? $coord : 10) * $dbu }]
      set y [expr { ($back ? 10 : $coord) * $dbu }]
      set half [expr { int(0.8 * $dbu) }]
      set expected [list [expr { $x - $half }] [expr { $y - $half }] \
        [expr { $x + $half }] [expr { $y + $half }]]
      check "$label has the intended 1.6 um contact and location" { set bounds } $expected
      set port_overlap 0
      foreach pin [$port getBPins] {
        foreach box [$pin getBoxes] {
          if { [$box getTechLayer] eq $layer && [overlaps $bounds [box_bounds $box]] } {
            set port_overlap 1
          }
        }
      }
      check "$label physically touches its DEF port" { set port_overlap } 1
      set rail_overlap 0
      set wrong_rail_overlap 0
      foreach supply { VDD VSS } {
        foreach swire [[$block findNet $supply] getSWires] {
          foreach box [$swire getWires] {
            if { [$box getTechLayer] eq $layer && [overlaps $bounds [box_bounds $box]] } {
              if { $supply eq $net_name } {
                set rail_overlap 1
              } else {
                set wrong_rail_overlap 1
              }
            }
          }
        }
      }
      check "$label physically touches its supply rail" { set rail_overlap } 1
      check "$label avoids the opposite supply rail" { set wrong_rail_overlap } 0
      lassign [box_bounds [$inst getBBox]] x0 y0 x1 y1
      check "$label stays inside the die" {
        expr {$x0 >= 0 && $y0 >= 0 && $x1 <= 20*$dbu && $y1 <= 20*$dbu}
      } 1
      if { !$back } { set front_rect($chip_name,$net_name) $bounds }
    }
  }
}
check "Six physical bumps were loaded" { set bump_count } 6
foreach net { VDD VSS } {
  check "$net front bump rectangles align between the chiplets" {
    expr {$front_rect(chipA,$net) eq $front_rect(chipB,$net)}
  } 1
}
exit_summary
