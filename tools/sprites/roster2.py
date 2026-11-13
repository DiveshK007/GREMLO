"""Gremlo 1.0, round two: more frames, more life.

Extends roster.py without editing it:
  * rows 1 (walk), 2 (climb) and 6 (sign) are redrawn
  * 14 new rows (15-28): turn, start/stop, gaze, sit, edge peek, yawn,
    grabbed, thrown, landing, social, tools, night, focus, hold
  * a 9-slice sign kit per species, so the app can draw a plate of any width
  * per-frame metadata: signRect (row 6) and plateAnchor (row 28)

Outputs per species, in packs2/<id>/:
  main.png      rows 0-14   (canvas)
  ext.png       rows 15-28  (canvas)
  spritesheet.webp / .png   all 29 rows (the app)
  signkit.png   16 x 9 px 9-slice, 1 unit = 1 px
  pet.json
"""
import importlib.util, sys, os, json
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('roster', os.path.join(HERE, 'roster.py'))
R = importlib.util.module_from_spec(spec)
sys.modules['roster'] = R
spec.loader.exec_module(R)

Body, SPECIES, CX, H = R.Body, R.SPECIES, R.CX, R.H
R.OUTLINED.update(set('q'))
CW, CH, COLS, SCALE, BASE = 192, 208, 8, 7, 194


def arm_col(sp):
    return {'wing': 'b', 'robot': 'b'}.get(sp['arms'], 'c')

# ------------------------------------------------------------ new limbs ----

_orig_arms = Body.arms


def arms(self, kind='down'):
    if kind not in ('climbL', 'climbR', 'hold', 'hi5', 'dangle', 'meditate', 'tool', 'none', 'overhead'):
        return _orig_arms(self, kind)
    if kind == 'none':
        return self
    ay = self.row(self.sp['arm_f'])
    hw = self.hw(self.sp['arm_f'])
    c = self.centre(ay)
    L, Rr = c - hw - 1, c + hw + 1
    col = arm_col(self.sp)
    if kind == 'climbL':
        self.rect(L - 1, ay - 5, L, ay, col); self.rect(Rr, ay + 1, Rr, ay + 3, col)
    elif kind == 'climbR':
        self.rect(Rr, ay - 5, Rr + 1, ay, col); self.rect(L, ay + 1, L, ay + 3, col)
    elif kind == 'hold':
        self.rect(L - 2, ay - 1, L, ay, col); self.rect(Rr, ay - 1, Rr + 2, ay, col)
    elif kind == 'hi5':
        self.rect(L, ay, L, ay + 3, col)
        self.rect(Rr, ay - 5, Rr + 1, ay - 1, col); self.rect(Rr + 1, ay - 7, Rr + 2, ay - 5, col)
    elif kind == 'dangle':
        self.rect(L - 1, ay - 8, L, ay, col); self.rect(Rr, ay - 8, Rr + 1, ay, col)
    elif kind == 'meditate':
        self.rect(L - 2, ay + 2, L, ay + 3, col); self.rect(Rr, ay + 2, Rr + 2, ay + 3, col)
    elif kind == 'tool':
        self.rect(L, ay, L, ay + 3, col); self.rect(Rr, ay - 1, Rr + 2, ay, col)
    elif kind == 'overhead':
        t, _ = self.headtop()
        top = t - 2
        w = 0 if self.sp['arms'] in ('robot', 'nub') else 1
        self.rect(L - w, top, L, ay + 1, col); self.rect(Rr, top, Rr + w, ay + 1, col)
        ANCH[id(self.g)] = top + 1
    return self


ANCH = {}
Body.arms = arms

# ------------------------------------------------------------- new sign ----

def sign_wide(self):
    """A wide board gripped at both ends. Face is 'f' so its rect can be read back."""
    by = self.row(0.50)
    c = self.centre(by)
    half = max(11, max(self.prof) + 1)
    self.rect(c - half, by, c + half, by + 6, 'k')
    self.rect(c - half + 1, by + 1, c + half - 1, by + 5, 'f')
    self.rect(c - half + 3, by + 2, c + half - 6, by + 2, 'l')
    self.rect(c - half + 3, by + 4, c + 2, by + 4, 'l')
    col = arm_col(self.sp)
    self.rect(c - half - 1, by + 2, c - half, by + 4, col)
    self.rect(c + half, by + 2, c + half + 1, by + 4, col)
    return self


