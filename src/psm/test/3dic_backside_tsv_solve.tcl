# Solve the backside-TSV 3D PDN and verify its inter-die IR drop.
set test_name 3dic_backside_tsv_solve
source "helpers.tcl"

read_3dbx "3dic_backside_tsv.3dbx"

# Synthetic 0.1 ohm front-to-front bond resistance.
add_3d_pdn_connection \
  -net VDD \
  -source_chip chipA \
  -source_port VDD_FRONT \
  -target_chip chipB \
  -target_port VDD \
  -resistance 0.1
add_3d_pdn_connection \
  -net VSS \
  -source_chip chipA \
  -source_port VSS_FRONT \
  -target_chip chipB \
  -target_port VSS \
  -resistance 0.1

# Chip A and Chip B draw 10 mA and 20 mA from VDD and return the same
# currents into VSS.
add_3d_pdn_current \
  -net VDD -chip chipA -port VDD_FRONT -current -0.01
add_3d_pdn_current \
  -net VDD -chip chipB -port VDD -current -0.02
add_3d_pdn_current \
  -net VSS -chip chipA -port VSS_FRONT -current 0.01
add_3d_pdn_current \
  -net VSS -chip chipB -port VSS -current 0.02

# The package supplies Chip A through its backside bumps.
set_3d_pdn_voltage_source \
  -net VDD -chip chipA -port VDD_BACK -voltage 1.0
set_3d_pdn_voltage_source \
  -net VSS -chip chipA -port VSS_BACK -voltage 0.0

check "PSM solves the combined VDD network" {
  solve_3d_power_grid -net VDD
} 1
check "PSM solves the combined VSS network" {
  solve_3d_power_grid -net VSS
} 1

set vdd_source [get_3d_pdn_voltage \
  -net VDD -chip chipA -port VDD_BACK]
set vdd_a [get_3d_pdn_voltage \
  -net VDD -chip chipA -port VDD_FRONT]
set vdd_b [get_3d_pdn_voltage \
  -net VDD -chip chipB -port VDD]
set vss_source [get_3d_pdn_voltage \
  -net VSS -chip chipA -port VSS_BACK]
set vss_a [get_3d_pdn_voltage \
  -net VSS -chip chipA -port VSS_FRONT]
set vss_b [get_3d_pdn_voltage \
  -net VSS -chip chipB -port VSS]

check "VDD backside package source is fixed at 1 V" {
  expr {abs($vdd_source - 1.0) < 1.0e-9}
} 1
check "VSS backside package source is fixed at 0 V" {
  expr {abs($vss_source) < 1.0e-9}
} 1
check "VDD decreases from package through Chip A into Chip B" {
  expr {$vdd_source > $vdd_a && $vdd_a > $vdd_b && $vdd_b > 0.0}
} 1
check "VSS increases from package through Chip A into Chip B" {
  expr {$vss_b > $vss_a && $vss_a > $vss_source}
} 1

# Only Chip B's 20 mA crosses each 0.1 ohm inter-die resistor, so the
# voltage difference across that resistor must be I*R = 0.002 V.
check "VDD inter-die voltage drop is 2 mV" {
  expr {abs(($vdd_a - $vdd_b) - 0.002) < 1.0e-7}
} 1
check "VSS inter-die voltage rise is 2 mV" {
  expr {abs(($vss_b - $vss_a) - 0.002) < 1.0e-7}
} 1

exit_summary
