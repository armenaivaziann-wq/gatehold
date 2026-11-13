"""Музыка, синтезированная с нуля (без чужих записей и сэмплов): тема меню, тема боя и короткие
заставки победы и поражения. Лад — ре фригийский доминантовый (D Eb F# G A Bb C) с минорными
аккордами: «пустынное», тревожное звучание.

Инструменты — простые формулы: щипковая струна (алгоритм Карплуса — Стронга, похоже на уд),
мягкий пэд из гармоник, бас, большие барабаны (тайко), хлопок, хай-хэт, дарбука (дум и тек),
флейта (синус с вибрато и дыханием), ветер. Петли собраны из целых тактов, хвосты нот
заворачиваются в начало — склейка бесшовная.

Запуск: python3 tools/make_music.py  → audio/music/music_battle.wav, sting_win.wav, sting_lose.wav
"""
import math
import os
import random
import struct
import wave

RATE = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "music")
rnd = random.Random(2026)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def write(name, samples, peak_to=0.9):
    peak = max(1e-6, max(abs(s) for s in samples))
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * peak_to * 32767)) for s in samples))
    print("wrote", name, round(len(samples) / RATE, 1), "s")


class Track:
    """Дорожка-петля длиной seconds: ноты складываются по кругу (хвосты — в начало)."""

    def __init__(self, seconds, loop=True):
        self.n = int(RATE * seconds)
        self.buf = [0.0] * self.n
        self.loop = loop

    def add(self, start_s, samples, gain=1.0):
        i0 = int(start_s * RATE)
        n = self.n
        buf = self.buf
        for j, v in enumerate(samples):
            k = i0 + j
            if k >= n:
                if not self.loop:
                    break
                k %= n
            buf[k] += v * gain


# --- инструменты ---------------------------------------------------------------------------

def pluck(freq, dur, bright=0.5):
    """Щипковая струна (Карплус — Стронг): шумовой импульс в линии задержки, усреднение гасит."""
    period = max(2, int(RATE / freq))
    line = [rnd.uniform(-1, 1) for _ in range(period)]
    # Мягче атака — чуть сгладить исходный шум
    for k in range(1, period):
        line[k] = line[k] * bright + line[k - 1] * (1 - bright)
    out = []
    idx = 0
    n = int(dur * RATE)
    decay = 0.996
    for j in range(n):
        a = line[idx]
        b = line[(idx + 1) % period]
        line[idx] = (a + b) * 0.5 * decay
        out.append(a)
        idx = (idx + 1) % period
    fade = min(n, int(0.02 * RATE))
    for j in range(fade):
        out[n - 1 - j] *= j / fade
    return out


def pad(freqs, dur, attack=0.4, release=0.6):
    """Мягкий пэд: у каждой ноты несколько гармоник и лёгкая расстройка, медленные вход и спад."""
    n = int(dur * RATE)
    out = [0.0] * n
    for f in freqs:
        for det in (0.997, 1.003):
            ph = rnd.random()
            step = f * det / RATE
            for j in range(n):
                ph += step
                p = ph - math.floor(ph)
                s = math.sin(math.tau * p) + 0.35 * math.sin(2 * math.tau * p) + 0.15 * math.sin(3 * math.tau * p)
                out[j] += s
    lp = 0.0
    for j in range(n):
        t = j / RATE
        env = min(t / attack, 1.0) * min((dur - t) / release, 1.0)
        lp += (out[j] - lp) * 0.08
        out[j] = lp * max(env, 0.0) / (len(freqs) * 2)
    return out


def bass(freq, dur):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    lp = 0.0
    for j in range(n):
        t = j / RATE
        ph += freq / RATE
        p = ph - math.floor(ph)
        s = sum(math.sin(math.tau * p * h) / h for h in (1, 2, 3, 4))
        env = math.exp(-t * 5.0) * min(t / 0.005, 1.0) * min((dur - t) / 0.02, 1.0)
        lp += (s - lp) * 0.2
        out.append(lp * env)
    return out


def taiko(dur=0.6, pitch=1.0):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    lp = 0.0
    for j in range(n):
        t = j / RATE
        f = (55 + 70 * math.exp(-t * 25)) * pitch
        ph += f / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.1
        out.append(math.sin(math.tau * ph) * math.exp(-t * 6) * 1.2 + lp * math.exp(-t * 30) * 0.8)
    return out


