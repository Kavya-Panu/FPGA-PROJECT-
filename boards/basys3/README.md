# Basys 3 hardware demonstration

The user's board photo confirms a Digilent Basys 3. The selected Vivado part `xc7a35tcpg236-1` is correct for this board. This demo uses its 100 MHz oscillator, four switches, centre/up buttons, LEDs and four-digit display. Pin assignments are based on the [Digilent master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc).

The Basys 3 has no onboard Ethernet MAC/PHY connector. The demo generates Ethernet/IP/UDP byte streams inside the FPGA and feeds the same parser used in the 10G interface project. It demonstrates real packet-processing logic in hardware once programmed; it does not receive a physical 10G network stream. The board's facilities are documented in the [Basys 3 reference manual](https://www.amd.com/content/dam/amd/en/documents/university/aup-boards/XUPBasys3/documentation/Basys3_rm_8_22_2014.pdf).

## Program the demo

Use the included [programming file](prebuilt/basys3_demo.bit). Its [build evidence](../../reports/fpga-validation.md) records passing routed timing at 100 MHz in Vivado 2025.1. The first physical board test remains pending.

1. Connect the Basys 3 to the PC using its micro-USB programming port and turn on board power.
2. In Vivado, open **Hardware Manager → Open Target → Auto Connect**.
3. Select the detected `xc7a35t` device and choose **Program Device**.
4. Select `boards/basys3/prebuilt/basys3_demo.bit` and program the FPGA. No debug-probes file is required.
5. Put SW3 down (off) for manual mode. Press the upper button, BTNU, once to reset the demo.
6. Select a packet with SW2–SW0, then press and release the centre button, BTNC.

This loads volatile FPGA configuration. The demo does not write the board's flash memory; a power cycle removes the loaded configuration unless the board subsequently boots it from some separately programmed nonvolatile source.

## Controls

Switch up means 1; switch down means 0. Read the three selection switches as SW2 SW1 SW0, with SW0 the rightmost of those three.

| SW2 SW1 SW0 | Packet | Expected outcome | LED |
|---|---|---|---|
| 000 | AAPL, price 99.0000 | BUY | LD0 |
| 001 | AAPL, price 105.0000 | HOLD | LD2 |
| 010 | AAPL, price 111.0000 | SELL | LD1 |
| 011 | UNKNOWN! symbol | Symbol miss | LD3 |
| 100 | Wrong destination UDP port | Rejected | LD4 |
| 101 | Corrupted UDP payload/checksum | Rejected | LD4 |
| 110 | MAC bad-frame indication | Rejected | LD4 |
| 111 | Truncated frame | Rejected | LD4 |

The AAPL table row has buy=100.0000 and sell=110.0000. Selection 110 has correct packet bytes but a separate bad-frame sideband; a PCAP alone cannot encode this injected MAC status.

- **BTNC:** send one packet. Holding it does not repeat. Wait for the switches to settle before pressing.
- **BTNU:** reset the parser, configuration, results and counters.
- **SW3 on:** automatically replay the selected packet roughly twice per second. SW3 off restores manual operation.
- **LD0–LD4:** classification of the most recently sent packet. Cleared when a new packet starts.
- **LD5:** unexpected configuration error or dropped action. It should stay off.
- **LD6:** busy pulse; it is too short to see during normal operation.
- **LD7:** initialized indicator.
- **LD14–LD8:** low seven bits of the received-frame counter, in binary.
- **LD15:** clock heartbeat, about one full blink every 1.34 seconds.
- **Four-digit display:** emitted BUY+SELL action count, in hexadecimal, modulo 65,536. HOLD/rejected/missing-symbol packets do not increment it.

For a quick demonstration, select 000 and send: display becomes 0001. Select 001 and send: display remains 0001. Select 010 and send: display becomes 0002. Select any error case and send: LD4 lights and the display remains 0002. The signal LEDs may differ from the red power LED or green DONE LED; use the LD numbers printed beside the user LED row.

## Build from source

From the repository root in a Vivado-enabled terminal:

```text
vivado -mode batch -source scripts/build_basys3.tcl
```

On the development computer:

```powershell
& 'C:\Xilinx\2025.1\Vivado\bin\vivado.bat' -mode batch -source scripts/build_basys3.tcl
```

Output: `build/basys3/basys3_demo.bit`. The build script checks routed setup and hold slack before generating the bitstream. Inspect the saved reports for constraints, DRC and CDC too. The standalone core's 156.25 MHz OOC report is a separate result; it does not describe this 100 MHz demo.

All internal registers are timed at 100 MHz. Switches and buttons are asynchronous and enter through explicit synchronizers. LEDs and display segments have no receiving clock: the constraints bound register-to-pin settling to 20 ns instead of inventing an external synchronous setup/hold requirement. These output exceptions do not relax internal pipeline timing.

To create a normal editable Vivado project, run `scripts/create_basys3_project.tcl` with Vivado in batch mode, then open the generated `build/basys3_project/basys3_demo.xpr`. You do not need to create the empty project shown in the earlier screenshot or add files individually.

## Verification and design limits

Run `python tools/check.py` with Icarus Verilog installed. This includes the board wrapper test: eight packet profiles, output fields, a rejected button glitch, held-button behavior, auto replay, power-on/button reset and a complete display scan. Button-debounce and repeat parameters are shortened only in the testbench; the hardware defaults are 10 ms and 0.5 seconds at 100 MHz.

The source clock remains 100 MHz throughout this demo. Nine packet beats therefore occupy 90 ns of interface slots; core output-valid appears four clocks / 40 ns after the last accepted beat if a signal is produced and the queue is empty. Manual/auto replay intervals intentionally dominate the total interval between packets. There is no physical network speed claim.

Only one fixed table row is configured here, so Vivado may optimize unused table logic and unused output fields. Use the full core benchmark for general eight-entry utilization. No UART, external Ethernet module, MAC IP license or external Pmod is required for this demo.
