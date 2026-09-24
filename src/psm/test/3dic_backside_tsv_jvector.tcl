# Build and validate signed 3D current vectors for the backside-TSV assembly.
set test_name 3dic_backside_tsv_jvector
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

check "The test topology contains backside TSV bridges" {
  check_3d_g_matrix -net VDD -require_tsv
} 1

# Negative current is drawn from VDD. Chip A draws 10 mA and Chip B draws
# 20 mA, so the VDD J vector must contain -30 mA total.
add_3d_pdn_current \
  -net VDD -chip chipA -port VDD_FRONT -current -0.01
add_3d_pdn_current \
  -net VDD -chip chipB -port VDD -current -0.02

# Positive current is returned into VSS at the corresponding load ports.
add_3d_pdn_current \
  -net VSS -chip chipA -port VSS_FRONT -current 0.01
add_3d_pdn_current \
  -net VSS -chip chipB -port VSS -current 0.02

check "PSM builds the combined VDD J vector" {
  check_3d_j_vector -net VDD
} 1
check "PSM builds the combined VSS J vector" {
  check_3d_j_vector -net VSS
} 1

exit_summary