def clap(dur=0.25):
    n = int(dur * RATE)
    out = []
    lp = slow = 0.0
    for j in range(n):
        t = j / RATE
        x = rnd.uniform(-1, 1)
        lp += (x - lp) * 0.5
        slow += (lp - slow) * 0.05
        bursts = 1.0 if t < 0.03 else math.exp(-(t - 0.03) * 18)
        out.append((lp - slow) * bursts)
    return out


def hat(dur=0.06):
    n = int(dur * RATE)
    out = []
    prev = 0.0
    for j in range(n):
        t = j / RATE
        x = rnd.uniform(-1, 1)
        out.append((x - prev) * math.exp(-t * 60))
        prev = x
    return out


def dum(dur=0.35):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    for j in range(n):
        t = j / RATE
        ph += (85 + 40 * math.exp(-t * 30)) / RATE
        out.append(math.sin(math.tau * ph) * math.exp(-t * 9))
    return out


def tek(dur=0.08):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    for j in range(n):
        t = j / RATE
        ph += 900 / RATE
        out.append((math.sin(math.tau * ph) * 0.6 + rnd.uniform(-1, 1) * 0.5) * math.exp(-t * 55))
    return out


def flute(freq, dur):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    lp = 0.0
    for j in range(n):
        t = j / RATE
        vib = 1 + 0.006 * math.sin(math.tau * 5.2 * t) * min(t / 0.4, 1.0)
        ph += freq * vib / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.3
        env = min(t / 0.15, 1.0) * min((dur - t) / 0.25, 1.0)
        s = math.sin(math.tau * ph) + 0.12 * math.sin(2 * math.tau * ph) + lp * 0.08
        out.append(s * max(env, 0.0))
    return out


def wind(dur):
    n = int(dur * RATE)
    out = []
    lp = lp2 = 0.0
    for j in range(n):
        t = j / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.02
        lp2 += (lp - lp2) * 0.05
        swell = 0.6 + 0.4 * math.sin(math.tau * t / dur * 2)
        out.append(lp2 * swell)
    return out


# --- лад и аккорды ---------------------------------------------------------------------------

D, EB, F, FS, G, A, BB, C, CS, E = 62, 63, 65, 66, 67, 69, 70, 72, 73, 64
CHORDS = {
    "Dm": [D, F, A],
    "Eb": [EB, G, BB],
    "Bb": [BB - 12, D, F],
    "Gm": [G - 12, BB - 12, D],
    "A": [A - 12, CS, E],
    "D": [D, FS, A],
}


# --- тема боя: 120 уд/мин, 16 тактов --------------------------------------------------------

def battle():
    beat = 0.5
    bar = beat * 4
    bars = ["Dm", "Dm", "Eb", "Eb", "Dm", "Dm", "A", "A"] * 2
    tr = Track(bar * len(bars))
    for b, name in enumerate(bars):
        t0 = b * bar
        chord = CHORDS[name]
        # Пэд держит аккорд весь такт
        tr.add(t0, pad([midi(n) for n in chord], bar + 0.3), 0.55)
        # Бас: восьмые на основном тоне с октавой
        root = chord[0] - 24 if chord[0] >= 60 else chord[0] - 12
        for k, step in enumerate([0, 0, 12, 0, 0, 12, 0, 7]):
            tr.add(t0 + k * beat / 2, bass(midi(root + step), beat / 2 * 0.95), 0.55)
        # Барабаны: тайко на 1, 3 и «и» третьей; хлопок на 2 и 4; хэт восьмыми
        for pos, pitch in ((0, 1.0), (2, 1.0), (2.5, 1.25)):
            tr.add(t0 + pos * beat, taiko(0.6, pitch), 0.9)
        for pos in (1, 3):
            tr.add(t0 + pos * beat, clap(), 0.35)
        for k in range(8):
            tr.add(t0 + k * beat / 2, hat(), 0.12 if k % 2 else 0.2)
        # Сбивка в конце каждой восьмёрки тактов: дробь тайко
        if b % 8 == 7:
            for k in range(6):
                tr.add(t0 + 2.5 * beat + k * beat / 4, taiko(0.3, 1.5 + k * 0.1), 0.5)
    # Мелодия: щипковая струна, две фразы по 8 тактов (вторая — выше и гуще)
    phrase = [(0, A, 1), (1, BB, 0.5), (1.5, A, 0.5), (2, G, 1), (3, FS, 1),
              (4, A, 1.5), (5.5, G, 0.5), (6, FS, 1), (7, EB, 1),
              (8, D, 1), (9, EB, 0.5), (9.5, FS, 0.5), (10, G, 1), (11, A, 1),
              (12, BB, 1.5), (13.5, A, 0.5), (14, G, 1), (15, FS, 1),
              (16, A, 2), (18, C, 1), (19, BB, 1), (20, A, 2), (22, G, 1), (23, FS, 1),
              (24, G, 1), (25, FS, 0.5), (25.5, EB, 0.5), (26, D, 2), (28, CS - 12 + 12, 2), (30, D, 2)]
    for half in (0, 1):
        for pos, note, length in phrase:
            t = half * 8 * bar + pos * beat
            n = note + (12 if half == 1 and pos >= 16 else 0)
            tr.add(t, pluck(midi(n), length * beat + 0.4, 0.6), 0.5)
            if half == 1:
                tr.add(t, pluck(midi(n - 12), length * beat + 0.3, 0.4), 0.25)
    return tr.buf


