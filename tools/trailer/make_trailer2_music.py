"""Музыка короткого трейлера (30 с, 120 уд/мин): инструменты — из make_trailer_music.py (а те —
из музыки игры). Склейки трейлера (tools/trailer/trailer2.gd) стоят на ударах.

Запуск: python3 tools/trailer/make_trailer2_music.py <выход.wav>
"""
import os
import sys

_src = open(os.path.join(os.path.dirname(__file__), "make_trailer_music.py"), encoding="utf-8").read()
exec(_src[:_src.index("def trailer():")])

LENGTH = 30.0


def trailer2():
    tr = Track(LENGTH, loop=False)
    dm, eb, a = CHORDS["Dm"], CHORDS["Eb"], CHORDS["A"]
    # 0–6 с: ветер, гул, тайко всё чаще, райзер к 6 с
    tr.add(0.0, wind(7.0), 0.35)
    tr.add(0.0, pad([midi(n - 24) for n in dm], 7.0, 1.5, 1.0), 0.7)
    for t in (0.0, 1.0, 2.0, 3.0, 3.5, 4.0, 4.5, 5.0, 5.25, 5.5, 5.75):
        tr.add(t, taiko(0.7, 0.7 + (t / 6.0) * 0.5), 0.55 + t * 0.06)
    for t, n, d in ((0.5, A, 1.0), (1.5, BB, 0.5), (2.0, A, 1.5)):
        tr.add(t, flute(midi(n), d + 0.3), 0.25)
    tr.add(2.0, braam(midi(D - 36), 2.0, 0.6), 0.5)
    tr.add(4.0, riser(2.0), 0.6)
    # 6 с: БРАМ — первый выстрел
    tr.add(6.0, braam(midi(D - 36), 2.4), 1.0)
    tr.add(6.0, boom(2.0), 0.8)
    # 6–18 с: бой, удар на каждой склейке
    chords = [dm, dm, eb, eb, dm, a]
    for k, b in enumerate(range(3, 9)):
        groove(tr, b * BAR, chords[k], 1.0, double=k >= 3)
    for t in (9.0, 10.5, 12.0, 13.5, 15.0):
        accent(tr, t)
    phrase = [(0, A, 1), (1, BB, 0.5), (1.5, A, 0.5), (2, G, 1), (3, FS, 1), (4, A, 1.5), (5.5, G, 0.5),
              (6, FS, 1), (7, EB, 1)]
    for rep in (0, 1):
        for pos, n, d in phrase:
            tr.add(8.0 + rep * 4.0 + pos * BEAT, pluck(midi(n), d * BEAT + 0.4, 0.65), 0.45)
    # Пике молота: райзер к удару о землю (~16.2 с), большой бум
    tr.add(15.0, riser(1.2), 0.7)
    tr.add(16.2, boom(2.5), 1.3)
    tr.add(16.2, braam(midi(D - 36), 2.0, 1.2), 0.9)
    # 18–22 с: монтаж локаций — двойной ритм, удар каждую секунду
    for k, b in enumerate(range(9, 11)):
        groove(tr, b * BAR, (dm, a)[k], 1.15, double=True)
    for t in (18.0, 19.0, 20.0, 21.0):
        accent(tr, t)
    roll(tr, 21.0, 8, 0.8)
    # 22–24 с: «ДЕРЖИ ОБОРОНУ.» — брам и тайко, райзер до обрыва
    tr.add(22.0, braam(midi(D - 36), 2.0), 1.0)
    tr.add(22.0, boom(2.0), 0.6)
    tr.add(22.5, riser(1.5), 0.7)
    tr.add(23.0, taiko(0.8, 0.9), 0.9)
    # 24 с: обрыв, тишина; 24.4 — логотип
    cut = int(24.0 * RATE)
    for j in range(cut, min(cut + int(0.4 * RATE), tr.n)):
        tr.buf[j] = 0.0
    tr.add(24.4, boom(4.0), 1.2)
    tr.add(24.4, braam(midi(D - 36), 4.5, 0.8), 1.0)
    tr.add(24.4, pad([midi(n - 12) for n in dm], 5.5, 0.3, 2.5), 0.5)
    for k, n in enumerate((D, F, A, D + 12)):
        tr.add(26.0 + k * 0.3, pluck(midi(n), 2.5, 0.6), 0.45)
    fade = int(2.0 * RATE)
    for j in range(tr.n - fade, tr.n):
        tr.buf[j] *= (tr.n - j) / fade
    return tr.buf


if __name__ == "__main__":
    out = sys.argv[1]
    OUT = os.path.dirname(out)
    write(os.path.basename(out), trailer2(), 0.95)
