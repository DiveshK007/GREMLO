"""Notchi sound kit. Every sound is synthesised here, so it is ours to ship.

Rules: short (under 0.9 s), soft attack, nothing above -6 dBFS peak, nothing
harsh above 6 kHz. Sounds are off by default for sponsored moments; the line
itself never makes a noise.

Writes sounds/<name>.wav (44.1 kHz, 16-bit mono) and sounds/levels.json
(32-bucket peak envelope per sound, for the design board).
"""
import numpy as np, os, json, wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sounds')


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.08, curve=3.0):
    e = np.ones(n)
    na, nr = max(1, int(SR * a)), max(1, int(SR * r))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def tone(f, d, shape='sine', a=0.005, r=None, vib=0.0, glide=None):
    x = t(d)
    fr = np.full_like(x, f, dtype=float) if glide is None else np.geomspace(f, glide, len(x))
    if vib:
        fr = fr * (1 + vib * np.sin(2 * np.pi * 6 * x))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    if shape == 'sine':
        y = np.sin(ph)
    elif shape == 'tri':
        y = 2 / np.pi * np.arcsin(np.sin(ph))
    elif shape == 'square':
        y = np.tanh(3 * np.sin(ph)) * .6
    elif shape == 'fm':
        y = np.sin(ph + 1.6 * np.sin(2 * ph))
    elif shape == 'pluck':
        y = np.sin(ph) * np.exp(-x * 18) + .3 * np.sin(2 * ph) * np.exp(-x * 30)
    return y * env(len(x), a, r if r is not None else d * .7)


def noise(d, lo=200, hi=4000, a=0.002, r=None):
    n = int(SR * d)
    w = np.random.default_rng(7).standard_normal(n)
    F = np.fft.rfft(w)
    fq = np.fft.rfftfreq(n, 1 / SR)
    F[(fq < lo) | (fq > hi)] = 0
    y = np.fft.irfft(F, n)
    y /= np.abs(y).max() + 1e-9
    return y * env(n, a, r if r is not None else d * .8)


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(SR * gap)))
    return np.concatenate(out)


def mix(*layers):
    n = max(len(l) for l in layers)
    y = np.zeros(n)
    for l in layers:
        y[:len(l)] += l
    return y


def lowpass(y, fc):
    F = np.fft.rfft(y)
    fq = np.fft.rfftfreq(len(y), 1 / SR)
    F *= 1 / np.sqrt(1 + (fq / fc) ** 4)
    return np.fft.irfft(F, len(y))


def save(name, y, peak_db=-6):
    y = lowpass(y, 7000)
    y = y / (np.abs(y).max() + 1e-9) * 10 ** (peak_db / 20)
    pad = np.zeros(int(SR * 0.01))
    y = np.concatenate([pad, y, pad])
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((y * 32767).astype('<i2').tobytes())
    b = np.array_split(np.abs(y), 32)
    return {'name': name, 'ms': int(len(y) / SR * 1000), 'levels': [round(float(x.max()) / 10 ** (peak_db / 20), 3) for x in b]}


# -------------------------------------------------------------- voices ----
# One "say" blip per species, plus a happy and a grumpy variant. Pitch and
# timbre follow the species: Notchi is a plain mid hum, Pip a chirp, Byte a
# square beep, Puff a breathy low, Wisp a soft bell, Tako a bubbly wobble.

VOICES = {
    'notchi': dict(f=440, shape='tri', d=.09, n=2, step=1.12),
    'pip':    dict(f=1320, shape='sine', d=.05, n=3, step=1.26, glide=1.4),
    'moss':   dict(f=330, shape='sine', d=.14, n=2, step=1.06),
    'gloop':  dict(f=220, shape='sine', d=.16, n=2, step=.94, vib=.04),
    'byte':   dict(f=880, shape='square', d=.06, n=3, step=1.0),
    'puff':   dict(f=294, shape='sine', d=.18, n=1, step=1.0, breath=True),
    'wisp':   dict(f=988, shape='fm', d=.22, n=2, step=1.5),
    'tako':   dict(f=523, shape='sine', d=.07, n=3, step=1.19, vib=.09),
}


def voice(key, mood='say'):
    v = VOICES[key]
    mul = {'say': 1.0, 'happy': 1.12, 'grumpy': .84}[mood]
    parts = []
    f = v['f'] * mul
    for i in range(v['n'] + (1 if mood == 'happy' else 0)):
        step = v['step'] if mood != 'grumpy' else 1 / v['step']
        g = (f * v.get('glide', 1.0)) if v.get('glide') else None
        p = tone(f, v['d'], v['shape'], vib=v.get('vib', 0), glide=g)
        if v.get('breath'):
            p = mix(p, .35 * noise(v['d'], 300, 2500))
        parts.append(p)
        f *= step
    return seq(*parts, gap=.025)


