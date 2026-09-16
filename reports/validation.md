# Executed validation snapshot

Local functional simulation and generic synthesis. Source hashes in the JSON files identify the RTL checked; `source-manifest.json` also fingerprints the test and build sources. Reproduce with `python tools/check.py`, `python tests/run.py --demo --waves`, independent lint, and `scripts/synth.ys`. Refresh this snapshot with `python tools/save_evidence.py` after those checks pass.

## End-to-end regression

| Table entries | FIFO depth | Seed | Cycles checked | Completed frames | Transferred events | Result |
|---:|---:|---:|---:|---:|---:|---|
| 8 | 16 | 20260914 | 40,408 | 3,491 | 1,444 | PASS |
| 1 | 1 | 7 | 29,799 | 2,668 | 1,080 | PASS |
| 3 | 3 | 99 | 29,907 | 2,674 | 1,137 | PASS |

Total: **100,114 clock cycles**, **8,833 completed frames**, and **3,661 output handshakes**. Every post-edge output field, valid bit, FIFO level, configuration-error flag and public counter is compared with an independent Python reference. The actual RTL handshake log is separately checked for values and ordering. All input cycles are checked for permanently asserted RX ready.

Simulator: `Icarus Verilog version 12.0 (devel) (s20150603-1539-g2693dd32b)`. Python 3.12.14 was used for the local run. Seeds and per-scenario stimulus counts are saved in the result JSON files. These are functional test counts, not code coverage percentages or a formal proof. Deliberate resets can discard candidates/events; lifetime counter totals across those resets do not obey drained-pipeline equalities.

## Tested cases

- BUY/SELL inclusive boundaries, HOLD, unsigned price extremes, maximum/zero quantity, every table slot, unknown/disabled/duplicate symbols.
- Correct IPv4/UDP checksums, omitted UDP checksum, computed-zero checksum represented as 0xffff, corrupted IP header/address/checksum and UDP header/payload.
- Wrong port, VLAN, IPv6, IP options, bad version/type/magic, TTL zero, reserved fragment flag, MF, nonzero fragment offset, inconsistent IP/UDP lengths.
- Every truncation length 1–65, all 256 final byte-enable masks, malformed nonfinal masks, MAC error on every frame beat, source-valid gaps with ignored junk sidebands.
- Oversized frames up to 9,000 bytes followed by recovery, back-to-back traffic, configuration/lookup collision and invalid writes, FIFO full+pop+push, stable stalls, reset mid-frame and at each pipeline boundary.
- 1,024 consecutive supported frames in each of the three configurations, plus 4,400 seeded randomized mixed frames across the matrix.

## Additional unit checks and demo

The event FIFO passed **36,000 additional cycles** across depths 1, 3 and 16, including continuous enqueue/dequeue traffic, stalls, overflow, wrap and reset. The MAC adapter passed all eight valid/last/user control combinations for both good-frame and bad-frame flag conventions. The optimized checksum predicate passed **262,148 cases** against arithmetic folding. The Basys 3 wrapper passed all eight packet profiles, output-field checks, debounce/held-button behavior, automatic replay, reset and a complete display scan.

The six-packet demo passed 105 clocks with exactly two transfers: BUY AAPL at 99.0000 (sequence 1) and SELL AAPL at 111.0000 (sequence 3). Final counts: 6 received, 4 accepted, 2 rejected, 1 symbol miss, 1 HOLD, 2 enqueued and 0 dropped. See `../examples/` for the actual PCAP, waveform and event log.

## Latency and synthesis

The scoreboard-verified delay from final input sampling to first output-valid, when the FIFO is empty and the tick triggers an action, is **4 cycles** in every matrix case. The minimum first-input-to-valid delay is **12 cycles** for an uninterrupted supported frame. At a target 6.4 ns period these correspond to 25.6 ns and 76.8 ns; the earliest first-input-to-output-handshake is 13 cycles / 83.2 ns. Queue waiting and source gaps increase latency.

Independent slang 11.0.0 frontend check: **zero RTL diagnostics**.

Generic Yosys synthesis (`synth -noabc`, `check -assert`): **zero structural problems**, **zero inferred latches**, **14,436 generic bit-level cells**, including **4,867 flip-flop cells**. This is a technology-independent representation before technology mapping; these counts are not Xilinx LUT/FF utilization estimates. Small memories have been expanded into registers and multiplexers. The unused adapter is removed from the `tick_to_trade` hierarchy.

The full tool identification, command log and cell breakdown are preserved in `synthesis.txt` and `synthesis-stat.json`.

## Pending evidence

The college board is confirmed as Basys 3, part xc7a35tcpg236-1. Executed Vivado timing/resource results and bitstream status are recorded separately in `fpga-validation.md`; consult that report instead of treating the target clock as proven. The physical board demo, external MAC/PHY integration and sustained 10G traffic measurements are pending. The GitHub workflow has been prepared but has not run remotely.
