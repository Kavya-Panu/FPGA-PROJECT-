# Six-packet demonstration

The files in this folder are copied from an actual passing RTL demo run.

| Sequence | Input | Expected outcome |
|---:|---|---|
| 1 | AAPL, 99.0000 | BUY |
| 2 | AAPL, 105.0000 | HOLD, no event |
| 3 | AAPL, 111.0000 | SELL |
| 4 | UNKNOWN!, 100.0000 | Symbol miss, no event |
| 5 | AAPL on UDP port 4321 | Rejected, no event |
| 6 | AAPL with corrupted quantity byte and unrepaired UDP checksum | Rejected, no event |

All noncorrupt example quantities are 100. Default thresholds are buy=100.0000 and sell=110.0000. Expected counters after drain: received 6, accepted 4, rejected 2, misses 1, holds 1, enqueued 2, dropped 0.

Open `demo.pcap` in Wireshark for Ethernet/IP/UDP fields. The tick is a custom format; use `docs/architecture.md` for its payload. The capture excludes FCS and uses illustrative timestamps.

Open `demo.vcd` in GTKWave for the simulation. `demo-events.csv` contains actual RTL output handshakes. `demo-results.json` records the check result and RTL hashes. Regenerate with `python tests/run.py --demo --waves`; new files appear under `build/demo/`.
