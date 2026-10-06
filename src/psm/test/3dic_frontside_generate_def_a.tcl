# Generate Chip A with its frontside power grid and signal routes.
source "helpers.tcl"


read_lef ../../../test/Nangate45/Nangate45_tech.lef


read_lef ../../../test/Nangate45/Nangate45_stdcell.lef


read_liberty ../../../test/Nangate45/Nangate45_typ.lib


read_lef ../../../test/Nangate45/fake_bumps.lef


read_verilog ./3dic_frontside_top.v


link_design flop_chip_a


# we explicitly specify the die and core area because the existing bump in Nangate45 is 29um
# If we proceed with utilization argument, then a very small chip will be produced
# site name is given in Nangate45_tech.lef line 770 SITE...
# The larger die separates the signal bumps, including space for PADs placement
initialize_floorplan -die_area {0 0 130 130} -core_area {10 10 90 90} \
  -site FreePDK45_38x28_10R_NP_162NW_34O


# For x - Distance from row start = 20 − 10.07 = 9.93 µm,
# Number of slots = 9.93 ÷ 0.19 ≈ 52.26, Nearest whole number = 52
# For y - Distance from first row = 20 − 11.20 = 8.80 µm,
# Number of rows = 8.80 ÷ 1.40 ≈ 6.29, Nearest whole number = 6
place_inst -name ff -origin {19.95 19.60}
place_inst -name inv -origin {39.90 19.60}
place_inst -name buf_inst -origin {59.85 19.60}


check_placement -verbose


add_global_connection -net VDD -pin_pattern {^VDD$} -power
add_global_connection -net VSS -pin_pattern {^VSS$} -ground


global_connect


set_voltage_domain -name CORE -power VDD -ground VSS


define_pdn_grid -name main_grid -pins {metal6} -voltage_domains {CORE}


# Vertical metal6 straps for VDD and VSS
add_pdn_stripe -grid main_grid -layer metal6 -width 0.48 -pitch 80.0 \
  -offset 20.0 -starts_with GROUND -number_of_straps 1


# Horizontal metal1 straps connecting the VDD/VSS of std cells
add_pdn_stripe -grid main_grid -layer metal1 -width 0.17 -pitch 2.80 \
  -offset 8.40 -starts_with GROUND -number_of_straps 1


add_pdn_connect -grid main_grid -layers {metal1 metal6}


pdngen -skip_trim


check_power_grid -net VDD


check_power_grid -net VSS


# Place the power bumps. Their metal5 PADs touch the existing PDN via stacks.
# These origins equal the bump-map centres minus 14.5 um in X and Y.
set block [ord::get_db_block]
foreach {name net x y} {
  bump_vdd VDD 70.07 21.00
  bump_vss VSS 30.07 19.60
} {
  place_inst -name $name -cell BUMP -origin [list $x $y] -status FIRM
  set bump [$block findInst $name]
  [$bump findITerm PAD] connect [$block findNet $net]
}

# Create routing tracks.
make_tracks

# Keep the small signal ports on metal4 underneath their metal5 bump PADs.
# Each port is inside its PAD's area when viewed from above. Separate layers
# avoid the complete same-layer overlap that causes ODB-0420 in extraction.

place_pin -pin_name clk -layer metal4 -location {14.50 60.50} -pin_size {1 1}

place_pin -pin_name d -layer metal4 -location {80.50 51.50} -pin_size {1 1}

place_pin -pin_name q -layer metal4 -location {45.50 64.50} -pin_size {1 1}

# Keep ordinary signal wiring on the lower layers. The router also creates
# access to the standard-cell pins on metal1. M5 is for bump contacts;
# M6 carries the power-grid straps.
set_routing_layers -signal metal2-metal4

# Plan the paths.
global_route

# Create the actual metal wires and vias.
detailed_route -output_drc [make_result_file "3dic_frontside_a_routing.drc"]
if { [detailed_route_num_drvs] != 0 } {
  error "Signal routing has DRC violations."
}


# The detailed router does not make pin access for COVER BUMP cells.
# Add the signal bumps after routing, then connect them with the vias below.
# Keep names and origins consistent with this chiplet's bump map.
foreach {name net x y} {
  bump_clk clk 10.50 60.50
  bump_d d 80.50 55.50
  bump_q q 45.50 60.50
} {
  place_inst -name $name -cell BUMP -origin [list $x $y] -status FIRM
  set bump [$block findInst $name]
  [$bump findITerm PAD] connect [$block findNet $net]
}

check_power_grid -net VDD
check_power_grid -net VSS

# Add just the final M4-to-M5 via at each signal port. Use the existing
# Nangate45 via4_0 definition; do not route signal wires on M5 or M6.
# The M4 port rectangle joins the routed signal to the via. The M5 landing
# touches the bump PAD. Coordinates here come from ODB and are already DBU.
# dbWireEncoder is also used in src/odb/test/test_wire_codec.tcl.
set tech [$block getTech]
set metal4 [$tech findLayer metal4]
set bump_via [$tech findVia via4_0]
set encoder [odb::dbWireEncoder]
foreach port_name {clk d q} {
  set port [$block findBTerm $port_name]
  set pin [lindex [$port getBPins] 0]
  set rect [lindex [$pin getBoxes] 0]
  set x [expr { ([$rect xMin] + [$rect xMax]) / 2 }]
  set y [expr { ([$rect yMin] + [$rect yMax]) / 2 }]
  $encoder append [[$port getNet] getWire]
  $encoder newPath $metal4 ROUTED
  $encoder addPoint $x $y
  $encoder addTechVia $bump_via
  $encoder end
}
$encoder -delete

# Check again with all bump PADs present, before saving the finished DEF.
set drc_file [make_result_file "3dic_frontside_a_bumps.drc"]
drt::check_drc -output_file $drc_file
if { [file size $drc_file] != 0 } {
  error "The completed layout has DRC violations; see $drc_file"
}

write_def 3dic_frontside_a.def
