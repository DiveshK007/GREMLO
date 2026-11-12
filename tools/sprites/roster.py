"""Notchi 1.0 — species engine.

Eight original creatures, one pose vocabulary. Each species defines a silhouette,
limb style, decor and palette; the pose library is shared so every pet can do
everything (walk, hold the sign, wave the flag, get annoyed...).

Outputs, per species, a pack in the Codex desktop-pet layout extended to 15 rows:
cell 192 x 208, 8 columns, one animation per row.
"""
import json, os, math, random
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 44, 42          # grid units per frame
CX = 18                # body centre x

def hx(s, a=255):
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) + (a,)

OUTLINED = set('csrdpabhxquvmn')

COMMON = {
    'o': hx('0B0B0B'), 'e': hx('0B0B0B'), 'w': hx('FFFFFF'), 'k': hx('0B0B0B'),
    'f': hx('F4F2ED'), 'l': hx('3C3C3C'), 'g': hx('FF5A3C'), 'z': hx('000000', 70),
    'q': hx('2E2E2E'), 'u': hx('F4F2ED'), 'v': hx('FFC93C'), 'm': hx('5B4BB5'),
    'n': hx('FF5A3C'), 't': hx('7FD3FF'),
}

# ---------------------------------------------------------------- species --

SPECIES = {
    'notchi': dict(
        name='Notchi', kind='bean', accent='FF5A3C',
        line='The original. Lives in the notch, holds the sign, pays its way.',
        profile=[2, 4, 5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 8, 8, 7, 6, 6],
        legs='stub', arms='stub', belly='patch',
        eye_f=0.28, eye_dx=5, mouth_f=0.56, arm_f=0.56,
        pal=dict(c='F4F2ED', s='DAD6CC', r='FF5A3C', d='D63D22', p='FF8A72',
                 a='FF5A3C', b='D63D22', h='FFFFFF')),
    'pip': dict(
        name='Pip', kind='bird', accent='FFC93C',
        line='A round little bird. Chirps when a build goes green.',
        profile=[2, 4, 6, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 7, 6, 4],
        legs='bird', arms='wing', belly='oval',
        eye_f=0.30, eye_dx=6, mouth_f=0.50, arm_f=0.52,
        pal=dict(c='FFD54A', s='E9B92A', r='FFF3C4', d='F2DC9A', p='FF9E7A',
                 a='FF8A3D', b='E0A21F', h='FFFFFF')),
    'moss': dict(
        name='Moss', kind='sprout', accent='8FD14F',
        line='A sprout that grows a leaf for every meal it eats.',
        profile=[3, 5, 6, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 7, 6],
        legs='stub', arms='stub', belly='patch',
        eye_f=0.30, eye_dx=5, mouth_f=0.55, arm_f=0.56,
        pal=dict(c='9BD65A', s='7BB83E', r='DDF3C2', d='C4E6A0', p='6FAF3C',
                 a='3E8E2F', b='2F6E22', h='FFFFFF')),
    'gloop': dict(
        name='Gloop', kind='slime', accent='2ED3B7',
        line='A patient slime. Splits in two when it is really happy.',
        profile=[3, 5, 7, 8, 9, 10, 10, 11, 11, 11, 12, 12, 12],
        legs='none_ground', arms='nub', belly=None,
        eye_f=0.36, eye_dx=5, mouth_f=0.66, arm_f=0.60,
        pal=dict(c='34D6BB', s='1FB39A', r='7FF0DD', d='1FB39A', p='7FF0DD',
                 a='1FB39A', b='15917C', h='E6FFFA')),
    'byte': dict(
        name='Byte', kind='robot', accent='4CC9FF',
        line='A tidy robot with a screen for a face. Glitches when tests fail.',
        profile=[6, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 7],
        legs='robot', arms='robot', belly=None, screen=True,
        eye_f=0.24, eye_dx=5, mouth_f=0.50, arm_f=0.60,
        pal=dict(c='CDD2DA', s='A6ADB8', r='CDD2DA', d='A6ADB8', p='4CC9FF',
                 a='4CC9FF', b='7C8592', h='FFFFFF', x='101418')),
    'puff': dict(
        name='Puff', kind='cloud', accent='8FA8FF',
        line='A small cloud. Rains a little when the agent fails.',
        profile=[5, 8, 9, 10, 11, 11, 11, 11, 11, 10, 9, 7],
        legs='none_float', arms='nub', belly=None, bumps=True,
        eye_f=0.38, eye_dx=5, mouth_f=0.66, arm_f=0.55,
        pal=dict(c='F0F3FF', s='C9D2F5', r='F0F3FF', d='C9D2F5', p='B9C6FF',
                 a='8FA8FF', b='6F86E6', h='FFFFFF')),
    'wisp': dict(
        name='Wisp', kind='flame', accent='B48CFF',
        line='A quiet flame spirit. Burns brighter the better it eats.',
        profile=[1, 2, 2, 3, 4, 5, 6, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8],
        legs='none_float', arms='nub', belly='core',
        eye_f=0.52, eye_dx=5, mouth_f=0.76, arm_f=0.66,
        pal=dict(c='B48CFF', s='8F66E8', r='E7DBFF', d='CDB6FF', p='D9C2FF',
                 a='F3EDFF', b='8F66E8', h='FFFFFF')),
    'tako': dict(
        name='Tako', kind='octopus', accent='FF7AB6',
        line='A tiny octopus. Squirts ink when you poke it too much.',
        profile=[3, 5, 6, 7, 8, 8, 9, 9, 9, 9, 9, 9, 8],
        legs='tentacle', arms='tentacle', belly=None,
        eye_f=0.46, eye_dx=5, mouth_f=0.78, arm_f=0.70,
        pal=dict(c='FF7AB6', s='E25A97', r='FFB0D2', d='E25A97', p='FFB0D2',
                 a='FFB0D2', b='E25A97', h='FFFFFF')),
}

ORDER = ['notchi', 'pip', 'moss', 'gloop', 'byte', 'puff', 'wisp', 'tako']


def palette(sp):
    p = dict(COMMON)
    for k, v in sp['pal'].items():
        p[k] = hx(v)
    p['y'] = hx(sp['accent'])
    return p


