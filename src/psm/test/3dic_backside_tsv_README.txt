GT2N TWO-CHIP BACKSIDE POWER EXAMPLE

Purpose
-------
Load two 20 x 20 micron chiplets, supply Chip A from its backside, and
carry VDD and VSS through Chip A to the front-facing Chip B.
Both chiplets use GT2N. This version is not a mixed-PDK example.
Each chiplet has three real GT2N logic cells: a flip-flop (ff), an inverter
(inv), and a buffer (buf). Each also has two separate custom bridge cells,
tsv_vdd and tsv_vss, connecting the front power grid to the buried power
rails. Bumps are additional objects.
This remains a power-network example, not a routed functional logic design.
The goal is to check that the power paths are connected and that PSM
calculates the voltage drop from the package through the two chiplets.

Run the complete example
------------------------
For a normal demonstration, run these two commands in your Linux shell:

cd /home/cmratnap/Documents/27_Aug_2026_OpenRoad/OpenROAD/src/psm/test
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_solve.tcl

The solve script loads the assembly, creates the test bond resistors,
loads wire/via resistance values, applies the supply and current loads,
then calculates and checks the voltages. Its final Summary should report
100% pass. It starts in a fresh process and exits when finished.

Why there are several Tcl files
------------------------------
3dic_backside_tsv_connections_setup.tcl: creates the two test bond resistors.
3dic_backside_tsv_rc_setup.tcl: loads the GT2N wire and via resistance values.
3dic_backside_tsv_solve.tcl: runs the complete example and voltage checks.
The other Tcl tests check individual problems, such as broken wires,
missing voltage sources, invalid resistance or lost data after saving ODB.
You do not need to run every test for a normal demonstration. The solve
script already calls both setup scripts. The sections below also explain
how to load and inspect the example interactively.

What comes from GT2N, and what is custom?
---------------------------------------
gt2n_data/gt2_tech.lef defines the real layer names, widths and backside
flags. gt2n_data/gt2_6t_w31_svt.lef is the existing standard-cell library.
Both files are loaded unchanged.

3dic_backside_gt2n_cells.lef is our separate TEST library. It defines:
  GT2N_TEST_BUMP_FRONT: a 1.6 x 1.6 micron PAD on frontside RDL.
  GT2N_TEST_BUMP_BACK:  a 1.6 x 1.6 micron PAD on backside BRDL.
  GT2N_TEST_TSV_VDD: a 2 x 2 micron cell with one VDD pin on RDL and BRDL.
  GT2N_TEST_TSV_VSS: a 2 x 2 micron cell with one VSS pin on RDL and BRDL.

Each bridge is flagged LEF58_BACKSIDE_BRIDGE. PSM models its cross-side
connection with its fixed 0.001 ohm BridgeConnection edge. These are
abstract test models, not GT2N-provided or manufacturing-qualified TSVs.
No bump height or detailed TSV cross-section is specified by this LEF.

Where the bumps are placed
--------------------------
The custom .bmap files belong to the design. Coordinates are microns.
For these masters the cell-boundary center and PAD center coincide.

File                             VDD PAD center     VSS PAD center
3dic_backside_tsv_a_front.bmap    (10, 5)            (10, 15)
3dic_backside_tsv_b_front.bmap    (10, 5)            (10, 15)
3dic_backside_tsv_a_back.bmap     (5, 10)            (15, 10)

The .3dbv file references all three maps and the LEFs/DEFs. The .3dbx
file includes that .3dbv and places Chip B with an MZ flip. This changes
which way Chip B faces without changing the bump x/y coordinates.

Each DEF places the power ports and wires. Front RDL rails are horizontal
at y=5 and y=15 microns. Both chips have vertical BRDL rails at x=5 and
x=15. Their bridges connect the two sides at (5,5) for VDD and (15,15) for
VSS. These large rails are 1.6 microns wide. Chip B also declares TSV support
because it contains these custom front-to-back bridge models.

