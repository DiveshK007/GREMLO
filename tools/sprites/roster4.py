"""Notchi 1.0, round four: bugs, git moods, tricks, the room.

Builds on roster3.py. New pet rows 31-38 and a shared props sheet.
  31 chase      6  run after the bug, pounce
  32 gulp       6  catch, chomp, chew, happy
  33 covereyes  4  force push: paws over eyes, one peek
  34 tangled    4  merge conflict: wrapped in yarn
  35 backflip   6  crouch, jump, three quarter-turns, land  (app adds the jump arc)
  36 juggle     4  three balls
  37 moonwalk   4  leaning back, shades on
  38 wrist      4  meeting soon: checks its watch, taps it, waves

props.png: bug frames, yarn, dream icons, seasonal decor, room furniture,
footprint. 1 px = 1 sprite unit; props.json lists every cell.
"""
import importlib.util, sys, os, json
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('roster3', os.path.join(HERE, 'roster3.py'))
R3 = importlib.util.module_from_spec(spec)
sys.modules['roster3'] = R3
spec.loader.exec_module(R3)
R2, R = R3.R2, R3.R
Body, SPECIES, CX = R.Body, R.SPECIES, R.CX
CW, CH, COLS = 192, 208, 8

# ------------------------------------------- extra pre-outline drawings ---
_hat3 = Body.hat


def arm_c(b):
    return R2.arm_col(b.sp)


def paw(b, x0, y0, w, h):
    col = arm_c(b)
    b.rect(x0 - 1, y0 - 1, x0 + w, y0 + h, 'o')
    b.rect(x0, y0, x0 + w - 1, y0 + h - 1, col)


def hat(self, kind):
    if not kind or kind.split(':')[0] not in ('cover', 'peek1', 'yarn', 'balls', 'wrist', 'tap'):
        return _hat3(self, kind)
    k, _, arg = kind.partition(':')
    ey = self.row(self.sp['eye_f'])
    ec = self.centre(ey)
    dx = self.sp['eye_dx']
    if k in ('cover', 'peek1'):
        paw(self, ec + dx - 4, ey - 1, 5, 5)
        if k == 'cover':
            paw(self, ec - dx - 1, ey - 1, 5, 5)
    elif k == 'yarn':
        ph = int(arg or 0)
        top = self.top + 3
        for i, y in enumerate(range(top + ph, self.bottom - 1, 4)):
            sp = self.spans.get(y)
            if not sp:
                continue
            l, r = sp
            for x in range(l - 1, r + 2):
                yy = y + ((x - l) * (1 if i % 2 else -1)) // 6
                self.put(x, yy, 'n')
        bx, by = ec + 9, self.bottom + 1
        self.disc(bx, by - 2, 2.4, 'n')
        self.put(bx - 1, by - 3, 'u'); self.put(bx + 1, by - 1, 'u')
    elif k == 'balls':
        ph = int(arg or 0)
        t, c = self.headtop()
        spots = [(c - 7, t - 4), (c, t - 9), (c + 7, t - 4), (c, t - 2)]
        cols = ['n', 'v', 't']
        for i in range(3):
            x, y = spots[(i + ph) % 4]
            self.disc(x, y, 1.4, cols[i])
    elif k in ('wrist', 'tap'):
        ay = self.row(self.sp['arm_f'])
        hw = self.hw(self.sp['arm_f'])
        c = self.centre(ay)
        col = arm_c(self)
        L = c - hw - 1
        self.rect(L - 1, ay - 3, L + 4, ay - 2, col)   # forearm across the chest
        self.rect(L + 2, ay - 4, L + 3, ay - 1, 'k')    # watch strap
        self.put(L + 2, ay - 3, 'v'); self.put(L + 3, ay - 3, 'v')
        if k == 'tap':
            paw(self, L + 5, ay - 5, 2, 2)
    return self


Body.hat = hat
make = R3.with_hat


