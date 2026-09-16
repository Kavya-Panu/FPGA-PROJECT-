"""Save actual Vivado results. Never turn a script exit into a timing-pass claim."""
from pathlib import Path
import hashlib
import json
import re
import shutil

ROOT=Path(__file__).resolve().parents[1]
def metrics(folder):
    text=(folder/"timing_summary.rpt").read_text()
    section=text.split("| Design Timing Summary",1)[1]
    row=next(line.split() for line in section.splitlines() if re.match(r"^\s*-?\d+\.\d+\s+-?\d+\.\d+",line))
    utilization=(folder/"utilization.rpt").read_text()
    def count(label):
        match=re.search(r"\|\s*"+re.escape(label)+r"\s*\|\s*(\d+)\s*\|",utilization)
        return int(match.group(1)) if match else None
    return {"wns_ns":float(row[0]),"tns_ns":float(row[1]),"setup_failing_endpoints":int(row[2]),
            "whs_ns":float(row[4]),"ths_ns":float(row[5]),"hold_failing_endpoints":int(row[6]),
            "wpws_ns":float(row[8]),"slice_luts":count("Slice LUTs"),"slice_registers":count("Slice Registers")}

results={}
for kind,directory in [("full_core_156mhz","vivado_ooc"),("basys3_100mhz","basys3")]:
    src=ROOT/"build"/directory
    dest=ROOT/"reports"/directory
    dest.mkdir(parents=True,exist_ok=True)
    result=metrics(src)
    result["timing_pass"]=result["wns_ns"]>=0 and result["whs_ns"]>=0 and result["wpws_ns"]>=0
    result["part"]="xc7a35tcpg236-1"
    result["tool"]="Vivado 2025.1"
    result["period_ns"]=6.4 if kind=="full_core_156mhz" else 10.0
    for path in src.glob("*.rpt"):
        # Retain exact measurements and tool metadata while making paths portable.
        content=path.read_text().replace(str(ROOT).replace("\\","/"),".").replace(str(ROOT),".")
        (dest/path.name).write_text(content)
    results[kind]=result

board=results["basys3_100mhz"]
bit=ROOT/"build/basys3/basys3_demo.bit"
if not board["timing_pass"] or not bit.exists():
    raise SystemExit("No timing-passing board bitstream to publish")
prebuilt=ROOT/"boards/basys3/prebuilt"
prebuilt.mkdir(exist_ok=True)
shutil.copyfile(bit,prebuilt/bit.name)
board["bitstream_sha256"]=hashlib.sha256(bit.read_bytes()).hexdigest()
board["bitstream_bytes"]=bit.stat().st_size
sources={}
for subdir in ["rtl","boards/basys3","scripts","constraints"]:
    for path in sorted((ROOT/subdir).rglob("*")):
        if path.is_file() and path.suffix in {".sv",".tcl",".xdc",".py"}:
            sources[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
results["source_sha256"]=sources
(ROOT/"reports/fpga-results.json").write_text(json.dumps(results,indent=2)+"\n")
core=results["full_core_156mhz"]
rows="\n".join(f"| {name} | {r['period_ns']} | {r['wns_ns']:.3f} | {r['whs_ns']:.3f} | "
               f"{r['slice_luts']:,} | {r['slice_registers']:,} | {'PASS' if r['timing_pass'] else 'NOT MET'} |"
               for name,r in [("Full core OOC",core),("Basys 3 demo",board)])
report=f"""# FPGA implementation results

Both builds ran locally in **Vivado 2025.1** for **xc7a35tcpg236-1**, the FPGA on the confirmed Basys 3. The FPGA itself has not been programmed or observed by the assistant.

| Build | Period (ns) | Worst setup slack (ns) | Worst hold slack (ns) | Slice LUTs | Registers | Timing |
|---|---:|---:|---:|---:|---:|---|
{rows}

Positive slack meets the stated timing check. Read both setup and hold columns. Raw timing, constraint, utilization and DRC reports are saved in `vivado_ooc/` and `basys3/`; the latter also includes a CDC report. Machine-readable results and source hashes are in `fpga-results.json`.

## Basys 3 board demo

A **100 MHz** programming file was successfully generated only after routed setup and hold checks passed. It is supplied as `../boards/basys3/prebuilt/basys3_demo.bit` ({board['bitstream_bytes']:,} bytes).

SHA256: `{board['bitstream_sha256']}`.

The design uses the Basys 3 oscillator and documented physical pins. All switch and button inputs feed explicit synchronizers; switches and the send button also pass through a debounce stage. Those asynchronous input paths are excepted from external clock timing. All internal register-to-register paths retain 100 MHz setup and hold checks. LED and display ports have no external capture clock: their registered outputs instead have a 20 ns datapath-only settling limit, with no external hold requirement. The exceptions terminate only at the human-visible indicator ports. See the [AMD constraint semantics](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/set_max_delay) and the shipped XDC. The design uses internal packet ROM data, one fixed AAPL row and an always-ready consumer, so some unused general-purpose logic is optimized away.

Follow `../boards/basys3/README.md` to program and exercise it. Physical button/LED tests and traffic observation are still pending. No physical 10G network claim follows from this result.

## Full-core 156.25 MHz experiment

The full configurable core was separately synthesized, placed and routed out of context with the 6.4 ns example constraints. Overall timing result: **{'PASS' if core['timing_pass'] else 'NOT MET'}**. Its boundary inputs/outputs have no physical partition-pin placement; Vivado reports partial-routing limitations for those OOC boundaries, so input/output timing is not a substitute for a real MAC/consumer integration.

The general eight-entry core's resource counts above include all runtime configuration inputs. They should not be compared directly with the fixed-row demo as though both were identical configurations. The optimized checksum acceptance check preserves the four-cycle end-of-packet to event-valid latency and passed the full packet regression plus 262,148 arithmetic-equivalence cases.

The project still needs a suitable Ethernet MAC/PHY board, actual integration constraints and real packet measurements to establish a 10G hardware implementation. The Basys 3 demonstration provides a practical hardware path for learning and interviews without purchasing a different board now.
"""
(ROOT/"reports/fpga-validation.md").write_text(report)
print(json.dumps({k:v for k,v in results.items() if k!="source_sha256"},indent=2))
