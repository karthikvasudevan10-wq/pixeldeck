"""Artwork for the Pixel Deck v2 design canvas. Everything is generated here so it is original."""
import json, math, random, os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), 'out') + '/'
os.makedirs(OUT, exist_ok=True)
SP = json.load(open(os.path.join(os.path.dirname(__file__), 'sprites.json')))
PAL = SP.pop('pal')

def hx(h, a=255):
    h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)

def up(im, s): return im.resize((im.width * s, im.height * s), Image.NEAREST)

def sprite_img(name, fi=0):
    S = SP[name]; f = S['frames'][fi]
    im = Image.new('RGBA', (S['w'], S['h']), (0, 0, 0, 0))
    for y, r in enumerate(f):
        for x, c in enumerate(r):
            if c != '.': im.putpixel((x, y), hx(PAL[c]))
    return im

# ---------- 1. a "photo": dusk over a lake with a cottage (procedural, painterly) ----------
W = H = 1024
rnd = random.Random(4)
ph = Image.new('RGB', (W, H))
px = ph.load()
top, mid, low = (58, 52, 120), (236, 120, 132), (255, 196, 140)
for y in range(H):
    t = y / (H * 0.55)
    if t < 0.6: c = tuple(int(top[i] + (mid[i] - top[i]) * (t / 0.6)) for i in range(3))
    else: c = tuple(int(mid[i] + (low[i] - mid[i]) * min(1, (t - 0.6) / 0.4)) for i in range(3))
    for x in range(W): px[x, y] = c
d = ImageDraw.Draw(ph)
# sun + glow
for r, a in [(220, 30), (160, 50), (110, 90)]:
    gl = Image.new('RGBA', (W, H), (0, 0, 0, 0)); ImageDraw.Draw(gl).ellipse([620 - r, 520 - r, 620 + r, 520 + r], fill=(255, 220, 160, a))
    ph = Image.alpha_composite(ph.convert('RGBA'), gl.filter(ImageFilter.GaussianBlur(40))).convert('RGB')
