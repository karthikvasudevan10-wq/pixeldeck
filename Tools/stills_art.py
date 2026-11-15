#!/usr/bin/env python3
"""Draws the starter stills (single-frame pixel art) for the gallery's Stills tab and writes them
to PixelDeck/Resources/Starter/stills.json, in the same character-grid format as sprites.json
(each sprite carries its own palette).

    python3 Tools/stills_art.py [--preview DIR]

Every piece is at most 64 x 64, so free users can edit them. Shapes are filled, then shaded
(light from the top left) and outlined automatically.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "PixelDeck", "Resources", "Starter", "stills.json")
INK = "#1B1530"


class Art:
    def __init__(self, w, h, bg=None):
        self.w, self.h = w, h
        self.px = [[bg] * w for _ in range(h)]
        self.mask = [[False] * w for _ in range(h)]   # pixels that get an outline around them

    def set(self, x, y, c, outline=True):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h and c:
            self.px[y][x] = c
            if outline:
                self.mask[y][x] = True

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def fill(self, inside, base, light=None, shade=None, outline=True, bbox=None):
        """Fills every pixel where inside(x, y), shading by position in the shape's bounding box."""
        pts = [(x, y) for y in range(self.h) for x in range(self.w) if inside(x + 0.5, y + 0.5)]
        if not pts:
            return pts
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        x0, x1, y0, y1 = bbox or (min(xs), max(xs), min(ys), max(ys))
        for x, y in pts:
            u = (x - x0) / max(1, x1 - x0) - 0.5
            v = (y - y0) / max(1, y1 - y0) - 0.5
            c = base
            if light and u + v < -0.45: c = light
            elif shade and u + v > 0.35: c = shade
            self.set(x, y, c, outline)
        return pts

    def disc(self, cx, cy, r, *cols, ry=None, **kw):
        ry = ry or r
        return self.fill(lambda x, y: ((x - cx) / r) ** 2 + ((y - cy) / ry) ** 2 <= 1, *cols, **kw)

    def rect(self, x, y, w, h, *cols, **kw):
        return self.fill(lambda px, py: x <= px < x + w and y <= py < y + h, *cols, **kw)

    def poly(self, pts, *cols, **kw):
        def inside(px, py):
            n, c = len(pts), False
            for i in range(n):
                (xa, ya), (xb, yb) = pts[i], pts[(i + 1) % n]
                if (ya > py) != (yb > py) and px < (xb - xa) * (py - ya) / (yb - ya) + xa:
                    c = not c
            return c
        return self.fill(inside, *cols, **kw)

    def outline(self, color=INK):
        """A 1-pixel outline around everything drawn with outline=True."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.mask[y][x]:
                    continue
                if any(0 <= x + dx < self.w and 0 <= y + dy < self.h and self.mask[y + dy][x + dx]
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    add.append((x, y))
        for x, y in add:
            self.px[y][x] = color


# --- The pieces ------------------------------------------------------------------------------

def strawberry():
    a = Art(32, 32)
    a.poly([(6, 11), (26, 11), (24, 20), (16, 29), (8, 20)], "#E63946", "#FF7A85", "#A61E33")
    a.disc(16, 13, 10, "#E63946", "#FF7A85", "#A61E33", ry=5)
    for y in range(12, 27, 3):                                   # seeds
        for x in range(8 + (y // 3) % 2 * 2, 25, 4):
            if a.get(x, y) in ("#E63946", "#FF7A85", "#A61E33"):
                a.set(x, y, "#FFE066")
    for (cx, cy, r) in [(11, 9, 3.2), (16, 8, 3.4), (21, 9, 3.2)]:
        a.disc(cx, cy, r, "#4FA33A", "#7BE07B", "#2E7A2E", ry=2)
    a.rect(15, 3, 2, 4, "#2E7A2E")
    a.outline()
    a.set(11, 15, "#FFFFFF", False); a.set(10, 16, "#FFFFFF", False)  # shine
    return a


def potion():
    a = Art(32, 32)
    a.disc(16, 20, 10, "#C9D6F2", "#FFFFFF", "#9EAFD6")                 # glass
    a.rect(13, 6, 6, 6, "#C9D6F2", "#FFFFFF", "#9EAFD6")                 # neck
    a.rect(12, 3, 8, 4, "#9C6B3C", "#C08A55", "#6E4A28")                 # cork
    a.fill(lambda x, y: (x - 16) ** 2 + (y - 20) ** 2 <= 8.5 ** 2 and y >= 18, "#8E5CF0", "#B794FF", "#5E36B8")  # liquid
    a.outline()
    for (x, y) in [(13, 22), (18, 24), (16, 21), (20, 21)]:
        a.set(x, y, "#E6DAFF", False)
    a.set(10, 15, "#FFFFFF", False); a.set(10, 16, "#FFFFFF", False); a.set(11, 14, "#FFFFFF", False)
    return a


def mushroom():
    a = Art(32, 32)
    a.rect(12, 17, 8, 11, "#FFF1D6", "#FFFFFF", "#E2CBA6")                # stem
    a.fill(lambda x, y: ((x - 16) / 13) ** 2 + ((y - 17) / 11) ** 2 <= 1 and y <= 18,
           "#E63946", "#FF7A85", "#A61E33")                              # cap
    for (cx, cy, r) in [(11, 11, 2.2), (19, 9, 2.6), (24, 14, 1.8), (8, 16, 1.6), (16, 15, 1.6)]:
        a.disc(cx, cy, r, "#FFF6E0", outline=False)
    a.rect(4, 27, 24, 2, "#4FA33A", "#7BE07B", "#2E7A2E")                 # grass
    a.outline()
    a.set(13, 22, INK, False); a.set(18, 22, INK, False)                   # a face
    a.set(15, 24, "#E06A8A", False); a.set(16, 24, "#E06A8A", False)
    return a


def cactus():
    a = Art(32, 32)
    g, gl, gd = "#4FA33A", "#7BE07B", "#2E7A2E"
    a.rect(13, 6, 7, 18, g, gl, gd, bbox=(13, 19, 6, 23))                 # trunk
    a.disc(16.5, 7, 3.5, g, gl, gd, ry=2.5)
    a.rect(7, 12, 4, 7, g, gl, gd); a.disc(9, 12, 2, g, gl, gd)            # left arm
    a.rect(9, 17, 5, 3, g, gl, gd)
    a.rect(22, 9, 4, 7, g, gl, gd); a.disc(24, 9, 2, g, gl, gd)            # right arm
    a.rect(19, 14, 4, 3, g, gl, gd)
    a.poly([(9, 23), (24, 23), (22, 30), (11, 30)], "#D9734A", "#F29A6E", "#A8502E")  # pot
    a.rect(8, 22, 17, 3, "#E2875C", "#F29A6E", "#A8502E")
    a.outline()
    for (x, y) in [(15, 10), (17, 14), (15, 18), (8, 15), (24, 12)]:
        a.set(x, y, "#E8F7C8", False)                                     # spines
    a.disc(16.5, 4.5, 1.6, "#FF5C8A", outline=False); a.set(16, 4, "#FFE066", False)  # flower
    return a


def ice_cream():
    a = Art(32, 32)
    a.poly([(9, 16), (23, 16), (16, 30)], "#E2A65C", "#F2C98A", "#B47A3A")  # cone
    for y in range(17, 28, 3):                                            # waffle
        for x in range(9, 24):
            if a.get(x, y) and abs((x + y) % 6) == 0: a.set(x, y, "#B47A3A")
    a.disc(16, 15, 7.5, "#7BE0C0", "#B8F5E2", "#3FA88A", ry=4)            # mint
    a.disc(16, 9, 6.5, "#FF8FAB", "#FFC2D1", "#D9607F", ry=5)             # strawberry
    a.disc(17, 3.5, 2, "#E63946", "#FF7A85", "#A61E33")                    # cherry
    a.outline()
    a.set(18, 1, "#2E7A2E", False); a.set(19, 0, "#2E7A2E", False)
    for (x, y, c) in [(12, 9, "#FFE066"), (19, 8, "#7BE07B"), (15, 6, "#3A86FF"), (20, 11, "#FFFFFF"), (11, 14, "#FFFFFF")]:
        a.set(x, y, c, False)                                             # sprinkles
    return a


def planet():
    a = Art(40, 32, "#120E1F")
    for (x, y) in [(3, 4), (35, 3), (6, 26), (31, 28), (37, 15), (2, 17), (24, 2), (14, 29)]:
        a.set(x, y, "#FFF6E0", False)
    a.set(10, 3, "#FFD23F", False); a.set(29, 7, "#C8B6FF", False)
    # The back of the ring, behind the planet.
    ring = lambda x, y, r1, r2: r1 <= ((x - 20) / 18) ** 2 + ((y - 17) / 5.5) ** 2 <= r2
    a.fill(lambda x, y: ring(x, y, 0.5, 1) and y < 17, "#9A86E0", outline=False)
    a.disc(20, 16, 9, "#FF8B3D", "#FFC07A", "#C95A1E")
    for y in (12, 17, 21):                                                 # bands
        for x in range(10, 31):
            if a.get(x, y) in ("#FF8B3D", "#FFC07A", "#C95A1E"): a.set(x, y, "#E2662A")
    a.fill(lambda x, y: ring(x, y, 0.5, 1) and y >= 17, "#C8B6FF", "#EDE6FF", "#9A86E0")
    a.outline("#0A0714")
    return a


def cottage():
    a = Art(40, 40)
    a.rect(0, 33, 40, 7, "#4FA33A", "#7BE07B", "#2E7A2E")                  # grass
    a.rect(9, 18, 22, 16, "#F3E3C3", "#FFF6E0", "#DCC9A6")                 # walls
    a.poly([(5, 19), (20, 6), (35, 19)], "#C0392B", "#E05A4A", "#8E2A20")   # roof
    a.rect(26, 7, 4, 8, "#8A8698", "#B0ADBC", "#6A6678")                   # chimney
    a.rect(17, 24, 6, 10, "#9C6B3C", "#C08A55", "#6E4A28")                 # door
    a.rect(11, 22, 5, 5, "#FFD23F", "#FFF0A0", "#E0A82A")                  # windows (lit)
    a.rect(24, 22, 5, 5, "#FFD23F", "#FFF0A0", "#E0A82A")
    a.outline()
    for wx in (13, 26):
        a.set(wx, 22, INK, False); a.set(wx, 23, INK, False); a.set(wx, 24, INK, False); a.set(wx, 25, INK, False); a.set(wx, 26, INK, False)
    a.rect(11, 24, 5, 1, INK, outline=False); a.rect(24, 24, 5, 1, INK, outline=False)
    a.set(21, 29, "#FFD23F", False)                                       # door knob
    for (cx, cy, r) in [(30, 3, 1.6), (33, 1, 1.2)]:
        a.disc(cx, cy, r, "#E8E8F0", outline=False)                       # smoke
    for (x, c) in [(4, "#FF5C8A"), (7, "#FFD23F"), (33, "#C8B6FF"), (36, "#FF5C8A")]:
        a.set(x, 34, c, False); a.set(x, 35, "#2E7A2E", False)             # flowers
    return a


def sunset():
    W, H = 64, 40
    a = Art(W, H)
    bands = ["#2B1B5E", "#5B2A7E", "#9E3D7B", "#E0576B", "#F28C5E", "#FFC36B"]
    horizon = 26
    for y in range(horizon):
        f = y / horizon * len(bands)
        i = min(int(f), len(bands) - 1)
        for x in range(W):
            c = bands[i]
            if i + 1 < len(bands) and f - i > 0.8 and (x + y) % 2 == 0: c = bands[i + 1]
            a.set(x, y, c, False)
    a.fill(lambda x, y: (x - 32) ** 2 + (y - 26) ** 2 <= 9 ** 2 and y < horizon, "#FFE38A", outline=False)
    a.fill(lambda x, y: (x - 32) ** 2 + (y - 26) ** 2 <= 7 ** 2 and y < horizon, "#FFF6C8", outline=False)
    ridge = lambda x: 22 + 2.5 * math.sin(x / 6.0) + 1.5 * math.sin(x / 2.7)
    for x in range(W):                                                     # far hills either side
        if abs(x - 32) > 12:
            for y in range(int(ridge(x)), horizon): a.set(x, y, "#3A2050", False)
    for y in range(horizon, H):                                            # sea
        for x in range(W):
            a.set(x, y, "#2B2F6B" if y > horizon + 4 else "#3A3F86", False)
    for y in range(horizon + 1, H, 2):                                     # sun's reflection
        half = max(1, 9 - (y - horizon) // 2)
        for x in range(32 - half, 32 + half + 1):
            if (x + y // 2) % 3: a.set(x, y, "#FFC36B" if y < horizon + 6 else "#F28C5E", False)
    for (x, y) in [(6, 4), (14, 2), (50, 5), (58, 2), (40, 3)]:
        a.set(x, y, "#FFF6E0", False)
    for (bx, by) in [(18, 10), (22, 12)]:                                  # birds
        a.set(bx, by, "#2B1B3D", False); a.set(bx - 1, by - 1, "#2B1B3D", False); a.set(bx + 1, by - 1, "#2B1B3D", False)
    # A little sailboat.
    a.poly([(44, 27), (52, 27), (50, 30), (46, 30)], "#1B1530", outline=False)
    a.poly([(48, 18), (48, 27), (53, 27)], "#FFF6E0", outline=False)
    a.poly([(47, 20), (47, 27), (43.5, 27)], "#FFD9B0", outline=False)
    return a


PIECES = [
    ("strawberry", "Strawberry", strawberry),
    ("potion", "Potion", potion),
    ("mushroom", "Mushroom", mushroom),
    ("cactus", "Cactus", cactus),
    ("icecream", "Ice cream", ice_cream),
    ("planet", "Ringed planet", planet),
    ("cottage", "Cottage", cottage),
    ("sunset", "Sunset sail", sunset),
]

CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&*+-/:;<=>?@^_~"


def encode():
    out = {}
    for key, label, make in PIECES:
        a = make()
        assert a.w <= 64 and a.h <= 64, key
        colors = []
        for row in a.px:
            for c in row:
                if c and c.upper() not in colors: colors.append(c.upper())
        assert len(colors) <= len(CHARS)
        k = {c: CHARS[i] for i, c in enumerate(colors)}
        out[key] = {"w": a.w, "h": a.h, "fps": 8, "label": label,
                    "pal": {CHARS[i]: c for i, c in enumerate(colors)},
                    "frames": [["".join(k[c.upper()] if c else "." for c in row) for row in a.px]]}
    return out


def preview(folder):
    from PIL import Image
    os.makedirs(folder, exist_ok=True)
    tiles = []
    for key, label, make in PIECES:
        a = make()
        img = Image.new("RGB", (a.w, a.h), (43, 31, 71))
        for y, row in enumerate(a.px):
            for x, c in enumerate(row):
                if c: img.putpixel((x, y), tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)))
        tiles.append(img.resize((a.w * 6, a.h * 6), Image.NEAREST))
    W = sum(t.width for t in tiles[:4]) + 50; H = max(t.height for t in tiles[:4]) + max(t.height for t in tiles[4:]) + 30
    sheet = Image.new("RGB", (max(W, sum(t.width for t in tiles[4:]) + 50), H), (18, 14, 31))
    x = 10
    for t in tiles[:4]: sheet.paste(t, (x, 10)); x += t.width + 10
    x = 10; y = 20 + max(t.height for t in tiles[:4])
    for t in tiles[4:]: sheet.paste(t, (x, y)); x += t.width + 10
    sheet.save(os.path.join(folder, "stills.png"))


if __name__ == "__main__":
    data = encode()
    with open(OUT, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB, {len(data)} stills)")
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
