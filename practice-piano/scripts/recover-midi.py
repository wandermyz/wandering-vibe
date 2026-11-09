#!/usr/bin/env python3
"""Recover complete MIDI events from a Practice Piano crash draft; keep the original."""
import pathlib
import struct
import sys


def read_variable(file):
    value = 0
    for _ in range(4):
        byte = file.read(1)
        if not byte:
            raise EOFError
        value = (value << 7) | (byte[0] & 127)
        if byte[0] < 128:
            return value
    raise ValueError("Invalid delta time")


def recover(source):
    destination = source.with_suffix("")
    if not source.name.endswith(".mid.draft"):
        raise ValueError("Expected a .mid.draft file")
    with source.open("rb") as file:
        header = file.read(22)
        if header[:18] != bytes.fromhex("4d546864000000060000000101e04d54726b"):
            raise ValueError("Not a Practice Piano MIDI draft")
        valid_end = 22
        ended = False
        while True:
            try:
                read_variable(file)
                status = file.read(1)
                if not status:
                    break
                if 0x80 <= status[0] <= 0xEF:
                    count = 1 if status[0] & 0xE0 == 0xC0 else 2
                    payload = file.read(count)
                    if len(payload) != count or any(b >= 128 for b in payload):
                        break
                elif status == b"\xff":
                    kind = file.read(1)
                    size = read_variable(file)
                    if not kind:
                        break
                    # Skip incrementally, without retaining long events.
                    remaining = size
                    while remaining:
                        block = file.read(min(4096, remaining))
                        if not block:
                            raise EOFError
                        remaining -= len(block)
                    ended = kind == b"\x2f" and size == 0
                else:
                    break
                valid_end = file.tell()
                if ended:
                    break
            except (EOFError, ValueError):
                break
        if valid_end == 22:
            raise ValueError("No complete MIDI events were written")
        ending = b"" if ended else b"".join(
            bytes([0, 0xB0 | channel, controller, 0])
            for channel in range(16) for controller in (64, 66, 120, 123)
        ) + b"\x00\xff\x2f\x00"
        track_size = valid_end - 22 + len(ending)
        with destination.open("xb") as output:
            output.write(header[:18] + struct.pack(">I", track_size))
            file.seek(22)
            remaining = valid_end - 22
            while remaining:
                block = file.read(min(65536, remaining))
                output.write(block)
                remaining -= len(block)
            output.write(ending)
    print(destination)


if __name__ == "__main__":
    try:
        recover(pathlib.Path(sys.argv[1]))
    except (IndexError, OSError, ValueError) as error:
        sys.exit(f"Recovery failed: {error}")
