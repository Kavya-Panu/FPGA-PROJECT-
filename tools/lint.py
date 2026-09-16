#!/usr/bin/env python3
"""Optional independent SystemVerilog front-end check: pip install pyslang==11.0.0."""
from pathlib import Path
import sys
import pyslang

root=Path(__file__).resolve().parents[1]
compilation=pyslang.ast.Compilation()
sources=sorted((root/"rtl").glob("*.sv"))
sources += [root/"boards/basys3/basys3_demo_top.sv",root/"boards/basys3/basys3_packet_rom.sv"]
for source in sources:
    compilation.addSyntaxTree(pyslang.syntax.SyntaxTree.fromFile(str(source)))
diagnostics=compilation.getAllDiagnostics()
print(pyslang.DiagnosticEngine.reportAll(compilation.sourceManager,diagnostics))
print(f"slang {pyslang.__version__}: {len(diagnostics)} RTL diagnostics")
sys.exit(bool(len(diagnostics)))
