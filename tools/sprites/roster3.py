"""Gremlo 1.0, round three: the closet and the hatch.

Builds on roster2.py (which builds on roster.py) without editing either.
  * six new accessories: bow, flower crown, scarf, shades, cap, star clip
  * row 29 'wardrobe2': the six new accessories on the idle pose
  * row 30 'hatch': 8-frame hatching sequence (rest, wobble, wobble, crack,
    crack, glow, burst, hello)
  * accessories.png: every accessory (12) as an overlay per species, so the
    app can layer any of them on any upright frame
  * pet.json v5: headAnchor per frame, accessory strip metadata

Outputs packs3/<id>/ : spritesheet.webp/.png (31 rows), ext2.png (rows 29-30),
signkit.png, accessories.png, pet.json
"""
import importlib.util, sys, os, json
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('roster2', os.path.join(HERE, 'roster2.py'))
R2 = importlib.util.module_from_spec(spec)
sys.modules['roster2'] = R2
spec.loader.exec_module(R2)
R = R2.R
Body, SPECIES, CX, H = R.Body, R.SPECIES, R.CX, R.H
CW, CH, COLS, SCALE, BASE = 192, 208, 8, 7, 194

ACCESSORIES = ['beanie', 'crown', 'headphones', 'party', 'wizard', 'glasses',
               'bow', 'flower', 'scarf', 'shades', 'cap', 'star']

# ------------------------------------------------------- new accessories ---
_orig_hat = Body.hat


def hat(self, kind):
    if kind in ('beanie', 'crown', 'headphones', 'party', 'wizard', 'glasses'):
        return _orig_hat(self, kind)
    t, c = self.headtop()
    if kind == 'bow':
        self.rect(c + 2, t - 3, c + 4, t - 1, 'n'); self.put(c + 3, t - 4, 'n'); self.put(c + 3, t, 'n')
        self.rect(c + 6, t - 3, c + 8, t - 1, 'n'); self.put(c + 7, t - 4, 'n'); self.put(c + 7, t, 'n')
        self.rect(c + 5, t - 2, c + 5, t - 2, 'm')
    elif kind == 'flower':
        for i, x in enumerate(range(c - 6, c + 7, 4)):
            col = ('n', 'v', 't', 'n')[i % 4]
            self.put(x, t - 2, col); self.put(x - 1, t - 1, col); self.put(x + 1, t - 1, col); self.put(x, t, col)
            self.put(x, t - 1, 'v' if col != 'v' else 'u')
            if x + 2 <= c + 6:
                self.put(x + 2, t, 'g')
    elif kind == 'scarf':
        y = self.row(self.sp['mouth_f']) + 3
        sp = self.spans.get(y) or self.spans.get(y - 1)
        if sp:
            l, r = sp
            self.rect(l, y, r, y + 1, 'n')
            for x in range(l + 1, r, 3):
                self.put(x, y, 'u')
            self.rect(r - 3, y + 2, r - 2, y + 5, 'n'); self.put(r - 3, y + 5, 'u')
    elif kind == 'shades':
        ey = self.row(self.sp['eye_f'])
        ec = self.centre(ey)
        dx = self.sp['eye_dx']
        for sx in (-dx - 1, dx - 3):
            x = ec + sx
            self.rect(x, ey - 1, x + 4, ey + 3, 'k')
            self.put(x + 1, ey, 't')
        self.rect(ec - dx + 4, ey, ec + dx - 4, ey, 'k')
    elif kind == 'cap':
        for i, w in enumerate((4, 6, 7)):
            self.rect(c - w, t - 2 + i, c + w, t - 2 + i, 'm')
        self.rect(c + 3, t + 1, c + 10, t + 1, 'm')
        self.put(c - 1, t - 1, 'v'); self.put(c, t - 1, 'v')
    elif kind == 'star':
        x, y = c - 5, t - 1
        for (a, b) in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0), (0, -2)):
            self.put(x + a, y + b, 'v')
        self.put(x, y, 'u')
    return self