def resample(prof, n):
    if n == len(prof):
        return list(prof)
    out = []
    for i in range(n):
        t = i * (len(prof) - 1) / max(n - 1, 1)
        a, b = int(t), min(int(t) + 1, len(prof) - 1)
        out.append(prof[a] + (prof[b] - prof[a]) * (t - a))
    return out

# ------------------------------------------------------------------- grid --

class Body:
    def __init__(self, sp, top=6, rows=None, widen=0, lean=0.0, scale=1.0):
        self.sp, self.g, self.top = sp, {}, top
        n = rows or len(sp['profile'])
        prof = resample(sp['profile'], n)
        self.prof = [max(1, int(round(h * scale)) + widen) for h in prof]
        self.rows = n
        self.spans = {}
        for i, hw in enumerate(self.prof):
            c = CX + int(round(lean * (n - i)))
            self.spans[top + i] = (c - hw, c + hw)

    # helpers
    def put(self, x, y, c):
        self.g[(x, y)] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
                self.g[(x, y)] = c

    def disc(self, cx, cy, r, c, only_empty=False):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.3:
                    if not only_empty or (x, y) not in self.g:
                        self.g[(x, y)] = c

    @property
    def bottom(self):
        return self.top + self.rows - 1

    def row(self, f):
        return self.top + int(round(f * (self.rows - 1)))

    def hw(self, f):
        return self.prof[int(round(f * (self.rows - 1)))]

    def centre(self, y):
        if y in self.spans:
            l, r = self.spans[y]
            return (l + r) // 2
        return CX

    def headtop(self):
        """Top-most body pixel row and its centre (after bumps etc.)."""
        ys = [y for (x, y), c in self.g.items() if c in ('c', 's')]
        t = min(ys) if ys else self.top
        xs = [x for (x, y), c in self.g.items() if y == t and c in ('c', 's')]
        return t, (min(xs) + max(xs)) // 2 if xs else CX

    # ---------------------------------------------------------- body ----
    def fill(self):
        for y, (l, r) in self.spans.items():
            for x in range(l, r + 1):
                self.put(x, y, 'c')
        if self.sp.get('bumps'):            # cloud tops
            c = self.centre(self.top + 2)
            hw = self.prof[min(3, self.rows - 1)]
            self.disc(c - hw * 0.55, self.top + 1.5, 3.2, 'c')
            self.disc(c + 0.5, self.top - 0.5, 4.2, 'c')
            self.disc(c + hw * 0.6, self.top + 1.8, 3.0, 'c')
        return self

    def shade(self):
        rows = {}
        for (x, y), c in self.g.items():
            if c == 'c':
                rows.setdefault(y, []).append(x)
        for y, xs in rows.items():
            self.put(max(xs), y, 's')
        return self

    # ---------------------------------------------------------- limbs ---
    def legs(self, phase='stand'):
        st = self.sp['legs']
        b = self.bottom
        c = self.centre(b)
        hwb = self.prof[-1]
        shift = {'stand': (0, 0, 0, 0), 'walk1': (-1, 0, 1, -1), 'walk2': (1, -1, -1, 0),
                 'walk3': (0, 0, 0, 0), 'walk4': (1, -1, 1, -1), 'tap': (0, 0, 0, -1),
                 'air': (1, 0, -1, 0), 'spread': (-2, 0, 2, 0), 'tuck': (2, -1, -2, -1)}
        lx, ly, rx, ry = shift.get(phase, (0, 0, 0, 0))
        if st == 'stub':
            w = 3
            L = c - hwb + 1 + lx
            R = c + hwb - 3 + rx
            self.rect(L, b + 1 + ly, L + w - 1, b + 3 + ly, 'c')
            self.rect(R, b + 1 + ry, R + w - 1, b + 3 + ry, 'c')
        elif st == 'bird':
            for (x0, dy, dx) in ((c - 3 + lx, ly, -1), (c + 2 + rx, ry, 1)):
                self.rect(x0, b + 1 + dy, x0, b + 3 + dy, 'a')
                self.rect(x0 - 1, b + 3 + dy, x0 + 1, b + 3 + dy, 'a')
        elif st == 'robot':
            for (x0, dy) in ((c - 5 + lx, ly), (c + 3 + rx, ry)):
                self.rect(x0, b + 1 + dy, x0 + 1, b + 2 + dy, 's')
                self.rect(x0 - 1, b + 3 + dy, x0 + 2, b + 3 + dy, 'b')
        elif st == 'tentacle':
            wig = {'stand': (0, 0, 0, 0), 'walk1': (1, 0, -1, 0), 'walk2': (0, 1, 0, -1),
                   'walk3': (-1, 0, 1, 0), 'walk4': (0, -1, 0, 1), 'tuck': (-1, -1, -1, -1),
                   'spread': (1, 1, 1, 1), 'air': (0, 1, 1, 0), 'tap': (0, 0, 0, 1)}.get(phase, (0, 0, 0, 0))
            xs = (c - 7, c - 3, c + 2, c + 6)
            dirs = (-1, -1, 1, 1)
            for i, x0 in enumerate(xs):
                ln = 4 + wig[i]
                self.rect(x0, b + 1, x0 + 1, b + ln, 'c')
                self.put(x0 + (2 if dirs[i] > 0 else -1), b + ln, 'c')
        elif st == 'none_ground':
            l, r = self.spans[b]
            self.rect(l - 1, b, l - 1, b, 'c')
            self.rect(r + 1, b, r + 1, b, 's')
        return self

    def arms(self, kind='down'):
        st = self.sp['arms']
        ay = self.row(self.sp['arm_f'])
        hw = self.hw(self.sp['arm_f'])
        c = self.centre(ay)
        L, R = c - hw - 1, c + hw + 1
        if st == 'stub':
            if kind == 'down':
                self.rect(L, ay, L, ay + 3, 'c'); self.rect(R, ay, R, ay + 3, 'c')
            elif kind == 'out':
                self.rect(L - 1, ay, L, ay + 1, 'c'); self.rect(R, ay, R + 1, ay + 1, 'c')
            elif kind == 'raise':
                self.rect(L, ay, L, ay + 3, 'c'); self.rect(R, ay - 3, R + 1, ay + 1, 'c')
            elif kind == 'up':
                self.rect(L - 1, ay - 4, L, ay + 1, 'c'); self.rect(R, ay - 4, R + 1, ay + 1, 'c')
            elif kind == 'wave':
                self.rect(L, ay, L, ay + 3, 'c'); self.rect(R, ay - 5, R + 1, ay - 1, 'c')
        elif st == 'wing':
            if kind in ('down', 'raise'):
                self.rect(L - 1, ay, L, ay + 3, 'b')
                if kind == 'down':
                    self.rect(R, ay, R + 1, ay + 3, 'b')
                else:
                    self.rect(R, ay - 3, R + 2, ay - 1, 'b')
            elif kind == 'out':
                self.rect(L - 2, ay, L, ay + 1, 'b'); self.rect(R, ay, R + 2, ay + 1, 'b')
            elif kind in ('up', 'wave'):
                self.rect(L - 2, ay - 4, L, ay - 1, 'b'); self.rect(R, ay - 4, R + 2, ay - 1, 'b')
        elif st == 'robot':
            if kind == 'down':
                self.rect(L, ay, L, ay + 2, 's'); self.rect(L - 1, ay + 3, L, ay + 4, 'b')
                self.rect(R, ay, R, ay + 2, 's'); self.rect(R, ay + 3, R + 1, ay + 4, 'b')
            elif kind == 'out':
                self.rect(L - 2, ay, L, ay, 's'); self.rect(L - 4, ay - 1, L - 3, ay + 1, 'b')
                self.rect(R, ay, R + 2, ay, 's'); self.rect(R + 3, ay - 1, R + 4, ay + 1, 'b')
            elif kind in ('up', 'wave', 'raise'):
                self.rect(R, ay - 3, R, ay, 's'); self.rect(R, ay - 5, R + 1, ay - 4, 'b')
                if kind == 'up':
                    self.rect(L, ay - 3, L, ay, 's'); self.rect(L - 1, ay - 5, L, ay - 4, 'b')
                else:
                    self.rect(L, ay, L, ay + 2, 's'); self.rect(L - 1, ay + 3, L, ay + 4, 'b')
        elif st == 'tentacle':
            if kind in ('up', 'wave', 'raise'):
                self.rect(R, ay - 3, R + 1, ay, 'c'); self.put(R + 2, ay - 4, 'c'); self.put(R + 1, ay - 4, 'c')
                if kind == 'up':
                    self.rect(L - 1, ay - 3, L, ay, 'c'); self.put(L - 2, ay - 4, 'c'); self.put(L - 1, ay - 4, 'c')
            elif kind == 'out':
                self.rect(L - 2, ay, L, ay + 1, 'c'); self.rect(R, ay, R + 2, ay + 1, 'c')
        elif st == 'nub':
            if kind == 'down':
                self.rect(L, ay, L, ay + 1, 'c'); self.rect(R, ay, R, ay + 1, 'c')
            elif kind == 'out':
                self.rect(L - 1, ay, L, ay + 1, 'c'); self.rect(R, ay, R + 1, ay + 1, 'c')
            elif kind in ('up', 'wave', 'raise'):
                self.rect(R, ay - 3, R + 1, ay - 1, 'c')
                if kind == 'up':
                    self.rect(L - 1, ay - 3, L, ay - 1, 'c')
                else:
                    self.rect(L, ay, L, ay + 1, 'c')
        return self

    # ---------------------------------------------------------- decor ---
    def belly(self):
        kind = self.sp.get('belly')
        if not kind:
            return self
        if kind == 'patch':
            widths = [3, 4, 5, 5, 4]
            y0 = self.row(0.70)
        elif kind == 'oval':
            widths = [3, 4, 5, 5, 5, 4, 3]
            y0 = self.row(0.56)
        elif kind == 'core':
            widths = [2, 3, 4, 4, 3]
            y0 = self.row(0.66)
        last = None
        for i, w in enumerate(widths):
            y = y0 + i
            if y not in self.spans:
                break
            l, r = self.spans[y]
            c = (l + r) // 2
            for x in range(max(c - w, l + 1), min(c + w, r - 1) + 1):
                self.put(x, y, 'r')
            last = y
        if last is not None and kind == 'patch':
            l, r = self.spans[last]
            for x in range(l + 2, r - 1):
                if self.g.get((x, last)) == 'r':
                    self.put(x, last, 'd')
        return self

    def decor(self, grow=0, flare=0, phase=0):
        k = self.sp['kind']
        t = self.top
        c = self.centre(t)
        if k == 'sprout':
            stem = 2 + grow
            self.rect(c, t - stem, c, t - 1, 'b')
            y = t - stem
            for (x, yy) in ((c - 1, y), (c - 2, y), (c - 3, y - 1), (c - 2, y - 1)):
                self.put(x, yy, 'a')
            for (x, yy) in ((c + 1, y + 1), (c + 2, y + 1), (c + 2, y), (c + 3, y)):
                self.put(x, yy, 'a')
            if grow >= 2:
                self.disc(c, y - 1.5, 1.2, 'n')
                self.put(c, y - 1, 'v')
            ey = self.row(self.sp['eye_f']) + 5
            ec = self.centre(ey)
            for (x, yy) in ((ec - 6, ey), (ec - 5, ey + 1), (ec + 5, ey), (ec + 6, ey + 1)):
                self.put(x, yy, 'p')
        elif k == 'bird':
            for (x, yy) in ((c, t - 1), (c - 1, t - 2), (c + 1, t - 2), (c, t - 3)):
                self.put(x, yy, 'b')
        elif k == 'robot':
            self.rect(c, t - 3, c, t - 1, 'b')
            self.rect(c - 1, t - 5, c, t - 4, 'a')
            l, r = self.spans[self.row(0.15)]
            self.rect(l + 2, self.row(0.12), r - 2, self.row(0.50), 'x')
            by = self.row(0.78)
            self.put(c - 2, by, 'a'); self.put(c + 1, by, 'b'); self.put(c + 3, by, 'b')
        elif k == 'octopus':
            for (dx, dy) in ((-3, 2), (2, 1), (4, 4)):
                self.put(c + dx, t + dy, 'p'); self.put(c + dx + 1, t + dy, 'p')
        elif k == 'flame':
            tip = 2 + flare
            sway = (-1, 0, 1, 0)[phase % 4]
            for i in range(1, tip + 1):
                self.put(c + (sway if i > 1 else 0), t - i, 'c')
            self.put(c + sway, t - tip, 'a')
            b = self.bottom
            l, r = self.spans[b]
            wave = phase % 2
            for x in range(l, r + 1):
                if (x - l + wave) % 4 in (0, 1):
                    self.put(x, b + 1, 'c')
        elif k == 'slime':
            self.rect(c - 5, t + 2, c - 4, t + 3, 'h')
            self.put(c - 3, t + 2, 'h')
            l, r = self.spans[self.row(0.55)]
            self.rect(r, self.row(0.55), r, self.row(0.55) + 2, 'c')
        return self

    # ----------------------------------------------------------- face ---
    def eyes(self, kind='open'):
        screen = self.sp.get('screen')
        col = 'a' if screen else 'e'
        ey = self.row(self.sp['eye_f']) + (1 if screen else 0)
        c = self.centre(ey)
        dx = self.sp['eye_dx']
        for i, sx in enumerate((-dx, dx - 2)):
            left = i == 0
            x = c + sx
            if kind == 'open':
                self.rect(x, ey, x + 2, ey + 3, col)
                if not screen:
                    self.put(x, ey, 'w'); self.put(x + 1, ey, 'w')
            elif kind == 'wide':
                self.rect(x, ey - 1, x + 2, ey + 4, col)
                if not screen:
                    self.put(x, ey - 1, 'w'); self.put(x + 1, ey - 1, 'w')
            elif kind == 'droop':
                self.rect(x, ey + 2, x + 2, ey + 3, col)
            elif kind == 'closed':
                self.rect(x, ey + 2, x + 2, ey + 2, col)
            elif kind == 'happy':
                self.put(x, ey + 3, col); self.put(x + 1, ey + 1, col)
                self.put(x + 2, ey + 3, col); self.put(x + 1, ey + 2, col)
                self.put(x, ey + 2, col); self.put(x + 2, ey + 2, col)
            elif kind == 'sad':
                self.put(x, ey + 1, col); self.put(x + 1, ey + 3, col)
                self.put(x + 2, ey + 1, col); self.put(x + 1, ey + 2, col)
            elif kind == 'dizzy':
                self.put(x, ey, col); self.put(x + 2, ey, col); self.put(x + 1, ey + 1, col)
                self.put(x, ey + 2, col); self.put(x + 2, ey + 2, col)
            elif kind == 'angry':
                self.rect(x, ey + 2, x + 2, ey + 3, col)
                if left:
                    self.put(x, ey - 1, col); self.put(x + 1, ey, col); self.put(x + 2, ey + 1, col)
                else:
                    self.put(x, ey + 1, col); self.put(x + 1, ey, col); self.put(x + 2, ey - 1, col)
            elif kind == 'cross':
                self.rect(x, ey + 1, x + 2, ey + 3, col)
                if left:
                    self.put(x, ey - 1, col); self.put(x + 1, ey - 1, col)
                else:
                    self.put(x + 1, ey - 1, col); self.put(x + 2, ey - 1, col)
            elif kind == 'heart':
                hc = 'g'
                for (a, b2) in ((0, 0), (2, 0), (0, 1), (1, 1), (2, 1), (1, 2)):
                    self.put(x + a, ey + 1 + b2, hc)
            elif kind == 'glitch':
                self.rect(x + (1 if left else -1), ey, x + 2 + (1 if left else -1), ey + 1, col)
                self.rect(x, ey + 3, x + 1, ey + 3, col)
            elif kind == 'look':
                self.rect(x + 1, ey, x + 2, ey + 3, col)
                if not screen:
                    self.put(x + 1, ey, 'w')
        return self

    def mouth(self, kind='smile', side=0):
        screen = self.sp.get('screen')
        col = 'a' if screen else 'e'
        my = self.row(self.sp['mouth_f'])
        c = self.centre(my) + side
        if kind == 'smile':
            self.put(c - 1, my, col); self.put(c, my + 1, col); self.put(c + 1, my, col)
        elif kind == 'grin':
            self.rect(c - 2, my, c + 2, my, col); self.rect(c - 1, my + 1, c + 1, my + 1, col)
        elif kind == 'flat':
            self.rect(c - 1, my, c + 1, my, col)
        elif kind == 'open':
            self.rect(c - 1, my, c + 1, my + 1, col)
        elif kind == 'o':
            self.rect(c - 1, my, c, my + 1, col)
        elif kind == 'frown':
            self.put(c - 1, my + 1, col); self.put(c, my, col); self.put(c + 1, my + 1, col)
        elif kind == 'wobble':
            self.put(c - 2, my, col); self.put(c - 1, my + 1, col)
            self.put(c, my, col); self.put(c + 1, my + 1, col)
        elif kind == 'yawn':
            self.rect(c - 1, my - 1, c + 1, my + 2, col)
        return self

    def beak(self, open_=False):
        if self.sp['kind'] != 'bird':
            return self
        y = self.row(0.44)
        c = self.centre(y)
        self.rect(c - 1, y, c + 1, y, 'a'); self.put(c, y + 1, 'a')
        if open_:
            self.put(c, y + 1, 'e'); self.rect(c - 1, y + 2, c + 1, y + 2, 'a')
        return self

    def cheeks(self):
        cy = self.row(self.sp['eye_f']) + 5
        hw = self.hw(min(1.0, self.sp['eye_f'] + 0.18))
        c = self.centre(cy)
        col = 'p'
        self.rect(c - hw + 1, cy, c - hw + 2, cy, col)
        self.rect(c + hw - 2, cy, c + hw - 1, cy, col)
        return self

    # ------------------------------------------------------------ hats ---
    def hat(self, kind):
        t, c = self.headtop()
        if kind == 'beanie':
            for i, w in enumerate((3, 5, 6, 7)):
                self.rect(c - w, t - 3 + i, c + w, t - 3 + i, 'q')
            self.rect(c - 7, t + 1, c + 7, t + 1, 'u')
            self.disc(c, t - 4.5, 1.3, 'u')
        elif kind == 'crown':
            self.rect(c - 5, t - 2, c + 5, t, 'v')
            for x in (c - 5, c - 2, c + 1, c + 4):
                self.rect(x, t - 4, x + 1, t - 3, 'v')
            self.put(c - 1, t - 1, 'n'); self.put(c, t - 1, 'n')
        elif kind == 'headphones':
            l = c - self.hw(0.2) - 1
            r = c + self.hw(0.2) + 1
            for x in range(l + 1, r):
                self.put(x, t - 1, 'q')
            self.rect(l - 1, t + 3, l + 1, t + 6, 'q'); self.rect(r - 1, t + 3, r + 1, t + 6, 'q')
            self.rect(l, t + 4, l, t + 5, 'n'); self.rect(r, t + 4, r, t + 5, 'n')
            self.rect(l, t - 1, l, t + 2, 'q'); self.rect(r, t - 1, r, t + 2, 'q')
        elif kind == 'party':
            for i in range(6):
                w = i // 2
                col = 'n' if i % 2 == 0 else 'v'
                self.rect(c - w, t - 6 + i, c + w, t - 6 + i, col)
            self.put(c, t - 7, 'u')
        elif kind == 'wizard':
            for i in range(7):
                w = i // 2 + (1 if i > 4 else 0)
                self.rect(c - w + 1, t - 7 + i, c + w + 1, t - 7 + i, 'm')
            self.rect(c - 6, t, c + 6, t, 'm')
            self.put(c + 1, t - 3, 'v')
        elif kind == 'glasses':
            ey = self.row(self.sp['eye_f'])
            ec = self.centre(ey)
            dx = self.sp['eye_dx']
            for sx in (-dx - 1, dx - 3):
                x = ec + sx
                self.rect(x, ey - 1, x + 4, ey - 1, 'k'); self.rect(x, ey + 4, x + 4, ey + 4, 'k')
                self.rect(x, ey - 1, x, ey + 4, 'k'); self.rect(x + 4, ey - 1, x + 4, ey + 4, 'k')
            self.rect(ec - dx + 4, ey + 1, ec + dx - 4, ey + 1, 'k')
        return self

    # ----------------------------------------------------------- props ---
    def sign(self):
        by = self.row(0.54)
        c = self.centre(by)
        self.rect(c - 5, by, c + 5, by + 4, 'f')
        self.rect(c - 7, by - 2, c - 6, by + 6, 'k'); self.rect(c + 6, by - 2, c + 7, by + 6, 'k')
        self.rect(c - 7, by - 2, c + 7, by - 1, 'k'); self.rect(c - 7, by + 5, c + 7, by + 6, 'k')
        self.rect(c - 4, by + 1, c + 3, by + 1, 'l'); self.rect(c - 4, by + 3, c, by + 3, 'l')
        self.rect(c - 9, by + 3, c - 8, by + 5, 'c'); self.rect(c + 8, by + 3, c + 9, by + 5, 'c')
        return self

    def flag(self, up=True):
        ay = self.row(self.sp['arm_f'])
        x = self.centre(ay) + self.hw(self.sp['arm_f']) + 3
        ty = self.top + (0 if up else 4)
        self.rect(x, ty, x, ay - 2, 'k')
        self.rect(x + 1, ty, x + 6, ty + 4, 'g')
        return self

    def bowl(self, level=2):
        b = self.bottom + 3
        c = self.centre(self.bottom) + 10
        self.rect(c - 4, b - 2, c + 4, b, 'k')
        if level > 0:
            self.rect(c - 3, b - 3, c + 3, b - 3, 'y')
        if level > 1:
            self.rect(c - 2, b - 4, c + 2, b - 4, 'y')
        return self

    # ---------------------------------------------------------- extras ---
    def sparkles(self):
        t, c = self.top, CX
        for (x, y) in ((c - 13, t + 1), (c + 13, t + 4), (c - 11, t + 14), (c + 14, t + 13), (c + 1, t - 6)):
            for (a, b) in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
                self.put(x + a, y + b, 'y')
        return self

    def zees(self):
        t, c = self.top, CX
        for (x, y, n) in ((c + 10, t - 1, 3), (c + 14, t - 5, 2)):
            self.rect(x, y, x + n - 1, y, 'e'); self.put(x + n - 2, y + 1, 'e')
            self.rect(x, y + 2, x + n - 1, y + 2, 'e')
        return self

    def heart(self):
        t, c = self.headtop()
        x, y = c + 7, t - 3
        for (a, b) in ((0, 0), (1, 0), (3, 0), (4, 0), (0, 1), (1, 1), (2, 1), (3, 1), (4, 1),
                       (1, 2), (2, 2), (3, 2), (2, 3)):
            self.put(x + a, y + b, 'g')
        return self

    def anger(self):
        t, c = self.headtop()
        x, y = c + 6, t
        for (a, b) in ((0, 0), (2, 0), (1, 1), (0, 2), (2, 2)):
            self.put(x + a, y + b, 'g')
        return self

    def sweat(self):
        t, c = self.headtop()
        x, y = c - 8, t + 2
        self.put(x, y, 't'); self.rect(x - 1, y + 1, x + 1, y + 2, 't')
        return self

    def notes(self, phase=0):
        t, c = self.headtop()
        for i, (dx, dy) in enumerate(((7, -2), (11, -6))):
            y = t + dy - phase
            x = c + dx
            self.rect(x + 1, y - 3, x + 1, y, 'k'); self.rect(x - 1, y, x, y + 1, 'k')
            self.put(x + 2, y - 3, 'k')
        return self

    def rain(self, phase=0):
        b = self.bottom
        l, r = self.spans[b]
        for i, x in enumerate(range(l + 1, r, 3)):
            y = b + 2 + ((i + phase) % 3) * 2
            self.rect(x, y, x, y + 1, 't')
        return self

    def ink(self, phase=0):
        my = self.row(self.sp['mouth_f'])
        x = self.centre(my) + 6
        r = 1.5 + phase
        self.disc(x + 2 + phase * 2, my, r, 'k', only_empty=True)
        return self

    def glitch_screen(self, seed=0):
        rnd = random.Random(seed)
        for (x, y), c in list(self.g.items()):
            if c == 'x' and rnd.random() < 0.18:
                self.g[(x, y)] = 'a'
        return self

    def outline(self):
        solid = {k for k, v in self.g.items() if v in OUTLINED}
        ring = set()
        for (x, y) in solid:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in solid and n not in self.g:
                    ring.add(n)
        for p in ring:
            self.g[p] = 'o'
        return self

    def shadow(self, gap=3):
        if self.sp['legs'] != 'none_float':
            return self
        ys = [y for (x, y) in self.g]
        b = max(ys) + gap
        c = self.centre(self.bottom)
        w = max(4, int(self.prof[-1] * 0.8))
        for x in range(c - w, c + w + 1):
            self.g[(x, b)] = 'z'
        for x in range(c - w + 2, c + w - 1):
            self.g[(x, b + 1)] = 'z'
        return self


