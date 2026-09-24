# THis test checks the connectivity of the PDN
# So we will be using the check_power_grid command
# with required args -net VDD and
# we alo pass in the optional parameter -floorplanning
# so that any movable cell does not blokc the PDN geometry check


# So first load the helpers to load the openRoad Testing utilities
source helpers.tcl


# The DEF depends on the LEF
# OpenROAD must read the LEF first
# so it can understand the layer, via, and cell names referenced by the DEF


# Now load the Tech LEF file
# THe lef file helps us provide techincal and physical information -
# routing layers, via definitions, cell pins, cell geometry
# LEF = reusable physical definitions/metadata
read_lef Nangate45/Nangate45.lef


# Now load and read the DEF file
# THe def file contains and provides us with -
# design name, cell instances, cell placement coordinates, signal net connections,
# VDD/VSS nets, power grid and vias, chip/core dimensions
# DEF = actual design-instance data
read_def Nangate45_data/gcd.def


# Mention the actual PSM command being tested
# Also pass in required arguments and any optional arguments
check_power_grid -net VDD -floorplanning -dont_require_terminals


# Perform the comparison between the generated output and the golden output
diff_files crn4x_test.ok results/crn4x_test-tcl.log
