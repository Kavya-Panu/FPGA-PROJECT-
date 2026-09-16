#!/usr/bin/env python3
"""Run the supported end-to-end parameter matrix and consecutive-cycle FIFO tests."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
iverilog = os.environ.get("IVERILOG","iverilog")
vvp = os.environ.get("VVP","vvp")
for size,depth,seed,frames in [(8,16,20260914,2000),(1,1,7,1200),(3,3,99,1200)]:
    subprocess.run([sys.executable,str(ROOT/"tests/run.py"),"--table-size",str(size),
        "--fifo-depth",str(depth),"--seed",str(seed),"--random",str(frames),
        "--iverilog",iverilog,"--vvp",vvp],check=True)
build=ROOT/"build"; build.mkdir(exist_ok=True)
for depth in [1,3,16]:
    executable=build/f"fifo-{depth}.vvp"
    subprocess.run([iverilog,"-g2012","-Wall","-s","tb_event_fifo",
        f"-Ptb_event_fifo.DEPTH={depth}","-o",str(executable),
        str(ROOT/"rtl/event_fifo.sv"),str(ROOT/"tests/tb_event_fifo.sv")],check=True)
    result=subprocess.run([vvp,str(executable)],check=True,text=True,capture_output=True)
    print(result.stdout.strip())
    (build/f"fifo-{depth}.log").write_text(result.stdout+result.stderr)
    if "PASS FIFO unit" not in result.stdout:
        raise SystemExit("FIFO test failed to report PASS")
executable=build/"mac-adapter.vvp"
subprocess.run([iverilog,"-g2012","-Wall","-s","tb_mac_rx_adapter","-o",str(executable),
    str(ROOT/"rtl/mac_rx_adapter.sv"),str(ROOT/"tests/tb_mac_rx_adapter.sv")],check=True)
result=subprocess.run([vvp,str(executable)],check=True,text=True,capture_output=True)
print(result.stdout.strip())
(build/"mac-adapter.log").write_text(result.stdout+result.stderr)
if "PASS MAC adapter" not in result.stdout:
    raise SystemExit("MAC adapter test failed to report PASS")
executable=build/"checksum.vvp"
subprocess.run([iverilog,"-g2012","-Wall","-s","tb_checksum","-o",str(executable),
    str(ROOT/"rtl/market_data_parser.sv"),str(ROOT/"tests/tb_checksum.sv")],check=True)
result=subprocess.run([vvp,str(executable)],check=True,text=True,capture_output=True)
print(result.stdout.strip())
(build/"checksum.log").write_text(result.stdout+result.stderr)
if "PASS checksum identity" not in result.stdout:
    raise SystemExit("Checksum identity test failed to report PASS")
subprocess.run([sys.executable,str(ROOT/"boards/basys3/test_demo.py")],check=True)
