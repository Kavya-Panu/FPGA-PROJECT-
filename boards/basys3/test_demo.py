"""Run a real RTL simulation of the board controls and demo datapath."""
import os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
build=ROOT/"build"; build.mkdir(exist_ok=True)
iverilog=os.environ.get("IVERILOG","iverilog")
vvp=os.environ.get("VVP","vvp")
sources=sorted((ROOT/"rtl").glob("*.sv"))+sorted((ROOT/"boards/basys3").glob("*.sv"))
executable=build/"basys3-test.vvp"
subprocess.run([iverilog,"-g2012","-Wall","-s","tb_basys3_demo","-o",str(executable),
                *map(str,sources)],check=True)
r=subprocess.run([vvp,str(executable)],check=True,capture_output=True,text=True,timeout=120)
print(r.stdout.strip())
(build/"basys3-test.log").write_text(r.stdout+r.stderr)
if "PASS Basys 3" not in r.stdout: raise SystemExit("No pass result")