def rows4(key):
    sp = SPECIES[key]
    n = len(sp['profile'])
    flo = sp['legs'] in ('none_float', 'none_ground')
    L = lambda i: ('walk1', 'walk3', 'walk2', 'walk3')[i % 4]
    chase = [make(key, None, top=6 + (i % 2), lean=0.14, leg=L(i), arm='out', eye='wide', mo='open', phase=i) for i in range(4)]
    chase += [make(key, None, top=4, rows=n + 1, lean=0.2, leg='spread', arm='up', eye='wide', mo='open'),
              make(key, None, top=8, rows=n - 2, widen=1, lean=0.1, leg='spread', arm='out', eye='happy', mo='grin')]
    gulp = [make(key, None, eye='wide', mo='open', arm='out'),
            make(key, None, top=7, rows=n - 1, eye='closed', mo='o'),
            make(key, None, widen=1, eye='happy', mo='flat', cheek=True),
            make(key, None, widen=1, eye='closed', mo='flat', cheek=True),
            make(key, None, eye='happy', mo='grin', cheek=True),
            make(key, None, top=5, eye='heart', mo='smile', heart=True)]
    cover = [make(key, 'cover', mo='o'), make(key, 'cover', mo='o', sweat=True),
             make(key, 'peek1', eye='wide', mo='o'), make(key, 'cover', mo='flat')]
    tangled = [make(key, 'yarn:%d' % i, eye=('cross' if i % 2 else 'dizzy'), mo='wobble', lean=(0.05 if i % 2 else -0.05),
                    sweat=(i == 2)) for i in range(4)]
    tuck = make(key, None, leg='tuck', arm='up', eye='closed', mo='grin')
    flip = [make(key, None, top=9, rows=n - 3, widen=1, leg='spread', arm='down', eye='closed', mo='flat'),
            make(key, None, top=3, rows=n + 2, arm='up', eye='wide', mo='open'),
            R2.rot(tuck, 1), R2.rot(tuck, 2), R2.rot(tuck, 3),
            make(key, None, top=5, arm='up', eye='happy', mo='grin', cheek=True, spark=True)]
    juggle = [make(key, 'balls:%d' % i, arm=('raise' if i % 2 else 'wave'), eye='look', mo='smile') for i in range(4)]
    moon = [make(key, 'shades', lean=-0.08, leg=('walk2', 'walk4', 'walk1', 'walk3')[i], arm='out', mo='grin') for i in range(4)]
    if flo:
        moon = [make(key, 'shades', lean=-0.08, top=6 + (i % 2), arm='out', mo='grin') for i in range(4)]
    wrist = [make(key, 'wrist', eye='look', mo='flat'), make(key, 'tap', eye='look', mo='o'),
             make(key, 'wrist', eye='wide', mo='o'), make(key, None, arm='wave', eye='happy', mo='smile')]
    return [chase, gulp, cover, tangled, flip, juggle, moon, wrist]


NAMES = R3.NAMES + ['chase', 'gulp', 'covereyes', 'tangled', 'backflip', 'juggle', 'moonwalk', 'wrist']

# ------------------------------------------------------------------ props --
PAL = {'o': (11, 11, 11), 'k': (26, 26, 28), 'n': (232, 68, 58), 'w': (244, 242, 237), 'y': (255, 201, 60),
       'g': (143, 209, 79), 'G': (82, 121, 45), 'b': (76, 201, 255), 'B': (44, 118, 150), 'p': (180, 140, 255),
       'P': (255, 122, 182), 'O': (255, 138, 42), 'c': (241, 217, 166), 't': (122, 78, 45), 'T': (74, 47, 27),
       's': (138, 143, 152), 'S': (201, 205, 211), 'r': (36, 36, 44)}

