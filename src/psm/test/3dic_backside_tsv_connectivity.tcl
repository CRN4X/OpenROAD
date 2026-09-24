# Check 3D reachability across the bond and backside bridge, including isolated metal.
set test_name 3dic_backside_tsv_connectivity
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"

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
set bridge_master [[$block findInst tsv_bridge] getMaster]

# The inter-die bond remains, but it cannot reach the backside power rail.
$bridge_master setBacksideBridge 0
foreach { command error_id } { check_3d_power_grid PSM-0140 check_3d_g_matrix PSM-0137 } {
  set failed [catch { $command -net VDD } error]
  check "$command rejects a missing backside bridge" {
    expr {$failed && [string first $error_id $error] >= 0}
  } 1
}
$bridge_master setBacksideBridge 1

# This small B1 patch has no terminal and no edges. It must still be counted
# when checking reachability, even though the original VDD network is intact.
set island [odb::dbSWire_create [$block findNet VDD] ROUTED]
odb::dbSBox_create $island [[$chip_a getTech] findLayer B1] \
  30000 30000 30500 30500 STRIPE
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
