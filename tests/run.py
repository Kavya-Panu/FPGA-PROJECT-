#!/usr/bin/env python3
"""Generate independent expected results, compile RTL, and check every clock edge."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict, deque
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from packets import make_frame, parse_frame, repair_checksums, write_pcap, checksum

SYMBOLS = [b"AAPL    ", b"MSFT    ", b"NVDA    ", b"AMZN    ",
           b"GOOG    ", b"META    ", b"AMD     ", b"INTC    "]
INPUT_NAMES = "rst valid last error keep data ready we index enable symbol buy sell".split()
COUNTERS = "rx accepted rejected misses holds enqueued dropped".split()


class Reference:
    def __init__(self, size, depth):
        self.size, self.depth = size, depth
        self.iw = max(1, (size-1).bit_length())
        self.lw = depth.bit_length()
        self.cycle = 0
        self.totals = Counter()
        self.transfers = []
        self.latencies = []
        self.reset()

    def reset(self):
        self.table = [None] * self.size
        self.queue = deque()
        self.schedule = defaultdict(list)
        self.stats = Counter()
        self.frame = bytearray()
        self.frame_bad = False
        self.frame_start = None

    def step(self, v):
        c = self.cycle
        cfg_error = 0
        if v["rst"]:
            self.reset()
        else:
            if self.queue and v["ready"]:
                event, eop, sop = self.queue.popleft()
                self.transfers.append((c, event))
            for kind, item in self.schedule.pop(c, []):
                if kind == "validate":
                    tick, eop, sop = item
                    key = "accepted" if tick else "rejected"
                    self.stats[key] += 1
                    self.totals[key] += 1
                    if tick:
                        self.schedule[c+1].append(("lookup", (tick, eop, sop)))
                elif kind == "lookup":
                    tick, eop, sop = item
                    match = next(((i, row) for i, row in enumerate(self.table)
                                  if row and row[0] == tick["symbol"]), None)
                    if match:
                        i, (_, buy, sell) = match
                        action = 1 if tick["price"] <= buy else 2 if tick["price"] >= sell else 0
                        event = (action, i, tick["symbol"], tick["sequence"], tick["price"], tick["quantity"])
                        self.schedule[c+1].append(("decision", (event, eop, sop)))
                    else:
                        self.schedule[c+1].append(("miss", None))
                elif kind == "miss":
                    self.stats["misses"] += 1; self.totals["misses"] += 1
                elif kind == "decision":
                    if item[0][0]:
                        self.schedule[c+1].append(("enqueue", item))
                    else:
                        self.stats["holds"] += 1; self.totals["holds"] += 1
                elif kind == "enqueue":
                    if len(self.queue) < self.depth:
                        was_empty = not self.queue
                        self.queue.append(item)
                        self.stats["enqueued"] += 1; self.totals["enqueued"] += 1
                        if was_empty:
                            self.latencies.append({"eop_to_valid_cycles": c-item[1],
                                                   "sop_to_valid_cycles": c-item[2]})
                    else:
                        self.stats["dropped"] += 1; self.totals["dropped"] += 1
            # Lookup above observes the old row on a simultaneous write.
            if v["we"]:
                if v["index"] >= self.size or (v["enable"] and v["buy"] >= v["sell"]):
                    cfg_error = 1; self.totals["cfg_errors"] += 1
                else:
                    self.table[v["index"]] = (v["symbol"], v["buy"], v["sell"]) if v["enable"] else None
            if v["valid"]:
                if self.frame_start is None:
                    self.frame_start = c
                keep = v["keep"]
                if (not v["last"] and keep != 255) or keep == 0 or keep & (keep+1):
                    self.frame_bad = True
                self.frame_bad |= bool(v["error"])
                data = v["data"].to_bytes(8, "little")
                self.frame.extend(data[i] for i in range(8) if keep & (1 << i))
                if v["last"]:
                    self.stats["rx"] += 1; self.totals["rx"] += 1
                    tick = None if self.frame_bad else parse_frame(bytes(self.frame))
                    self.schedule[c+1].append(("validate", (tick, c, self.frame_start)))
                    self.frame = bytearray(); self.frame_bad = False; self.frame_start = None
        event = self.queue[0][0] if self.queue else (0,)*6
        fields = [(cfg_error, 1), (bool(self.queue), 1)]
        fields += list(zip(event, [2,self.iw,64,32,32,32]))
        fields += [(len(self.queue), self.lw)]
        fields += [(self.stats[k] & 0xFFFFFFFF, 32) for k in COUNTERS]
        observed = 0
        for value, width in fields:
            observed = (observed << width) | int(value)
        self.cycle += 1
        return observed


class Stimulus:
    def __init__(self, stream, size, depth, seed):
        self.stream = stream
        self.ref = Reference(size, depth)
        self.rng = random.Random(seed)
        self.coverage = Counter()
        self.ready = 1
        self.sequence = 0

    def cycle(self, **kwargs):
        v = dict.fromkeys(INPUT_NAMES, 0)
        v["ready"] = self.ready
        v.update(kwargs)
        expected = self.ref.step(v)
        self.stream.write(" ".join(f"{v[k]:x}" for k in INPUT_NAMES) + f" {expected:x}\n")

    def idle(self, n=1, **kwargs):
        for _ in range(n):
            self.cycle(**kwargs)

    def configure(self, index=0, symbol=SYMBOLS[0], buy=1000000, sell=1100000, enable=1):
        self.cycle(we=1, index=index, symbol=int.from_bytes(symbol, "big"), buy=buy, sell=sell, enable=enable)

    def configure_all(self):
        for i in range(self.ref.size):
            self.configure(i, SYMBOLS[i % len(SYMBOLS)])

    def frame(self, data=None, tag="valid", gap=False, keep_override=None, error_at=None, **kwargs):
        self.sequence += 1
        data = make_frame(sequence=self.sequence, **kwargs) if data is None else data
        self.coverage[tag] += 1
        for j, off in enumerate(range(0, len(data), 8)):
            if gap:
                self.idle(self.rng.randrange(3), data=self.rng.getrandbits(64), keep=0x55, last=1, error=1)
            chunk = data[off:off+8]
            keep = (1 << len(chunk))-1
            if keep_override and j in keep_override:
                keep = keep_override[j]
            self.cycle(valid=1, last=int(off+8 >= len(data)), error=int(error_at == j),
                       keep=keep, data=int.from_bytes(chunk.ljust(8, b"\xa5"), "little"))


def generate(path, size, depth, seed, random_frames):
    with path.open("w", encoding="ascii") as stream:
        s = Stimulus(stream, size, depth, seed)
        s.idle(3, rst=1)
        s.frame(tag="table_disabled")
        s.idle(8); s.configure_all()
        for price in [0, 999999, 1000000, 1000001, 1099999, 1100000, 1100001, 0xFFFFFFFF]:
            s.frame(price=price, tag="threshold_boundary")
        for i in range(size):
            s.frame(symbol=SYMBOLS[i % len(SYMBOLS)], tag="table_slot")
        s.frame(symbol=b"UNKNOWN!", tag="symbol_miss")
        s.frame(udp_checksum=False, tag="udp_checksum_omitted")
        s.frame(flags=0, tag="df_clear")
        s.frame(quantity=0xFFFFFFFF, tag="quantity_max")
        s.frame(quantity=0, tag="quantity_zero")
        s.frame(port=1235, tag="wrong_port")
        s.frame(gap=True, tag="valid_bubbles")
        # Deliberately create a computed-zero UDP checksum, encoded as ffff.
        zero = bytearray(make_frame(sequence=0xFFFF, udp_checksum=False))
        pseudo = bytes(zero[26:34]) + b"\0\x11\0\x20"
        zero[34:36] = b"\0\0"
        zero[34:36] = checksum(pseudo + bytes(zero[34:])).to_bytes(2,"big")
        zero[40:42] = b"\xff\xff"
        assert parse_frame(bytes(zero)) is not None
        s.frame(bytes(zero), tag="udp_checksum_ffff")
        mutations = [(12, b"\x86\xdd", "ipv6"), (12,b"\x81\x00","vlan"),
                     (14,b"\x46","ip_options"), (14,b"\x65","wrong_ip_version"),
                     (16,b"\0\x33","ip_length_short"), (16,b"\0\x35","ip_length_long"),
                     (20,b"\x20\0","more_fragments"), (20,b"\0\x01","fragment_offset"),
                     (20,b"\x80\0","reserved_flag"), (22,b"\0","ttl_zero"),
                     (23,b"\x06","tcp"), (38,b"\0\x1f","udp_length_short"),
                     (38,b"\0\x21","udp_length_long"), (42,b"XX","bad_magic"),
                     (44,b"\x02","bad_version"), (45,b"\x02","bad_type")]
        for offset, value, tag in mutations:
            data = bytearray(make_frame())
            data[offset:offset+len(value)] = value
            s.frame(repair_checksums(bytes(data)), tag=tag)
        for offset in [24, 26, 30, 40, 58, 65]:
            data = bytearray(make_frame()); data[offset] ^= 1
            s.frame(bytes(data), tag="checksum_corruption")
        # Every truncation boundary, all final keeps, and non-final keep holes.
        for length in range(1, 66):
            s.frame(make_frame()[:length], tag="truncated")
        for mask in range(256):
            s.frame(keep_override={8:mask}, tag="final_keep_exhaustive")
        for beat in range(8):
            for mask in [0, 1, 0x55, 0x7F, 0xFE]:
                s.frame(keep_override={beat:mask}, tag="nonfinal_keep_error")
        for beat in range(9):
            s.frame(error_at=beat, tag="mac_error_each_beat")
        for length in [67, 72, 128, 1514, 9000]:
            s.frame(make_frame()+bytes(length-66), tag="oversize_drain_recovery")
            s.frame(tag="after_oversize")
        # Configuration rejection preserves the old row.
        s.idle(8)
        s.configure(buy=1100000, sell=1000000); s.frame(tag="bad_config_preserves_row")
        s.configure(buy=1000000, sell=1000000); s.frame(tag="equal_config_rejected")
        if size < 1 << s.ref.iw:
            s.configure(index=size); s.frame(tag="index_out_of_range")
        if size > 1:
            s.configure(1, SYMBOLS[0], buy=2000000, sell=3000000)
            s.frame(price=1050000, tag="duplicate_lowest_index_hold")
            s.configure(0, enable=0); s.frame(price=1050000, tag="duplicate_disabled_low_slot")
        s.idle(8); s.configure_all()
        # A write exactly on the parallel lookup edge must use the old row.
        s.frame(price=1000000, tag="lookup_write_collision")
        s.idle(1)
        s.configure(buy=1, sell=2)
        s.frame(price=1000000, tag="lookup_write_new_value")
        s.idle(8); s.configure_all()
        # Fill, drop, keep stable while stalled, then full pop+push replacement.
        s.ready = 0
        for _ in range(depth+5):
            s.frame(tag="fifo_full_stall")
        s.idle(8)
        s.frame(tag="fifo_full_simultaneous_pop_push")
        s.idle(3)
        s.cycle(ready=1)
        s.idle(4)
        s.ready = 1; s.idle(depth+10)
        # Flush occupied FIFO and in-flight packet using synchronous reset.
        s.ready = 0
        s.frame(tag="reset_queued_event"); s.idle(8)
        raw = make_frame()
        for off in range(0,32,8):
            s.cycle(valid=1, keep=255, data=int.from_bytes(raw[off:off+8],"little"))
        s.idle(2, rst=1); s.ready=1
        s.configure_all(); s.frame(tag="reset_midpacket_recovery")
        s.idle(8)
        # Reset after EOP and at each pipeline boundary, including a queued event.
        for delay in range(5):
            s.ready=0
            s.frame(tag="reset_pipeline_stage")
            s.idle(delay); s.idle(1, rst=1)
            s.ready=1; s.configure_all()
            s.frame(tag="reset_pipeline_stage_recovery"); s.idle(8)
        # 1024 consecutive 66-byte frames, with no source idle clocks.
        for _ in range(1024):
            s.frame(tag="continuous_burst")
        s.idle(10)
        for _ in range(random_frames):
            s.ready = int(s.rng.random() > 0.3)
            price = s.rng.choice([0,999999,1000000,1050000,1100000,0xFFFFFFFF])
            data = make_frame(sequence=s.sequence+1, symbol=s.rng.choice(SYMBOLS+[b"UNKNOWN!"]),
                              price=price, quantity=s.rng.randrange(1,2**32),
                              udp_checksum=bool(s.rng.randrange(2)))
            mode = s.rng.randrange(8)
            kwargs = {}
            if mode == 0:
                b = bytearray(data); pos=s.rng.randrange(12,66); b[pos] ^= 1 << s.rng.randrange(8); data=bytes(b)
            elif mode == 1:
                data=data[:s.rng.randrange(1,66)]
            elif mode == 2:
                kwargs["error_at"] = s.rng.randrange(9)
            elif mode == 3:
                kwargs["keep_override"] = {s.rng.randrange(9):s.rng.randrange(256)}
            s.frame(data, gap=bool(s.rng.randrange(2)), tag="random_mixed", **kwargs)
            if s.rng.random() < 0.03:
                s.configure(s.rng.randrange(size), s.rng.choice(SYMBOLS),
                            buy=1000000, sell=1100000, enable=s.rng.randrange(2))
        s.ready=1; s.idle(depth+20)
        assert not s.ref.queue and not s.ref.schedule
        # Counters and in-flight validation are intentionally reset together.
        assert s.ref.stats["rx"] == s.ref.stats["accepted"] + s.ref.stats["rejected"]
        return s


def generate_demo(path, size, depth, seed):
    with path.open("w",encoding="ascii") as stream:
        s = Stimulus(stream,size,depth,seed)
        s.idle(3,rst=1); s.configure_all(); s.idle(2)
        frames = [make_frame(sequence=1,price=990000),
                  make_frame(sequence=2,price=1050000),
                  make_frame(sequence=3,price=1110000),
                  make_frame(sequence=4,symbol=b"UNKNOWN!"),
                  make_frame(sequence=5,port=4321)]
        damaged = bytearray(make_frame(sequence=6)); damaged[65] ^= 1
        frames.append(bytes(damaged))
        for frame in frames:
            s.frame(frame,tag="demo"); s.idle(3)
        s.idle(20)
        write_pcap(path.parent/"demo.pcap",frames)
        return s


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--seed", type=int, default=20260914)
    p.add_argument("--random", type=int, default=2000)
    p.add_argument("--table-size", type=int, default=8, choices=range(1,9))
    p.add_argument("--fifo-depth", type=int, default=16)
    p.add_argument("--iverilog", default=os.environ.get("IVERILOG", "iverilog"))
    p.add_argument("--vvp", default=os.environ.get("VVP", "vvp"))
    p.add_argument("--waves", action="store_true")
    p.add_argument("--demo", action="store_true", help="Six-packet interview demo")
    args = p.parse_args()
    if not 1 <= args.fifo_depth <= 256:
        p.error("FIFO depth must be 1..256")
    build = ROOT / "build" / ("demo" if args.demo else f"t{args.table_size}-f{args.fifo_depth}-s{args.seed}")
    build.mkdir(parents=True, exist_ok=True)
    s = (generate_demo(build/"vectors.txt",args.table_size,args.fifo_depth,args.seed) if args.demo else
         generate(build/"vectors.txt",args.table_size,args.fifo_depth,args.seed,args.random))
    sources = sorted((ROOT/"rtl").glob("*.sv"))
    executable = build / "test.vvp"
    compile_cmd = [args.iverilog,"-g2012","-Wall","-s","tb_tick_to_trade",
        f"-Ptb_tick_to_trade.TABLE_SIZE={args.table_size}",f"-Ptb_tick_to_trade.FIFO_DEPTH={args.fifo_depth}",
        "-o",str(executable),*[str(x) for x in sources],str(ROOT/"tests/tb_tick_to_trade.sv")]
    try:
        compile_run = subprocess.run(compile_cmd,cwd=ROOT,text=True,capture_output=True,check=True)
        (build/"compile.log").write_text(compile_run.stdout+compile_run.stderr)
        cmd = [args.vvp,str(executable),f"+vectors={build/'vectors.txt'}",f"+events={build/'events.csv'}"]
        if args.waves:
            cmd.append(f"+waves={build/'waves.vcd'}")
        sim = subprocess.run(cmd,cwd=ROOT,text=True,capture_output=True,check=True,timeout=180)
    except FileNotFoundError as e:
        raise SystemExit(f"Missing simulator: {e.filename}. Install Icarus Verilog or pass --iverilog and --vvp.")
    except subprocess.CalledProcessError as e:
        print(e.stdout); print(e.stderr); raise SystemExit(e.returncode)
    (build/"simulation.log").write_text(sim.stdout+sim.stderr)
    print(sim.stdout.strip())
    if "PASS cycles=" not in sim.stdout:
        raise SystemExit("Simulator did not report PASS")
    # A second comparison checks the actual ordered handshake log.
    lines = (build/"events.csv").read_text().splitlines()[1:]
    actual = []
    for line in lines:
        c,a,i,sym,seq,price,qty = line.split(",")
        actual.append((int(c),(int(a),int(i),int(sym,16),int(seq),int(price),int(qty))))
    assert actual == s.ref.transfers, "Handshake event log mismatch"
    version = subprocess.run([args.iverilog,"-V"],capture_output=True,text=True).stdout.splitlines()[0]
    report = {"status":"PASS", "seed":args.seed, "table_size":args.table_size,
        "fifo_depth":args.fifo_depth,"cycles_checked":s.ref.cycle,
        "frames_completed":s.ref.totals["rx"],"events_transferred":len(actual),
        "totals_across_resets":dict(s.ref.totals),"coverage_stimulus_counts":dict(s.coverage),
        "eop_to_empty_fifo_valid_cycles":sorted({x["eop_to_valid_cycles"] for x in s.ref.latencies}),
        "minimum_sop_to_empty_fifo_valid_cycles":min(x["sop_to_valid_cycles"] for x in s.ref.latencies),
        "target_clock_ns":6.4,"timing_closed":False,"simulator":version,
        "rtl_sha256":{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in sources}}
    (build/"results.json").write_text(json.dumps(report,indent=2)+"\n")
    print(f"Independent packet model, all-cycle outputs/counters and {len(actual)} handshakes agree.")
    print(f"Report: {build/'results.json'}")
    if args.demo:
        for cycle,event in actual:
            action,index,symbol,sequence,price,quantity = event
            print(f"  cycle {cycle:3d}: {'BUY' if action == 1 else 'SELL'} "
                  f"{symbol.to_bytes(8,'big').decode('ascii').strip()} "
                  f"price={price/10000:.4f} quantity={quantity} sequence={sequence}")


if __name__ == "__main__":
    main()
