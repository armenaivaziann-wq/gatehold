"""Музыка трейлера (56 с, 120 уд/мин, такт — 2 с): инструменты из tools/make_music.py плюс
«брам» (низкий медный удар), «бум» (суб-удар) и «райзер» (нарастающий шум). Склейки трейлера
(tools/trailer/trailer.gd) стоят на границах тактов — удары в такт смене кадров.

Запуск: python3 tools/trailer/make_trailer_music.py <выход.wav>
"""
import math
import os
import sys

# Инструменты и лад — из музыки игры (без записи её файлов: хвост скрипта с write() отрезаем)
_src = open(os.path.join(os.path.dirname(__file__), "..", "make_music.py"), encoding="utf-8").read()
exec(_src[:_src.index("os.makedirs(OUT, exist_ok=True)")])

BEAT = 0.5
BAR = 2.0
LENGTH = 56.0


def braam(freq, dur, bright=1.0):
    """Низкий медный удар: пилы с расстройкой и квинтой, фильтр открывается и закрывается."""
    n = int(dur * RATE)
    out = []
    phs = [0.0] * 5
    det = (1.0, 1.006, 0.994, 1.5, 0.5)
    lp = 0.0
    for j in range(n):
        t = j / RATE
        s = 0.0
        for k, d in enumerate(det):
            phs[k] += freq * d / RATE
            p = phs[k] - math.floor(phs[k])
            s += (2 * p - 1) * (0.6 if k == 3 else 1.0)
        cut = (0.02 + 0.25 * bright * math.exp(-t * 1.8)) * min(t / 0.04, 1.0)
        lp += (s - lp) * cut
        env = min(t / 0.03, 1.0) * math.exp(-t * 0.9) * min((dur - t) / 0.3, 1.0)
        out.append(math.tanh(lp * 0.6) * env)
    return out


def boom(dur=3.0):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    lp = 0.0
    for j in range(n):
        t = j / RATE
        ph += (32 + 60 * math.exp(-t * 8)) / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.05
        out.append(math.sin(math.tau * ph) * math.exp(-t * 1.3) * 1.4 + lp * math.exp(-t * 4) * 1.2)
    return out


def riser(dur):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    lp = 0.0
    for j in range(n):
        t = j / RATE
        k = t / dur
        ph += (180 + 900 * k * k) / RATE
        lp += (rnd.uniform(-1, 1) - lp) * (0.02 + 0.5 * k * k)
        out.append((lp * 0.9 + math.sin(math.tau * ph) * 0.25) * k * k)
    return out


def groove(tr, t0, chord, gain=1.0, double=False):
    """Такт боевого ритма: пэд, бас восьмыми, тайко, хлопки, хэт."""
    tr.add(t0, pad([midi(n) for n in chord], BAR + 0.3), 0.5 * gain)
    root = chord[0] - 24 if chord[0] >= 60 else chord[0] - 12
    for k, step in enumerate([0, 0, 12, 0, 0, 12, 0, 7]):
        tr.add(t0 + k * BEAT / 2, bass(midi(root + step), BEAT / 2 * 0.95), 0.6 * gain)
    hits = ((0, 1.0), (1, 0.9), (2, 1.0), (2.5, 1.25), (3, 0.9), (3.5, 1.3)) if double else ((0, 1.0), (2, 1.0), (2.5, 1.25))
    for pos, pitch in hits:
        tr.add(t0 + pos * BEAT, taiko(0.6, pitch), 0.95 * gain)
    for pos in (1, 3):
        tr.add(t0 + pos * BEAT, clap(), 0.4 * gain)
    for k in range(16 if double else 8):
        step = BEAT / (4 if double else 2)
        tr.add(t0 + k * step, hat(), (0.12 if k % 2 else 0.2) * gain)


def roll(tr, t0, count=8, gain=0.6):
    for k in range(count):
        tr.add(t0 + k * BEAT / 4, taiko(0.3, 1.4 + k * 0.08), gain * (0.6 + 0.4 * k / count))


def accent(tr, t):
    """Удар на склейке: большое тайко и короткий брам."""
    tr.add(t, taiko(1.0, 0.75), 1.3)
    tr.add(t, braam(midi(D - 36), 1.2, 0.6), 0.45)


