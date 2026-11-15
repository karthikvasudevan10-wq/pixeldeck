#!/usr/bin/env python3
"""Draws the two large animated showcase sprites for the gallery and writes them to
PixelDeck/Resources/Starter/showcase.json, in the same character-grid format as sprites.json.

    python3 Tools/showcase_art.py [--preview DIR]

--preview also writes each scene as an upscaled PNG strip (needs Pillow). Both scenes loop
seamlessly: every moving thing completes a whole number of cycles in FRAMES frames.
"""
import json
import math
import os
import random
import sys

FRAMES = 16
FPS = 8
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "PixelDeck", "Resources", "Starter", "showcase.json")


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def copy(self):
        c = Canvas(self.w, self.h)
        c.px = [row[:] for row in self.px]
        return c

    def set(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if c and 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def frame(self, x, y, w, h, c):
        for xx in range(x, x + w):
            self.set(xx, y, c); self.set(xx, y + h - 1, c)
        for yy in range(y, y + h):
            self.set(x, yy, c); self.set(x + w - 1, yy, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy: err += dy; x0 += sx
            if e2 <= dx: err += dx; y0 += sy

    def disc(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x - cx) / max(rx, 0.5)) ** 2 + ((y - cy) / max(ry, 0.5)) ** 2 <= 1:
                    self.set(x, y, c)

    def stamp(self, rows, x, y, key, flip=False):
        """Draws a little character-art sprite: `key` maps characters to colours."""
        for j, row in enumerate(rows):
            r = row[::-1] if flip else row
            for i, ch in enumerate(r):
                if ch != "." and ch in key:
                    self.set(x + i, y + j, key[ch])


def noise(x, y, seed=0):
    """Stable pseudo-random 0..1 per pixel (no visible diagonal patterns)."""
    n = (x * 374761393 + y * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (n ^ (n >> 16)) / 0xFFFFFFFF


def sky(cv, bands, top, bottom):
    """Horizontal colour bands with a one-row checker dither at each boundary."""
    n = len(bands)
    for y in range(top, bottom):
        f = (y - top) / (bottom - top) * n
        i = min(int(f), n - 1)
        c = bands[i]
        if i + 1 < n and f - i > 0.85:
            c = bands[i + 1] if (y % 2 == 0) else c
        for x in range(cv.w):
            if i + 1 < n and f - i > 0.85:
                c = bands[i + 1] if (x + y) % 2 == 0 else bands[i]
            cv.set(x, y, c)


def cloud(cv, x, y, w, light, shade):
    puffs = [(0.25, 0.55, 0.22), (0.5, 0.35, 0.3), (0.75, 0.55, 0.22), (0.5, 0.7, 0.5)]
    hgt = w * 0.4
    for px, py, r in puffs:
        cv.disc(x + px * w, y + py * hgt, r * w, r * w * 0.75, light)
    # Shade the underside: the bottom two pixels of every column.
    for xx in range(int(x - 2), int(x + w + 3)):
        ys = [yy for yy in range(int(y - w), int(y + w)) if cv.get(xx, yy) == light]
        if ys:
            cv.set(xx, max(ys), shade)
            if len(ys) > 4 and xx % 3: cv.set(xx, max(ys) - 1, shade)


# ---------------------------------------------------------------------------------------------
# 1. A cute Japanese high street (shotengai) on a spring afternoon
# ---------------------------------------------------------------------------------------------

def highstreet():
    W, H = 160, 120
    C = dict(
        ink="#2B2238", sky1="#7EC8FF", sky2="#9AD6FF", sky3="#B9E3FF", sky4="#D8F0FF", sky5="#FFE9D6",
        cloud="#FFFFFF", cloudS="#DCEBFA", far="#C4C0E6", far2="#ADA8DA", farW="#E4E2F6",
        roof="#4A5470", roofHi="#6A7598", cream="#F3E3C3", creamS="#DCC9A6", peach="#F6C9A8", peachS="#DDAA88",
        mint="#BFE3CF", mintS="#9CC8B1", lilac="#D9C8EE", lilacS="#BBA8D6",
        red="#E63946", redD="#9E1F2B", white="#FFF6E0", green="#2E9E5B", greenD="#1F6E40", blue="#3A86FF",
        blueD="#2759B8", pink="#FF8FAB", pinkD="#D9607F", navy="#23305E", glow="#FFB23F", glowHi="#FFE66D",
        glass="#8EC9E8", glassHi="#D6F1FF", glassD="#4F7EA8", wood="#9C6B3C", woodD="#5E3B22",
        pave="#E2DACB", paveL="#C9BFAE", curb="#B3A894", sak="#FFB7CE", sakD="#FF8FB1", sakL="#FFE0EA",
        trunk="#6B4A3A", pole="#8A8698", wire="#4A4658", leaf="#4FA33A", leafD="#2E7A2E", neon="#FF5C8A",
        neonOff="#8E4060", cat="#F2A65A", catD="#C97A34", yellow="#FFD23F", steam="#FFFFFF", steamS="#EAF2FA",
        cake="#FFD6A5", choc="#7A4A2E", berry="#E63946", gray="#9A97A8",
    )
    bg = Canvas(W, H)
    sky(bg, [C["sky1"], C["sky2"], C["sky3"], C["sky4"], C["sky5"]], 0, 62)
    cloud(bg, 10, 6, 30, C["cloud"], C["cloudS"])
    cloud(bg, 96, 12, 24, C["cloud"], C["cloudS"])
    cloud(bg, 132, 4, 18, C["cloud"], C["cloudS"])

    # Distant skyline.
    rnd = random.Random(7)
    x = 0
    while x < W:
        w = rnd.randint(6, 14); top = rnd.randint(30, 46)
        col = C["far"] if rnd.random() < 0.6 else C["far2"]
        bg.rect(x, top, w, 70 - top, col)
        for wy in range(top + 3, 62, 4):
            for wx in range(x + 2, x + w - 2, 3):
                if rnd.random() < 0.45: bg.set(wx, wy, C["farW"])
        x += w

    # Pavement: stone slabs.
    GROUND = 98
    bg.rect(0, GROUND, W, H - GROUND, C["pave"])
    bg.rect(0, GROUND, W, 1, C["curb"])
    for y in range(GROUND + 1, H):
        row = (y - GROUND - 1) // 6
        if (y - GROUND - 1) % 6 == 5:
            bg.rect(0, y, W, 1, C["paveL"])
        else:
            for xx in range((row % 2) * 6, W, 12):
                bg.set(xx, y, C["paveL"])

    def building(x0, x1, top, wall, wallS, awn, awnB, sign=None):
        bg.rect(x0, top, x1 - x0, GROUND - top, wall)
        bg.rect(x1 - 2, top, 2, GROUND - top, wallS)               # shaded edge
        bg.rect(x0 - 1, top - 3, x1 - x0 + 2, 3, C["roof"])         # roof cap
        bg.rect(x0 - 1, top - 3, x1 - x0 + 2, 1, C["roofHi"])
        bg.rect(x0, top, x1 - x0, 1, wallS)
        # Upper-floor windows with little curtains and flower boxes.
        for wx in range(x0 + 4, x1 - 9, 13):
            bg.rect(wx, top + 6, 9, 9, C["ink"])
            bg.rect(wx + 1, top + 7, 7, 7, C["glass"])
            bg.rect(wx + 1, top + 7, 2, 7, C["white"]); bg.rect(wx + 6, top + 7, 2, 7, C["white"])
            bg.set(wx + 4, top + 8, C["glassHi"]); bg.set(wx + 3, top + 9, C["glassHi"])
            bg.rect(wx, top + 15, 9, 2, C["woodD"])
            for fx in range(wx + 1, wx + 8, 2):
                bg.set(fx, top + 14, C["leaf"] if fx % 4 else C["pink"])
        # Awning with stripes and a scalloped edge.
        ay = 70
        bg.rect(x0 - 1, ay, x1 - x0 + 2, 6, awn)
        for sx in range(x0 - 1, x1 + 1):
            if ((sx - x0) // 3) % 2 == 1:
                for yy in range(ay, ay + 6): bg.set(sx, yy, awnB)
            if (sx - x0) % 4 in (1, 2): bg.set(sx, ay + 6, awn if ((sx - x0) // 3) % 2 == 0 else awnB)
        bg.rect(x0 - 1, ay - 1, x1 - x0 + 2, 1, C["ink"])
        # Shop floor: wooden frame.
        bg.rect(x0, 77, x1 - x0, GROUND - 77, C["woodD"])

    building(0, 42, 44, C["cream"], C["creamS"], C["red"], C["white"])
    building(42, 80, 52, C["peach"], C["peachS"], C["pink"], C["white"])
    building(80, 122, 40, C["mint"], C["mintS"], C["blue"], C["white"])
    building(122, 160, 48, C["lilac"], C["lilacS"], C["green"], C["white"])

    # Ramen shop (left): sliding doors behind a navy noren.
    bg.rect(3, 79, 36, 19, C["wood"])
    for dx in range(3, 39, 9):
        bg.rect(dx + 1, 80, 7, 17, C["glassD"]); bg.rect(dx + 2, 81, 2, 6, C["glass"])
    bg.rect(8, 77, 26, 10, C["navy"])
    for nx in range(8, 34, 7): bg.rect(nx + 6, 79, 1, 8, C["ink"])          # splits
    bg.rect(18, 80, 6, 4, C["white"]); bg.set(20, 81, C["navy"]); bg.set(21, 82, C["navy"])  # emblem

    # Café (middle): display window with cakes, a door, a chalkboard sign outside.
    bg.rect(44, 79, 22, 15, C["ink"]); bg.rect(45, 80, 20, 13, C["glassHi"])
    bg.rect(45, 88, 20, 1, C["wood"])
    for i, (cx, col) in enumerate([(47, C["cake"]), (52, C["choc"]), (57, C["pink"]), (62, C["cake"])]):
        bg.rect(cx, 85, 4, 3, col); bg.set(cx + 1, 84, C["berry"])
        bg.rect(cx, 90, 3, 2, [C["choc"], C["cake"], C["sak"], C["yellow"]][i])
    bg.rect(68, 79, 10, 19, C["wood"]); bg.rect(69, 80, 8, 10, C["glass"]); bg.set(70, 89, C["glow"])
    board = ["kkkkkk", "kgggk.", "kgwgk.", "kgggk.", "kgwgk.", "kkkkk."]
    bg.stamp([".kkkk.", "kgggk", "kgwwgk", "kgggk", "kgwgk", "kgggk", "k...k"], 52, 92,
             {"k": C["woodD"], "g": C["leafD"], "w": C["white"]})

    # Neon shop (right-middle): glass doors.
    bg.rect(84, 79, 34, 19, C["ink"])
    for dx in range(85, 117, 8):
        bg.rect(dx, 80, 7, 18, C["glass"]); bg.rect(dx + 1, 81, 1, 8, C["glassHi"])
    bg.rect(86, 58, 32, 9, C["ink"])                                       # neon board (lit per frame)

    # Shop on the right: vending machines stand in front (drawn per frame for lights).
    bg.rect(149, 79, 9, 19, C["wood"]); bg.rect(150, 80, 7, 10, C["glass"])

    # Vertical hanging signs.
    def vsign(x, y, col):
        bg.rect(x - 1, y - 1, 9, 24, C["ink"]); bg.rect(x, y, 7, 22, col)
        for gy in range(y + 2, y + 20, 6):
            bg.rect(x + 2, gy, 3, 1, C["white"]); bg.rect(x + 3, gy, 1, 4, C["white"]); bg.rect(x + 1, gy + 3, 5, 1, C["white"])
    vsign(36, 46, C["red"])
    vsign(122, 46, C["navy"])

    # Power pole and sagging wires.
    bg.rect(79, 16, 3, GROUND - 16, C["pole"]); bg.rect(73, 20, 15, 2, C["pole"])
    for (a, b) in [((0, 22), (74, 21)), ((87, 21), (160, 24)), ((0, 28), (80, 26)), ((80, 26), (160, 30))]:
        (xa, ya), (xb, yb) = a, b
        for xx in range(xa, xb + 1):
            f = (xx - xa) / max(1, xb - xa)
            bg.set(xx, ya + (yb - ya) * f + 4 * math.sin(math.pi * f), C["wire"])

    # Street lamp (lily-of-the-valley style).
    bg.rect(103, 52, 1, GROUND - 52, C["pole"])
    bg.rect(99, 52, 9, 1, C["pole"])
    for lx in (98, 106):
        bg.stamp([".k.", "kwk", "kwk"], lx, 53, {"k": C["pole"], "w": C["white"]})

    # Bicycle in front of the neon shop.
    bike = [
        "....k.....k...",
        "...kkkkkkkk...",
        "..kk...k..k...",
        ".k..k.k.k..k..",
        "k....kk..kk.k.",
        "k....k....k.k.",
        ".k..k......k..",
        "..kk........kk",
    ]
    bg.stamp(bike, 86, 90, {"k": C["blueD"]})

    # Cherry tree in a planter (left), canopy over the ramen shop.
    bg.rect(13, 92, 12, 6, C["woodD"]); bg.rect(13, 92, 12, 1, C["wood"])
    bg.rect(18, 66, 3, 26, C["trunk"]); bg.line(19, 70, 12, 60, C["trunk"]); bg.line(20, 68, 27, 58, C["trunk"])
    rnd = random.Random(3)
    for (cx, cy, r) in [(19, 52, 13), (8, 58, 9), (30, 56, 10), (14, 44, 8), (26, 46, 8)]:
        bg.disc(cx, cy, r, r * 0.8, C["sak"])
    for _ in range(90):
        x = rnd.randint(0, 40); y = rnd.randint(36, 66)
        if bg.get(x, y) == C["sak"]:
            bg.set(x, y, C["sakD"] if rnd.random() < 0.55 else C["sakL"])
    for _ in range(26):                                                    # petals on the ground
        bg.set(rnd.randint(0, 60), rnd.randint(GROUND + 1, H - 1), C["sak"])

    # Potted plants by the café.
    for px in (42, 79):
        bg.rect(px - 2, 93, 5, 5, C["redD"]); bg.disc(px, 90, 3, 3, C["leaf"]); bg.set(px - 1, 89, C["leafD"])

    # -- Animated parts ---------------------------------------------------------------------
    petals = [(rnd.uniform(0, 48), rnd.uniform(40, 62), rnd.uniform(0, 1), rnd.uniform(0, 1)) for _ in range(16)]
    cat = {
        0: ["..k...k", ".kck.kck", ".kcccccck", "kcwkcwkck", "kcccpccck", ".kcccccck", "..kcccck", ".kccccck", ".kccdcck", ".kccdcck", "..kkkkkk"],
    }
    frames = []
    for t in range(FRAMES):
        cv = bg.copy()
        ph = 2 * math.pi * t / FRAMES

        # Paper lanterns sway and flicker.
        for i, lx in enumerate((4, 31)):
            sway = round(1.2 * math.sin(ph + i))
            cv.line(lx + 3, 76, lx + 3 + sway, 79, C["ink"])
            ox = lx + sway
            cv.rect(ox + 1, 79, 5, 1, C["ink"]); cv.rect(ox + 1, 88, 5, 1, C["ink"])
            cv.rect(ox, 80, 7, 8, C["red"])
            cv.rect(ox + 1, 80, 1, 8, C["redD"])
            lit = C["glowHi"] if (t + i * 3) % 6 else C["glow"]
            cv.rect(ox + 3, 82, 2, 4, lit)
            cv.set(ox + 3, 87, C["ink"])

        # Steam from the ramen shop's vent rises and loops.
        cv.rect(30, 40, 4, 4, C["gray"])
        for k in range(3):
            f = ((t / FRAMES) + k / 3) % 1
            sy = 38 - f * 20
            sx = 32 + 2 * math.sin(f * 2 * math.pi * 1.5 + k)
            if f < 0.85:
                cv.disc(sx, sy, 1.5 + f * 2, 1.2 + f * 1.5, C["steam"] if f < 0.5 else C["steamS"])

        # Neon sign blinks letter by letter.
        for i in range(5):
            on = (t // 2 + i) % 8 != 0 and not (t in (6, 7) and i == 2)
            col = C["neon"] if on else C["neonOff"]
            gx = 88 + i * 6
            cv.rect(gx, 60, 4, 1, col); cv.rect(gx + 1 + (i % 2), 60, 1, 5, col); cv.rect(gx, 64, 4, 1, col)
            if on: cv.set(gx + 3, 62, C["glowHi"])

        # Vending machines with blinking buttons.
        for vx, body in ((125, C["blue"]), (137, C["red"])):
            cv.rect(vx - 1, 71, 12, 27, C["ink"]); cv.rect(vx, 72, 10, 25, body)
            cv.rect(vx + 1, 73, 8, 9, C["white"])
            for r in range(3):
                for cc in range(4):
                    cv.set(vx + 2 + cc * 2, 74 + r * 3, [C["red"], C["yellow"], C["green"], C["blueD"]][(r + cc) % 4])
                    lit = (t + r * 4 + cc) % 8 == 0
                    cv.set(vx + 2 + cc * 2, 76 + r * 3, C["glowHi"] if lit else C["gray"])
            cv.rect(vx + 2, 90, 6, 3, C["ink"])
            cv.rect(vx + 6, 84, 2, 3, C["glowHi"] if t % 4 < 2 else C["glow"])

        # Banner flags (nobori) ripple.
        for fx in (60, 74):
            cv.rect(fx, 66, 1, 32, C["wood"])
            for y in range(68, 88):
                off = round(math.sin(ph * 2 + y * 0.45 + fx))
                for xx in range(5):
                    col = C["yellow"] if xx < 4 else C["red"]
                    if 72 <= y <= 74: col = C["red"]
                    cv.set(fx + 1 + xx + (off if xx > 1 else 0), y, col)

        # A cat by the café, tail swishing.
        cv.stamp(cat[0], 44, 87, {"k": C["ink"], "c": C["cat"], "w": C["white"], "p": C["pink"], "d": C["catD"]})
        tail = [(53, 96), (54, 95), (55, 94 + round(math.sin(ph * 2))), (56, 93 + round(math.sin(ph * 2 + 1)))]
        for x, y in tail: cv.set(x, y, C["catD"])

        # Falling cherry petals: each falls 60 px per loop, swaying.
        for (x0, y0, p, q) in petals:
            f = (t / FRAMES + p) % 1
            y = y0 + f * 60
            x = x0 + 6 * f + 2.5 * math.sin(2 * math.pi * (2 * f + q))
            cv.set(x, y, C["sak"] if int(q * 10) % 3 else C["sakD"])
            if int(q * 10) % 2: cv.set(x + 1, y, C["sakL"])

        frames.append(cv)
    return dict(w=W, h=H, fps=FPS, label="Japanese high street in spring", frames=frames)


# ---------------------------------------------------------------------------------------------
# 2. Mountains, a river, spring flowers, blue sky, and a boy with his cassette player
# ---------------------------------------------------------------------------------------------

def landscape():
    W, H = 192, 108
    C = dict(
        ink="#1B1530", s1="#3D8BFF", s2="#5A9EFF", s3="#7BB4FF", s4="#9FCBFF", s5="#C7E4FF",
        cloud="#FFFFFF", cloudS="#DDEBFF",
        far="#8C9CE0", farS="#7181CC", snow="#FFFFFF", snowS="#D2DCF8",
        mid="#4E8FA6", midS="#3D7590", forest="#2F6B5A", forestL="#3F8A6A",
        hill="#79C850", hillL="#9BDA6A", hillD="#58A83E", meadow="#8FD45E", meadowD="#6FBE48",
        river="#3A86FF", riverL="#7CC0FF", riverS="#E8FBFF", bank="#D8C88E",
        pine="#255E43", pineL="#367A55", sak="#FFB7CE", sakD="#FF8FB1", trunk="#6B4A3A",
        f1="#FF5C8A", f2="#FFD23F", f3="#FFFFFF", f4="#C8B6FF", f5="#FF8B3D", stem="#3F8E33",
        hair="#3A2A20", skin="#F2C9A0", skinS="#D9A57A", shirt="#FF8B3D", shirtS="#D9692A",
        jeans="#3A5BA8", jeansS="#2B437E", shoe="#FFFFFF", sole="#E63946", phones="#E63946",
        walk="#C9CCD6", walkS="#9EA2B0", tape="#3A86FF", note="#FF5C8A", noteS="#B8336A",
        rock="#A9A3B8", rockS="#8A839C", bird="#2B2238", fly="#FFD23F", flyS="#FF8B3D",
    )
    bg = Canvas(W, H)
    sky(bg, [C["s1"], C["s2"], C["s3"], C["s4"], C["s5"]], 0, 64)
    cloud(bg, 12, 8, 34, C["cloud"], C["cloudS"])
    cloud(bg, 70, 3, 22, C["cloud"], C["cloudS"])
    cloud(bg, 118, 12, 30, C["cloud"], C["cloudS"])
    cloud(bg, 168, 5, 18, C["cloud"], C["cloudS"])

    # Far, snow-capped range.
    peaks = [(14, 24, 1.1), (48, 34, 0.95), (84, 28, 1.0), (124, 40, 0.9), (160, 30, 1.05), (190, 22, 1.0)]
    base = 62
    for x in range(W):
        best, side, ptop = None, 0, 0
        for (px, ph, sl) in peaks:
            top = base - ph + abs(x - px) * sl
            if best is None or top < best:
                best, side, ptop = top, (1 if x > px else -1), base - ph
        top = int(best)
        for y in range(max(0, top), base + 8):
            col = C["farS"] if side > 0 else C["far"]
            if y < ptop + 9 + (x * 7 % 3):
                col = C["snowS"] if side > 0 else C["snow"]
            bg.set(x, y, col)

    # Middle range: forested ridges.
    for x in range(W):
        top = int(58 + 5 * math.sin(x / 13.0) + 3 * math.sin(x / 5.3 + 1) - 4 * math.exp(-((x - 30) / 18) ** 2))
        for y in range(top, 80):
            col = C["mid"] if y < top + 3 else (C["forestL"] if noise(x, y, 1) < 0.18 else C["forest"])
            if math.sin(x / 13.0) > 0.6 and y < top + 6: col = C["midS"]
            bg.set(x, y, col)
        if x % 4 == 0:                                                         # tiny pines on the ridge
            bg.set(x, top - 1, C["pine"]); bg.set(x, top - 2, C["pine"]); bg.set(x - 1, top, C["pine"]); bg.set(x + 1, top, C["pine"])

    # Rolling hills and the meadow.
    def hill_top(x):
        return 70 + 4 * math.sin(x / 17.0 + 0.5) + 2 * math.sin(x / 7.0)
    for x in range(W):
        top = int(hill_top(x))
        for y in range(top, H):
            col = C["hill"]
            if y < top + 1: col = C["hillL"]
            elif y > 84: col = C["meadowD"] if noise(x, y, 2) < 0.08 else C["meadow"]
            elif noise(x, y, 3) < 0.1: col = C["hillD"]
            bg.set(x, y, col)

    # The river: from a gap in the ridge, winding down and widening towards the viewer.
    river_rows = {}
    for y in range(60, H):
        k = (y - 60) / (H - 60)
        cx = 96 - 40 * k + 9 * math.sin((y - 60) / 7.0)
        half = 1 + 22 * k ** 1.6
        x0, x1 = int(cx - half), int(cx + half)
        river_rows[y] = (x0, x1)
        for x in range(x0, x1 + 1):
            bg.set(x, y, C["river"] if (x - x0) > 1 and (x1 - x) > 1 else C["riverL"])
        if y > 74:
            bg.set(x0 - 1, y, C["bank"]); bg.set(x1 + 1, y, C["bank"])
            if y > 90: bg.set(x0 - 2, y, C["bank"]); bg.set(x1 + 2, y, C["bank"])

    # Trees on the hills: pines and blossoming cherries.
    def pine(x, y, h):
        for j in range(h):
            w = (j * 2) // 3
            for i in range(-w, w + 1):
                bg.set(x + i, y + j, C["pine"] if i < 0 or j % 3 == 2 else C["pineL"])
        bg.set(x, y + h, C["trunk"])

    def cherry(x, y, r):
        bg.rect(x, y, 1, r + 3, C["trunk"])
        bg.disc(x, y - 1, r, r * 0.8, C["sak"])
        for i in range(-r, r + 1, 2):
            bg.set(x + i, y - 1 + (i % 3) - 1, C["sakD"])
    for (x, y, h) in [(8, 64, 6), (14, 66, 5), (164, 63, 7), (172, 65, 5), (56, 66, 4), (140, 67, 5)]:
        pine(x, y, h)
    for (x, y, r) in [(30, 69, 4), (44, 71, 3), (122, 70, 4), (180, 71, 3), (152, 72, 3)]:
        cherry(x, y, r)

    # Spring flowers across the meadow (positions fixed; heads sway in the loop).
    rnd = random.Random(11)
    flowers = []
    for _ in range(150):
        x, y = rnd.randint(0, W - 1), rnd.randint(78, H - 2)
        x0, x1 = river_rows.get(y, (999, -1))
        if x0 - 3 <= x <= x1 + 3: continue
        if 132 <= x <= 176 and y >= 74: continue                                # leave room for the boy
        flowers.append((x, y, rnd.choice(["f1", "f2", "f3", "f4", "f5", "f1", "f2"]), rnd.random(), y > 94))
    for (x, y, *_ ) in flowers:
        bg.set(x, y + 1, C["stem"])

    # The boy's grassy knoll and rock.
    bg.disc(154, 101, 26, 9, C["hill"])
    bg.disc(154, 100, 24, 3, C["hillL"])
    bg.disc(155, 89, 10, 9, C["rock"]); bg.disc(158, 93, 7, 5, C["rockS"])
    bg.set(150, 83, C["snow"]); bg.set(151, 82, C["snow"])

    # The boy, sitting on the rock looking out over the valley (facing left).
    # Side view, sitting on a boulder and facing left over the valley. The head is separate so it
    # can nod; the headphone band and cup are part of it.
    head = [
        "....kkkPkkk...",
        "..kkhhhhPhhkk.",
        ".khhhhhhhPhhhk",
        ".khhhhhhhPhhhk",
        "khhhhhhhPPPPhk",
        "kssshhhhPPPPPk",
        "ksksshhhPPPPPk",
        "kssssshhhPPPk.",
        ".ksssssshhhhk.",
        "..kssssssshk..",
        "...kkkkkkkk...",
    ]
    body = [
        ".......kssk.......",
        ".....kkoooookk....",
        "....koooooooooOk..",
        "....kooooooooOOk..",
        "....kOoooooooOOk..",
        "....kOoooooooOOk..",
        "....kSOkooooOOOk..",
        "...kSSkoooooOOOk..",
        ".kkSSkoooooOOOk...",
        "kWWWWkkkkkkkkkk...",
        "kWTTWkjjjjjjjJJk..",
        "kWWWWkjjjjjjJJJJk.",
        ".kkkkjjjjjjjjJJJk.",
        ".kjjjjjkkkkkkkkk..",
        ".kjjjk............",
        ".kjjjk............",
        ".kjjjk............",
        ".kjjjk............",
        "kwwwwwk...........",
        "krrrrrk...........",
    ]
    bkey = {"k": C["ink"], "j": C["jeans"], "J": C["jeansS"], "w": C["shoe"], "r": C["sole"], "S": C["jeans"],
            "o": C["shirt"], "O": C["shirtS"], "W": C["walk"], "T": C["tape"], "h": C["hair"], "s": C["skin"],
            "P": C["phones"]}

    birds = [(60, 22, 14, 0.0), (74, 18, 10, 0.4)]
    flies = [(110, 92, 0.0, "fly"), (36, 96, 0.5, "f4")]
    frames = []
    for t in range(FRAMES):
        cv = bg.copy()
        ph = 2 * math.pi * t / FRAMES

        # River sparkles travel downstream (period FRAMES rows, so the loop is seamless).
        for y, (x0, x1) in river_rows.items():
            for x in range(x0 + 1, x1):
                band = (y - t) % FRAMES
                if (x * 5 + band * 11) % 41 == 0:
                    cv.set(x, y, C["riverS"])
                elif (x * 3 + band * 7) % 29 == 0:
                    cv.set(x, y, C["riverL"])

        # Flowers sway in the breeze.
        for (x, y, col, p, big) in flowers:
            off = 1 if math.sin(ph + p * 6.28 + x * 0.08) > 0.55 else 0
            cv.set(x + off, y, C[col])
            if big:
                cv.set(x + off - 1, y, C[col]); cv.set(x + off + 1, y, C[col]); cv.set(x + off, y - 1, C[col])
                cv.set(x + off, y, C["f2"] if col != "f2" else C["f5"])

        # Birds wheel in a circle, flapping.
        for (cx, cy, r, p) in birds:
            a = ph + p * 6.28
            bx, by = cx + r * math.cos(a), cy + r * 0.45 * math.sin(a)
            up = (t // 2) % 2 == 0
            cv.set(bx, by, C["bird"])
            cv.set(bx - 1, by - (1 if up else 0), C["bird"]); cv.set(bx + 1, by - (1 if up else 0), C["bird"])
            cv.set(bx - 2, by - (1 if up else -1), C["bird"]); cv.set(bx + 2, by - (1 if up else -1), C["bird"])

        # Butterflies flutter around the flowers.
        for (cx, cy, p, col) in flies:
            a = ph + p * 6.28
            fx, fy = cx + 8 * math.sin(a), cy + 3 * math.sin(2 * a)
            cv.set(fx, fy, C["ink"])
            if t % 2 == 0:
                cv.set(fx - 1, fy - 1, C[col]); cv.set(fx + 1, fy - 1, C[col])
                cv.set(fx - 1, fy, C[col]); cv.set(fx + 1, fy, C[col])
            else:
                cv.set(fx - 1, fy, C[col]); cv.set(fx + 1, fy, C[col])

        # The boy nods along to the beat (down on beats 2 and 4 of each bar of four frames).
        bob = 1 if t % 4 in (1, 2) else 0
        BX, BY = 142, 66
        cv.stamp(body, BX, BY + 11, bkey)
        cv.stamp(head, BX + 1, BY + bob, bkey)
        # The cord from the headphone cup down to the cassette player in his lap.
        cv.line(BX + 12, BY + 8 + bob, BX + 12, BY + 13, C["ink"])
        cv.line(BX + 12, BY + 13, BX + 5, BY + 20, C["ink"])
        # A foot taps on the beat.
        if t % 4 in (1, 2):
            cv.rect(BX, BY + 29, 7, 1, C["hillL"]); cv.rect(BX + 1, BY + 28, 6, 1, C["shoe"])

        # Music notes float up from the headphones and drift away.
        for k in range(3):
            f = (t / FRAMES + k / 3) % 1
            nx = BX - 2 - f * 14 + 2 * math.sin(f * 6.28 * 1.5)
            ny = BY + 4 - f * 26
            if f < 0.9:
                col = C["note"] if f < 0.6 else C["noteS"]
                if k % 2 == 0:   # ♪
                    cv.rect(int(nx), int(ny), 2, 2, col); cv.rect(int(nx) + 1, int(ny) - 4, 1, 4, col); cv.set(int(nx) + 2, int(ny) - 4, col); cv.set(int(nx) + 3, int(ny) - 3, col)
                else:            # ♫
                    cv.rect(int(nx), int(ny), 2, 2, col); cv.rect(int(nx) + 4, int(ny) - 1, 2, 2, col)
                    cv.rect(int(nx) + 1, int(ny) - 4, 1, 4, col); cv.rect(int(nx) + 5, int(ny) - 5, 1, 4, col)
                    cv.rect(int(nx) + 1, int(ny) - 5, 5, 1, col)

        frames.append(cv)
    return dict(w=W, h=H, fps=FPS, label="Boy with a cassette player above a spring valley", frames=frames)


# ---------------------------------------------------------------------------------------------

CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&*+-/:;<=>?@^_~"


def encode(scenes):
    """Each scene gets its own palette (`pal` inside the sprite)."""
    out, counts = {}, []
    for name, s in scenes.items():
        colors = []
        for f in s["frames"]:
            for row in f.px:
                for c in row:
                    if c and c.upper() not in colors:
                        colors.append(c.upper())
        assert len(colors) <= len(CHARS), f"{name}: {len(colors)} colours is more than the format holds"
        key = {c: CHARS[i] for i, c in enumerate(colors)}
        out[name] = {
            "w": s["w"], "h": s["h"], "fps": s["fps"], "label": s["label"],
            "pal": {CHARS[i]: c for i, c in enumerate(colors)},
            "frames": [["".join(key[c.upper()] if c else "." for c in row) for row in f.px] for f in s["frames"]],
        }
        counts.append(len(colors))
    return out, counts


def preview(scenes, folder):
    from PIL import Image
    os.makedirs(folder, exist_ok=True)
    for name, s in scenes.items():
        scale = 4
        for i in (0, 5):
            img = Image.new("RGBA", (s["w"], s["h"]), (0, 0, 0, 0))
            for y, row in enumerate(s["frames"][i].px):
                for x, c in enumerate(row):
                    if c: img.putpixel((x, y), tuple(int(c[k:k + 2], 16) for k in (1, 3, 5)) + (255,))
            img.resize((s["w"] * scale, s["h"] * scale), Image.NEAREST).save(os.path.join(folder, f"{name}_{i}.png"))
        # Animated GIF of the loop.
        gif = []
        for f in s["frames"]:
            img = Image.new("RGB", (s["w"], s["h"]), (18, 14, 31))
            for y, row in enumerate(f.px):
                for x, c in enumerate(row):
                    if c: img.putpixel((x, y), tuple(int(c[k:k + 2], 16) for k in (1, 3, 5)))
            gif.append(img.resize((s["w"] * 3, s["h"] * 3), Image.NEAREST))
        gif[0].save(os.path.join(folder, f"{name}.gif"), save_all=True, append_images=gif[1:], duration=1000 // s["fps"], loop=0)


if __name__ == "__main__":
    scenes = {"highstreet": highstreet(), "valley": landscape()}
    data, n = encode(scenes)
    with open(OUT, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print(f"wrote {OUT} ({os.path.getsize(OUT) // 1024} KB, {n} colours)")
    if "--preview" in sys.argv:
        preview(scenes, sys.argv[sys.argv.index("--preview") + 1])