Body.sign = sign_wide

# ---------------------------------------------------------------- extras ----

def gaze_eyes(b, d):
    sp = b.sp
    screen = sp.get('screen')
    col = 'a' if screen else 'e'
    ey = b.row(sp['eye_f']) + (1 if screen else 0)
    c = b.centre(ey)
    dx = sp['eye_dx']
    shift = (-1 if d < 0 else 1 if d > 0 else 0)
    for sx in (-dx, dx - 2):
        x = c + sx + shift
        b.rect(x, ey, x + 2, ey + 3, col)
        if not screen:
            sx2 = x if d <= 0 else x + 1
            b.put(sx2, ey, 'w'); b.put(sx2 + 1, ey, 'w')
            if abs(d) == 2:
                b.put(x + (0 if d < 0 else 2), ey + 1, 'w')
    b.mouth('smile' if d == 0 else 'flat', side=(-2 if d < 0 else 2 if d > 0 else 0) * (1 if abs(d) == 2 else 0))


def tool(b, kind):
    ay = b.row(b.sp['arm_f'])
    hx = b.centre(ay) + b.hw(b.sp['arm_f']) + 4
    hy = ay - 1
    if kind == 'wrench':
        for i in range(4):
            b.put(hx + i, hy + 1 - i, 'q')
        b.rect(hx + 3, hy - 5, hx + 5, hy - 3, 'q'); b.put(hx + 4, hy - 5, 'f') if False else None
        b.g.pop((hx + 4, hy - 5), None)
    elif kind == 'magnifier':
        b.disc(hx + 3, hy - 4, 2.6, 'k')
        b.disc(hx + 3, hy - 4, 1.5, 't')
        b.put(hx + 1, hy - 1, 'k'); b.put(hx, hy, 'k')
    elif kind == 'flask':
        b.rect(hx + 2, hy - 7, hx + 2, hy - 5, 'u')
        for i, w in enumerate((1, 1, 2, 2)):
            b.rect(hx + 2 - w, hy - 4 + i, hx + 2 + w, hy - 4 + i, 'u')
        b.rect(hx, hy - 2, hx + 4, hy - 1, 'y')
    elif kind == 'terminal':
        b.rect(hx, hy - 5, hx + 6, hy, 'q')
        b.put(hx + 1, hy - 4, 'y'); b.rect(hx + 3, hy - 4, hx + 4, hy - 4, 'u')
        b.rect(hx + 1, hy - 2, hx + 2, hy - 2, 'u')
    elif kind == 'globe':
        b.disc(hx + 3, hy - 4, 2.8, 'k')
        b.disc(hx + 3, hy - 4, 2.0, 't')
        b.rect(hx + 1, hy - 4, hx + 5, hy - 4, 'k'); b.rect(hx + 3, hy - 6, hx + 3, hy - 2, 'k')
    elif kind == 'notepad':
        b.rect(hx, hy - 6, hx + 4, hy, 'u')
        for yy in (hy - 5, hy - 3, hy - 1):
            b.rect(hx + 1, yy, hx + 3, yy, 'l')


