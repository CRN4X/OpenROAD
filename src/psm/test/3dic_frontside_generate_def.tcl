# comment link_design command and write_def depending on the chiplet


read_lef ../../../test/Nangate45/Nangate45_tech.lef


read_lef ../../../test/Nangate45/Nangate45_stdcell.lef


read_liberty ../../../test/Nangate45/Nangate45_typ.lib


read_verilog ./3dic_frontside_top.v


# link_design flop_chip_a


link_design flop_chip_b


# we explicitly specify the die and core area because the existing bump in Nangate45 is 29um
# If we proceed with utilization argument, then a very small chip will be produced
# site name is given in Nangate45_tech.lef line 770 SITE...
initialize_floorplan -die_area {0 0 100 100} -core_area {10 10 90 90} \
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


# write_def 3dic_frontside_a.def


write_def 3dic_frontside_b.def
