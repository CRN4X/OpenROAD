# Check 3D reachability across the bond and backside bridge, including isolated metal.
set test_name 3dic_backside_tsv_connectivity
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"
source "3dic_backside_tsv_rc.tcl"

foreach net { VDD VSS } {
  set rseg($net) [add_3d_pdn_connection \
    -net $net \
    -source_chip chipA \
    -source_port ${net}_FRONT \
    -target_chip chipB \
    -target_port $net \
    -resistance 0.1]
  check "Connected $net passes the 3D power-grid check" {
    check_3d_power_grid -net $net
  } 1
  check "Connected $net passes the 3D G-matrix check" {
    check_3d_g_matrix -net $net -require_tsv
  } 1
}

set chip_a [[[[ord::get_db] getChip] findChipInst chipA] getMasterChip]
set block [$chip_a getBlock]
# The two supply bridges use different masters. Disabling one supply's
# bridge model affects that supply on both chips, while the other stays live.
foreach { net other_net } { VDD VSS VSS VDD } {
  set bridge_master [[$block findInst tsv_[string tolower $net]] getMaster]
  $bridge_master setBacksideBridge 0
  foreach { command error_id } { check_3d_power_grid PSM-0140 check_3d_g_matrix PSM-0137 } {
    set failed [catch { $command -net $net } error]
    check "$command rejects a missing $net backside bridge" {
      expr {$failed && [string first $error_id $error] >= 0}
    } 1
  }
  check "$other_net stays connected when the $net bridge is disabled" {
    check_3d_power_grid -net $other_net
  } 1
  check "$other_net retains its own bridge in the G matrix" {
    check_3d_g_matrix -net $other_net -require_tsv
  } 1
  $bridge_master setBacksideBridge 1
  check "Restoring the $net bridge restores connectivity" {
    check_3d_power_grid -net $net
  } 1
}

# Keep the net assignments, but move a real logic cell off its BPR rails.
# The network check must catch missing physical power contacts on either net.
set chip_b [[[[ord::get_db] getChip] findChipInst chipB] getMasterChip]
set ff [[$chip_b getBlock] findInst ff]
lassign [$ff getOrigin] origin_x origin_y
$ff setOrigin $origin_x [expr { $origin_y + 2000 }]
foreach net { VDD VSS } {
  foreach { command error_id } { check_3d_power_grid PSM-0140 check_3d_g_matrix PSM-0137 } {
    set failed [catch { $command -net $net } error]
    check "$command rejects a cell detached from its $net rail" {
      expr {$failed && [string first $error_id $error] >= 0}
    } 1
  }
}
$ff setOrigin $origin_x $origin_y
foreach net { VDD VSS } {
  check "Restoring the cell restores $net connectivity" { check_3d_power_grid -net $net } 1
}

# This separate BRDL patch has no terminal and no edges. It must still be counted
# when checking reachability, even though the original VDD network is intact.
set island [odb::dbSWire_create [$block findNet VDD] ROUTED]
odb::dbSBox_create $island [[$chip_a getTech] findLayer BRDL] \
  18400 30400 21600 33600 STRIPE
foreach { command error_id } { check_3d_power_grid PSM-0140 check_3d_g_matrix PSM-0137 } {
  set failed [catch { $command -net VDD } error]
  check "$command rejects isolated metal with no connections" {
    expr {$failed && [string first $error_id $error] >= 0}
  } 1
}
odb::dbSWire_destroy $island

check "Restoring VDD removes the connectivity failure" {
  check_3d_power_grid -net VDD
} 1
check "Restoring VDD also restores the G matrix" {
  check_3d_g_matrix -net VDD -require_tsv
} 1

# Both chip PDNs are intact, but their electrical bond is now missing.
odb::dbChipRSeg_destroy $rseg(VDD)
foreach { command error_id } { check_3d_power_grid PSM-0103 check_3d_g_matrix PSM-0137 } {
  set failed [catch { $command -net VDD } error]
  check "$command rejects a missing inter-die connection" {
    expr {$failed && [string first $error_id $error] >= 0}
  } 1
}

check "VSS remains connected when only VDD is broken" {
  check_3d_power_grid -net VSS
} 1

exit_summary