# --- тема меню: 84 уд/мин, 16 тактов --------------------------------------------------------

def menu():
    beat = 60.0 / 84.0
    bar = beat * 4
    bars = ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"] * 2
    tr = Track(bar * len(bars))
    tr.add(0.0, wind(bar * len(bars)), 0.25)
    for b, name in enumerate(bars):
        t0 = b * bar
        chord = CHORDS[name]
        tr.add(t0, pad([midi(n - 12) for n in chord], bar + 0.8, 0.9, 1.0), 0.6)
        # Арпеджио уда: вверх-вниз по аккорду восьмыми
        arp = chord + [chord[0] + 12, chord[1] + 12, chord[2] + 12]
        order = [0, 1, 2, 3, 4, 3, 2, 1]
        for k, idx in enumerate(order):
            tr.add(t0 + k * beat / 2, pluck(midi(arp[idx] - 12), beat * 1.5, 0.45), 0.32 if k % 2 == 0 else 0.22)
        # Дарбука: дум — тек тек — дум — тек (тихо)
        for pos, kind in ((0, "d"), (1, "t"), (1.5, "t"), (2, "d"), (3, "t")):
            tr.add(t0 + pos * beat, dum() if kind == "d" else tek(), 0.35 if kind == "d" else 0.18)
    # Флейта: редкие долгие ноты во второй половине
    melody = [(32, A, 4), (36, G, 2), (38, FS, 2), (40, A, 4), (44, BB, 2), (46, A, 2),
              (48, G, 4), (52, FS, 2), (54, EB, 2), (56, D, 6)]
    for pos, note, length in melody:
        tr.add(pos * beat, flute(midi(note + 12), length * beat), 0.22)
    return tr.buf


# --- заставки ---------------------------------------------------------------------------------

def sting_win():
    tr = Track(3.5, loop=False)
    for k, n in enumerate([D, FS, A, D + 12, FS + 12, A + 12]):
        tr.add(k * 0.11, pluck(midi(n), 2.5, 0.7), 0.5)
    tr.add(0.6, pad([midi(n) for n in CHORDS["D"]], 2.9, 0.2, 1.2), 0.9)
    tr.add(0.6, taiko(0.8, 1.0), 0.7)
    return tr.buf


def sting_lose():
    tr = Track(3.5, loop=False)
    for k, n in enumerate([A, G, F, D, CS - 12, D - 12]):
        tr.add(k * 0.22, pluck(midi(n - 12), 2.0, 0.4), 0.5)
    tr.add(0.0, taiko(1.0, 0.8), 0.9)
    tr.add(1.3, taiko(1.2, 0.7), 0.9)
    tr.add(1.3, pad([midi(n - 12) for n in CHORDS["Dm"]], 2.2, 0.3, 1.2), 0.8)
    return tr.buf


os.makedirs(OUT, exist_ok=True)
# Тема меню теперь — трек пользователя (audio/music/music_menu.mp3); старая синтезированная:
# write("music_menu.wav", menu())
write("music_battle.wav", battle())
write("sting_win.wav", sting_win())
write("sting_lose.wav", sting_lose())
