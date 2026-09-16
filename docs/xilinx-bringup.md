# Connecting the core to a Xilinx board

## What can be built now

The college board is confirmed as **Basys 3**, part `xc7a35tcpg236-1`. Use the [Basys 3 internal-packet demo](../boards/basys3/README.md) for this board. It has no onboard Ethernet interface. Vivado 2025.1 is available locally and the [FPGA report](../reports/fpga-validation.md) records the executed builds.

The core and its tests remain vendor neutral. `scripts/vivado_ooc.tcl` performs a device-only implementation flow at a 6.4 ns clock. Its clock and I/O budgets are examples, not a board constraint file. The general MAC integration instructions below apply to a future suitable Ethernet platform.

From the repository root in a Vivado-enabled terminal:

```text
vivado -mode batch -source scripts/vivado_ooc.tcl -tclargs xc7a35tcpg236-1
```

For another device, replace the part with its complete package and speed grade. The flow produces a checkpoint, utilization, timing, DRC and constraint-check reports under `build/vivado_ooc/`. It does not create a bitstream or choose physical pins. Check setup, hold, unconstrained paths and DRC in the generated reports; a successful script exit alone is not proof of timing closure. AMD documents the use of [check_timing](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/check_timing) to identify timing-constraint problems.

## Information to obtain from the college

Record the board model/revision, exact FPGA part, available transceiver connector (for example SFP+ or a suitable expansion path), reference-clock frequency, board schematic/master constraints, Vivado version, and the Ethernet IP available in the lab. Confirm there is a compatible 10G traffic source or a loopback setup. A board that can run this logic may still lack the physical interface required for a 10G link.

Use the board/vendor example for clocks, transceiver pins, resets and MAC/PCS/PMA first. Verify its Ethernet receive path before inserting this parser. Device-specific transceiver settings should come from that example and the matching board documentation.

## Stream connection

Configure a 64-bit receive interface with Ethernet headers retained and preamble/FCS stripped. Supply a normalized error indication through `mac_rx_adapter`. Its output wires connect directly to the top module's corresponding `s_axis_*` ports. Both modules are in the MAC receive clock domain; the adapter is combinational.

| MAC convention in the exact IP guide | `GOOD_FRAME_TUSER` | Normalized parser flag |
|---|---:|---|
| TUSER=1 means bad frame | 0 | TUSER unchanged |
| TUSER=1 means good frame on TLAST | 1 | TLAST AND NOT TUSER |

The older [Xilinx 10G Ethernet MAC PG072](https://docs.amd.com/api/khub/documents/y6kqi3sEJLyLWhNGcTzgSA/content) uses **good=1** on the final beat, so that interface needs setting 1. Other MACs can use the opposite convention. Select this from the exact generated IP documentation and validate it with one good frame and one deliberate FCS error. The parser's final-status check depends on this mapping.

If the MAC has no RX ready port, leave the core's constant-high `s_axis_tready` unconnected. If it supports ready, drive it from the core's ready output. No output-event stall propagates back to the MAC.

## Clocks and controls

Run the core at the MAC's receive clock. Synchronize reset release to that clock and arrange a clean frame boundary after reset. Do not connect configuration strobes, DIP switches, AXI-Lite registers or software buses directly across clock domains. A host-control bridge must transfer a whole row atomically; independent bit synchronizers are not sufficient for multibit configuration.

For the first board demo, a short initialization controller in the RX clock domain can program a fixed AAPL row after reset. Keep the event consumer ready and capture events with an ILA. An AXI-Lite control block, coherent counter snapshots and asynchronous event FIFO can follow if the host is on another clock.

## Board acceptance sequence

1. Confirm the vendor Ethernet example receives known traffic and reports the correct status polarity.
2. Replace its receive consumer with the adapter and core. Program AAPL buy=1,000,000 and sell=1,100,000.
3. Inject the six demo packets. Expect BUY sequence 1, SELL sequence 3, one HOLD, one symbol miss, two rejected packets and no overflow. For an actual bad-FCS test, use an appropriate MAC/traffic-generator path; a normal host NIC usually generates its own FCS.
4. Capture input last/valid, parser tick valid, output valid/action/sequence and counters. Verify four RX clocks from a good final beat to first output valid with an empty queue.
5. Run sustained supported and mixed traffic. Record generator settings, packet counts, duration, errors, queue drops and the exact bitstream/build ID.
6. Save routed timing/utilization reports and board captures. Repeat under output stalls, then restore consumption and check accounting.

Use the sample PCAP as packet content, not as proof of traffic-generator timing. Its timestamps are illustrative and it contains no FCS bytes.

## Evidence needed before upgrading performance claims

Keep the exact part, tool version, clock constraints, routed setup/hold results, LUT/FF/BRAM usage, MAC configuration, and observed line-rate packet counts together. Quote latency with start/end points and state whether it includes the PHY/MAC. The FPGA results distinguish the full-core OOC experiment from the 100 MHz Basys 3 demonstration; neither establishes physical network performance.
