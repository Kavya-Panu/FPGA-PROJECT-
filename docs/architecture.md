# Architecture and interface contract

## Scope

This core processes one mock tick per UDP datagram. It deliberately implements a fixed feed profile so that byte locations, validation, latency, and verification remain explicit. It is a symbol lookup and threshold engine, not an exchange order-matching engine.

Supported: Ethernet II type 0x0800; IPv4 version 4 and IHL 5; no fragmentation; nonzero TTL; UDP protocol 17; configured destination port; one 24-byte tick; total frame length 66 bytes excluding FCS. DF may be clear or set. IPv4 UDP checksum zero is accepted as omitted; every nonzero UDP checksum is validated, including the pseudoheader. A computed-zero checksum encoded as 0xffff is tested.

Rejected: VLAN, IPv6, IPv4 options, fragments, malformed lengths, unsupported tick fields, zero quantity, invalid byte enables, MAC errors, truncated frames, and extra bytes after the tick. Other protocols and wrong ports contribute to the aggregate rejected counter. Ethernet DA/SA and IP address filtering are left to integration; this core alone accepts any addresses satisfying the packet checks.

The protocol/checksum rules follow [RFC 791](https://www.rfc-editor.org/rfc/rfc791) and [RFC 768](https://www.rfc-editor.org/rfc/rfc768). The extra fixed-format restrictions above are application choices.

## Input stream

All logic uses rising edges of `clk`. `rst` is synchronous, active high. `s_axis_tready` is permanently high. Input is discarded during reset. Restart the upstream MAC at a frame boundary when releasing reset; this stream has no explicit start-of-packet signal.

`s_axis_tdata[7:0]` carries the earliest byte. Byte lane `i` corresponds to `tkeep[i]`. Every nonfinal beat has `tkeep=0xff`; the ninth and final beat of a supported frame has `tkeep=0x03`. `tvalid=0` cycles are ignored completely and may occur inside a frame. Data and status must meet the normal clocked interface timing.

The core's `s_axis_tuser=1` means the frame is bad. A bad flag on any valid beat is sticky for that frame. Do not directly connect a good-frame flag to this port. The [MAC adapter](../rtl/mac_rx_adapter.sv) handles both conventions; see the board guide.

There is no byte compaction or arbitrary alignment shifter. SOP is the first valid beat after reset or the previous valid TLAST. The beat counter saturates at 15; an oversized frame is drained until TLAST without wrapping into a new apparent header. If TLAST never arrives, only reset or a later TLAST can resynchronize it. The core cannot infer a new packet boundary from a continuous malformed stream.

## Mock tick, network byte order

Price is an unsigned 32-bit integer in units of 0.0001. A price of 1,000,000 means 100.0000. Quantity is an unsigned nonzero 32-bit integer. A symbol is exactly eight bytes, conventionally uppercase ASCII padded on the right with spaces. The RTL compares all eight bytes as opaque bits.

| Payload offset | Frame offset | Bytes | Field | Value/meaning |
|---:|---:|---:|---|---|
| 0 | 42 | 2 | Magic | `0x544b` (TK) |
| 2 | 44 | 1 | Version | 1 |
| 3 | 45 | 1 | Message type | 1 (tick) |
| 4 | 46 | 4 | Sequence | Passed to output |
| 8 | 50 | 8 | Symbol | e.g. `AAPL` plus four spaces |
| 16 | 58 | 4 | Price | Unsigned fixed point |
| 20 | 62 | 4 | Quantity | Must be nonzero |

UDP length is 32 (8 + 24); IP total length is 52 (20 + 32). Ethernet header length is 14. Preamble, SFD and FCS must be stripped by the MAC. This frame needs no Ethernet minimum-length padding. Application sequence numbers are metadata only: duplicate, stale and out-of-order ticks are not suppressed in this version.

## Word-indexed parser state machine

| Beat | Frame bytes | Work |
|---:|---|---|
| 0 | 0–7 | DA/SA data; initialize frame position |
| 1 | 8–15 | EtherType, IPv4 version/IHL; start IP checksum |
| 2 | 16–23 | IP length, fragmentation flags, TTL and protocol |
| 3 | 24–31 | IP checksum and addresses; UDP pseudoheader sum |
| 4 | 32–39 | Finish IP address, UDP ports and UDP length |
| 5 | 40–47 | UDP checksum, tick magic/version/type, sequence high |
| 6 | 48–55 | Sequence low, first six symbol bytes |
| 7 | 56–63 | Last two symbol bytes, price, quantity high |
| 8 | 64–65 | Quantity low; capture end-of-frame candidate |

Word sums use network-order pairs and a balanced four-word addition. IP and UDP sums accumulate while the frame streams; the full frame is never buffered. The final candidate registers isolate accumulation from the validation/commit stage. The fixed profile needs only a 20-bit IP accumulator (at most 10 × 65,535) and a 21-bit UDP accumulator (at most 20 × 65,535 + 49). Saturating frame position prevents an oversized frame from repeatedly adding words; these bounds also apply to rejected frames. Explicit widths remove unreachable high carry-chain bits.

Checksum acceptance avoids a chain of end-around-carry additions. For a 32-bit sum, folding to 0xffff occurs when the 16-bit halves sum to 0xffff or 0x1fffe. This is equivalent to complementary halves, or the all-ones 32-bit value. An XOR/reduction check implements that identity. A dedicated RTL test compares it against arithmetic folding for 262,148 cases, including all complementary pairs, adjacent values, random sums, zero and all ones. Packet acceptance and the four-cycle latency are unchanged.

## Pipeline timing

Let N be the rising edge accepting the last packet beat:

| Edge | Result after this edge |
|---|---|
| N | Candidate fields, final status and checksum sums captured |
| N+1 | Validated tick asserted, or rejected counter incremented |
| N+2 | All enabled symbol and threshold comparisons captured |
| N+3 | Lowest matching slot selected; event or miss/HOLD counted |
| N+4 | Event enqueued; output valid appears if queue was empty |
| N+5 | Earliest output handshake when ready is continuously high |

Validation waits for TLAST because the MAC can discover an FCS error at the end of a frame. A speculative action at byte 63 could act on a frame later reported corrupt. This design commits only after final status is available.

Adjacent frames need no parser idle cycles. The testbench drives 1,024 supported frames consecutively in each matrix run. Each uses nine beats; its final beat contains two valid bytes. At 156.25 MHz that source stress pattern is 17.36 million frames/second internally. Actual wire throughput also includes preamble, FCS and inter-frame gap, so the source stress rate is not a physical network measurement.

## Table configuration and matching

`TABLE_SIZE` defaults to 8; tested values are 1, 3 and 8. Keep derived index widths at their defaults. Table rows reset disabled. Drive `cfg_we=1` for one clock with index, enable, 64-bit symbol, buy and sell thresholds. All configuration inputs are synchronous to `clk`.

An enabled row requires buy < sell. Invalid thresholds or an out-of-range representable index leave the row unchanged and pulse `cfg_error` for one clock. A disable write permits any threshold values. A write and lookup on the same edge use the old row for that lookup. A write before the lookup edge affects the in-flight packet. The update is atomic for one row; there is no atomic bank-wide table update.

All rows compare symbol, buy threshold and sell threshold concurrently. A register separates comparisons from a small priority selector. If duplicate enabled symbols exist, the lowest row index wins, including when that row says HOLD and a later row would trade. This behavior is explicitly tested.

## Output and overflow

`m_event_action` is 1 for BUY, 2 for SELL. Action 0 never appears with valid high. Index, symbol, sequence, price and quantity accompany each event. A transfer occurs only on a rising edge with both valid and ready high. All output fields and valid stay stable during stalls, except when reset flushes the queue. When invalid, output data is zero.

The FIFO defaults to 16 entries. Depths 1, 3 and 16 are tested, including simultaneous push and pop while full. The newest event is discarded if the queue is full and no dequeue occurs on that edge. Old events remain ordered; `events_dropped` increments. RX processing continues. A FIFO cannot guarantee lossless processing under indefinitely stalled consumption.

There is no empty-FIFO combinational bypass. Enqueue becomes visible after its edge; earliest consumption occurs at the next edge. This makes output timing and the latency claim unambiguous.

## Counters and reset

All counters are unsigned 32-bit, wrap modulo 2^32, and reset to zero. Counters belong to the RX domain; software reads need a coherent snapshot/CDC mechanism in a board wrapper.

| Counter | Increment condition |
|---|---|
| `rx_frames` | Valid TLAST received, regardless of acceptance |
| `accepted_frames` | Candidate passes packet and tick validation |
| `rejected_frames` | Candidate fails validation or is unsupported |
| `symbol_misses` | Valid tick has no enabled matching symbol |
| `holds` | Lowest matching row has buy < price < sell |
| `events_enqueued` | Action enters FIFO |
| `events_dropped` | Action arrives at full FIFO with no simultaneous pop |

After the pipeline drains, and absent reset/wrap: received = accepted + rejected; accepted = misses + holds + enqueued + dropped. During pipeline activity these equalities can lag. Reset discards in-flight candidates, queued events and table configuration; it does not count discarded state as overflow.

## Deliberate limits and follow-on work

There is no real exchange protocol, packet authentication, redundant-feed arbitration, sequence recovery, order transmission, position accounting or risk management. Add sequence/session tracking, address/feed filters and operational controls before considering any realistic trading workflow. The current project is intended to demonstrate RTL packet processing and verification.

The next engineering work is board-specific integration and routed timing closure. Further feed features should each add packet tests and documented latency/resource changes: VLAN support, variable IP header lengths, multiple ticks per datagram, atomic table banks, an AXI-Lite control wrapper, or BRAM-based scaling.