d = ImageDraw.Draw(ph)
d.ellipse([570, 470, 670, 570], fill=(255, 236, 190))
# mountains, two ranges
def mountain(base, amp, col, seed):
    r = random.Random(seed); pts = [(0, H)]; y = base
    for x in range(0, W + 40, 40):
        y = max(base - amp, min(base + amp // 3, y + r.randint(-60, 55))); pts.append((x, y))
    pts.append((W, H)); d.polygon(pts, fill=col)
mountain(470, 150, (122, 86, 150), 2)
mountain(560, 90, (84, 60, 118), 9)
# lake
d.rectangle([0, 600, W, H], fill=(96, 82, 150))
for y in range(600, 760, 6):
    d.line([(560 + rnd.randint(-30, 10), y), (680 + rnd.randint(-10, 30), y)], fill=(255, 210, 170), width=3)
# far shore trees and cottage
for x in range(0, W, 26):
    h = rnd.randint(40, 90); d.polygon([(x, 600), (x + 13, 600 - h), (x + 26, 600)], fill=(46, 38, 78))
d.rectangle([180, 520, 300, 600], fill=(236, 214, 190)); d.polygon([(165, 525), (240, 465), (315, 525)], fill=(170, 70, 90))
d.rectangle([225, 555, 255, 600], fill=(90, 50, 60)); d.rectangle([195, 540, 215, 560], fill=(255, 210, 120)); d.rectangle([265, 540, 285, 560], fill=(255, 210, 120))
# foreground reeds and grass
d.rectangle([0, 900, W, H], fill=(52, 70, 70))
for i in range(160):
    x = rnd.randint(0, W); h = rnd.randint(40, 160)
    d.line([(x, H), (x + rnd.randint(-20, 20), H - 120 - h)], fill=(40 + rnd.randint(0, 30), 70 + rnd.randint(0, 40), 60), width=4)
ph = ph.filter(ImageFilter.GaussianBlur(2.2))
noise = Image.effect_noise((W, H), 18).convert('RGB')
ph = Image.blend(ph, noise, 0.06)
ph.save(OUT + 'photo.jpg', quality=88)

# ---------- 2. photo -> pixel art ----------
def pixelate(im, n, colours=None, palette=None, dither=False):
    small = im.resize((n, n), Image.BOX)
    if palette:
        pimg = Image.new('P', (1, 1)); flat = []
        for c in palette: flat += list(hx(c)[:3])
        flat += flat[:3] * (256 - len(palette)); pimg.putpalette(flat)
        q = small.quantize(palette=pimg, dither=Image.FLOYDSTEINBERG if dither else Image.NONE)
    else:
        q = small.quantize(colors=colours, method=Image.MEDIANCUT, dither=Image.NONE)
    return q.convert('RGB')

PD10 = ['#1B1530', '#FFF6E0', '#7BE07B', '#2E9E5B', '#FFD23F', '#FF8B3D', '#FF5C8A', '#C8B6FF', '#3A86FF', '#9C6B3C']
p48 = pixelate(ph, 48, colours=16); up(p48, 10).save(OUT + 'photo-px48.png'); p48.save(OUT + 'photo-px48-1x.png')
p32 = pixelate(ph, 32, colours=12); up(p32, 15).save(OUT + 'photo-px32.png')
p64 = pixelate(ph, 64, colours=24); up(p64, 8).save(OUT + 'photo-px64.png')
pd = pixelate(ph, 48, palette=PD10, dither=False); up(pd, 10).save(OUT + 'photo-px48-pd.png')
BAY = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
def lum_map(im, n, pal, dither):
    small = im.resize((n, n), Image.BOX).convert('L'); out = Image.new('RGB', (n, n)); k = len(pal) - 1
    lo, hi = min(small.getdata()), max(small.getdata())
    for y in range(n):
        for x in range(n):
            v = (small.getpixel((x, y)) - lo) / max(1, hi - lo) * k
            b = (BAY[y % 4][x % 4] + 0.5) / 16 if dither else 0.5
            i = min(k, int(v) + (1 if v - int(v) > b else 0))
            out.putpixel((x, y), hx(pal[i])[:3])
    return out

# ---------- 3. retro modes from the same picture ----------
retro = {
    'retro-1bit': ['#120E1F', '#FFF6E0'],
    'retro-green': ['#0F2A12', '#2F5A2B', '#8BB33A', '#C9E07A'],
    'retro-ink': ['#141414', '#5A5A5A', '#A8A8A8', '#F2F0E8'],
    'retro-8': ['#000000', '#1D2B8F', '#B2213A', '#7E2553', '#1E8C4E', '#29ADFF', '#FFCC33', '#FFF1E8'],
}
for k, pal in retro.items():
    if k == 'retro-8': img = pixelate(ph, 48, palette=pal, dither=False)
    else: img = lum_map(ph, 48, pal, dither=(k == 'retro-1bit'))
    up(img, 10).save(OUT + k + '.png')

# ---------- 4. tiles and a level ----------
T = 16
TP = {'grass': '#5BC067', 'grassD': '#2E8B57', 'dirt': '#8A5A3C', 'dirtD': '#5E3B22', 'stone': '#6E6A8E', 'stoneD': '#47425F', 'stoneL': '#9A95B8',
      'water': '#3A86FF', 'waterL': '#8FC4FF', 'wood': '#9C6B3C', 'leaf': '#2E9E5B', 'leafL': '#7BE07B', 'cream': '#FFF6E0', 'pink': '#FF5C8A', 'yellow': '#FFD23F', 'ink': '#1B1530'}
def tile(kind, seed=0):
    r = random.Random(seed); im = Image.new('RGBA', (T, T), (0, 0, 0, 0)); p = im.load()
    def P(x, y, c): p[x, y] = hx(TP[c])
    if kind in ('grasstop', 'dirt'):
        for y in range(T):
            for x in range(T): P(x, y, 'dirt' if (x * 7 + y * 3 + seed) % 11 else 'dirtD')
        if kind == 'grasstop':
            for x in range(T):
                h = 4 + (1 if (x * 5 + seed) % 3 == 0 else 0)
                for y in range(h): P(x, y, 'grass' if y < h - 1 else 'grassD')
    elif kind == 'brick':
        for y in range(T):
            for x in range(T):
                row = y // 4; off = 4 if row % 2 else 0
                P(x, y, 'stoneD' if y % 4 == 3 or (x + off) % 8 == 7 else ('stoneL' if y % 4 == 0 else 'stone'))
    elif kind == 'water':
        for y in range(T):
            for x in range(T): P(x, y, 'waterL' if (y == 2 and (x + seed) % 6 < 3) or (y == 9 and (x + seed + 3) % 7 < 2) else 'water')
    elif kind == 'block':
        for y in range(T):
            for x in range(T):
                edge = x in (0, T - 1) or y in (0, T - 1)
                P(x, y, 'ink' if edge else 'yellow')
        for (x, y) in [(6, 4), (7, 4), (8, 4), (9, 5), (9, 6), (8, 7), (7, 8), (7, 9), (7, 11)]: P(x, y, 'cream')
    elif kind == 'tree':
        for y in range(10, T):
            for x in (7, 8): P(x, y, 'wood')
        for y in range(1, 11):
            for x in range(T):
                if (x - 7.5) ** 2 / 36 + (y - 5.5) ** 2 / 22 < 1: P(x, y, 'leafL' if (x + y) % 5 == 0 or (x < 7 and y < 5) else 'leaf')
    elif kind == 'flower':
        for y in range(9, T): P(8, y, 'leaf')
        P(7, 12, 'leafL'); P(9, 11, 'leafL')
        for (x, y) in [(8, 6), (7, 7), (9, 7), (8, 8)]: P(x, y, 'pink')
        P(8, 7, 'yellow')
    elif kind == 'cloud':
        for y in range(4, 13):
            for x in range(T):
                if (x - 5) ** 2 / 20 + (y - 8) ** 2 / 10 < 1 or (x - 10) ** 2 / 20 + (y - 7) ** 2 / 12 < 1: P(x, y, 'cream')
    return im
tiles = [('grasstop', 1), ('dirt', 2), ('brick', 3), ('water', 4), ('block', 5), ('tree', 6), ('flower', 7), ('cloud', 8)]
sheet = Image.new('RGBA', (T * 4 + 3 * 2, T * 2 + 2), (0, 0, 0, 0))
for i, (k, s) in enumerate(tiles):
    sheet.paste(tile(k, s), ((i % 4) * (T + 2), (i // 4) * (T + 2)))
up(sheet, 6).save(OUT + 'tileset.png')
for k, s in tiles: up(tile(k, s), 6).save(OUT + f'tile-{k}.png')

LV = ['........................',
      '...c..........c.........',
      '.............c......c...',
      '..........$.$...........',
      '.........BBBBB..........',
      '....$...................',
      '...BBB.........T.....f..',
      '.....................GGG',
      '..T....f.....GGGGG..Gdd.',
      'GGGGGGGGG..GGddddd..Gddd',
      'dddddddddwwddddddd~~dddd',
      'dddddddddwwddddddd~~dddd']
def level(day=False, hero=True):
    w, h = len(LV[0]), len(LV)
    im = Image.new('RGBA', (w * T, h * T), hx('#2B2050') if not day else hx('#8FC4FF'))
    dr = ImageDraw.Draw(im)
    # sky bands
    bands = ['#1A1430', '#211A3D', '#2B2050'] if not day else ['#6FB2FF', '#8FC4FF', '#B4D8FF']
    for i, c in enumerate(bands): dr.rectangle([0, i * h * T // 6, w * T, (i + 1) * h * T // 6], fill=hx(c))
    rr = random.Random(2)
    if not day:
        for i in range(40):
            x, y = rr.randrange(0, w * T), rr.randrange(0, h * T // 2); im.putpixel((x, y), hx('#FFF6E0'))
    for y, row in enumerate(LV):
        for x, ch in enumerate(row):
            k = {'G': 'grasstop', 'd': 'dirt', 'B': 'brick', 'w': 'water', '~': 'water', 'T': 'tree', 'f': 'flower', 'c': 'cloud'}.get(ch)
            if k: im.alpha_composite(tile(k, x + y), (x * T, y * T))
            if ch == '$':
                c = sprite_img('coin', 0); im.alpha_composite(c, (x * T + 4, y * T + 4))
    if hero:
        s = sprite_img('slime', 0); s = s.crop(s.getbbox()); im.alpha_composite(s, (2 * T + 2, 9 * T - s.height))
    # flag
    dr.line([(22 * T + 8, 7 * T), (22 * T + 8, 5 * T - 6)], fill=hx('#FFF6E0'), width=2)
    dr.polygon([(22 * T + 9, 5 * T - 6), (22 * T + 18, 5 * T - 2), (22 * T + 9, 5 * T + 2)], fill=hx('#FF5C8A'))
    return im
lvl = level(); up(lvl, 3).save(OUT + 'level.png'); up(lvl, 2).save(OUT + 'level-2x.png')
up(level(day=True), 3).save(OUT + 'level-day.png')

# ---------- 5. shading: pillow vs light from top-left ----------
def sphere(mode):
    n = 20; im = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    ramp = ['#2A1B5C', '#4B2E8A', '#7A4FC4', '#A98BF0', '#E2D6FF']
    for y in range(n):
        for x in range(n):
            dx, dy = x - 9.5, y - 9.5
            if dx * dx + dy * dy > 81: continue
            if mode == 'pillow':
                dd = math.hypot(dx, dy) / 9; i = 4 - min(4, int(dd * 4.3))
            else:
                l = (-(dx) * 0.6 - dy * 0.75) / 9 + 0.15; i = max(0, min(4, int((l + 1) * 2.4)))
            im.putpixel((x, y), hx(ramp[i]))
    for y in range(n):
        for x in range(n):
            if im.getpixel((x, y))[3] == 0 and any(0 <= x + a < n and 0 <= y + b < n and im.getpixel((x + a, y + b))[3] and im.getpixel((x + a, y + b))[:3] != hx('#1B1530')[:3] for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                im.putpixel((x, y), hx('#1B1530'))
    return im
up(sphere('pillow'), 12).save(OUT + 'shade-pillow.png'); up(sphere('light'), 12).save(OUT + 'shade-light.png')

# ---------- 6. pixel-perfect strokes ----------
def stroke(clean):
    n = 22; im = Image.new('RGBA', (n, n), (0, 0, 0, 0)); pts = []
    for i in range(2000):
        a = math.pi * (0.04 + 0.92 * i / 2000)
        x = int(round(10.5 - 8.5 * math.cos(a))); y = int(round(19 - 15 * math.sin(a)))
        if not pts or pts[-1] != (x, y): pts.append((x, y))
    # make it strictly 8-connected without corner doubles
    clean_pts = []
    for p in pts:
        if len(clean_pts) >= 2:
            a, b = clean_pts[-2], clean_pts[-1]
            if abs(a[0] - p[0]) <= 1 and abs(a[1] - p[1]) <= 1: clean_pts[-1] = p; continue
        clean_pts.append(p)
    out = list(clean_pts)
    if not clean:
        out = []
        for i, p in enumerate(clean_pts):
            if i and abs(p[0] - clean_pts[i - 1][0]) == 1 and abs(p[1] - clean_pts[i - 1][1]) == 1 and i % 2 == 0:
                out.append((p[0], clean_pts[i - 1][1]))
            out.append(p)
    for x, y in out:
        if 0 <= x < n and 0 <= y < n: im.putpixel((x, y), hx('#FF5C8A'))
    return im
for k, c in (('raw', False), ('clean', True)):
    s = up(stroke(c), 14); d2 = ImageDraw.Draw(s)
    for i in range(0, s.width, 14): d2.line([(i, 0), (i, s.height)], fill=(255, 255, 255, 18)); d2.line([(0, i), (s.width, i)], fill=(255, 255, 255, 18))
    s.save(OUT + f'stroke-{k}.png')

# ---------- 7. bead pattern ----------
sl = sprite_img('slime', 0); sl = sl.crop(sl.getbbox())
cell = 34; bw, bh = sl.width, sl.height
bead = Image.new('RGBA', (bw * cell + 2, bh * cell + 2), hx('#FFFDF8'))
db = ImageDraw.Draw(bead)
for y in range(bh):
    for x in range(bw):
        c = sl.getpixel((x, y))
        x0, y0 = x * cell + 1, y * cell + 1
        db.rectangle([x0, y0, x0 + cell, y0 + cell], outline=hx('#E2D9C8'))
        if c[3]:
            db.ellipse([x0 + 3, y0 + 3, x0 + cell - 3, y0 + cell - 3], fill=c)
            db.ellipse([x0 + 12, y0 + 12, x0 + cell - 12, y0 + cell - 12], fill=hx('#FFFDF8'))
for i in range(0, bw + 1, 5): db.line([(i * cell + 1, 0), (i * cell + 1, bead.height)], fill=hx('#6B6256'), width=2)
for i in range(0, bh + 1, 5): db.line([(0, i * cell + 1), (bead.width, i * cell + 1)], fill=hx('#6B6256'), width=2)
bead.save(OUT + 'bead-slime.png')
counts = {}
for y in range(bh):
    for x in range(bw):
        c = sl.getpixel((x, y))
        if c[3]: counts['#%02X%02X%02X' % c[:3]] = counts.get('#%02X%02X%02X' % c[:3], 0) + 1
json.dump(counts, open(OUT + 'bead-counts.json', 'w'))

# ---------- 8. stamps ----------
STAMPS = {
    'eye': ['.kkkk.', 'kwwwwk', 'kwkkwk', 'kwkkwk', 'kwwwwk', '.kkkk.'],
    'star': ['...y...', '...y...', '.yyyyy.', 'yyyyyyy', '.yyyyy.', '.yy.yy.', 'y.....y'],
    'mushroom': ['..pppp..', '.pwppwp.', 'pppppppp', 'pwpppppw', '..wwww..', '..wkkw..', '..wwww..'],
    'bush': ['..dd.dd..', '.dggdggd.', 'dggggggd.', 'dgglggggd', 'ddggggdd.'],
    'heart': ['.pp.pp.', 'pwpppp.', 'ppppppp', '.ppppp.', '..ppp..', '...p...'],
    'sign': ['uuuuuuu', 'uwwwwwu', 'uwkkkwu', 'uwwwwwu', 'uuuuuuu', '...u...', '...u...'],
}
SPAL = {'k': '#1B1530', 'w': '#FFF6E0', 'y': '#FFD23F', 'p': '#FF5C8A', 'g': '#7BE07B', 'd': '#2E9E5B', 'l': '#C8F5C8', 'u': '#9C6B3C'}
for k, rows in STAMPS.items():
    w = max(len(r) for r in rows); im = Image.new('RGBA', (w, len(rows)), (0, 0, 0, 0))
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != '.': im.putpixel((x, y), hx(SPAL[ch]))
    up(im, 8).save(OUT + f'stamp-{k}.png')
up(tile('tree', 6), 4).save(OUT + 'stamp-tree.png'); up(tile('cloud', 8), 4).save(OUT + 'stamp-cloud.png')

# ---------- 9. colour adjust: slime hue shift ----------
import colorsys
def shift(im, dh=0, dl=0, ds=0):
    o = im.copy(); p = o.load()
    for y in range(o.height):
        for x in range(o.width):
            r, g, b, a = p[x, y]
            if not a: continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if s < 0.15: continue
            r2, g2, b2 = colorsys.hls_to_rgb((h + dh) % 1, max(0, min(1, l + dl)), max(0, min(1, s + ds)))
            p[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return o
up(sl, 20).save(OUT + 'slime-before.png'); up(shift(sl, dh=0.55, dl=0.02), 20).save(OUT + 'slime-after.png')

# ---------- 10. a castle drawn "by an assistant" (for the Mac AI board), half finished ----------
cast = Image.new('RGBA', (40, 32), (0, 0, 0, 0)); cp = ImageDraw.Draw(cast)
cp.rectangle([6, 14, 33, 31], fill=hx('#6E6A8E')); cp.rectangle([4, 8, 11, 31], fill=hx('#9A95B8')); cp.rectangle([28, 8, 35, 31], fill=hx('#9A95B8'))
for x in range(4, 12, 2): cp.rectangle([x, 6, x, 7], fill=hx('#9A95B8'))
for x in range(28, 36, 2): cp.rectangle([x, 6, x, 7], fill=hx('#9A95B8'))
cp.rectangle([16, 22, 23, 31], fill=hx('#1B1530')); cp.rectangle([7, 12, 8, 14], fill=hx('#FFD23F')); cp.rectangle([31, 12, 32, 14], fill=hx('#FFD23F'))
cp.line([(7, 0), (7, 5)], fill=hx('#FFF6E0')); cp.polygon([(8, 0), (12, 2), (8, 4)], fill=hx('#FF5C8A'))
cast.save(OUT + 'castle-1x.png'); up(cast, 12).save(OUT + 'castle.png')
part = cast.copy(); pp = ImageDraw.Draw(part); pp.rectangle([20, 0, 40, 32], fill=(0, 0, 0, 0)); up(part, 12).save(OUT + 'castle-half.png')
print('ok', len(os.listdir(OUT)))
