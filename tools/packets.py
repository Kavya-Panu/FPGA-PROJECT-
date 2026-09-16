"""Dependency-free packet builder and independent, byte-oriented reference parser."""
from __future__ import annotations

import struct

TICK = struct.Struct("!HBBI8sII")


def checksum(data: bytes) -> int:
    if len(data) & 1:
        data += b"\0"
    total = sum(struct.unpack(f"!{len(data)//2}H", data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def make_frame(sequence=1, symbol=b"AAPL    ", price=1000000, quantity=100,
               port=1234, udp_checksum=True, source_port=5000, flags=0x4000) -> bytes:
    if len(symbol) != 8:
        raise ValueError("Symbol must contain exactly eight bytes (ASCII, space padded).")
    payload = TICK.pack(0x544B, 1, 1, sequence, symbol, price, quantity)
    src, dst = bytes([192, 0, 2, 1]), bytes([239, 1, 2, 3])
    udp = struct.pack("!HHHH", source_port, port, 8 + len(payload), 0) + payload
    if udp_checksum:
        pseudo = src + dst + struct.pack("!BBH", 0, 17, len(udp))
        value = checksum(pseudo + udp) or 0xFFFF
        udp = udp[:6] + struct.pack("!H", value) + udp[8:]
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20+len(udp), 0x1234,
                     flags, 64, 17, 0, src, dst)
    ip = ip[:10] + struct.pack("!H", checksum(ip)) + ip[12:]
    eth = bytes.fromhex("01005e0102030200000000010800")
    return eth + ip + udp


def repair_checksums(frame: bytes) -> bytes:
    """Recompute fixed-offset checksums to isolate a malformed field in tests."""
    data = bytearray(frame)
    data[24:26] = b"\0\0"
    data[24:26] = struct.pack("!H", checksum(bytes(data[14:34])))
    data[40:42] = b"\0\0"
    pseudo = bytes(data[26:34]) + bytes([0, data[23]]) + bytes(data[38:40])
    data[40:42] = struct.pack("!H", checksum(pseudo + bytes(data[34:66])) or 0xFFFF)
    return bytes(data)


def parse_frame(frame: bytes, port=1234):
    """Return tick dictionary or None. Does not model RTL words or parser state."""
    if len(frame) != 66 or frame[12:14] != b"\x08\x00":
        return None
    version_ihl, _, length, _, flags, ttl, protocol, _, src, dst = struct.unpack(
        "!BBHHHBBH4s4s", frame[14:34])
    if (version_ihl != 0x45 or length != 52 or flags & 0xBFFF or
            ttl == 0 or protocol != 17 or checksum(frame[14:34]) != 0):
        return None
    _, destination, udp_length, udp_ck = struct.unpack("!HHHH", frame[34:42])
    if destination != port or udp_length != 32:
        return None
    pseudo = src + dst + struct.pack("!BBH", 0, protocol, udp_length)
    if udp_ck and checksum(pseudo + frame[34:]) != 0:
        return None
    magic, version, kind, seq, symbol, price, qty = TICK.unpack(frame[42:])
    if (magic, version, kind) != (0x544B, 1, 1) or qty == 0:
        return None
    return {"symbol": int.from_bytes(symbol, "big"), "sequence": seq,
            "price": price, "quantity": qty}


def write_pcap(path, frames):
    with open(path, "wb") as stream:
        stream.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for n, frame in enumerate(frames):
            stream.write(struct.pack("<IIII", 0, n, len(frame), len(frame)))
            stream.write(frame)
