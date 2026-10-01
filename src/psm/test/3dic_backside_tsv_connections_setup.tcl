# Test setup only: run after read_3dbx and before PSM analysis.
# Use the existing ODB APIs, as in odb/test/cpp/TestChips.cpp.
# Read the same assembly bond rule as the Nangate RCX tests. The value is
# a test assumption, not extracted GT2N data. This script does not run RCX.
set _bond_rules_file [file join [file dirname [info script]] 3dic_cross_assembly.rules]
set _bond_stream [open $_bond_rules_file r]
set _bond_resistance {}
set _bond_in_table 0
try {
  while { [gets $_bond_stream _bond_line] >= 0 } {
    # Match the RCX format: ignore comments and use the first HBV in the table.
    regsub {#.*$} $_bond_line {} _bond_line
    lassign [regexp -all -inline {\S+} $_bond_line] _bond_token _bond_value
    if { $_bond_token eq "VIA_RESISTANCE" } {
      set _bond_in_table 1
      continue
    }
    if { !$_bond_in_table } { continue }
    if { $_bond_token eq "END" } { break }
    if { $_bond_token eq "HBV" } {
      set _bond_resistance $_bond_value
      break
    }
  }
} finally {
  close $_bond_stream
}
if {
  ![string is double -strict $_bond_resistance]
  || [catch { expr { $_bond_resistance > 0.0 && $_bond_resistance < Inf } } _bond_valid]
  || !$_bond_valid
} {
  error "Expected a positive finite HBV resistance in $_bond_rules_file"
}
unset _bond_rules_file _bond_stream _bond_in_table _bond_line
unset _bond_token _bond_value _bond_valid
set _bond_top [[ord::get_db] getChip]
set _bond_links {}

# Read the two bump members already assigned by the assembly Verilog.
# Package bumps belong to Chip A's local DEF nets, outside these assembly nets.
foreach _bond_net [$_bond_top getChipNets] {
  set _bond_name [$_bond_net getName]
  if { $_bond_name ni {VDD VSS} } { continue }
  if {
    [llength [psm::get_3d_chip_rsegs $_bond_net]] != 0
    || [psm::get_3d_chip_cap_node_count $_bond_net] != 0
  } {
    error "Power-net resistors already exist; start a fresh OpenROAD session."
  }
  if { [$_bond_net getNumBumpInsts] != 2 } {
    error "Expected exactly two assembly bumps on $_bond_name."
  }
  set _bond_bumps {}
  foreach _bond_index {0 1} {
    # The empty list supplies ODB's hierarchy-path argument.
    set _bond_bump [$_bond_net getBumpInst $_bond_index {}]
    set _bond_chip [[$_bond_bump getChipRegionInst] getChipInst]
    dict set _bond_bumps [$_bond_chip getName] $_bond_bump
  }
  if { [lsort [dict keys $_bond_bumps]] ne {chipA chipB} } {
    error "Expected one chipA bump and one chipB bump on $_bond_name."
  }
  lappend _bond_links [list $_bond_net \
    [list [dict get $_bond_bumps chipA] [dict get $_bond_bumps chipB]]]
}
if { [llength $_bond_links] != 2 } { error "Expected both VDD and VSS chip nets." }

# Create the two endpoint nodes and the resistor connecting them in ODB.
foreach _bond_link $_bond_links {
  lassign $_bond_link _bond_net _bond_bumps
  set _bond_nodes {}
  foreach _bond_bump $_bond_bumps {
    set _bond_node [odb::dbChipCapNode_create $_bond_net]
    $_bond_node setChipBumpInst $_bond_bump
    lappend _bond_nodes $_bond_node
  }
  set _bond_rseg [odb::dbChipRSeg_create $_bond_net \
    [lindex $_bond_nodes 0] [lindex $_bond_nodes 1]]
  $_bond_rseg setResistance $_bond_resistance
}
unset _bond_resistance _bond_top _bond_links _bond_net _bond_name
unset _bond_bumps _bond_index _bond_chip
unset _bond_bump _bond_link _bond_nodes _bond_node _bond_rseg