def trailer():
    tr = Track(LENGTH, loop=False)
    dm, eb, a = CHORDS["Dm"], CHORDS["Eb"], CHORDS["A"]
    # 0–8 с: ветер, низкий гул, редкие тайко, флейта — тишина перед бурей
    tr.add(0.0, wind(12.0), 0.35)
    tr.add(0.0, pad([midi(n - 24) for n in dm], 12.0, 2.5, 2.0), 0.7)
    for t in (0.0, 2.0, 4.0, 5.0, 6.0, 7.0):
        tr.add(t, taiko(0.8, 0.7), 0.6 if t < 4 else 0.8)
    for t, n, d in ((1.0, A, 1.0), (2.0, BB, 0.5), (2.5, A, 1.5), (5.0, G, 0.5), (5.5, FS, 2.0)):
        tr.add(t, flute(midi(n), d + 0.3), 0.25)
    # 8–12 с: бас и хэт подключаются, к 12 с — райзер
    for b in range(4, 6):
        t0 = b * BAR
        root = D - 36
        for k, step in enumerate([0, 0, 12, 0, 0, 12, 0, 7]):
            tr.add(t0 + k * BEAT / 2, bass(midi(root + 12 + step), BEAT / 2 * 0.95), 0.5)
        for pos in (0, 2):
            tr.add(t0 + pos * BEAT, taiko(0.6, 1.0), 0.8)
        for k in range(8):
            tr.add(t0 + k * BEAT / 2, hat(), 0.12)
    tr.add(10.0, riser(2.0), 0.5)
    # 12 с: БРАМ — «ТЫСЯЧИ.»
    tr.add(12.0, braam(midi(D - 36), 2.4), 1.0)
    tr.add(12.0, boom(2.0), 0.7)
    # 14–30 с: полный бой, удары на каждой склейке
    chords = [dm, dm, eb, eb, dm, dm, a, a]
    for k, b in enumerate(range(7, 15)):
        groove(tr, b * BAR, chords[k % 8])
    for t in (14.0, 18.0, 22.0, 24.0, 26.0, 28.0):
        accent(tr, t)
    phrase = [(0, A, 1), (1, BB, 0.5), (1.5, A, 0.5), (2, G, 1), (3, FS, 1), (4, A, 1.5), (5.5, G, 0.5),
              (6, FS, 1), (7, EB, 1), (8, D, 1), (9, EB, 0.5), (9.5, FS, 0.5), (10, G, 1), (11, A, 1),
              (12, BB, 1.5), (13.5, A, 0.5), (14, G, 1), (15, FS, 1)]
    for rep in (0, 1):
        for pos, n, d in phrase:
            t = 14.0 + rep * 8.0 + pos * BEAT
            tr.add(t, pluck(midi(n), d * BEAT + 0.4, 0.65), 0.5)
            if rep == 1:
                tr.add(t, pluck(midi(n - 12), d * BEAT + 0.3, 0.45), 0.25)
    roll(tr, 29.0)
    # 30–32 с: «УДЕРЖИ ВОРОТА.» — брам и тайко вполсилы
    tr.add(30.0, braam(midi(D - 36), 2.2), 1.0)
    tr.add(30.0, boom(2.0), 0.6)
    tr.add(31.0, taiko(0.8, 0.9), 0.9)
    # 32–38 с: монтаж локаций — двойной ритм, удар на каждой секунде, райзер в конце
    for k, b in enumerate(range(16, 19)):
        groove(tr, b * BAR, (dm, eb, a)[k], 1.1, double=True)
    for t in range(32, 38):
        tr.add(float(t), taiko(0.8, 0.8), 0.9)
    tr.add(36.0, riser(2.0), 0.6)
    # 38–44 с: босс — тяжёлые брамы, тайко, тьма
    for t in (38.0, 40.0, 42.0):
        tr.add(t, braam(midi(EB - 36 if t == 40.0 else D - 36), 2.2, 1.2), 1.0)
        tr.add(t, taiko(1.2, 0.6), 1.3)
        tr.add(t + 1.0, taiko(1.0, 0.7), 1.0)
        tr.add(t + 1.5, taiko(0.6, 0.9), 0.7)
    tr.add(38.0, pad([midi(n - 24) for n in eb], 6.0, 1.0, 1.0), 0.5)
    roll(tr, 43.0, 8, 0.8)
    # 44–48 с: кульминация — всё сразу, райзер до обрыва
    for k, b in enumerate(range(22, 24)):
        groove(tr, b * BAR, (dm, a)[k], 1.25, double=True)
    tr.add(44.0, braam(midi(D - 36), 2.0), 0.8)
    tr.add(46.0, braam(midi(A - 48), 2.0), 0.8)
    tr.add(45.0, riser(3.0), 0.8)
    for k, n in enumerate((A, BB, A, G, A, C + 12 - 12, BB, A)):
        tr.add(44.0 + k * BEAT, pluck(midi(n + 12), BEAT + 0.3, 0.7), 0.5)
    # 48 с: обрыв, полсекунды тишины; 48.5 — логотип: бум и брам, короткий мотив
    cut = int(48.0 * RATE)
    for j in range(cut, min(cut + int(0.5 * RATE), tr.n)):
        tr.buf[j] = 0.0
    tr.add(48.5, boom(4.0), 1.2)
    tr.add(48.5, braam(midi(D - 36), 5.0, 0.8), 1.0)
    tr.add(48.5, pad([midi(n - 12) for n in dm], 7.0, 0.3, 3.0), 0.5)
    for k, n in enumerate((D, F, A, D + 12)):
        tr.add(51.0 + k * 0.3, pluck(midi(n), 2.5, 0.6), 0.45)
    tr.add(53.5, taiko(1.2, 0.7), 0.9)
    # Плавно в тишину к концу
    fade = int(2.0 * RATE)
    for j in range(tr.n - fade, tr.n):
        tr.buf[j] *= (tr.n - j) / fade
    return tr.buf


if __name__ == "__main__":
    out = sys.argv[1]
    OUT = os.path.dirname(out)
    write(os.path.basename(out), trailer(), 0.95)
