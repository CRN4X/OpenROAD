# Verify two front bumps per assembly net, local package bumps, and saved resistors.
set test_name 3dic_backside_tsv_odb
source "helpers.tcl"
source "3dic_helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"

# Assembly nets describe the front-to-front bonds. Package bumps and the
# backside source ports must remain connected through Chip A's local DEF PDN.
set db [ord::get_db]
check "All six physical bump instances remain" { llength [$db getChipBumpInsts] } 6
foreach unfolded [$db getUnfoldedChipNets] {
  set net_name [[$unfolded getChipNet] getName]
  set members {}
  foreach item [$unfolded getConnectedBumps] {
    set bump [$item getChipBumpInst]
    set chip [[$bump getChipRegionInst] getChipInst]
    set port [[$bump getChipBump] getBTerm]
    lappend members "[$chip getName]/[$port getName]"
  }
  check "$net_name assembly members are only the two facing front bumps" {
    lsort $members
  } [list chipA/${net_name}_FRONT chipB/$net_name]
}
set chip_a [[$db getChip] findChipInst chipA]
set block_a [[$chip_a getMasterChip] getBlock]
foreach net_name { VDD VSS } {
  set back [$block_a findBTerm ${net_name}_BACK]
  set front [$block_a findBTerm ${net_name}_FRONT]
  check "$net_name package bump remains on Chip A's local PDN" {
    expr { [$back getNet] eq [$front getNet]
           && [[$back getChipBump] getNet] eq [$front getNet] }
  } 1
}

foreach net [[[ord::get_db] getChip] getChipNets] {
  check "read_3dbx does not create resistors on [$net getName]" {
    llength [psm::get_3d_chip_rsegs $net]
  } 0
  check "read_3dbx does not create endpoint nodes on [$net getName]" {
    psm::get_3d_chip_cap_node_count $net
  } 0
}
source "3dic_backside_tsv_connections.tcl"
check "The old PDN helper is absent" { info commands add_3d_pdn_connection } {}
foreach net_name { VDD VSS } {
  set rseg [get_3dic_rseg $net_name]
  set net [$rseg getChipNet]
  check "$net_name has exactly two assembly bump members" {
    $net getNumBumpInsts
  } 2
  check "$net_name has two resistor endpoint nodes" {
    psm::get_3d_chip_cap_node_count $net
  } 2
  check "$net_name has the stated test resistance" {
    expr { abs([$rseg getResistance] - 0.1) < 1e-6 }
  } 1
  foreach endpoint { Source Target } chip_name { chipA chipB } suffix { _FRONT {} } {
    set node [$rseg get${endpoint}CapNode]
    set bump [$node getChipBumpInst]
    check "$net_name $endpoint chip" {
      [[$bump getChipRegionInst] getChipInst] getName
    } $chip_name
    check "$net_name $endpoint port" { [$node getBTerm] getName } ${net_name}${suffix}
  }
}

set failed [catch { source "3dic_backside_tsv_connections.tcl" } message]
check "Repeated test setup reports existing resistors" {
  expr { $failed && [string first "already exist" $message] >= 0 }
} 1
foreach net_name { VDD VSS } {
  set net [[get_3dic_rseg $net_name] getChipNet]
  check "$net_name still has one resistor after repeated setup" {
    llength [psm::get_3d_chip_rsegs $net]
  } 1
  check "$net_name still has two endpoint nodes after repeated setup" {
    psm::get_3d_chip_cap_node_count $net
  } 2
}

# Save actual ODB objects and verify them in a new process without rerunning setup.
set snapshot [file normalize [make_result_file "test_connections.odb"]]
write_db $snapshot
set reload_script [make_result_file "reload_connections.tcl"]
set stream [open $reload_script w]
puts $stream [list read_db $snapshot]
puts $stream {
  set db [ord::get_db]
  if { [llength [$db getChipBumpInsts]] != 6 } {
    error "Saved database is missing physical bumps"
  }
  set chip_a [[$db getChip] findChipInst chipA]
  set block_a [[$chip_a getMasterChip] getBlock]
  foreach name {VDD VSS} {
    set back [$block_a findBTerm ${name}_BACK]
    set front [$block_a findBTerm ${name}_FRONT]
    if { [$back getNet] ne [$front getNet]
         || [[$back getChipBump] getNet] ne [$front getNet] } {
      error "Saved $name package bump is no longer on Chip A's local PDN"
    }
  }
  foreach unfolded [$db getUnfoldedChipNets] {
    set name [[$unfolded getChipNet] getName]
    set members {}
    foreach item [$unfolded getConnectedBumps] {
      set bump [$item getChipBumpInst]
      set chip [[$bump getChipRegionInst] getChipInst]
      set port [[$bump getChipBump] getBTerm]
      lappend members "[$chip getName]/[$port getName]"
    }
    if { [lsort $members] ne [list chipA/${name}_FRONT chipB/$name] } {
      error "Saved $name has the wrong assembly bump members"
    }
  }
  set found 0
  foreach net [[[ord::get_db] getChip] getChipNets] {
    set name [$net getName]
    if { $name ni {VDD VSS} } { continue }
    incr found
    set segments [psm::get_3d_chip_rsegs $net]
    if { [llength $segments] != 1 || [psm::get_3d_chip_cap_node_count $net] != 2 } {
      error "Saved $name is missing its resistor or endpoint nodes"
    }
    set rseg [lindex $segments 0]
    if { abs([$rseg getResistance] - 0.1) > 1e-6 } {
      error "Saved $name has the wrong resistance"
    }
    foreach endpoint {Source Target} chip_name {chipA chipB} suffix {_FRONT {}} {
      set node [$rseg get${endpoint}CapNode]
      set bump [$node getChipBumpInst]
      set chip [[$bump getChipRegionInst] getChipInst]
      if { [$chip getName] ne $chip_name || [[$node getBTerm] getName] ne "${name}${suffix}" } {
        error "Saved $name has the wrong $endpoint endpoint"
      }
    }
  }
  if { $found != 2 } { error "Saved database is missing supply nets" }
  puts RELOAD_PASS
}
close $stream
set failed [catch {
  exec [info nameofexecutable] -no_init -no_splash -exit $reload_script 2>@1
} output]
if { $failed || [string first RELOAD_PASS $output] < 0 } { puts $output }
check "ODB bump membership, local package nets, and resistors survive save/reload" {
  expr { !$failed && [string first RELOAD_PASS $output] >= 0 }
} 1

exit_summary