# ------------------------------------------------------------------ poses --

def make(key, top=6, rows=None, widen=0, lean=0.0, scale=1.0, eye='open', mo='smile',
         leg='stand', arm='down', cheek=False, sign=False, flag=False, flag_up=True,
         spark=False, zzz=False, food=None, heart=False, anger=False, sweat=False,
         notes=None, rain=None, ink=None, glitch=None, grow=0, flare=0, phase=0,
         hat=None, beak_open=False, back=False, side=0, egg=None, split=False):
    sp = SPECIES[key]
    if egg is not None:
        return make_egg(key, egg)
    float_ = sp['legs'] in ('none_float', 'none_ground')
    if float_ and leg.startswith('walk'):
        n = int(leg[-1])
        top += (0, -1, 0, -1)[n - 1]
        widen += (0, 0, 1, 0)[n - 1] if sp['legs'] == 'none_ground' else 0
    b = Body(sp, top, rows, widen, lean, scale)
    b.fill()
    if not float_:
        b.legs(leg)
    elif sp['legs'] == 'none_ground':
        b.legs(leg)
    b.arms(arm)
    b.shade()
    if not back:
        b.belly()
    b.decor(grow=grow, flare=flare, phase=phase)
    if not back:
        if side:
            ey = b.row(sp['eye_f']); c = b.centre(ey)
            col = 'a' if sp.get('screen') else 'e'
            b.rect(c + 2, ey, c + 4, ey + 3, col)
            if not sp.get('screen'):
                b.put(c + 2, ey, 'w')
            b.mouth(mo, side=4)
        else:
            b.eyes(eye)
            b.mouth(mo)
        b.beak(beak_open)
        if cheek:
            b.cheeks()
    if glitch is not None:
        b.glitch_screen(glitch)
    if hat:
        b.hat(hat)
    if sign:
        b.sign()
    if flag:
        b.flag(flag_up)
    if food is not None:
        b.bowl(food)
    b.outline()
    if spark:
        b.sparkles()
    if zzz:
        b.zees()
    if heart:
        b.heart()
    if anger:
        b.anger()
    if sweat:
        b.sweat()
    if notes is not None:
        b.notes(notes)
    if rain is not None:
        b.rain(rain)
    if ink is not None:
        b.ink(ink)
    if split:
        g2 = make(key, top=top + 8, rows=max(6, (rows or len(sp['profile'])) // 2), scale=0.6,
                  eye='happy', mo='smile', cheek=True)[0]
        for (x, y), c in g2.items():
            b.g[(x + 14, y)] = c
    b.shadow()
    return b.g, 0


def make_egg(key, stage):
    """stage 0 = egg, 1 = cracked, 2 = hatching (eyes peeking)."""
    sp = SPECIES[key]
    b = Body(sp, 12, None, 0, 0, 1.0)
    b.spans = {}
    prof = [3, 4, 5, 6, 6, 7, 7, 7, 7, 7, 6, 5]
    for i, hw in enumerate(prof):
        b.spans[12 + i] = (CX - hw, CX + hw)
    b.prof, b.rows, b.top = prof, len(prof), 12
    for y, (l, r) in b.spans.items():
        for x in range(l, r + 1):
            b.put(x, y, 'u')
    for (dx, dy) in ((-3, 3), (2, 2), (3, 6), (-2, 8), (1, 9)):
        b.put(CX + dx, 12 + dy, 'y'); b.put(CX + dx + 1, 12 + dy, 'y')
    if stage >= 1:
        for (x, y) in ((CX - 4, 17), (CX - 3, 16), (CX - 2, 17), (CX - 1, 16), (CX, 17), (CX + 1, 16), (CX + 2, 17)):
            b.put(x, y, 'e')
    if stage >= 2:
        b.rect(CX - 5, 12, CX + 5, 16, 'c')
        b.rect(CX - 3, 13, CX - 2, 15, 'e'); b.rect(CX + 2, 13, CX + 3, 15, 'e')
        b.put(CX - 3, 13, 'w'); b.put(CX + 2, 13, 'w')
    solid = {k for k, v in b.g.items() if v in ('u', 'c', 'y')}
    for (x, y) in list(solid):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in b.g:
                b.g[n] = 'o'
    return b.g, 0


def peek(key, eye='open'):
    """Just the eyes and the crown of the head, for Notch Live compact."""
    g, _ = make(key, top=6, eye=eye, mo='flat')
    sp = SPECIES[key]
    cut = 6 + int(round(sp['eye_f'] * (len(sp['profile']) - 1))) + 5
    return {k: v for k, v in g.items() if k[1] <= cut}, 0


def hatchling(key, eye='wide'):
    """The pet's head poking out of the bottom half of its eggshell."""
    sp = SPECIES[key]
    g, _ = make(key, top=6, eye=eye, mo='smile', cheek=True, arm='none', leg='tuck')
    my = 6 + int(round(sp['mouth_f'] * (len(sp['profile']) - 1)))
    cut = my + 2
    head = {k: v for k, v in g.items() if k[1] <= cut}
    xs = [x for (x, y) in head if y == cut]
    hw = max(6, (max(xs) - min(xs)) // 2) if xs else 7
    c = (max(xs) + min(xs)) // 2 if xs else CX
    out = dict(head)
    shell = {}
    for i, w in enumerate((hw, hw, hw, hw - 1, hw - 2, hw - 4)):
        for x in range(c - w, c + w + 1):
            shell[(x, cut - 1 + i)] = 'u'
    for x in range(c - hw, c + hw + 1):
        if (x - c) % 3 == 0:
            shell[(x, cut - 2)] = 'u'
    for (dx, dy) in ((-3, 1), (2, 2), (4, 0)):
        shell[(c + dx, cut + dy)] = 'y'
    out.update(shell)
    for (x, y) in list(shell):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in out:
                out[n] = 'o'
    return out, 0


# ---------------------------------------------------------------- the rows --

def rows_for(key):
    sp = SPECIES[key]
    flo = sp['legs'] in ('none_float',)
    special = {
        'notchi': [dict(arm='up', eye='closed', mo='yawn'), dict(top=4, rows=21, arm='up', eye='closed', mo='yawn'),
                   dict(top=5, arm='up', eye='happy', mo='open'), dict(arm='out', eye='happy', mo='smile', cheek=True)],
        'pip': [dict(beak_open=True, notes=0, eye='happy'), dict(top=5, beak_open=True, notes=1, eye='happy', arm='up'),
                dict(beak_open=True, notes=2, eye='closed', arm='out'), dict(eye='happy', cheek=True)],
        'moss': [dict(grow=0, eye='closed', mo='flat'), dict(grow=1, eye='open', mo='o'),
                 dict(grow=2, eye='wide', mo='open', arm='up'), dict(grow=2, eye='happy', mo='smile', cheek=True)],
        'gloop': [dict(rows=11, widen=1, eye='closed', mo='flat'), dict(rows=9, widen=2, eye='closed', mo='wobble'),
                  dict(rows=10, widen=1, eye='happy', mo='smile', split=True), dict(eye='happy', mo='grin', cheek=True, split=True)],
        'byte': [dict(eye='glitch', mo='flat', glitch=1), dict(eye='dizzy', mo='wobble', glitch=2, lean=0.05),
                 dict(eye='glitch', mo='flat', glitch=3, lean=-0.05), dict(eye='open', mo='smile')],
        'puff': [dict(eye='sad', mo='frown', rain=0), dict(eye='sad', mo='frown', rain=1),
                 dict(eye='closed', mo='frown', rain=2), dict(eye='droop', mo='flat', rain=0)],
        'wisp': [dict(flare=1, eye='open'), dict(flare=3, eye='wide', mo='open', phase=1),
                 dict(flare=5, eye='happy', mo='grin', phase=2, spark=True), dict(flare=2, eye='happy', cheek=True, phase=3)],
        'tako': [dict(eye='angry', mo='o', ink=0), dict(eye='angry', mo='o', ink=1, arm='out'),
                 dict(eye='closed', mo='o', ink=2), dict(eye='cross', mo='flat', ink=3)],
    }[key]
    R = [
        # 0 eat
        [dict(food=2), dict(top=7, food=2, mo='open', arm='out'), dict(top=8, rows=None, food=1, eye='closed', mo='open', arm='out'),
         dict(top=8, food=1, eye='closed', mo='flat', arm='out'), dict(top=7, food=0, mo='open', arm='out'),
         dict(food=0, eye='happy', mo='smile', cheek=True)],
        # 1 walk
        [dict(leg='walk1', arm='out', lean=0.03, phase=0), dict(top=5, leg='walk2', lean=0.02, phase=1),
         dict(leg='walk3', arm='out', lean=0.03, phase=2), dict(top=5, leg='walk4', lean=0.02, phase=3),
         dict(leg='walk1', arm='out', lean=0.03, eye='closed', phase=0), dict(top=5, leg='walk2', lean=0.02, phase=1),
         dict(leg='walk3', arm='out', lean=0.03, phase=2), dict(top=5, leg='walk4', lean=0.02, phase=3)],
        # 2 climb (rotated at render time)
        [dict(leg='walk1', arm='up', mo='flat', phase=0), dict(leg='walk2', arm='out', mo='flat', phase=1),
         dict(leg='walk3', arm='up', mo='flat', phase=2), dict(leg='walk4', arm='out', mo='flat', phase=3),
         dict(leg='walk1', arm='up', mo='flat', eye='closed', phase=0), dict(leg='walk2', arm='out', mo='flat', phase=1),
         dict(leg='walk3', arm='up', mo='flat', phase=2), dict(leg='walk4', arm='out', mo='flat', phase=3)],
        # 3 greet
        [dict(leg='tuck', arm='up', eye='wide', mo='o'), dict(leg='spread', arm='out', eye='wide', mo='open'),
         dict(top=10, widen=1, leg='spread', arm='out', eye='closed', mo='flat', rows=max(8, len(sp['profile']) - 6)),
         dict(arm='wave', eye='happy', mo='smile', cheek=True)],
        # 4 celebrate
        [dict(arm='up', eye='happy', mo='grin', cheek=True, spark=True), dict(top=4, side=1, arm='up', mo='smile', spark=True),
         dict(top=3, arm='up', eye='happy', mo='grin', spark=True), dict(top=4, side=1, arm='up', mo='smile', spark=True),
         dict(arm='up', eye='happy', mo='grin', cheek=True, spark=True)],
        # 5 idle
        [dict(), dict(leg='tap', mo='flat'), dict(eye='closed', mo='flat'), dict(eye='look', mo='flat'),
         dict(eye='droop', mo='frown', sweat=True), dict(top=10, rows=max(8, len(sp['profile']) - 6), widen=1, leg='tuck', eye='closed', mo='flat', zzz=True),
         dict(top=11, rows=max(7, len(sp['profile']) - 7), widen=1, leg='tuck', eye='closed', mo='flat', zzz=True),
         dict(top=4, arm='up', eye='wide', mo='open')],
        # 6 sign
        [dict(sign=True, mo='flat'), dict(top=5, sign=True, mo='flat', phase=1), dict(sign=True, eye='closed', mo='flat', phase=2),
         dict(top=5, sign=True, mo='smile', phase=3), dict(sign=True, mo='flat'), dict(top=5, sign=True, cheek=True, phase=1)],
        # 7 flag
        [dict(top=9, widen=1, arm='raise', flag=True, flag_up=False, eye='wide', mo='open', rows=max(8, len(sp['profile']) - 3)),
         dict(top=3, leg='air', arm='up', flag=True, eye='wide', mo='open'),
         dict(top=2, leg='air', arm='up', flag=True, eye='wide', mo='o'),
         dict(arm='raise', flag=True, flag_up=False, mo='open'),
         dict(top=9, widen=1, arm='raise', flag=True, flag_up=False, eye='wide', mo='open', rows=max(8, len(sp['profile']) - 3)),
         dict(top=3, leg='air', arm='up', flag=True, eye='wide', mo='o')],
        # 8 fail
        [dict(top=7, lean=0.09, leg='walk1', arm='out', eye='wide', mo='o'),
         dict(top=14, rows=max(6, len(sp['profile']) - 8), widen=2, lean=0.12, leg='spread', arm='out', eye='dizzy', mo='flat'),
         dict(top=16, rows=max(5, len(sp['profile']) - 10), widen=2, leg='spread', arm='out', eye='closed', mo='wobble'),
         dict(top=16, rows=max(5, len(sp['profile']) - 10), widen=2, leg='spread', arm='out', eye='dizzy', mo='wobble'),
         dict(top=8, leg='stand', eye='sad', mo='frown', sweat=True), dict(eye='sad', mo='frown')],
        # 9 hover
        [dict(eye='wide', mo='smile', arm='out'), dict(top=5, eye='happy', mo='grin', cheek=True, arm='up', heart=True),
         dict(side=1, mo='smile'), dict(eye='heart', mo='smile', cheek=True, arm='out', heart=True)],
        # 10 annoy
        [dict(eye='cross', mo='flat'), dict(eye='angry', mo='frown', arm='out'),
         dict(widen=1, eye='angry', mo='frown', arm='out', anger=True),
         dict(top=7, widen=1, eye='angry', mo='open', arm='up', cheek=True, anger=True),
         dict(top=9, widen=2, eye='angry', mo='open', arm='out', leg='spread', cheek=True, anger=True),
         dict(top=7, widen=1, eye='angry', mo='open', arm='up', cheek=True, anger=True)],
        # 11 special move
        special,
        # 12 evolution: egg, crack, hatching, hatchling, hatchling blink, elder
        [dict(egg=0), dict(egg=1), dict(egg=2),
         'hatch_wide', 'hatch_closed',
         dict(top=5, eye='open', mo='smile', hat='glasses', widen=1)],
        # 13 wardrobe
        [dict(hat='beanie'), dict(hat='crown', eye='happy', cheek=True), dict(hat='headphones', eye='closed', mo='smile'),
         dict(hat='party', eye='happy', mo='grin', cheek=True), dict(hat='wizard', eye='look'), dict(hat='glasses', mo='flat')],
        # 14 peek (for the notch)
        ['peek_open', 'peek_look', 'peek_closed', 'peek_open'],
    ]
    return R


ROW_NAMES = ['eat', 'walk', 'climb', 'greet', 'celebrate', 'idle', 'sign', 'flag', 'fail',
             'hover', 'annoy', 'special', 'evolve', 'wardrobe', 'peek']


def build(key):
    frames = []
    for r, row in enumerate(rows_for(key)):
        out = []
        for f in row:
            if isinstance(f, str) and f.startswith('hatch'):
                g, lift = hatchling(key, f.split('_')[1])
            elif isinstance(f, str):
                eye = {'peek_open': 'open', 'peek_look': 'look', 'peek_closed': 'closed'}[f]
                g, lift = peek(key, eye)
            else:
                g, lift = make(key, **f)
                if r == 2:
                    g = {(H + 2 - y, x): c for (x, y), c in g.items()}
            out.append((g, lift))
        frames.append(out)
    return frames


# ---------------------------------------------------------------- render ---

CW, CH, COLS, SCALE, BASE = 192, 208, 8, 7, 194


def paste(img, g, col, row, pal, lift=0, anchor='feet'):
    xs = [x for (x, y) in g]
    ys = [y for (x, y) in g]
    if not xs:
        return
    h = (max(ys) + 1 - min(ys)) * SCALE
    w = (max(xs) + 1 - min(xs)) * SCALE
    s = SCALE
    if h > CH - 6 or w > CW - 4:           # shrink to fit rather than clip
        s = max(3, min((CH - 8) // (max(ys) + 1 - min(ys)), (CW - 6) // (max(xs) + 1 - min(xs))))
        h = (max(ys) + 1 - min(ys)) * s
    ox = col * CW + CW // 2 - int((min(xs) + max(xs) + 1) / 2 * s)
    if anchor == 'top':
        oy = row * CH + 6 - min(ys) * s
    else:
        oy = row * CH + BASE - lift - (max(ys) + 1) * s
    dr = ImageDraw.Draw(img)
    for (x, y), c in g.items():
        px, py = ox + x * s, oy + y * s
        dr.rectangle([px, py, px + s - 1, py + s - 1], fill=pal[c])


def render(key, outdir):
    frames = build(key)
    pal = palette(SPECIES[key])
    img = Image.new('RGBA', (COLS * CW, len(frames) * CH), (0, 0, 0, 0))
    for r, row in enumerate(frames):
        for c, (g, lift) in enumerate(row):
            paste(img, g, c, r, pal, lift, anchor='top' if r == 14 else 'feet')
    d = os.path.join(outdir, f'notchi-{key}' if key != 'notchi' else 'notchi')
    os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, 'spritesheet.webp'), 'WEBP', lossless=True, quality=100)
    img.save(os.path.join(d, 'spritesheet.png'), 'PNG')
    sp = SPECIES[key]
    json.dump({
        'id': os.path.basename(d), 'displayName': sp['name'],
        'description': sp['line'], 'spriteVersionNumber': 3,
        'spritesheetPath': 'spritesheet.webp',
        'notchi': {'species': key, 'accent': '#' + sp['accent'],
                   'rows': {n: {'row': i, 'frames': len(frames[i])} for i, n in enumerate(ROW_NAMES)}}
    }, open(os.path.join(d, 'pet.json'), 'w'), indent=2)
    return img


if __name__ == '__main__':
    out = os.path.join(HERE, 'packs')
    for k in ORDER:
        im = render(k, out)
        print(k, im.size)
