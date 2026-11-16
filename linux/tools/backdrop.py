#!/usr/bin/env python3
"""A desktop backdrop for screenshots: a soft blue gradient, written as a PNG with the standard library only.

usage: backdrop.py OUT.png WIDTH HEIGHT
"""
import struct
import sys
import zlib


def main() -> None:
    out, width, height = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    top, bottom = (38, 92, 150), (62, 132, 196)
    rows = []
    for y in range(height):
        t = y / max(1, height - 1)
        row = bytearray([0])
        for x in range(width):
            # A little light from the top left, so the island is seen against something.
            glow = max(0.0, 1.0 - ((x / width) ** 2 + (y / height) ** 2) ** 0.5) * 0.18
            color = [min(255, int(top[i] + (bottom[i] - top[i]) * t + 255 * glow * 0.4)) for i in range(3)]
            row += bytes(color)
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6))
    png += chunk(b"IEND", b"")
    with open(out, "wb") as handle:
        handle.write(png)


if __name__ == "__main__":
    main()