Body.hat = hat

# make2 doesn't take a hat; add it by wrapping Body.outline (hats go under the outline)
HAT_NEXT = [None]
_orig_outline = Body.outline


def outline(self, *a, **k):
    if HAT_NEXT[0]:
        self.hat(HAT_NEXT[0])
    return _orig_outline(self, *a, **k)


Body.outline = outline


def with_hat(key, kind, **kw):
    HAT_NEXT[0] = kind
    try:
        return R2.make2(key, **kw)
    finally:
        HAT_NEXT[0] = None

# ----------------------------------------------------------------- hatch ---

def shear(g, k):
    if not g:
        return g
    yb = max(y for (x, y) in g)
    return {(x + int(round((yb - y) * k)), y): c for (x, y), c in g.items()}


def crack(g, level):
    g = dict(g)
    path = [(CX - 4, 17), (CX - 3, 16), (CX - 2, 17), (CX - 1, 16), (CX, 17), (CX + 1, 16), (CX + 2, 17)]
    if level >= 1:
        for p in path[:3]:
            if p in g:
                g[p] = 'e'
    if level >= 2:
        for p in path + [(CX + 3, 16), (CX + 4, 17), (CX - 5, 16), (CX - 1, 18), (CX - 1, 19)]:
            if p in g:
                g[p] = 'e'
    return g


def glow(g, phase=0):
    g = dict(g)
    pts = ((CX - 11, 13), (CX + 11, 15), (CX - 9, 24), (CX + 10, 25), (CX, 7)) if phase == 0 else \
          ((CX - 10, 10), (CX + 12, 11), (CX - 12, 20), (CX + 9, 21), (CX + 2, 6))
    for (x, y) in pts:
        for (a, b) in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
            g.setdefault((x + a, y + b), 'y')
    return g


def burst(key):
    g, _ = R.make_egg(key, 2)
    out = {(x, y): c for (x, y), c in g.items() if y >= 15}
    # two shell pieces flying up and out
    for (ox, oy, d) in ((CX - 9, 7, -1), (CX + 6, 6, 1)):
        piece = [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (3, 1)]
        for (a, b) in piece:
            out[(ox + a * 1, oy + b)] = 'u'
        for (a, b) in piece:
            for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (ox + a + dx, oy + b + dy)
                if n not in out:
                    out[n] = 'o'
    # the head coming out
    head = {(x, y): c for (x, y), c in g.items() if y < 15 and c != 'o'}
    out.update({(x, y - 2): c for (x, y), c in head.items()})
    return glow(out, 1)


def hatch_row(key):
    e0, _ = R.make_egg(key, 0)
    e1, _ = R.make_egg(key, 1)
    hl, _ = R.hatchling(key, 'wide')
    return [e0, shear(e0, -0.18), shear(e0, 0.18), crack(shear(e0, -0.1), 1), crack(e0, 2),
            glow(e1, 0), burst(key), hl]

# --------------------------------------------------------------- render ---

def headtop_of(g):
    ys = [y for (x, y), c in g.items() if c in ('c', 's')]
    if not ys:
        return None
    t = min(ys)
    xs = [x for (x, y), c in g.items() if y == t and c in ('c', 's')]
    return t, (min(xs) + max(xs)) // 2


NO_HATS = {2, 12, 14, 19, 22, 30}   # rotated, egg, notch peek, edge peek, thrown, hatch


