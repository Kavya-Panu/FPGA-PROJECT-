# Primary references and tool provenance

Protocol and integration references checked on 2026-09-14. The mock tick format, action policy and fixed packet-profile restrictions are project-specific.

- [RFC 791 — Internet Protocol](https://www.rfc-editor.org/rfc/rfc791): IPv4 fields, header checksum and fragmentation.
- [RFC 768 — User Datagram Protocol](https://www.rfc-editor.org/rfc/rfc768): UDP header, length, pseudoheader checksum and omitted-checksum convention.
- [AMD/Xilinx PG072 — 10G Ethernet MAC v15.1](https://docs.amd.com/api/khub/documents/y6kqi3sEJLyLWhNGcTzgSA/content): 64-bit MAC receive interface, end-of-frame status, FCS handling and 156.25 MHz clock. This specific guide uses TUSER=1 for a good final frame.
- [AMD UG835 — check_timing](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/check_timing): inspection of timing constraints.
- [AMD UG835 — set_max_delay](https://docs.amd.com/r/2025.1-English/ug835-vivado-tcl-commands/set_max_delay): datapath-only delay limits and their hold-check semantics, used only for the Basys 3 indicator outputs.
- [AMD UG903 — Non-Project Flows](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Non-Project-Flows): scripted constraints and synthesis flow. Use the version matching the college tool installation.
- [Icarus Verilog installation guide](https://steveicarus.github.io/iverilog/usage/installation.html): simulator installation and sources.
- [Icarus Verilog for Windows package maintainer](https://bleyer.org/icarus/): the local validation used the v12 Windows package. Exact reported compiler version is saved in result JSON.
- [Yosys download instructions](https://yosyshq.net/yosys/download.html): native synthesis tools and OSS CAD Suite.
- [YoWASP Yosys packaging](https://github.com/YoWASP/yosys): WebAssembly packaging used for the local generic synthesis run. Exact version appears in the synthesis log.
- [slang SystemVerilog compiler](https://github.com/MikePopoloski/slang): independent SystemVerilog frontend, used through `pyslang` 11.0.0 for lint.

- [Digilent Basys 3 master constraints](https://github.com/Digilent/digilent-xdc/blob/master/Basys-3-Master.xdc): clock, switches, buttons, LEDs and display pin assignments.
- [Basys 3 reference manual](https://www.amd.com/content/dam/amd/en/documents/university/aup-boards/XUPBasys3/documentation/Basys3_rm_8_22_2014.pdf): board identification and peripherals.
- [AMD Artix-7 family](https://www.amd.com/en/products/adaptive-socs-and-fpgas/fpga/artix-7.html) and [10GBASE-R PCS/PMA](https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/10gbase-r.html): Artix-7 GTP limits and the 10.3125 Gb/s serial rate required by a direct 10GBASE-R link. The Basys 3 demo bypasses the external link entirely.

No vendor MAC source, licensed IP core, or tool executable is included in the project archive. A project-specific Basys 3 programming bitstream may be included with its build evidence. The CI workflow is provided for use after creating a GitHub repository; it has not been executed on GitHub during this local build.
