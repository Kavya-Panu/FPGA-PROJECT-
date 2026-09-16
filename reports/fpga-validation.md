# FPGA implementation results

Both builds ran locally in **Vivado 2025.1** for **xc7a35tcpg236-1**, the FPGA on the confirmed Basys 3. The FPGA itself has not been programmed or observed by the assistant.

| Build | Period (ns) | Worst setup slack (ns) | Worst hold slack (ns) | Slice LUTs | Registers | Timing |
|---|---:|---:|---:|---:|---:|---|
| Full core OOC | 6.4 | -0.414 | -0.602 | 1,131 | 2,228 | NOT MET |
| Basys 3 demo | 10.0 | 0.676 | 0.024 | 575 | 784 | PASS |

Positive slack meets the stated timing check. Read both setup and hold columns. Raw timing, constraint, utilization and DRC reports are saved in `vivado_ooc/` and `basys3/`; the latter also includes a CDC report. Machine-readable results and source hashes are in `fpga-results.json`.

## Basys 3 board demo

A **100 MHz** programming file was successfully generated only after routed setup and hold checks passed. It is supplied as `../boards/basys3/prebuilt/basys3_demo.bit` (2,192,139 bytes).

SHA256: `1214c51a48aab564778785196080e5309d9e82ce1e64300d887bc00f6d16440c`.

The design uses the Basys 3 oscillator and documented physical pins. All switch and button inputs feed explicit synchronizers; switches and the send button also pass through a debounce stage. Those asynchronous input paths are excepted from external clock timing. All internal register-to-register paths retain 100 MHz setup and hold checks. LED and display ports have no external capture clock: their registered outputs instead have a 20 ns datapath-only settling limit, with no external hold requirement. The exceptions terminate only at the human-visible indicator ports. See the [AMD constraint semantics](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/set_max_delay) and the shipped XDC. The design uses internal packet ROM data, one fixed AAPL row and an always-ready consumer, so some unused general-purpose logic is optimized away.

Follow `../boards/basys3/README.md` to program and exercise it. Physical button/LED tests and traffic observation are still pending. No physical 10G network claim follows from this result.

## Full-core 156.25 MHz experiment

The full configurable core was separately synthesized, placed and routed out of context with the 6.4 ns example constraints. Overall timing result: **NOT MET**. Its boundary inputs/outputs have no physical partition-pin placement; Vivado reports partial-routing limitations for those OOC boundaries, so input/output timing is not a substitute for a real MAC/consumer integration.

The general eight-entry core's resource counts above include all runtime configuration inputs. They should not be compared directly with the fixed-row demo as though both were identical configurations. The optimized checksum acceptance check preserves the four-cycle end-of-packet to event-valid latency and passed the full packet regression plus 262,148 arithmetic-equivalence cases.

The project still needs a suitable Ethernet MAC/PHY board, actual integration constraints and real packet measurements to establish a 10G hardware implementation. The Basys 3 demonstration provides a practical hardware path for learning and interviews without purchasing a different board now.