ART = {
 'bug0': ["....nnnn.....", "..nnnnnnnn...", ".nnknnnnknnkk", "nnnnnnnnnnnkk", ".nknnnnnknnk.", "..nnnnnnnnn..", "..k..k..k....", ".k..k..k....."],
 'bug1': ["....nnnn.....", "..nnnnnnnn...", ".nnknnnnknnkk", "nnnnnnnnnnnkk", ".nknnnnnknnk.", "..nnnnnnnnn..", "...k..k..k...", "....k..k..k.."],
 'bug2': ["....nnnn.....", "..nnnnnnnn...", ".nnknnnnknnkk", "nnnnnnnnnnnkk", ".nknnnnnknnk.", "..nnnnnnnnn..", "..k...k.k....", "...k.k...k..."],
 'bug3': ["....nnnn.....", "..nnnnnnnn...", ".nnknnnnknnkk", "nnnnnnnnnnnkk", ".nknnnnnknnk.", "..nnnnnnnnn..", "...k.k...k...", "..k...k.k...."],
 'bugsquash': ["..k.......k..", ".nnnnnnnnnnkk", "nnknnnknnnnkk", "..k..k..k..k."],
 'yarn': ["..PPPPP...", ".PPwPPPP..", "PPPPwPPPP.", "PwPPPwPPP.", "PPwPPPwPP.", "PPPwPPPwP.", "PPPPwPPPP.", ".PPPPwPP..", "..PPPPP.PP", "........PP"],
 'd-wrench': ["ss.....", "s.s....", ".sss...", "...s...", "....s..", ".....ss", ".....ss"],
 'd-flask': ["..SSS..", "...S...", "...S...", "..SbS..", ".SbbbS.", "SbbbbbS", "SSSSSSS"],
 'd-bug': [".k...k.", "..k.k..", ".nnnnn.", "nnknknn", "nnnnnnn", ".nnknn.", "..n.n.."],
 'd-star': ["...y...", "...y...", "yyyyyyy", ".yyyyy.", "..yyy..", ".yy.yy.", "y.....y"],
 'd-moon': ["..yyy..", ".yy....", "yy.....", "yy.....", "yy.....", ".yy....", "..yyy.."],
 'd-heart': [".nn.nn.", "nnnnnnn", "nnnnnnn", ".nnnnn.", "..nnn..", "...n..."],
 'd-check': ["......g", ".....gg", "g...gg.", "gg.gg..", ".ggg...", "..g...."],
 'd-merge': ["b.....b", "b.....b", "b....b.", "b...b..", "b..b...", "bbb....", "b......"],
 's-diya': [".....y.....", "....yOy....", "....yOy....", ".....O.....", "OO.......OO", ".OOOOOOOOO.", "..OcccccO..", "...OOOOO..."],
 's-snow': ["....b....", ".b..b..b.", "..b.b.b..", "...bbb...", "bbbbwbbbb", "...bbb...", "..b.b.b..", ".b..b..b.", "....b...."],
 's-pumpkin': ["....g....", "...tg....", ".OOOOOOO.", "OOOOOOOOO", "OOkOOOkOO", "OOOOOOOOO", "OOOkkkOOO", ".OOOOOOO."],
 's-lantern': ["...T...", "..TTT..", ".nnnnn.", "nnyyynn", "nnyyynn", "nnyyynn", ".nnnnn.", "..TTT.."],
 'f-rug': ["....PPPPPPPPPPPPPPPP....", "..PPwwPPwwPPwwPPwwPPPP..", "PPPPPPPPPPPPPPPPPPPPPPPP", "..PPwwPPwwPPwwPPwwPPPP..", "....PPPPPPPPPPPPPPPP...."],
 'f-lamp': ["..yyyyy..", ".yyyyyyy.", "yyyyyyyyy", "....T....", "....T....", "....T....", "....T....", "....T....", "....T....", "....T....", "....T....", "....T....", "...TTT...", "..TTTTT.."],
 'f-plant': ["....g.g....", "..g.ggg.g..", ".gg.gGg.gg.", "..ggg.ggg..", "g..gGggg..g", "gg..ggg..gg", ".ggg.g.ggg.", "...ggggg...", "..OOOOOOO..", "..OOOOOOO..", "...OOOOO...", "...OOOOO..."],
 'f-shelf': ["TTTTTTTTTTTTTT", "TnnbbyyppgnnbT", "TnnbbyyppgnnbT", "TnnbbyyppgnnbT", "TTTTTTTTTTTTTT", "TbgnnyppbbngyT", "TbgnnyppbbngyT", "TbgnnyppbbngyT", "TTTTTTTTTTTTTT", "TppyyngbbppnnT", "TppyyngbbppnnT", "TppyyngbbppnnT", "TTTTTTTTTTTTTT", "T............T"],
 'f-beanbag': ["....bbbbbb....", "..bbbbbbbbbb..", ".bbbbwbbbbbbb.", "bbbbbbbbbbbbbb", "bbbbbbbbbbbbbb", "bBbbbbbbbbbbBb", ".bBBbbbbbbBBb.", "..bbBBBBBBbb.."],
 'f-poster': ["SSSSSSSSSS", "SppppppppS", "SppyyppppS", "SppyyppppS", "SppppppppS", "SppppppnpS", "SpppppnnpS", "SppppnnnpS", "SpppnnnnpS", "SppnnnnnnS", "SSSSSSSSSS"],
 'f-fishbowl': ["...SSSSS...", "..S.....S..", ".S.......S.", "SbbbbbbbbbS", "SbbOObbbbbS", "SbOOObbbbbS", "SbbOObbgbbS", ".SbbbbbgbS.", "..SSSSSSS.."],
 'f-lights': ["TT........................TT", "..TT.........................", "....TTT..y........n.....TTT..", ".......TTTTTTTTTTTTTTTTT.....", "........n....b......g........"],
 'f-records': ["kkkkkkkkkkkk", "kTTTTTTTTTTk", "kTrrrrrrrrTk", "kTrkkkkkkrTk", "kTrkkwwkkrTk", "kTrkkkkkkrTk", "kTrrrrrrrrTk", "kTTTTTTTTTTk", "kkkkkkkkkkkk", ".T........T."],
 'paw': [".k.k.", "k.k.k", ".kkk.", ".kkk.", "..k.."],
}


