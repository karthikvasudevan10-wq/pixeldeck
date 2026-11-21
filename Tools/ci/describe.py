#!/usr/bin/env python3
"""Describes a screenshot as text, for checking a layout from a build log.

usage: describe.py shot.bmp CELL [X Y W H]

The picture (an uncompressed 24 or 32 bit BMP, as `sips -s format bmp` writes) is sampled every
CELL pixels inside the rectangle (the whole picture by default). Each colour gets a letter, most
common first, and every row is printed run-length encoded: "12a 3b" is twelve cells of a, then three of b.
"""
import struct
import sys
from collections import Counter


def load(path):
    data = open(path, "rb").read()
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    step = bpp // 8
    stride = (width * step + 3) & ~3
    flipped = height > 0
    height = abs(height)

    def pixel(x, y):
        row = height - 1 - y if flipped else y
        i = offset + row * stride + x * step
        return data[i + 2], data[i + 1], data[i]      # stored blue, green, red

    return width, height, pixel


def main():
    path, cell = sys.argv[1], int(sys.argv[2])
    width, height, pixel = load(path)
    x0, y0, w, h = (int(v) for v in sys.argv[3:7]) if len(sys.argv) >= 7 else (0, 0, width, height)
    rows = []
    for y in range(y0 + cell // 2, min(y0 + h, height), cell):
        rows.append([tuple(c >> 4 for c in pixel(x, y)) for x in range(x0 + cell // 2, min(x0 + w, width), cell)])
    counts = Counter(c for row in rows for c in row)
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    names = {c: letters[i] for i, (c, _) in enumerate(counts.most_common(len(letters)))}
    print(f"picture {width}x{height}, region {x0},{y0} {w}x{h}, one cell = {cell}px, {len(rows[0]) if rows else 0} cells across")
    print("colours: " + "  ".join(f"{names[c]}=#{c[0]:x}{c[1]:x}{c[2]:x}" for c, _ in counts.most_common(len(letters))))
    last, repeats = None, 0
    for n, row in enumerate(rows):
        runs, prev, count = [], None, 0
        for c in row:
            name = names.get(c, "?")
            if name == prev:
                count += 1
            else:
                if prev is not None:
                    runs.append(f"{count}{prev}")
                prev, count = name, 1
        runs.append(f"{count}{prev}")
        line = " ".join(runs)
        if line == last:
            repeats += 1
            continue
        if repeats:
            print(f"      (same for {repeats} more)")
        print(f"{y0 + n * cell:5d} {line}")
        last, repeats = line, 0
    if repeats:
        print(f"      (same for {repeats} more)")


if __name__ == "__main__":
    main()