def accessory_strip(key):
    """12 cells of 40 x 40 units; anchor (20, 12) = the head-top centre of the idle pose."""
    sp = SPECIES[key]
    pal = R.palette(sp)
    base = R2.make2(key, mo='flat')
    t, c = headtop_of(base)
    W, Hh, AX, AY = 40, 40, 20, 12
    img = Image.new('RGBA', (W * len(ACCESSORIES), Hh), (0, 0, 0, 0))
    px = img.load()
    for i, a in enumerate(ACCESSORIES):
        g = with_hat(key, a, mo='flat')
        for (x, y), col in g.items():
            if base.get((x, y)) != col and col != 'z':
                X, Y = AX + (x - c), AY + (y - t)
                if 0 <= X < W and 0 <= Y < Hh:
                    px[i * W + X, Y] = pal[col]
    return img, {'names': ACCESSORIES, 'cell': [W, Hh], 'anchor': [AX, AY], 'unitsPerPixel': 1,
                 'note': 'scale by the frame\'s sprite unit (7 px at full size) and put anchor on headAnchor'}


def build3(key):
    main, extra = R2.build2(key)
    acc_row = [(with_hat(key, a, **kw), 0, 'feet') for a, kw in
               (('bow', dict(eye='happy', cheek=True)), ('flower', dict(eye='closed', mo='smile')),
                ('scarf', dict()), ('shades', dict(mo='grin')), ('cap', dict(eye='look')),
                ('star', dict(eye='happy', mo='smile', cheek=True)))]
    hatch = [(g, 0, 'feet') for g in hatch_row(key)]
    return main + extra + [acc_row, hatch]


NAMES = R2.ALL_NAMES + ['wardrobe2', 'hatch']


def render(key, outdir):
    sp = SPECIES[key]
    pal = R.palette(sp)
    rows = build3(key)
    full = Image.new('RGBA', (COLS * CW, len(rows) * CH), (0, 0, 0, 0))
    sign, plate, heads = [], [], []
    for r, row in enumerate(rows):
        hr = []
        for c, (g, lift, anchor) in enumerate(row):
            place = R2.paste(full, g, c, r, pal, lift, anchor)
            if r == 6:
                sign.append(R2.rect_of(g, place))
            if r == 28 and place:
                plate.append([CW // 2, place[1] + R2.ANCH[id(g)] * place[2]])
            ht = headtop_of(g) if r not in NO_HATS else None
            if ht and place:
                ox, oy, s = place
                hr.append([ox + ht[1] * s + s // 2, oy + ht[0] * s, s])
            else:
                hr.append(None)
        heads.append(hr)
    d = os.path.join(outdir, 'gremlo' if key == 'gremlo' else f'gremlo-{key}')
    os.makedirs(d, exist_ok=True)
    full.save(os.path.join(d, 'spritesheet.webp'), 'WEBP', lossless=True, quality=100)
    full.save(os.path.join(d, 'spritesheet.png'))
    full.crop((0, 29 * CH, COLS * CW, 31 * CH)).save(os.path.join(d, 'ext2.png'))
    R2.signkit(key).save(os.path.join(d, 'signkit.png'))
    acc, accmeta = accessory_strip(key)
    acc.save(os.path.join(d, 'accessories.png'))
    json.dump({
        'id': os.path.basename(d), 'displayName': sp['name'], 'description': sp['line'],
        'spriteVersionNumber': 5, 'spritesheetPath': 'spritesheet.webp',
        'gremlo': {
            'species': key, 'accent': '#' + sp['accent'], 'cell': [CW, CH], 'columns': COLS,
            'rows': {n: {'row': i, 'frames': len(rows[i])} for i, n in enumerate(NAMES)},
            'signRect': sign, 'plateAnchor': plate,
            'signKit': {'path': 'signkit.png', 'size': [20, 11], 'slice': {'top': 3, 'right': 4, 'bottom': 3, 'left': 4}, 'scale': 3},
            'headAnchor': heads,
            'headAnchorNote': '[x, y, unitPx] per row per frame in cell px; null = hide accessories on that frame',
            'accessories': dict(accmeta, path='accessories.png'),
            'anchors': {'edgepeek': 'left', 'thrown': 'centre', 'peek': 'top'}
        }
    }, open(os.path.join(d, 'pet.json'), 'w'))
    return full.size


if __name__ == '__main__':
    out = os.path.join(HERE, 'packs3')
    for k in R.ORDER:
        print(k, render(k, out))