Logic cells and their power connections
--------------------------------------
The three logic-cell positions are identical on both chiplets:

Instance  Function     GT2N master                        Origin (microns)
ff        Flip-flop    gt2_6t_dffasync_x1_w31_svt           (6.006, 2.016)
inv       Inverter     gt2_6t_inv_x1_w31_svt                (8.022, 2.016)
buf       Buffer       gt2_6t_buf_x1_w31_svt                (10.038, 2.016)

The DEF COMPONENTS count is 5: three logic cells plus tsv_vdd and tsv_vss.
The BMAP reader adds the bump instances separately (four on Chip A, two on
Chip B). The logic cells do not overlap one another or the bridge cells.

The GUI draws two small, independent bridge boundaries on each chip:
  tsv_vdd: (4,4) to (6,6) microns, connected only to VDD.
  tsv_vss: (14,14) to (16,16) microns, connected only to VSS.
The 1.6 micron RDL/BRDL contacts remain centered at (5,5) and (15,15).

These GT2N cells have lowercase vdd/vss pins on BPR, not M1. SPECIALNETS
assigns them to the uppercase VDD/VSS supply nets. All three share a BPR
VDD rail at y=2.160 microns and a BPR VSS rail at y=2.016 microns. The
flip-flop is double height and also touches a VSS rail at y=2.304 microns.
The BPR rails are 0.032 microns wide.

Existing GT2N vias BV0_0, BV1_0, BV2_0, BV3_0 and BV4_0 connect BPR through
BM1, BM2, BM3 and BM4 to BRDL. VDD uses a stack at (5,2.160); VSS uses one
at (15,2.016), with an extra BV0_0/BM1 connection to the upper ground rail.
The continuous BPR rails distribute power to all three cells, so they can
share these stacks. This is a connectivity example, not a DRC-closed layout.

Two unrouted signal nets connect ff.Q to inv.A, then inv.Y to buf.A.
Clock, data, reset and set inputs are not driven in this power-network test.
The solve test still applies explicit aggregate loads at the chip ports;
it does not derive switching currents from the three logic cells.

Load the layout
---------------
For an interactive session, run these commands in your Linux shell:

cd /home/cmratnap/Documents/27_Aug_2026_OpenRoad/OpenROAD/src/psm/test
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init

Then run this INSIDE the OpenROAD Tcl console:

read_3dbx "3dic_backside_tsv.3dbx"

This loads the chiplets, bumps, ports, nets and bond information into ODB.
It does not create the electrical resistor objects between the chiplets.

To open the desktop GUI, add -gui to the OpenROAD startup command.
In the GUI, enable RDL and BRDL to see the contacts and rails. Enable BPR, M0 and M1 and zoom around x=6..11, y=2..2.4
microns to see ff, inv and buf. The logic cells are much smaller than the
1.6 micron bumps: the inverter is only 0.084 microns wide. A remote shell
needs a working GUI/display connection before a desktop window can appear.
Restart OpenROAD to reload edited LEF/DEF/BMAP files into a fresh database.
Data edits do not require a rebuild.

Create and check the test's electrical connections
--------------------------------------------------
Continue INSIDE the same OpenROAD Tcl console, before any power analysis:

source "3dic_backside_tsv_connections_setup.tcl"
source "3dic_backside_tsv_rc_setup.tcl"
check_3d_power_grid -net VDD
check_3d_power_grid -net VSS
check_3d_g_matrix -net VDD -require_tsv
check_3d_g_matrix -net VSS -require_tsv

The connections script creates two resistor objects in ODB:

chipA / VDD_FRONT ---- 0.1 ohm ---- chipB / VDD
chipA / VSS_FRONT ---- 0.1 ohm ---- chipB / VSS

The connections script asks each assembly net for its two bump members
using getNumBumpInsts and getBumpInst. read_3dbx already stored this membership
from the Verilog, so the script does not search chip regions to find it again.
It checks that there is one bump on chipA and one on chipB, and that no
resistor objects already exist, before adding either supply's resistor.

