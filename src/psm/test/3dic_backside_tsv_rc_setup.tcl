# Run after read_3dbx. Both chiplets share the GT2N technology.

# Use the existing RC table and commands
# to populate ODB layer/vias resistance values
set_cmd_units -resistance ohm -distance um -capacitance pF
source "gt2n_data/setRC.tcl"

# RDL is absent from the GT2N table. Use BRDL's 0.01 ohm/um as a test assumption.
set_layer_rc -layer RDL -resistance 0.01
