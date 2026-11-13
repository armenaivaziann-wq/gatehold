"""Звуки, синтезированные с нуля (без чужих записей): выстрел мушкетона, взрыв снаряда,
рёв огнемёта (зациклен) и его поджиг.

Запуск: python3 tools/make_sounds.py  → audio/sounds/*.wav
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "sounds")


def write(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.92 * 32767)) for s in samples))


def blunderbuss_shot():
    """Хлопок пороха: резкий шумовой удар, низкий «бум» и затухающий хвост с эхом."""
    rnd = random.Random(3)
    n = int(RATE * 1.4)
    out = []
    lp = 0.0
    lp2 = 0.0
    for i in range(n):
        t = i / RATE
        noise = rnd.uniform(-1, 1)
        # Шум сглаживается всё сильнее — хвост глуше начала
        a = 0.55 if t < 0.03 else max(0.04, 0.35 * math.exp(-t * 4.0))
        lp += (noise - lp) * a
        lp2 += (lp - lp2) * 0.2
        crack = noise * math.exp(-t * 90.0) * 1.2
        body = lp * math.exp(-t * 7.0) * 1.4
        rumble = lp2 * math.exp(-t * 2.6) * 1.6
        boom = math.sin(math.tau * (62.0 - 25.0 * t) * t) * math.exp(-t * 9.0) * 1.3
        out.append(crack + body + rumble + boom)
    # Короткое эхо от каньонов
    d = int(RATE * 0.19)
    for i in range(n - 1, d - 1, -1):
        out[i] += out[i - d] * 0.28
    attack = int(RATE * 0.002)
    for i in range(attack):
        out[i] *= i / attack
    return out


def explosion():
    """Взрыв: удар, раскатистый низкий гул, шипящий хвост и падающие камешки."""
    rnd = random.Random(11)
    n = int(RATE * 2.4)
    out = []
    lp = lp2 = lp3 = 0.0
    for i in range(n):
        t = i / RATE
        noise = rnd.uniform(-1, 1)
        lp += (noise - lp) * (0.6 if t < 0.02 else 0.12)
        lp2 += (lp - lp2) * 0.05
        lp3 += (lp2 - lp3) * 0.03
        crack = noise * math.exp(-t * 60.0) * 1.3
        body = lp * math.exp(-t * 3.5) * 1.2
        rumble = lp3 * math.exp(-t * 1.2) * 9.0
        boom = math.sin(math.tau * (48.0 - 22.0 * t) * t) * math.exp(-t * 4.0) * 1.4
        out.append(crack + body + rumble + boom)
    # Камешки: короткие щелчки в первую секунду
    for k in range(18):
        start = int(RATE * rnd.uniform(0.25, 1.4))
        amp = rnd.uniform(0.08, 0.25)
        for j in range(int(RATE * 0.01)):
            if start + j < n:
                out[start + j] += rnd.uniform(-1, 1) * amp * math.exp(-j / 80.0)
    d = int(RATE * 0.23)
    for i in range(n - 1, d - 1, -1):
        out[i] += out[i - d] * 0.3
    attack = int(RATE * 0.002)
    for i in range(attack):
        out[i] *= i / attack
    return out


def flame_loop():
    """Рёв огня: низкий шумовой гул с потрескиванием. Конец плавно перетекает в начало."""
    rnd = random.Random(21)
    n = int(RATE * 2.0)
    out = []
    lp = lp2 = 0.0
    for i in range(n):
        noise = rnd.uniform(-1, 1)
        lp += (noise - lp) * 0.08
        lp2 += (lp - lp2) * 0.02
        t = i / RATE
        flutter = 1.0 + 0.25 * math.sin(math.tau * 7.0 * t) * math.sin(math.tau * 3.1 * t)
        out.append((lp * 0.9 + lp2 * 3.0) * flutter)
    for k in range(70):
        start = rnd.randrange(n)
        amp = rnd.uniform(0.15, 0.45)
        for j in range(int(RATE * 0.004)):
            out[(start + j) % n] += rnd.uniform(-1, 1) * amp * math.exp(-j / 30.0)
    # Склейка: последние 0.2 с плавно переходят в начало
    fade = int(RATE * 0.2)
    head = out[:fade]
    for j in range(fade):
        w = j / fade
        out[n - fade + j] = out[n - fade + j] * (1 - w) + head[j] * w
    return out[fade:]


def flame_ignite():
    """Поджиг: короткий нарастающий «фух»."""
    rnd = random.Random(8)
    n = int(RATE * 0.5)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        lp += (rnd.uniform(-1, 1) - lp) * (0.05 + 0.4 * min(t / 0.12, 1.0))
        env = min(t / 0.06, 1.0) * math.exp(-max(t - 0.08, 0.0) * 7.0)
        out.append(lp * env * 2.0)
    return out


def gatling_loop():
    """Пулемёт: очередь — 10 сухих хлопков в секунду поверх гула вращения. Ровно 1 с —
    выстрелы ложатся одинаково, петля без стыка."""
    rnd = random.Random(85)
    n = RATE
    out = [0.0] * n
    shots = 10
    for k in range(shots):
        start = k * n // shots
        lp = 0.0
        amp = rnd.uniform(0.85, 1.0)
        for j in range(int(RATE * 0.07)):
            t = j / RATE
            lp += (rnd.uniform(-1, 1) - lp) * 0.4
            crack = rnd.uniform(-1, 1) * math.exp(-t * 160.0) * 1.2
            thump = math.sin(math.tau * 120 * t) * math.exp(-t * 55.0) * 0.8
            out[(start + j) % n] += (crack + lp * math.exp(-t * 45.0) + thump) * amp
    for i in range(n):
        t = i / RATE
        out[i] += math.sin(math.tau * 180 * t) * 0.06 + math.sin(math.tau * 360 * t) * 0.03
    return out


def _bandpass(samples, lo_a, hi_a):
    """Грубая полоса: сглаживание (срез верха) минус медленное сглаживание (срез низа)."""
    out = []
    lp = slow = 0.0
    for x in samples:
        lp += (x - lp) * hi_a
        slow += (lp - slow) * lo_a
        out.append(lp - slow)
    return out


def swarm_loop():
    """Рой жуков: частое пощёлкивание хитиновых лапок, стрекот и низкий гул.
    События раскиданы по кругу — конец бесшовно переходит в начало."""
    rnd = random.Random(41)
    n = int(RATE * 3.0)
    out = [0.0] * n
    # Щелчки лапок: тысячи коротких сухих щелчков
    for k in range(1100):
        start = rnd.randrange(n)
        amp = rnd.uniform(0.05, 0.4)
        length = int(RATE * rnd.uniform(0.002, 0.006))
        for j in range(length):
            out[(start + j) % n] += rnd.uniform(-1, 1) * amp * math.exp(-j / (length * 0.3))
    out = _bandpass(out, 0.08, 0.6)
    # Стрекот: короткие трели с быстрой частотной модуляцией
    for k in range(45):
        start = rnd.randrange(n)
        f0 = rnd.uniform(1800, 3400)
        length = int(RATE * rnd.uniform(0.04, 0.12))
        amp = rnd.uniform(0.08, 0.2)
        phase = 0.0
        for j in range(length):
            t = j / RATE
            f = f0 * (1 + 0.15 * math.sin(math.tau * 60 * t))
            phase += math.tau * f / RATE
            env = math.sin(math.pi * j / length) * (0.5 + 0.5 * math.sin(math.tau * 35 * t))
            out[(start + j) % n] += math.sin(phase) * amp * env
    # Низкий гул массы тел
    lp = lp2 = 0.0
    for i in range(n):
        lp += (rnd.uniform(-1, 1) - lp) * 0.02
        lp2 += (lp - lp2) * 0.05
        out[i] += lp2 * 2.5
    # Бесшовность: сгладить стык
    fade = int(RATE * 0.05)
    for j in range(fade):
        w = j / fade
        out[n - fade + j] = out[n - fade + j] * (1 - w) + out[j] * w
    return out[fade:]


def gate_hit():
    """Жук врезается в ворота: глухой удар в дерево и хруст."""
    rnd = random.Random(52)
    n = int(RATE * 0.7)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.15
        thud = math.sin(math.tau * (85 - 30 * t) * t) * math.exp(-t * 14.0) * 1.4
        body = lp * math.exp(-t * 18.0) * 1.6
        crunch = rnd.uniform(-1, 1) * math.exp(-max(t - 0.015, 0) * 60.0) * (0.6 if t > 0.012 else 0.0)
        out.append(thud + body + crunch)
    return out


def wave_horn():
    """Начало волны: низкий тревожный рог и гул из пещер."""
    rnd = random.Random(63)
    n = int(RATE * 3.2)
    out = []
    lp = lp2 = 0.0
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 98.0 * (1 + 0.012 * math.sin(math.tau * 5.0 * t)) * (0.94 if t < 0.25 else 1.0)
        phase += math.tau * f / RATE
        saw = sum(math.sin(phase * h) / h for h in range(1, 9))
        env = min(t / 0.35, 1.0) * (1.0 if t < 2.2 else max(0.0, 1 - (t - 2.2) / 1.0))
        lp += (saw - lp) * 0.08
        lp2 += (rnd.uniform(-1, 1) - lp2) * 0.01
        rumble = lp2 * 5.0 * min(t / 1.0, 1.0) * max(0.0, 1 - t / 3.2)
        out.append(lp * env * 0.9 + rumble)
    return out


def squish():
    """Смерть жука: короткий хруст хитина и мокрый шлепок."""
    rnd = random.Random(74)
    n = int(RATE * 0.25)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.35
        crack = rnd.uniform(-1, 1) * math.exp(-t * 90.0)
        wet = lp * math.exp(-t * 22.0) * 1.2
        chirp = math.sin(math.tau * (2400 - 6000 * t) * t) * math.exp(-t * 40.0) * 0.4
        out.append(crack + wet + chirp)
    return out



def _voice(out, start, length, f0_from, f0_to, formants, amp, rnd, tremolo=0.0):
    """Голосовой слог: импульсы связок с дрожью высоты через резонаторы-форманты (гласная)."""
    n = len(out)
    src = []
    phase = 0.0
    for j in range(length):
        t = j / RATE
        k = j / length
        f = f0_from + (f0_to - f0_from) * k
        f *= 1 + 0.03 * math.sin(math.tau * 6 * t) + rnd.uniform(-0.02, 0.02)
        phase += f / RATE
        pulse = 1.0 if phase >= 1.0 else 0.0
        phase -= math.floor(phase)
        env = min(k / 0.12, 1.0) * (1 - k) ** 1.5
        if tremolo:
            env *= 0.35 + 0.65 * max(0.0, math.sin(math.tau * tremolo * t))
        src.append((pulse * 3.0 + rnd.uniform(-1, 1) * 0.15) * env)
    voiced = [0.0] * length
    for fc, bw, gain in formants:
        r = math.exp(-math.pi * bw / RATE)
        c = 2 * r * math.cos(math.tau * fc / RATE)
        y1 = y2 = 0.0
        for j in range(length):
            y = src[j] + c * y1 - r * r * y2
            y2, y1 = y1, y
            voiced[j] += y * gain
    for j in range(length):
        out[(start + j) % n] += voiced[j] * amp


VOWELS = {
    "a": [(720, 110, 1.0), (1150, 140, 0.6), (2500, 200, 0.15)],
    "o": [(500, 100, 1.0), (880, 120, 0.55), (2400, 200, 0.1)],
    "u": [(360, 90, 1.0), (760, 120, 0.4), (2300, 200, 0.08)],
    "e": [(480, 100, 1.0), (1850, 150, 0.5), (2600, 200, 0.2)],
    "i": [(300, 80, 1.0), (2250, 160, 0.55), (3000, 220, 0.2)],
}


def goblin_loop():
    """Толпа гоблинов: ворчание и выкрики на разные гласные, хихиканье, топот босых ног.
    События раскиданы по кругу — конец бесшовно переходит в начало."""
    rnd = random.Random(85)
    n = int(RATE * 4.0)
    out = [0.0] * n
    # Топот: частые мягкие удары
    lp = 0.0
    steps = [0.0] * n
    for k in range(700):
        start = rnd.randrange(n)
        amp = rnd.uniform(0.2, 0.6)
        length = int(RATE * 0.05)
        for j in range(length):
            steps[(start + j) % n] += rnd.uniform(-1, 1) * amp * math.exp(-j / (length * 0.25))
    for i in range(n):
        lp += (steps[i] - lp) * 0.06
        out[i] += lp * 1.6
    # Ворчание и выкрики
    for k in range(70):
        f0 = rnd.uniform(95, 190)
        length = int(RATE * rnd.uniform(0.12, 0.35))
        bend = rnd.choice([0.75, 0.85, 1.1, 1.25])
        _voice(out, rnd.randrange(n), length, f0, f0 * bend, VOWELS[rnd.choice("aaoue")], rnd.uniform(0.05, 0.14), rnd)
    # Хихиканье «хе-хе-хе»
    for k in range(9):
        f0 = rnd.uniform(260, 380)
        length = int(RATE * rnd.uniform(0.35, 0.6))
        _voice(out, rnd.randrange(n), length, f0, f0 * 0.9, VOWELS["e"], rnd.uniform(0.05, 0.1), rnd, tremolo=rnd.uniform(7, 10))
    fade = int(RATE * 0.05)
    for j in range(fade):
        w = j / fade
        out[n - fade + j] = out[n - fade + j] * (1 - w) + out[j] * w
    return out[fade:]


def goblin_die():
    """Гибель гоблина: короткий визг вниз по высоте и глухой шлепок о землю."""
    rnd = random.Random(96)
    n = int(RATE * 0.45)
    out = [0.0] * n
    _voice(out, 0, int(RATE * 0.28), 520, 240, VOWELS["i"], 0.5, rnd)
    lp = 0.0
    for i in range(int(RATE * 0.14), n):
        t = (i - RATE * 0.14) / RATE
        lp += (rnd.uniform(-1, 1) - lp) * 0.08
        out[i] += (lp * 2.5 + math.sin(math.tau * 70 * t) * 0.6) * math.exp(-t * 20.0)
    return out



def gravigun_fire():
    """Выстрел гравипушки: глухой низкий «вумп» со спадом высоты и электрическое шипение."""
    rnd = random.Random(107)
    n = int(RATE * 0.7)
    out = []
    phase = 0.0
    lp = 0.0
    for i in range(n):
        t = i / RATE
        f = 220 * math.exp(-t * 7.0) + 45
        phase += math.tau * f / RATE
        body = math.sin(phase) * math.exp(-t * 5.0) * 1.2
        sub = math.sin(phase * 0.5) * math.exp(-t * 3.0) * 0.8
        lp += (rnd.uniform(-1, 1) - lp) * 0.5
        hiss = lp * math.exp(-t * 9.0) * 0.35 * (0.6 + 0.4 * math.sin(math.tau * 90 * t))
        out.append(body + sub + hiss)
    return out


def blackhole_loop():
    """Чёрная дыра: низкий качающийся гул и тонкий вой, затягивающий всё внутрь (зациклен)."""
    rnd = random.Random(118)
    n = int(RATE * 2.0)
    out = []
    lp = lp2 = 0.0
    for i in range(n):
        t = i / RATE
        # Частоты кратны 0.5 Гц — за две секунды целое число периодов, стык бесшовный
        wob = 1 + 0.25 * math.sin(math.tau * 1.5 * t)
        drone = (math.sin(math.tau * 55 * t) + 0.6 * math.sin(math.tau * 82.5 * t * 1.0)) * wob
        whine = math.sin(math.tau * (440 + 30 * math.sin(math.tau * 0.5 * t)) * t) * 0.12
        lp += (rnd.uniform(-1, 1) - lp) * 0.03
        lp2 += (lp - lp2) * 0.1
        out.append(drone * 0.6 + whine + lp2 * 3.0 * wob)
    return out


def blackhole_collapse():
    """Схлопывание: нарастающий всасывающий свист и глухой удар в конце."""
    rnd = random.Random(129)
    n = int(RATE * 0.9)
    out = []
    lp = 0.0
    phase = 0.0
    for i in range(n):
        t = i / RATE
        k = min(t / 0.45, 1.0)
        lp += (rnd.uniform(-1, 1) - lp) * (0.05 + 0.4 * k)
        suck = lp * (k ** 2) * (1.0 if t < 0.45 else math.exp(-(t - 0.45) * 30.0)) * 1.4
        if t >= 0.45:
            tt = t - 0.45
            phase += math.tau * (90 - 40 * tt) / RATE
            thump = math.sin(phase) * math.exp(-tt * 9.0) * 1.3
        else:
            thump = 0.0
        out.append(suck + thump)
    return out



def laser_loop():
    """Луч лазерной турели: электрический гул с дребезгом и высокий звенящий тон (зациклен).
    Частоты кратны 0.5 Гц — за две секунды целое число периодов, стык бесшовный."""
    rnd = random.Random(141)
    n = int(RATE * 2.0)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        buzz = sum(math.sin(math.tau * 110.0 * h * t) / h for h in range(1, 7))
        trem = 0.7 + 0.3 * math.sin(math.tau * 30.0 * t)
        ring = math.sin(math.tau * 1320.0 * t + 2.0 * math.sin(math.tau * 6.0 * t)) * 0.25
        lp += (rnd.uniform(-1, 1) - lp) * 0.6
        crackle = lp * 0.25 * (1.0 if rnd.random() < 0.03 else 0.3)
        out.append(buzz * 0.35 * trem + ring + crackle)
    return out


def hammer_swing():
    """Свист замаха молотом: шум через полосовой фильтр, тон поднимается и падает, нарастает и гаснет."""
    rnd = random.Random(171)
    n = int(RATE * 0.38)
    out = []
    lp = bp = 0.0
    for i in range(n):
        t = i / RATE
        k = t / 0.38
        env = math.sin(math.pi * min(1.0, k * 1.15)) ** 2
        a = 0.05 + 0.25 * math.sin(math.pi * k)   # «частота» фильтра: выше к середине замаха
        lp += (rnd.uniform(-1, 1) - lp) * a
        bp += (lp - bp) * 0.5
        out.append((lp - bp) * env * 2.0)
    return out


def hammer_slam():
    """Удар молота о землю: глухой низкий удар, хруст камня, гул и осыпающиеся комья."""
    rnd = random.Random(173)
    n = int(RATE * 1.3)
    out = []
    lp = lp2 = 0.0
    for i in range(n):
        t = i / RATE
        noise = rnd.uniform(-1, 1)
        lp += (noise - lp) * (0.5 if t < 0.02 else 0.12)
        lp2 += (lp - lp2) * 0.08
        thud = math.sin(math.tau * (55.0 - 22.0 * min(t, 0.4)) * t) * math.exp(-t * 7.0) * 1.8
        crunch = lp * math.exp(-t * 16.0) * 1.3
        rumble = lp2 * math.exp(-t * 3.0) * 2.2
        pebbles = noise * 0.25 * math.exp(-t * 4.0) if rnd.random() < 0.004 else 0.0
        out.append(thud + crunch + rumble + pebbles)
    attack = int(RATE * 0.002)
    for i in range(attack):
        out[i] *= i / attack
    return out


def saw_throw():
    """Выстрел дискомёта: щелчок пружины, звон раскрученного диска (тон падает, дрожит с частотой
    вращения) и свист воздуха вслед."""
    rnd = random.Random(181)
    n = int(RATE * 0.55)
    out = []
    lp = 0.0
    ph = [0.0, 0.0, 0.0]
    for i in range(n):
        t = i / RATE
        noise = rnd.uniform(-1, 1)
        # Щелчок и глухой толчок механизма
        click = noise * math.exp(-t * 300.0) * 1.2
        thunk = math.sin(math.tau * 140.0 * t) * math.exp(-t * 40.0) * 0.9
        # Звон диска: три негармонических тона, падают по высоте, дрожат от вращения
        spin = 0.6 + 0.4 * math.sin(math.tau * 55.0 * t)
        ring = 0.0
        for k, (f, a) in enumerate([(1850.0, 0.5), (2730.0, 0.3), (3900.0, 0.18)]):
            ph[k] += math.tau * f * (1.0 - 0.28 * min(t / 0.5, 1.0)) / RATE
            ring += math.sin(ph[k]) * a
        ring *= spin * math.exp(-t * 5.5) * (1.0 - math.exp(-t * 200.0))
        # Свист воздуха
        lp += (noise - lp) * 0.35
        whoosh = (noise - lp) * 0.5 * math.sin(math.pi * min(t / 0.5, 1.0)) ** 2
        out.append(click + thunk + ring + whoosh)
    return out


def saw_whirr():
    """Летящий диск: жужжание с дрожью вращения (зациклено, 1 с — частоты кратны 1 Гц)."""
    rnd = random.Random(183)
    n = RATE
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        spin = 0.55 + 0.45 * math.sin(math.tau * 48.0 * t)
        tone = (math.sin(math.tau * 820.0 * t) * 0.5 + math.sin(math.tau * 1230.0 * t) * 0.3) * spin
        lp += (rnd.uniform(-1, 1) - lp) * 0.3
        out.append(tone + lp * 0.35 * spin)
    return out


def tesla_loop():
    """Электропушка: сухой треск разрядов — щелчки и шипящие вспышки поверх низкого жужжания
    тока (зациклено, 2 с — частоты кратны 0,5 Гц)."""
    rnd = random.Random(191)
    n = int(RATE * 2.0)
    out = [0.0] * n
    for i in range(n):
        t = i / RATE
        hum = sum(math.sin(math.tau * 100.0 * h * t) / h for h in (1, 2, 3, 5)) * 0.18
        out[i] = hum * (0.7 + 0.3 * math.sin(math.tau * 9.0 * t))
    # Разряды: короткие вспышки шума с резким началом — то чаще, то реже
    pos = 0
    while pos < n:
        length = rnd.randint(int(RATE * 0.004), int(RATE * 0.03))
        amp = rnd.uniform(0.5, 1.0)
        lp = 0.0
        a = rnd.uniform(0.3, 0.9)
        for j in range(length):
            k = (pos + j) % n
            lp += (rnd.uniform(-1, 1) - lp) * a
            env = math.exp(-j / (length * 0.35))
            out[k] += lp * amp * env * 1.4
        pos += length + rnd.randint(int(RATE * 0.002), int(RATE * 0.05))
    # Шипящая «дуга» постоянно под треском
    lp = 0.0
    for i in range(n):
        lp += (rnd.uniform(-1, 1) - lp) * 0.8
        out[i] += lp * 0.12
    return out


os.makedirs(OUT, exist_ok=True)
write("blunderbuss_shot.wav", blunderbuss_shot())
write("explosion.wav", explosion())
write("flame_loop.wav", flame_loop())
write("flame_ignite.wav", flame_ignite())
write("gatling_loop.wav", gatling_loop())
write("swarm_loop.wav", swarm_loop())
write("gate_hit.wav", gate_hit())
write("wave_horn.wav", wave_horn())
write("squish.wav", squish())
print("ok")
write("goblin_loop.wav", goblin_loop())
write("goblin_die.wav", goblin_die())
write("gravigun_fire.wav", gravigun_fire())
write("blackhole_loop.wav", blackhole_loop())
write("blackhole_collapse.wav", blackhole_collapse())
write("laser_loop.wav", laser_loop())
write("hammer_swing.wav", hammer_swing())
write("hammer_slam.wav", hammer_slam())
write("saw_throw.wav", saw_throw())
write("saw_whirr.wav", saw_whirr())
write("tesla_loop.wav", tesla_loop())
