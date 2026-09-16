# Learn the finished design and present it

Start by reproducing the six-packet demo. It gives you a small, understandable result before you study the whole test suite. Keep `examples/demo-events.csv` next to the waveform while reading the RTL.

## Suggested learning sequence

| Step | Read / change | Evidence you understand it |
|---|---|---|
| 1 | `tools/packets.py`, packet layout in `architecture.md` | Decode one frame by hand; locate port, symbol, price and quantity |
| 2 | `market_data_parser.sv` | Explain why the first byte is in bits 7:0 but integer fields are network order |
| 3 | Parser checksum and candidate registers | Predict what happens when the final byte or MAC error flag changes |
| 4 | `symbol_match_engine.sv` | Explain parallel comparison, inclusive thresholds and lowest-index priority |
| 5 | `event_fifo.sv` | Trace full+pop+push, stall stability and reset behavior |
| 6 | `tests/run.py` and the SV testbench | Add a new malformed case, break the RTL deliberately, observe a failing test, restore it |
| 7 | Saved Xilinx OOC and Basys 3 reports | Identify critical path, slack, resource use and constraint boundaries |
| 8 | Board demo | Show input frames, output events, counters and measured latency |

Do not memorize the whole codebase. Be able to trace one BUY from bytes to output, one corrupt frame to rejection, and one full-queue event to the drop counter.

## Five-minute demo

1. Explain the input/output contract: Ethernet frame in, small decision event out.
2. Show the pipeline diagram and state why it processes eight bytes per clock.
3. Run the demo. AAPL 99.0000 produces BUY; 105.0000 produces HOLD; 111.0000 produces SELL. Unknown/wrong-port/corrupt packets do not create events.
4. Open the VCD in GTKWave and show last input beat, validated tick, compare stage, decision stage and output valid.
5. Run the regression or show the saved evidence with the source hashes. Explain what has and has not been measured on FPGA.

Useful wave signals are `dut.parser.beat`, `dut.parser.candidate_valid`, `dut.tick_valid`, `dut.matcher.match_valid`, `dut.event_valid`, `m_event_valid`, `m_event_ready`, and `m_event_sequence`. Select the AAPL BUY packet and count rising edges. The earliest handshake is one edge later than first output valid.

## Design questions you should be able to answer

**Why wait for the final beat?** The MAC may report bad FCS only at frame end. A price match before that point is provisional.

**Why use a fixed IPv4 header?** It gives constant offsets and a compact datapath. IP options and VLAN add parsing/alignment work; they should be added with explicit tests and timing measurements.

**How is the symbol lookup parallel?** Every table row has concurrent equality and threshold comparators. Registers capture their results, then a small priority network chooses the lowest matching row. A serial memory search would have different latency and scaling.

**Why not block the receive stream when the event queue fills?** A MAC receive path may not support indefinite backpressure. This design keeps parsing and counts dropped newest events. Lossless operation requires a bounded stall assumption or a larger system policy.

**Why is UDP checksum zero accepted?** IPv4 UDP permits an omitted checksum. A nonzero checksum is verified; the Ethernet MAC still provides frame integrity status. This does not authenticate a feed.

**What does 10G mean here?** The target interface is 64 bits at 156.25 MHz. Functional simulations show no parser-inserted stalls, but FPGA route timing and board traffic tests are still needed to establish physical throughput.

**What does the sequence field do?** It passes through to output. Duplicate/stale suppression and feed recovery are future extensions; UDP itself does not provide them.

**Is this a financial matching engine?** It is a parallel symbol and price-threshold engine. It does not match orders, build an order book, or transmit trades.

## Portfolio wording

Once you can reproduce and explain the implementation, adapt these statements to your actual contribution:

> Implemented and verified a SystemVerilog Ethernet/IPv4/UDP market-data parser with parallel symbol lookup, configurable price thresholds and buffered decision output. Built an independent Python reference model and cycle-level regression covering malformed packets, checksum errors, output stalls and reset recovery.

> Demonstrated four-cycle latency from final input beat to output-valid in RTL simulation for an empty event queue, targeting a 64-bit, 156.25 MHz MAC interface. Validated synthesizability with Yosys; FPGA timing closure and board integration in progress.

After board testing, replace the second statement with the actual part, routed clock result, resource use and measured packet performance. Do not describe target frequency as achieved Fmax or simulated core delay as wire-to-wire latency.

## Highest-value next improvements

Run the completed Basys 3 build on the physical board first and record the LED/display demo. The board's test source uses internal packets, so describe it accurately. Then choose one substantial extension you can defend: sequence/session handling with tests for wrap and duplicates; a double-buffered configuration table; multi-tick packet parsing; or an AXI-Lite control interface with a proper clock-domain bridge. Record the before/after latency and resource tradeoff.
