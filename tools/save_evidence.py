#!/usr/bin/env python3
"""Refresh the small checked-in evidence snapshot after all local checks pass."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
REPORTS = ROOT / "reports"
EXAMPLES = ROOT / "examples"
REPORTS.mkdir(exist_ok=True)
EXAMPLES.mkdir(exist_ok=True)
rtl_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/"rtl").glob("*.sv"))}
cases = ["t8-f16-s20260914", "t1-f1-s7", "t3-f3-s99"]
rows = []
for case in cases:
    result = json.loads((BUILD/case/"results.json").read_text())
    if result["status"] != "PASS" or result["rtl_sha256"] != rtl_hashes:
        raise SystemExit(f"Missing/stale passing results for {case}")
    rows.append(result)
    shutil.copyfile(BUILD/case/"results.json",REPORTS/f"{case}.json")
    # Preserve logs while removing machine-specific project paths.
    log=(BUILD/case/"simulation.log").read_text().replace(str(ROOT),".")
    (REPORTS/f"{case}.txt").write_text(log)

demo=json.loads((BUILD/"demo/results.json").read_text())
if demo["status"] != "PASS" or demo["rtl_sha256"] != rtl_hashes:
    raise SystemExit("Demo evidence is stale")
for source,destination in [("demo.pcap","demo.pcap"),("events.csv","demo-events.csv"),
                           ("waves.vcd","demo.vcd"),("results.json","demo-results.json")]:
    shutil.copyfile(BUILD/"demo"/source,EXAMPLES/destination)

unit_logs=[]
for depth in [1,3,16]:
    content=(BUILD/f"fifo-{depth}.log").read_text()
    if f"PASS FIFO unit cycles=12000 depth={depth}" not in content:
        raise SystemExit(f"FIFO unit check depth {depth} did not pass")
    unit_logs.append(content.replace(str(ROOT),"."))
adapter=(BUILD/"mac-adapter.log").read_text()
if "PASS MAC adapter" not in adapter:
    raise SystemExit("Adapter unit check did not pass")
unit_logs.append(adapter.replace(str(ROOT),"."))
for log_name, marker in [("checksum.log","PASS checksum identity"),("basys3-test.log","PASS Basys 3")]:
    content=(BUILD/log_name).read_text()
    if marker not in content:
        raise SystemExit(f"Missing passing check: {log_name}")
    unit_logs.append(content.replace(str(ROOT),"."))
(REPORTS/"unit-tests.txt").write_text("\n".join(unit_logs))
lint=(BUILD/"lint.log").read_text(encoding="utf-8-sig")
if "0 RTL diagnostics" not in lint:
    raise SystemExit("Independent lint did not pass")
(REPORTS/"lint.txt").write_text(lint)
synthesis=(BUILD/"synthesis.log").read_text()
if "Found and reported 0 problems." not in synthesis or "ERROR:" in synthesis:
    raise SystemExit("Synthesis did not pass")
shutil.copyfile(BUILD/"synthesis-stat.json",REPORTS/"synthesis-stat.json")
# Full synthesis log contains useful exact command/tool provenance.
(REPORTS/"synthesis.txt").write_text(synthesis)
stats=json.loads((BUILD/"synthesis-stat.json").read_text())
cells=stats["design"]["num_cells_by_type"]
if any("LATCH" in name.upper() for name in cells):
    raise SystemExit("Unexpected inferred latch")
manifest={}
for folder in ["rtl","tests","tools","scripts","constraints","boards"]:
    for path in sorted((ROOT/folder).rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            manifest[str(path.relative_to(ROOT)).replace("\\","/")]=hashlib.sha256(path.read_bytes()).hexdigest()
(REPORTS/"source-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
table="\n".join(f"| {r['table_size']} | {r['fifo_depth']} | {r['seed']} | {r['cycles_checked']:,} | "
                f"{r['frames_completed']:,} | {r['events_transferred']:,} | PASS |" for r in rows)
cycles=sum(r["cycles_checked"] for r in rows)
frames=sum(r["frames_completed"] for r in rows)
transfers=sum(r["events_transferred"] for r in rows)
ff=sum(count for name,count in cells.items() if "DFF" in name)
report=f"""# Executed validation snapshot

Local functional simulation and generic synthesis. Source hashes in the JSON files identify the RTL checked; `source-manifest.json` also fingerprints the test and build sources. Reproduce with `python tools/check.py`, `python tests/run.py --demo --waves`, independent lint, and `scripts/synth.ys`. Refresh this snapshot with `python tools/save_evidence.py` after those checks pass.

## End-to-end regression

| Table entries | FIFO depth | Seed | Cycles checked | Completed frames | Transferred events | Result |
|---:|---:|---:|---:|---:|---:|---|
{table}

Total: **{cycles:,} clock cycles**, **{frames:,} completed frames**, and **{transfers:,} output handshakes**. Every post-edge output field, valid bit, FIFO level, configuration-error flag and public counter is compared with an independent Python reference. The actual RTL handshake log is separately checked for values and ordering. All input cycles are checked for permanently asserted RX ready.

Simulator: `{rows[0]['simulator']}`. Python 3.12.14 was used for the local run. Seeds and per-scenario stimulus counts are saved in the result JSON files. These are functional test counts, not code coverage percentages or a formal proof. Deliberate resets can discard candidates/events; lifetime counter totals across those resets do not obey drained-pipeline equalities.

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

Generic Yosys synthesis (`synth -noabc`, `check -assert`): **zero structural problems**, **zero inferred latches**, **{stats['design']['num_cells']:,} generic bit-level cells**, including **{ff:,} flip-flop cells**. This is a technology-independent representation before technology mapping; these counts are not Xilinx LUT/FF utilization estimates. Small memories have been expanded into registers and multiplexers. The unused adapter is removed from the `tick_to_trade` hierarchy.

The full tool identification, command log and cell breakdown are preserved in `synthesis.txt` and `synthesis-stat.json`.

## Pending evidence

The college board is confirmed as Basys 3, part xc7a35tcpg236-1. Executed Vivado timing/resource results and bitstream status are recorded separately in `fpga-validation.md`; consult that report instead of treating the target clock as proven. The physical board demo, external MAC/PHY integration and sustained 10G traffic measurements are pending. The GitHub workflow has been prepared but has not run remotely.
"""
(REPORTS/"validation.md").write_text(report,encoding="utf-8")
print(f"Saved verified evidence: {cycles:,} end-to-end cycles; {frames:,} frames; {transfers:,} transfers.")
