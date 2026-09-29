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

The GUI now draws two small, independent bridge boundaries on each chip:
  tsv_vdd: (4,4) to (6,6) microns, connected only to VDD.
  tsv_vss: (14,14) to (16,16) microns, connected only to VSS.
The 1.6 micron RDL/BRDL contacts remain centered at (5,5) and (15,15).
The old combined 12 x 12 micron bridge rectangle has been removed.

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
Run these two commands in your Linux shell:

cd /home/cmratnap/Documents/27_Aug_2026_OpenRoad/OpenROAD/src/psm/test
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init

Then run this INSIDE the OpenROAD Tcl console:

read_3dbx "3dic_backside_tsv.3dbx"

If your OpenROAD session provides a GUI, enable RDL and BRDL to see the
contacts and rails. Enable BPR, M0 and M1 and zoom around x=6..11, y=2..2.4
microns to see ff, inv and buf. The logic cells are much smaller than the
1.6 micron bumps: the inverter is only 0.084 microns wide. A remote shell
needs a working GUI/display connection
before a desktop window can appear. Restart OpenROAD to reload edited
LEF/DEF/BMAP files into a fresh database. No binary rebuild is needed.

Connect and check the power networks
-----------------------------------
Continue INSIDE that same OpenROAD Tcl console:

source "3dic_backside_tsv_rc.tcl"
set vdd_rseg [add_3d_pdn_connection -net VDD -source_chip chipA -source_port VDD_FRONT -target_chip chipB -target_port VDD -resistance 0.1]
set vss_rseg [add_3d_pdn_connection -net VSS -source_chip chipA -source_port VSS_FRONT -target_chip chipB -target_port VSS -resistance 0.1]
check_3d_power_grid -net VDD
check_3d_power_grid -net VSS
check_3d_g_matrix -net VDD -require_tsv
check_3d_g_matrix -net VSS -require_tsv

The assembly describes which chip surfaces and supply nets belong together.
add_3d_pdn_connection adds the electrical resistor between two named bump
ports. Run each add command once in a fresh loaded design; attempting to
add the same link again reports a duplicate connection.

Resistance assumptions
----------------------
The GT2N technology LEF does not contain resistance values. The small
3dic_backside_tsv_rc.tcl script sets values only in the loaded database.
BRDL uses 0.01 ohm/micron from the existing gt2n_data/setRC.tcl table.
RDL uses the same value as an explicit test assumption, since that table
does not characterize RDL. With a 1.6 micron nominal width, each value is
0.016 ohm/square in OpenDB. The BPR, BM1..BM4 and BV0..BV4 resistance values
also come from the existing GT2N RC table. The bond resistance is a test value.
Use characterized models before interpreting voltages as PDK predictions.

Run automated checks
--------------------
From the Linux shell in src/psm/test (each starts a fresh OpenROAD process):

/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_bumps.tcl
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_connectivity.tcl
/home/cmratnap/Documents/27_Aug_2026_OpenRoad/install/OpenROAD/bin/openroad -no_init -no_splash -exit 3dic_backside_tsv_solve.tcl

The bump test checks all six contacts, their nets, ports, layers and rail
intersection, plus the three logic cells and every vdd/vss contact on each
chiplet. It also verifies that each bridge has one supply terminal and its
own small boundary. The connectivity test disables each supply's bridge
model separately and checks that the other supply still works. It also
moves a flip-flop off its rails to detect its disconnected power pins.
Expected ERROR lines inside that test are intentional; its final Summary
must say 100% pass.
The solve test supplies Chip A from the back and checks the voltage drop
across the inter-chip bonds for both VDD and VSS.

3dic_backside_tsv_broken.3dbx selects the deliberately broken Chip B DEF.
Its extra VDD stripe at y=10 microns is physically separate from the VDD
stripe at y=5, although both are named VDD. The disconnected and singular
tests verify that merely sharing a net name does not hide this open circuit.