# --------------------------------------------------------------- events ----

def door_open():
    return mix(noise(.18, 150, 1200, r=.15) * .5, tone(180, .22, 'sine', glide=260) * .7,
               np.concatenate([np.zeros(int(SR * .12)), tone(1568, .25, 'sine') * .25]))


def door_close():
    return mix(noise(.08, 100, 900) * .6, tone(140, .12, 'sine', glide=90))


def approval():
    return seq(tone(880, .09, 'sine'), tone(1175, .16, 'sine'), gap=.02)


def allow():
    return seq(tone(784, .07, 'pluck'), tone(1175, .18, 'pluck'), gap=.01)


def deny():
    return seq(tone(392, .09, 'tri'), tone(330, .16, 'tri'), gap=.015)


def celebrate():
    notes = [523, 659, 784, 1047]
    return mix(seq(*[tone(f, .09, 'pluck') for f in notes], gap=.01),
               np.concatenate([np.zeros(int(SR * .4)), noise(.35, 2000, 6000, r=.3) * .15]))


def fail():
    return seq(tone(392, .12, 'tri', glide=370), tone(311, .3, 'tri', glide=262, vib=.02), gap=.03)


def meal():
    crunch = [noise(.04, 800, 4000) * .5 for _ in range(3)]
    return seq(*crunch, tone(660, .1, 'sine'), tone(990, .18, 'sine'), gap=.05)


def boing():
    x = t(.45)
    f = 180 + 220 * np.exp(-x * 9) * np.abs(np.cos(2 * np.pi * 7 * x))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x * 5)
    return y


def whoosh():
    return noise(.3, 400, 3000, a=.12, r=.15)


def thud():
    return mix(tone(110, .14, 'sine', glide=60), noise(.05, 80, 600) * .5)


def dizzy():
    return seq(*[tone(1400 + 200 * (i % 2), .05, 'sine') for i in range(6)], gap=.02)


def poke(n):
    f = 600 + n * 90
    return tone(f, .05, 'pluck')


def stomp():
    return mix(thud(), seq(np.zeros(int(SR * .05)), tone(220, .12, 'square') * .4))


def highfive():
    return mix(noise(.05, 1500, 6000) * .8, tone(1047, .2, 'pluck') * .5)


def focus_start():
    return tone(523, .7, 'fm', a=.08, r=.6) * .8


def focus_end():
    return seq(tone(784, .3, 'fm', a=.02), tone(1047, .6, 'fm', a=.02), gap=.03)


def yawn():
    return tone(260, .7, 'sine', a=.15, glide=170, vib=.03) * .8


def snore():
    return mix(noise(.6, 100, 600, a=.25, r=.3) * .6, tone(90, .6, 'sine', a=.25, r=.3) * .3)


def hatch():
    cr = [noise(.03, 1000, 5000) * .6 for _ in range(3)]
    return seq(*cr, gap=.12) if False else seq(*cr, np.zeros(int(SR * .05)), tone(1047, .1, 'pluck'), tone(1568, .25, 'pluck'), gap=.08)


def offline():
    return seq(tone(523, .14, 'sine'), tone(392, .3, 'sine'), gap=.04) * .7


EVENTS = {
    'door-open': door_open, 'door-close': door_close, 'approval': approval, 'allow': allow,
    'deny': deny, 'celebrate': celebrate, 'fail': fail, 'meal': meal, 'boing': boing,
    'whoosh': whoosh, 'thud': thud, 'dizzy': dizzy, 'stomp': stomp, 'high-five': highfive,
    'focus-start': focus_start, 'focus-end': focus_end, 'yawn': yawn, 'snore': snore,
    'hatch': hatch, 'offline': offline,
}

if __name__ == '__main__':
    meta = []
    for k in VOICES:
        for m in ('say', 'happy', 'grumpy'):
            meta.append(save(f'voice-{k}-{m}', voice(k, m), -9))
    for n, fn in EVENTS.items():
        meta.append(save(n, fn(), -6 if n not in ('celebrate', 'approval') else -4))
    for i in range(1, 6):
        meta.append(save(f'poke-{i}', poke(i), -10))
    json.dump(meta, open(os.path.join(OUT, 'levels.json'), 'w'))
    print(len(meta), 'sounds', sum(m['ms'] for m in meta), 'ms total')