def draw_art(rows):
    h = len(rows); w = max(len(r) for r in rows)
    img = Image.new('RGBA', (w + 2, h + 2), (0, 0, 0, 0))
    px = img.load()
    solid = set()
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in PAL:
                px[x + 1, y + 1] = PAL[ch] + (255,)
                solid.add((x + 1, y + 1))
    for (x, y) in list(solid):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in solid and 0 <= n[0] < w + 2 and 0 <= n[1] < h + 2 and px[n][3] == 0:
                px[n] = PAL['o'] + (255,)
    return img


def props(outdir):
    cell, per = 32, 8
    names = list(ART)
    rows = (len(names) + per - 1) // per
    sheet = Image.new('RGBA', (cell * per, cell * rows), (0, 0, 0, 0))
    meta = {}
    for i, nm in enumerate(names):
        im = draw_art(ART[nm])
        cx, cy = (i % per) * cell, (i // per) * cell
        ox, oy = cx + (cell - im.width) // 2, cy + cell - im.height
        sheet.alpha_composite(im, (ox, oy))
        meta[nm] = {'x': ox, 'y': oy, 'w': im.width, 'h': im.height}
    sheet.save(os.path.join(outdir, 'props.png'))
    json.dump({'unitsPerPixel': 1, 'note': 'scale by 7 px per unit at full size; feet/bottom-aligned in 32-unit cells', 'items': meta},
              open(os.path.join(outdir, 'props.json'), 'w'), indent=1)
    return sheet.size


def render(key, outdir):
    sp = SPECIES[key]
    pal = R.palette(sp)
    rows = R3.build3(key) + [[(g, 0, 'feet') for g in row] for row in rows4(key)]
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
            ht = R3.headtop_of(g) if r not in R3.NO_HATS | {33, 34, 35, 37} else None
            hr.append([place[0] + ht[1] * place[2] + place[2] // 2, place[1] + ht[0] * place[2], place[2]] if (ht and place) else None)
        heads.append(hr)
    d = os.path.join(outdir, 'notchi' if key == 'notchi' else f'notchi-{key}')
    os.makedirs(d, exist_ok=True)
    full.save(os.path.join(d, 'spritesheet.webp'), 'WEBP', lossless=True, quality=100)
    full.save(os.path.join(d, 'spritesheet.png'))
    full.crop((0, 31 * CH, COLS * CW, 39 * CH)).save(os.path.join(d, 'ext3.png'))
    R2.signkit(key).save(os.path.join(d, 'signkit.png'))
    acc, accmeta = R3.accessory_strip(key)
    acc.save(os.path.join(d, 'accessories.png'))
    json.dump({
        'id': os.path.basename(d), 'displayName': sp['name'], 'description': sp['line'],
        'spriteVersionNumber': 6, 'spritesheetPath': 'spritesheet.webp',
        'notchi': {
            'species': key, 'accent': '#' + sp['accent'], 'cell': [CW, CH], 'columns': COLS,
            'rows': {n: {'row': i, 'frames': len(rows[i])} for i, n in enumerate(NAMES)},
            'signRect': sign, 'plateAnchor': plate,
            'signKit': {'path': 'signkit.png', 'size': [20, 11], 'slice': {'top': 3, 'right': 4, 'bottom': 3, 'left': 4}, 'scale': 3},
            'headAnchor': heads,
            'accessories': dict(accmeta, path='accessories.png'),
            'anchors': {'edgepeek': 'left', 'thrown': 'centre', 'peek': 'top'},
            'arcs': {'backflip': 'frames 1-4 airborne: add a 0.5 s jump arc, peak 1.6x body height'}
        }
    }, open(os.path.join(d, 'pet.json'), 'w'))
    return full.size


if __name__ == '__main__':
    out = os.path.join(HERE, 'packs4')
    os.makedirs(out, exist_ok=True)
    print('props', props(out))
    for k in R.ORDER:
        print(k, render(k, out))
