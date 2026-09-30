# Test setup only: run after read_3dbx and before PSM analysis.
# Use the existing ODB APIs, as in odb/test/cpp/TestChips.cpp.
# The 0.1-ohm value is an explicit test assumption, not extracted GT2N data.
set _bond_resistance 0.1
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