def nightcap(b):
    t, c = b.headtop()
    for i, w in enumerate((7, 6, 5, 4, 3, 2)):
        x0 = c - 7 + i
        b.rect(x0, t - 1 - i // 1 + (1 if i > 2 else 0), x0 + w * 2 - 1, t - 1 - i // 1 + (1 if i > 2 else 0), 'm')
    b.rect(c - 7, t, c + 6, t, 'u')
    b.disc(c + 7, t - 1, 1.3, 'u')


def stars(b, phase):
    t, c = b.headtop()
    pts = [(c - 7, t - 2), (c + 7, t - 1), (c, t - 5)] if phase == 0 else [(c - 5, t - 4), (c + 6, t - 4), (c + 1, t - 1)]
    for (x, y) in pts:
        for (a, d) in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
            b.put(x + a, y + d, 'v')


def orbit(b, phase):
    ey = b.row(b.sp['eye_f'])
    c = b.centre(ey)
    hw = max(b.prof) + 4
    dy = (-2, 0, 2, 0)[phase % 4]
    b.put(c - hw, ey + dy, 'y'); b.put(c + hw, ey - dy, 'y')
    b.put(c - hw, ey + dy + 1, 'y'); b.put(c + hw, ey - dy + 1, 'y')


def sit_legs(b, phase):
    st = b.sp['legs']
    bt = b.bottom
    c = b.centre(bt)
    hwb = b.prof[-1]
    sw = (0, 1, 0, -1)[phase % 4]
    if st == 'stub':
        L, Rr = c - hwb + 2, c + hwb - 4
        b.rect(L + sw, bt + 1, L + 2 + sw, bt + 5, 'c'); b.rect(Rr - sw, bt + 1, Rr + 2 - sw, bt + 5, 'c')
    elif st == 'bird':
        for x0, s in ((c - 3, sw), (c + 2, -sw)):
            b.rect(x0 + s, bt + 1, x0 + s, bt + 5, 'a'); b.rect(x0 - 1 + s, bt + 5, x0 + 1 + s, bt + 5, 'a')
    elif st == 'robot':
        for x0, s in ((c - 5, sw), (c + 3, -sw)):
            b.rect(x0 + s, bt + 1, x0 + 1 + s, bt + 4, 's'); b.rect(x0 - 1 + s, bt + 5, x0 + 2 + s, bt + 5, 'b')
    elif st == 'tentacle':
        for i, x0 in enumerate((c - 7, c - 3, c + 2, c + 6)):
            ln = 6 + (sw if i % 2 else -sw)
            b.rect(x0, bt + 1, x0 + 1, bt + ln, 'c')


def dangle_legs(b, phase):
    st = b.sp['legs']
    bt = b.bottom
    c = b.centre(bt)
    hwb = b.prof[-1]
    kick = phase % 2
    if st in ('stub', 'robot', 'bird'):
        col = {'stub': 'c', 'robot': 's', 'bird': 'a'}[st]
        w = 1 if st == 'bird' else 2
        L, Rr = c - hwb + 1, c + hwb - 2
        b.rect(L - kick, bt + 1, L - kick + w - 1, bt + (3 if kick else 5), col)
        b.rect(Rr + (1 - kick), bt + 1, Rr + (1 - kick) + w - 1, bt + (5 if kick else 3), col)
    elif st == 'tentacle':
        for i, x0 in enumerate((c - 7, c - 3, c + 2, c + 6)):
            b.rect(x0 + (kick if i < 2 else -kick), bt + 1, x0 + 1 + (kick if i < 2 else -kick), bt + 6, 'c')


def make2(key, top=6, rows=None, widen=0, lean=0.0, eye='open', mo='smile', leg='stand',
          arm='down', cheek=False, sign=False, gaze=None, sit=None, dangle=None, tool_=None,
          night=False, focus=None, starsph=None, spark=False, zzz=False, sweat=False,
          back=False, side=0, phase=0, heart=False):
    sp = SPECIES[key]
    flo = sp['legs'] in ('none_float', 'none_ground')
    b = Body(sp, top, rows, widen, lean, 1.0)
    b.fill()
    if sit is not None:
        if not flo:
            sit_legs(b, sit)
    elif dangle is not None:
        if not flo:
            dangle_legs(b, dangle)
    elif not flo or sp['legs'] == 'none_ground':
        b.legs(leg)
    b.arms(arm)
    b.shade()
    if not back:
        b.belly()
    b.decor(phase=phase)
    if not back:
        if gaze is not None:
            gaze_eyes(b, gaze)
        elif side:
            ey = b.row(sp['eye_f']); c = b.centre(ey)
            col = 'a' if sp.get('screen') else 'e'
            b.rect(c + 2, ey, c + 4, ey + 3, col)
            if not sp.get('screen'):
                b.put(c + 2, ey, 'w')
            b.mouth(mo, side=4)
        else:
            b.eyes(eye)
            b.mouth(mo)
        b.beak(mo in ('open', 'o', 'yawn'))
        if cheek:
            b.cheeks()
    if night:
        nightcap(b)
    if tool_:
        tool(b, tool_)
    if sign:
        b.sign()
    b.outline()
    if spark:
        b.sparkles()
    if zzz:
        b.zees()
    if sweat:
        b.sweat()
    if heart:
        b.heart()
    if starsph is not None:
        stars(b, starsph)
    if focus is not None:
        orbit(b, focus)
    b.shadow()
    return b.g


def rot(g, k):
    for _ in range(k % 4):
        g = {(H + 2 - y, x): c for (x, y), c in g.items()}
    return g


def crop_left(g, cut):
    return {(x, y): c for (x, y), c in g.items() if x >= cut}

# ------------------------------------------------------------ the rows ----

def walk_row(key):
    sp = SPECIES[key]
    if sp['legs'] == 'none_float':
        bob = (0, -1, -2, -2, -1, 0, 1, 1)
        return [dict(top=6 + d, widen=(1 if d == 1 else 0), rows=len(sp['profile']) - (1 if d == 1 else 0),
                     arm=('out' if i % 4 < 2 else 'down'), lean=0.03, phase=i) for i, d in enumerate(bob)]
    if sp['legs'] == 'none_ground':
        wd = (0, 1, 2, 1, 0, 1, 2, 1)
        return [dict(top=6 + w, widen=w, rows=len(sp['profile']) - w, lean=(0.04 if i < 4 else 0.02),
                     arm='down', phase=i) for i, w in enumerate(wd)]
    seq = [('walk1', 0, 'out'), ('walk1', 1, 'down'), ('walk3', 0, 'down'), ('walk4', -1, 'out'),
           ('walk2', 0, 'out'), ('walk2', 1, 'down'), ('walk3', 0, 'down'), ('walk4', -1, 'out')]
    return [dict(top=6 + dy, leg=l, arm=a, lean=0.03, phase=i) for i, (l, dy, a) in enumerate(seq)]


def rows2(key):
    sp = SPECIES[key]
    n = len(sp['profile'])
    sign_row = [dict(sign=True, mo='flat'), dict(top=5, sign=True, mo='flat'), dict(sign=True, eye='closed', mo='flat'),
                dict(top=5, sign=True, mo='smile'), dict(sign=True, gaze=1), dict(top=5, sign=True, cheek=True)]
    climb = [dict(leg=('walk1' if i % 2 == 0 else 'walk2'), arm=('climbL' if i % 2 == 0 else 'climbR'),
                  mo='flat', eye=('closed' if i == 4 else 'open'), phase=i, top=6 + (0 if i % 2 == 0 else -1))
             for i in range(8)]
    rows = {
        15: [dict(), dict(gaze=1), dict(side=1, mo='flat'), dict(back=True)],
        16: [dict(), dict(top=7, rows=n - 1, lean=0.06, arm='out', eye='look'), dict(leg='walk1', lean=0.05, arm='out'),
             dict(leg='walk3', lean=0.03), dict(lean=-0.06, arm='out', eye='wide', mo='o', leg='spread'), dict(top=5)],
        17: [dict(gaze=-2), dict(gaze=-1), dict(gaze=0), dict(gaze=1), dict(gaze=2)],
        18: [dict(top=8, rows=n - 2, sit=i, eye=('closed' if i == 2 else 'open'), mo='smile',
                  arm='down') for i in range(4)],
        19: ['edge_4', 'edge_1', 'edge_-3', 'edge_1b'],
        20: [dict(top=5, rows=n + 1, arm='up', eye='closed', mo='yawn'), dict(top=4, rows=n + 2, arm='up', eye='closed', mo='yawn'),
             dict(eye='droop', mo='o', arm='out'), dict(eye='open', mo='flat')],
        21: [dict(top=4, rows=n + 2, dangle=i, arm='dangle', eye=('cross' if i < 2 else 'wide'),
                  mo=('o' if i % 2 else 'wobble'), sweat=(i == 3)) for i in range(4)],
        22: ['throw_0', 'throw_1', 'throw_2', 'throw_3'],
        23: [dict(top=6 + n - max(6, int(n * .62)), rows=max(6, int(n * .62)), widen=2, arm='out', eye='closed', mo='flat', leg='spread'),
             dict(top=3, rows=n + 3, widen=-1, arm='up', eye='wide', mo='o'),
             dict(arm='out', eye='dizzy', mo='wobble', starsph=0), dict(arm='out', eye='dizzy', mo='wobble', starsph=1),
             dict(eye='closed', mo='flat'), dict(eye='happy', mo='smile', cheek=True)],
        24: [dict(arm='wave', eye='happy', mo='smile'), dict(arm='raise', eye='happy', mo='grin'),
             dict(arm='hi5', eye='wide', mo='open'), dict(arm='hi5', eye='happy', mo='grin', spark=True, cheek=True),
             dict(top=7, lean=0.12, leg='walk1', arm='out', mo='open'), dict(top=5, lean=0.12, leg='walk2', arm='down', mo='open')],
        25: [dict(arm='tool', tool_='wrench', mo='flat'), dict(arm='tool', tool_='magnifier', eye='look', mo='flat'),
             dict(arm='tool', tool_='flask', mo='o'), dict(arm='tool', tool_='terminal', mo='flat'),
             dict(arm='tool', tool_='globe', mo='smile'), dict(arm='tool', tool_='notepad', eye='happy', mo='smile')],
        26: [dict(night=True, eye='droop', mo='flat'), dict(night=True, arm='up', eye='closed', mo='yawn'),
             dict(night=True, top=9, rows=n - 3, widen=1, leg='tuck', eye='closed', mo='flat', zzz=True),
             dict(night=True, gaze=1)],
        27: [dict(arm='meditate', eye='closed', mo='flat', focus=i, rows=(n if i % 2 == 0 else n - 1),
                  widen=(0 if i % 2 == 0 else 1), top=(6 if i % 2 == 0 else 7)) for i in range(4)],
        28: [dict(arm='overhead', mo='flat'), dict(top=5, arm='overhead', mo='flat'), dict(arm='overhead', eye='closed', mo='flat'),
             dict(top=5, arm='overhead', mo='smile'), dict(arm='overhead', gaze=1), dict(top=5, arm='overhead', cheek=True)],
    }
    return walk_row(key), climb, sign_row, rows


EXT_NAMES = ['turn', 'startstop', 'gaze', 'sit', 'edgepeek', 'yawn', 'grabbed', 'thrown', 'land',
             'social', 'tools', 'night', 'focus', 'hold']
ALL_NAMES = R.ROW_NAMES + EXT_NAMES


def frame_for(key, f, r):
    if isinstance(f, str):
        if f.startswith('edge'):
            p = f.split('_')[1]
            cut = int(p.rstrip('b'))
            g = make2(key, gaze=2, eye='closed' if p.endswith('b') else 'open')
            if p.endswith('b'):
                g = make2(key, eye='closed', mo='flat')
            return crop_left(g, CX + cut), 'left'
        if f.startswith('throw'):
            k = int(f.split('_')[1])
            return rot(make2(key, leg='tuck', arm='up', eye=('dizzy' if k % 2 else 'wide'), mo='o'), k), 'centre'
    g = make2(key, **f)
    return g, 'feet'


def build2(key):
    base = R.build(key)
    walk, climb, sign_row, ext = rows2(key)
    base[1] = [(make2(key, **f), 0) for f in walk]
    base[2] = [(rot(make2(key, **f), 1), 0) for f in climb]
    base[6] = [(make2(key, **f), 0) for f in sign_row]
    main = [[(g, lift, 'top' if r == 14 else 'feet') for (g, lift) in row] for r, row in enumerate(base)]
    extra = []
    for r in range(15, 29):
        out = []
        for f in ext[r]:
            g, anchor = frame_for(key, f, r)
            out.append((g, 0, anchor))
        extra.append(out)
    return main, extra


def paste(img, g, col, row, pal, lift=0, anchor='feet'):
    xs = [x for (x, y) in g]
    ys = [y for (x, y) in g]
    if not xs:
        return None
    s = SCALE
    if (max(ys) + 1 - min(ys)) * s > CH - 6 or (max(xs) + 1 - min(xs)) * s > CW - 4:
        s = max(3, min((CH - 8) // (max(ys) + 1 - min(ys)), (CW - 6) // (max(xs) + 1 - min(xs))))
    if anchor == 'left':
        ox = col * CW - min(xs) * s
    else:
        ox = col * CW + CW // 2 - int((min(xs) + max(xs) + 1) / 2 * s)
    if anchor == 'top':
        oy = row * CH + 6 - min(ys) * s
    elif anchor == 'centre':
        oy = row * CH + CH // 2 - int((min(ys) + max(ys) + 1) / 2 * s)
    else:
        oy = row * CH + BASE - lift - (max(ys) + 1) * s
    dr = ImageDraw.Draw(img)
    for (x, y), c in g.items():
        px, py = ox + x * s, oy + y * s
        dr.rectangle([px, py, px + s - 1, py + s - 1], fill=pal[c])
    return ox - col * CW, oy - row * CH, s


def rect_of(g, place, colour='f'):
    pts = [(x, y) for (x, y), c in g.items() if c == colour]
    if not pts or not place:
        return None
    ox, oy, s = place
    x0 = min(p[0] for p in pts); x1 = max(p[0] for p in pts)
    y0 = min(p[1] for p in pts); y1 = max(p[1] for p in pts)
    return [ox + x0 * s, oy + y0 * s, (x1 - x0 + 1) * s, (y1 - y0 + 1) * s]


def plate_anchor(key, g, place):
    """Chest-height point between the two raised hands (row 28)."""
    sp = SPECIES[key]
    ox, oy, s = place
    ys = [y for (x, y) in g if g[(x, y)] in ('c', 's')]
    top = min(ys)
    ay = top + int(round(sp['arm_f'] * (len(sp['profile']) - 1))) - 1
    return [ox + CX * s + s // 2, oy + ay * s]


def signkit(key):
    """20 x 11 px 9-slice. Ends: a mitt gripping an ink frame. Middle: paper face that stretches.
    Slice 4 px left/right, 3 px top/bottom. Draw it at an integer scale (3x for a 48 px pet)."""
    sp = SPECIES[key]
    pal = R.palette(sp)
    hand = pal[arm_col(sp)]
    ink, face = pal['k'], pal['f']
    img = Image.new('RGBA', (20, 11), (0, 0, 0, 0))
    px = img.load()
    for x in range(3, 17):
        for y in range(1, 10):
            px[x, y] = ink
    for x in range(4, 16):
        for y in range(2, 9):
            px[x, y] = face
    for x0, out in ((1, 0), (17, 19)):
        for y in range(4, 7):
            px[x0, y] = hand; px[x0 + 1, y] = hand
            px[out, y] = ink
        for x in (x0, x0 + 1):
            px[x, 3] = ink; px[x, 7] = ink
    return img


def render(key, outdir):
    sp = SPECIES[key]
    pal = R.palette(sp)
    main, extra = build2(key)
    allrows = main + extra
    full = Image.new('RGBA', (COLS * CW, len(allrows) * CH), (0, 0, 0, 0))
    meta_sign, meta_plate = [], []
    for r, row in enumerate(allrows):
        for c, (g, lift, anchor) in enumerate(row):
            place = paste(full, g, c, r, pal, lift, anchor)
            if r == 6:
                meta_sign.append(rect_of(g, place))
            if r == 28 and place:
                ox, oy, sc = place
                meta_plate.append([CW // 2, oy + ANCH[id(g)] * sc])

    d = os.path.join(outdir, 'gremlo' if key == 'gremlo' else f'gremlo-{key}')
    os.makedirs(d, exist_ok=True)
    full.save(os.path.join(d, 'spritesheet.webp'), 'WEBP', lossless=True, quality=100)
    full.save(os.path.join(d, 'spritesheet.png'), 'PNG')
    full.crop((0, 0, COLS * CW, 15 * CH)).save(os.path.join(d, 'main.png'))
    full.crop((0, 15 * CH, COLS * CW, 29 * CH)).save(os.path.join(d, 'ext.png'))
    signkit(key).save(os.path.join(d, 'signkit.png'))
    json.dump({
        'id': os.path.basename(d), 'displayName': sp['name'], 'description': sp['line'],
        'spriteVersionNumber': 4, 'spritesheetPath': 'spritesheet.webp',
        'gremlo': {
            'species': key, 'accent': '#' + sp['accent'], 'cell': [CW, CH], 'columns': COLS,
            'rows': {n: {'row': i, 'frames': len(allrows[i])} for i, n in enumerate(ALL_NAMES)},
            'signRect': meta_sign,
            'plateAnchor': meta_plate,
            'plateAnchorNote': 'bottom-centre of the plate, cell px at full scale; the pet holds it overhead (row hold)',
            'signKit': {'path': 'signkit.png', 'size': [20, 11], 'slice': {'top': 3, 'right': 4, 'bottom': 3, 'left': 4}, 'scale': 3},
            'anchors': {'edgepeek': 'left', 'thrown': 'centre', 'peek': 'top'}
        }
    }, open(os.path.join(d, 'pet.json'), 'w'), indent=1)
    return full.size


if __name__ == '__main__':
    out = os.path.join(HERE, 'packs2')
    for k in R.ORDER:
        print(k, render(k, out))