It uses the existing odb::dbChipCapNode_create API for each endpoint and
odb::dbChipRSeg_create for the resistor between them. setChipBumpInst
attaches each endpoint to its bump. setResistance stores the resistance
value. ODB creates endpoint nodes with zero capacitance by default, so
there is no separate capacitance assignment. The same ODB creation APIs
are used by src/odb/test/cpp/TestChips.cpp.

This creation step is still needed: read_3dbx loads the assembly connections,
but does not create resistor objects. The script supplies the two test
resistors that PSM needs to calculate the chip-to-chip voltage drop.

The connections script reads the bond resistance from 3dic_cross_assembly.rules,
located beside the script. The file currently contains:

VIA_RESISTANCE
HBV 0.1
END

This is the same assembly rules file used by the Nangate RCX tests. The script
reads the first HBV entry in the VIA_RESISTANCE table and assigns that value
in ohms to both bond resistors. Comments and blank lines are ignored. A missing,
invalid or nonpositive resistance stops setup before any resistor is created.
The value is a test assumption, not a resistance extracted from GT2N geometry.
The setup script reads the file itself and does not call RCX. There is no
automatic extraction trigger in PSM.

Each supply path still has three physical bumps. They are connected in
two sections:

Inside Chip A (local DEF power net):
package bump -> backside PDN -> TSV bridge -> front bump

Between the chips (assembly power net):
Chip A front bump -> bond resistor -> Chip B front bump

3dic_backside_tsv_top.v connects only VDD_FRONT and VSS_FRONT to the
assembly supply nets. VDD_BACK and VSS_BACK are left unbound in that
Verilog file, so each assembly dbChipNet has exactly two bump members.
This does not remove the back bumps or disconnect them from the local PDN:
3dic_backside_tsv_a.def still connects each back port and front port to
the same local VDD or VSS net. The DEF wires and bridge contacts provide
the physical path. The BMAP files still place all six bumps.

PSM applies voltage sources to Chip A's local VDD_BACK and VSS_BACK ports.
The front bump's local power net lets PSM include this entire Chip A PDN,
including its backside source port, in the combined power network.

Source the connections script only once per freshly loaded example. It
reports an error if the power-net resistor objects already exist. To change
the assumed bond resistance, edit the HBV value in 3dic_cross_assembly.rules
and start a fresh session. The regression checks expect the supplied 0.1-ohm value.

The RC script sets the layer and via resistances. Supply voltages and
current loads are applied separately by the solve test. Reading the .3dbx
or sourcing the connections script does not attach a voltage source.

To see the stored resistor values, use this PSM query. It only reads ODB:

foreach net [[[ord::get_db] getChip] getChipNets] {
  foreach rseg [psm::get_3d_chip_rsegs $net] {
    puts "[$net getName]: [$rseg getResistance] ohm"
  }
}

write_db saves the resistor objects. After reopening that database with
read_db, do not source the connections script again: the objects are
already saved. A fresh read_3dbx needs the connections script again.
The last full write_3dbx export/reload check for this GT2N example failed
with ODB-0359 (a FIRM bump origin mismatch). Use the tested write_db/read_db
route to save and reopen the loaded design.

Why this test does not use full RCX extraction
----------------------------------------------
The existing extract_parasitics command already creates inter-chip
resistors as part of a full extraction. The Nangate45 test
3dic_cross_rcx_gmatrix.tcl demonstrates that existing flow. It uses
Nangate45/Nangate45.rcx_rules for wiring inside the chiplets and
3dic_cross_assembly.rules for the bonds. The 0.1-ohm bond value in that
rules file is a test assumption. No added RCX function is needed.

The original RCX implementation supports only two bumps per assembly net.
This example now meets that requirement; its package bumps belong to
Chip A's local nets and are not additional assembly-net members.
The GT2N files supplied here still do not include an RCX extraction model.
The tests therefore read the shared assembly bond rule in the Tcl setup script
and create the resistors with existing ODB APIs. Reading this bond value does
not require the missing technology extraction model or changes to RCX.

Resistance assumptions
----------------------
The GT2N technology LEF does not contain resistance values.
3dic_backside_tsv_rc_setup.tcl sets command units to ohms, microns and pF, then
sources the existing gt2n_data/setRC.tcl. Its set_layer_rc commands load
the values into ODB; we do not copy the table or modify the PDK files.
Both chiplets share this GT2N technology, so the setup applies to both.

Inside 3dic_backside_tsv_rc_setup.tcl, these are TWO SEPARATE Tcl commands:

set_cmd_units -resistance ohm -distance um -capacitance pF
source "gt2n_data/setRC.tcl"

Keep them on separate lines, in this order. The first command sets units;
the second runs the RC file using those units. Do not put a backslash
between these commands: a backslash would join them into one command.
If you source 3dic_backside_tsv_rc_setup.tcl, it already runs both commands, so
you do not need to type them again.

um means micrometres and is needed for resistance per unit wire length.
pF means picofarads. The shared GT2N RC file loads both resistance and
capacitance values. Our static DC analysis uses only resistance; loading
the capacitance values does not make this a transient analysis.

BRDL uses 0.01 ohm/micron from that existing table.
RDL uses the same value as an explicit test assumption, since that table
does not characterize RDL. With a 1.6 micron nominal width, each value is
0.016 ohm/square in OpenDB. The BPR, BM1..BM4 and BV0..BV4 resistance values
also come from the existing GT2N RC table. The bond resistance is a test value.
Use characterized models before interpreting voltages as PDK predictions.

External voltage and current loads
----------------------------------
3dic_backside_tsv_solve.tcl defines the external supply for this test:
  chipA / VDD_BACK: fixed at 1.0 V.
  chipA / VSS_BACK: fixed at 0.0 V (ground).
It applies these values with set_3d_pdn_voltage_source, a command added
for our 3D PSM analysis. The package is represented by these fixed voltages;
we do not model a board voltage regulator.

The same file uses add_3d_pdn_current to make Chip A draw 10 mA and Chip B
draw 20 mA from VDD, returning those currents to VSS. These are chosen test
loads. The voltages and loads are not obtained from LEF, the RC table, or
RCX extraction. The solve test applies them after loading the assembly,
creating the bond resistors and loading the wire/via resistance values.

Run automated checks
--------------------
From the Linux shell in src/psm/test (each starts a fresh OpenROAD process):

/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_odb.tcl
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_bumps.tcl
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_connectivity.tcl
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_solve.tcl

The ODB test checks that each assembly net contains only the two front
bumps, all six physical bumps remain, and the package bumps still belong
to Chip A's local supply nets. It checks that read_3dbx alone creates no
resistor objects, then runs the connections script and checks the
front-bump endpoints and 0.1-ohm values. It verifies that repeated setup
cannot add duplicates and that the bump membership, local package nets,
and resistors survive saving and reopening the ODB database.
The bump test checks all six contacts, their nets, ports, layers and rail
intersection, plus the three logic cells and every vdd/vss contact on each
chiplet. It also verifies that each bridge has one supply terminal and its
own small boundary. The connectivity test disables each supply's bridge
model separately and checks that the other supply still works. It also
moves a flip-flop off its rails to detect its disconnected power pins.
Expected ERROR lines inside that test are intentional; its final Summary
must say 100% pass.
The G-matrix test checks the TSV flags on both chiplets and builds the
combined network. Its -require_tsv option requires at least one modeled
backside bridge in that network. The separate connectivity test checks
that disabling either supply's bridge path causes a failure.
The solve test supplies Chip A from the back and checks the voltage drop
across the inter-chip bonds for both VDD and VSS.

3dic_backside_tsv_broken.3dbx selects the deliberately broken Chip B DEF.
Its extra VDD stripe at y=10 microns is physically separate from the VDD
stripe at y=5, although both are named VDD. The disconnected and singular
tests verify that merely sharing a net name does not hide this open circuit.
