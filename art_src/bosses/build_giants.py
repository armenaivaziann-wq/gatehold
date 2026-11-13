"""Боссы локаций 2–10 — великаны по референсу art_src/bosses/ref_giants.webp (свои модели в том же
духе): песчаный великан в красном капюшоне и шарфе, ледяной великан с ледяной бородой и шипами,
король-энт с рогами-ветвями и мхом, болотное чудище с черепом на плече и корягой, огненный демон
в лаве с рогами, полководец в латах с рогатым шлемом, красным плащом и шипастой булавой.
Перекраски: соляной великан, красный титан, сухой энт, кристальный великан, ночное чудище,
владыка орды (чёрные латы с золотом).

Скелет — как у Вождя гоблинов (build_bosses.py), чтобы boss_view.gd шагал, бил и ронял их так же:
Hips (в нём Torso, в Torso — ArmL и ArmR), LegL, LegR; начало каждой части — в её шарнире.
Великан коренастый: короткие толстые ноги, огромная грудь и кулаки, маленькая голова. Рост около
2 м (в игре масштаб под размер босса).

Запуск: Blender -b --factory-startup --python art_src/bosses/build_giants.py
Пишет mobs/bosses/<имя>.glb, art_src/bosses/giants.blend и превью в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

# Материалы и построители граней — общие с build_bosses.py (без его сборки моделей)
_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_bosses.py"), encoding="utf-8").read()
exec(_src[:_src.index("# --- вожак")])

OUT_BLEND = os.path.join(PROJECT, "art_src/bosses/giants.blend")
PALETTE.update({
    "Sand": ("D9B070", "C29858", "9A7442", 0.95, 0.0),
    "Salt": ("EDEBE5", "D3D1CB", "A9A7A1", 0.9, 0.0),
    "RedRock": ("C8673F", "A84E2F", "7C3822", 0.95, 0.0),
    "Ice": ("CFE6FA", "A9CBEE", "7FA4D6", 0.5, 0.05),
    "Navy": ("56669A", "435282", "303C62", 0.85, 0.0),
    "Crystal": ("D2A8F5", "B184E2", "8559B8", 0.45, 0.05),
    "CrystalDark": ("5A4A8A", "463A72", "322A54", 0.8, 0.0),
    "BlueGlow": ("9AE8FF", "6CD6FF", "3AB8F0", 0.4, 0.0),
    "Bark": ("8F5E37", "724728", "51301A", 0.95, 0.0),
    "Moss": ("9ABD52", "7A9C3A", "587626", 0.95, 0.0),
    "DryBark": ("A08466", "806650", "5C4838", 0.95, 0.0),
    "Autumn": ("E0A848", "C0862E", "90601E", 0.9, 0.0),
    "SwampSkin": ("789A50", "5E7C3E", "44592C", 0.9, 0.0),
    "Rag": ("5A5E3A", "46492C", "32341F", 0.95, 0.0),
    "GreenGlow": ("B6FF7A", "8CF04E", "5CC830", 0.4, 0.0),
    "NightSkin": ("5E6A8C", "4A5574", "343C56", 0.9, 0.0),
    "Basalt": ("4E3C46", "3C2E36", "2A2026", 0.9, 0.0),
    "Lava": ("FFA040", "FF7A20", "E05A10", 0.5, 0.0),
    "Horn": ("F0A040", "D08028", "A06018", 0.7, 0.0),
    "Plate": ("A2A2B0", "828290", "5E5E6A", 0.5, 0.5),
    "BlackPlate": ("54545F", "40404A", "2C2C34", 0.5, 0.5),
    "Gold": ("F2C55A", "D9A63C", "A87A26", 0.4, 0.6),
})
GLOWS.update({"BlueGlow": 4.0, "GreenGlow": 4.0, "Lava": 2.2})
MAT_NAMES[:] = [f"{b}_{t}" if t else b for b in PALETTE for t in TONES]
MAT.clear()
MAT.update({name: i for i, name in enumerate(MAT_NAMES)})

HIP_G = 0.72                  # шарниры бёдер
WAIST_G = 0.18                # поясница над тазом
SHOULDER_G = (0.66, 0.02, 0.5)  # плечо в Torso
HEAD = (0.0, 0.2, 0.74)       # центр головы в Torso: голова вперёд и вниз, утоплена в плечи


def chunks(rng, base, centers, size=0.14):
    """Каменные или ледяные сколы: повёрнутые бруски, торчащие из тела (как в референсе)."""
    for c in centers:
        rot = Matrix.Rotation(rng.uniform(-0.6, 0.6), 3, "X") @ Matrix.Rotation(rng.uniform(-0.6, 0.6), 3, "Y")
        s = size * rng.uniform(0.7, 1.2)
        box(c, (s, s * rng.uniform(0.8, 1.3), s * rng.uniform(0.6, 1.0)), base, bevel=0.01, rot=rot)


# --- общий великан -------------------------------------------------------------------------

def giant_leg(st, s):
    box((0, 0, -0.17), (0.42, 0.44, 0.38), st["legs"], bevel=0.035, top=(0.46, 0.48))
    box((0, 0.02, -0.47), (0.38, 0.4, 0.3), st["body"], bevel=0.03)
    box((0, 0.08, -0.65), (0.46, 0.56, 0.14), st["feet"], bevel=0.03, top=(0.42, 0.48))
    if st.get("leg_extra"):
        st["leg_extra"](s)


def giant_hips(st):
    box((0, 0, 0.04), (0.88, 0.5, 0.3), st["legs"], bevel=0.03, top=(0.9, 0.52))
    box((0, 0, 0.17), (0.94, 0.56, 0.11), st["belt"], bevel=0.015)
    for y, sign in ((0.27, 1), (-0.27, -1)):
        box((0, y, -0.1), (0.38, 0.04, 0.34), st["cloth"], bevel=0.01)
        spike((0, y, -0.27), (0, y + sign * 0.01, -0.46), 0.17, st["cloth"], segments=4)
    if st.get("hips_extra"):
        st["hips_extra"]()


def giant_torso(st):
    box((0, 0.02, 0.32), (0.84, 0.52, 0.64), st["body"], bevel=0.04, top=(1.28, 0.68))
    for x in (-0.24, 0.24):
        box((x, 0.29, 0.42), (0.44, 0.1, 0.3), st["body"], bevel=0.035)
    box((0, -0.04, 0.64), (0.98, 0.52, 0.2), st["body"], bevel=0.04, top=(0.62, 0.42))
    hx, hy, hz = HEAD
    box((hx, hy, hz), (0.38, 0.36, 0.32), st["head"], bevel=0.03, top=(0.34, 0.32))
    box((hx, hy + 0.17, hz + 0.08), (0.4, 0.06, 0.07), st["head"], bevel=0.015)
    for x in (-0.09, 0.09):
        rot = Matrix.Rotation(-0.3 if x < 0 else 0.3, 3, "Y")
        box((x, hy + 0.185, hz + 0.03), (0.1, 0.02, 0.045), st["eye"], rot=rot)
    if st.get("torso_extra"):
        st["torso_extra"]()


def giant_arm(st, s):
    box((s * 0.1, 0, -0.2), (0.42, 0.44, 0.46), st["body"], bevel=0.04, top=(0.46, 0.48))
    box((s * 0.17, 0.04, -0.58), (0.46, 0.48, 0.38), st["forearm"], bevel=0.04)
    box((s * 0.19, 0.08, -0.9), (0.48, 0.5, 0.38), st["fist"], bevel=0.045)
    box((s * 0.19, 0.3, -0.92), (0.42, 0.08, 0.22), st["fist"], bevel=0.02)
    if st.get("arm_extra"):
        st["arm_extra"](s)


# --- стили -------------------------------------------------------------------------------------

def sand_style(body, cloth, eye="Eye", seed=1):
    rng = random.Random(seed)
    hx, hy, hz = HEAD

    def torso():
        # Капюшон-повязка: макушка, затылок; шарф вокруг шеи и треугольником на грудь
        box((hx, hy - 0.02, hz + 0.18), (0.44, 0.42, 0.12), cloth, bevel=0.02, top=(0.38, 0.36))
        box((hx, hy - 0.17, hz + 0.02), (0.44, 0.08, 0.34), cloth, bevel=0.015)
        box((0, 0.04, 0.6), (0.72, 0.56, 0.15), cloth, bevel=0.025, top=(0.58, 0.46))
        spike((0, 0.33, 0.56), (0.05, 0.38, 0.12), 0.2, cloth, segments=4)
        chunks(rng, body, [(-0.5, -0.1, 0.66), (0.52, -0.08, 0.68), (-0.3, -0.26, 0.4), (0.28, -0.26, 0.3),
                           (0.0, -0.28, 0.55)])

    def arm(s):
        chunks(rng, body, [(s * 0.3, -0.05, -0.1), (s * 0.36, 0.0, -0.55), (s * 0.12, -0.22, -0.4)], 0.12)

    return {"body": body, "head": body, "legs": body, "feet": body, "forearm": body, "fist": body,
            "belt": cloth, "cloth": cloth, "eye": eye, "torso_extra": torso, "arm_extra": arm}


def ice_style(body, dark, eye, seed=2):
    rng = random.Random(seed)
    hx, hy, hz = HEAD

    def torso():
        # Ледяная борода, шипы на плечах, спине и макушке
        for k, x in enumerate((-0.14, -0.05, 0.05, 0.14)):
            spike((x, hy + 0.15, hz - 0.08), (x * 1.3, hy + 0.24, hz - 0.42 - 0.06 * (k % 2)), 0.08, body, segments=4)
        for x in (-0.09, 0.09):
            spike((x, hy, hz + 0.15), (x * 1.6, hy - 0.06, hz + 0.36), 0.06, body, segments=4)
        for s_ in (-1, 1):
            for a, b in (((0.52, 0.0, 0.7), (0.62, -0.06, 1.04)), ((0.62, -0.14, 0.62), (0.88, -0.24, 0.84)),
                         ((0.4, -0.2, 0.74), (0.42, -0.36, 1.0))):
                spike((s_ * a[0], a[1], a[2]), (s_ * b[0], b[1], b[2]), 0.09, body, segments=4)
        for z in (0.2, 0.45):
            spike((0, -0.28, z), (0, -0.56, z + 0.12), 0.1, body, segments=4)
        chunks(rng, body, [(-0.3, 0.3, 0.2), (0.32, 0.3, 0.24)], 0.12)

    def arm(s):
        box((s * 0.17, 0.04, -0.66), (0.5, 0.52, 0.18), dark, bevel=0.02)
        spike((s * 0.38, 0.0, -0.5), (s * 0.62, -0.06, -0.42), 0.06, body, segments=4)
        spike((s * 0.38, 0.04, -0.66), (s * 0.6, 0.02, -0.72), 0.05, body, segments=4)

    def leg(s):
        for x in (-0.12, 0.12):
            spike((x, 0.26, -0.66), (x * 1.3, 0.36, -0.62), 0.05, body, segments=4)

    return {"body": body, "head": body, "legs": body, "feet": body, "forearm": body, "fist": body,
            "belt": dark, "cloth": dark, "eye": eye, "torso_extra": torso, "arm_extra": arm, "leg_extra": leg}


def treant_style(bark, moss, seed=3):
    rng = random.Random(seed)
    hx, hy, hz = HEAD

    def torso():
        # Рога-ветви, мох на плечах, груди и макушке, моховая борода, полосы коры
        for s_ in (-1, 1):
            a = Vector((s_ * 0.12, hy - 0.02, hz + 0.14))
            b = Vector((s_ * 0.34, hy - 0.08, hz + 0.5))
            bar(a, b, (0.07, 0.07), bark, bevel=0.01)
            bar(b, b + Vector((s_ * 0.16, -0.04, 0.22)), (0.05, 0.05), bark)
            mid = a.lerp(b, 0.55)
            bar(mid, mid + Vector((s_ * 0.18, 0.08, 0.12)), (0.045, 0.045), bark)
            bar(b, b + Vector((-s_ * 0.06, 0.04, 0.2)), (0.04, 0.04), bark)
        for k, x in enumerate((-0.12, 0.0, 0.12)):
            spike((x, hy + 0.15, hz - 0.08), (x * 1.2, hy + 0.2, hz - 0.36 - 0.06 * (k == 1)), 0.08, moss, segments=4)
        box((hx, hy - 0.02, hz + 0.17), (0.34, 0.3, 0.06), moss, bevel=0.01)
        for c, sz in (((-0.5, 0.0, 0.7), (0.4, 0.46, 0.1)), ((0.5, 0.0, 0.7), (0.4, 0.46, 0.1)),
                      ((0.0, 0.3, 0.28), (0.36, 0.06, 0.3)), ((-0.24, 0.3, 0.52), (0.2, 0.06, 0.16))):
            box(c, sz, moss, bevel=0.015)
        for x in (-0.3, -0.1, 0.12, 0.32):
            box((x, 0.3, 0.12), (0.05, 0.04, 0.4), "Bark" if bark == "Bark" else bark, bevel=0.005)

    def arm(s):
        # Пальцы-сучья
        fist = Vector((s * 0.19, 0.08, -0.9))
        for k, d in enumerate((Vector((s * 0.1, 0.2, -0.3)), Vector((0, 0.24, -0.34)), Vector((-s * 0.1, 0.2, -0.3)))):
            bar(fist + Vector(((k - 1) * 0.12, 0.12, -0.12)), fist + Vector(((k - 1) * 0.12, 0.12, -0.12)) + d,
                (0.07, 0.07), bark, bevel=0.01)
        box((s * 0.3, 0.0, -0.1), (0.14, 0.4, 0.3), moss, bevel=0.01)

    def leg(s):
        # Корни у ступней
        for d in (Vector((0.24, 0.16, -0.12)), Vector((-0.2, 0.2, -0.12)), Vector((0.0, -0.26, -0.1))):
            bar((0, 0.06, -0.6), Vector((0, 0.06, -0.6)) + d, (0.08, 0.08), bark)

    return {"body": bark, "head": bark, "legs": bark, "feet": bark, "forearm": bark, "fist": bark,
            "belt": moss, "cloth": moss, "eye": "Eye", "torso_extra": torso, "arm_extra": arm, "leg_extra": leg}


def swamp_style(skin, rag, eye):
    hx, hy, hz = HEAD

    def torso():
        # Череп на левом плече, шипы по спине, рваные лохмотья на груди
        box((-0.56, 0.06, 0.82), (0.24, 0.24, 0.24), "Bone", bevel=0.03)
        box((-0.56, 0.12, 0.72), (0.18, 0.16, 0.08), "Bone", bevel=0.01)
        for x in (-0.62, -0.5):
            box((x, 0.185, 0.84), (0.07, 0.02, 0.07), "Mouth")
        for z, x in ((0.66, -0.3), (0.62, 0.3), (0.45, 0.0), (0.7, 0.0)):
            spike((x, -0.26, z), (x * 1.2, -0.52, z + 0.2), 0.08, skin, segments=4)
        spike((0.5, -0.02, 0.76), (0.66, -0.04, 1.02), 0.07, "Moss", segments=4)
        for k in range(5):
            x = -0.32 + k * 0.16
            box((x, 0.3, 0.02 - 0.05 * (k % 2)), (0.15, 0.04, 0.22 + 0.08 * (k % 2)), rag)

    def arm(s):
        if s > 0:
            # Коряга-дубина в правой руке
            fist = Vector((s * 0.19, 0.08, -0.9))
            d = Vector((0.25, 0.55, 0.8)).normalized()
            bar(fist - d * 0.25, fist + d * 0.5, (0.12, 0.12), "Wood", bevel=0.01)
            bar(fist + d * 0.45, fist + d * 1.15, (0.26, 0.26), "Wood", bevel=0.03, flare=1.3)
            for t, along in ((0.6, 0.5), (2.3, 0.7), (4.1, 0.85)):
                x, y, _ = _basis(d)
                c = fist + d * (0.45 + 0.7 * along)
                out = x * math.cos(t) + y * math.sin(t)
                bar(c + out * 0.12, c + out * 0.34 + d * 0.1, (0.07, 0.07), "Wood")
            box(fist + d * 0.9, (0.3, 0.3, 0.1), "Moss", bevel=0.01)

    return {"body": skin, "head": skin, "legs": rag, "feet": skin, "forearm": skin, "fist": skin,
            "belt": "Dark", "cloth": rag, "eye": eye, "torso_extra": torso, "arm_extra": arm}


def fire_style():
    hx, hy, hz = HEAD

    def torso():
        # Лавовые трещины-пластины, изогнутые рога, шипы на плечах
        for c, sz in (((0, 0.3, 0.38), (0.3, 0.05, 0.4)), ((-0.24, 0.32, 0.52), (0.26, 0.05, 0.12)),
                      ((0.24, 0.32, 0.52), (0.26, 0.05, 0.12)), ((0, 0.3, 0.1), (0.2, 0.05, 0.14))):
            box(c, sz, "Lava")
        for s_ in (-1, 1):
            a = Vector((s_ * 0.16, hy - 0.02, hz + 0.1))
            b = a + Vector((s_ * 0.18, -0.02, 0.18))
            bar(a, b, (0.11, 0.11), "Horn", bevel=0.01)
            spike(b, b + Vector((s_ * 0.02, 0.04, 0.24)), 0.07, "Horn", segments=5)
            spike((s_ * 0.56, -0.04, 0.72), (s_ * 0.74, -0.1, 1.0), 0.1, "Basalt", segments=4)
            box((s_ * 0.5, 0.04, 0.66), (0.4, 0.48, 0.1), "Lava", bevel=0.01)
        box((hx, hy + 0.15, hz - 0.1), (0.3, 0.1, 0.08), "Lava")

    def arm(s):
        box((s * 0.17, 0.04, -0.58), (0.5, 0.52, 0.12), "Lava")
        box((s * 0.19, 0.08, -0.82), (0.52, 0.54, 0.1), "Lava")

    def leg(s):
        box((0, 0.0, -0.32), (0.44, 0.46, 0.08), "Lava")

    return {"body": "Basalt", "head": "Basalt", "legs": "Basalt", "feet": "Lava", "forearm": "Basalt",
            "fist": "Lava", "belt": "Basalt", "cloth": "Basalt", "eye": "Eye", "torso_extra": torso,
            "arm_extra": arm, "leg_extra": leg}


def warlord_style(plate, trim, cape):
    hx, hy, hz = HEAD

    def torso():
        # Рогатый шлем с прорезью и красными глазами; шипастые наплечники; плащ и шарф
        box((hx, hy, hz + 0.03), (0.42, 0.4, 0.4), plate, bevel=0.03, top=(0.36, 0.34))
        box((hx, hy + 0.205, hz + 0.03), (0.3, 0.02, 0.05), "Mouth")
        for s_ in (-1, 1):
            spike((s_ * 0.2, hy, hz + 0.16), (s_ * 0.42, hy - 0.04, hz + 0.44), 0.07, "Bone", segments=5)
            box((s_ * 0.66, -0.02, 0.62), (0.5, 0.56, 0.34), plate, bevel=0.04, top=(0.4, 0.46))
            for a, b in (((0.66, 0.0, 0.8), (0.7, 0.0, 1.06)), ((0.86, -0.1, 0.66), (1.08, -0.14, 0.74)),
                         ((0.66, 0.2, 0.7), (0.72, 0.4, 0.8))):
                spike((s_ * a[0], a[1], a[2]), (s_ * b[0], b[1], b[2]), 0.075, "Steel", segments=4)
            box((s_ * 0.66, 0.0, 0.46), (0.52, 0.58, 0.05), trim)
        box((0, -0.32, 0.1), (0.9, 0.06, 1.0), cape, bevel=0.01)
        box((0, -0.3, -0.48), (0.8, 0.05, 0.3), cape)
        bar((-0.44, 0.33, 0.62), (0.4, 0.33, 0.04), (0.16, 0.04), cape)
        box((0, 0.3, 0.3), (0.5, 0.05, 0.4), plate, bevel=0.01)
        box((0, 0.33, 0.48), (0.5, 0.03, 0.04), trim)

    def arm(s):
        box((s * 0.17, 0.04, -0.58), (0.5, 0.52, 0.14), trim, bevel=0.01)
        if s > 0:
            # Шипастая булава
            fist = Vector((s * 0.19, 0.08, -0.9))
            d = Vector((0.2, 0.62, 0.76)).normalized()
            bar(fist - d * 0.2, fist + d * 0.62, (0.09, 0.09), "Leather", bevel=0.01)
            head = fist + d * 0.82
            box(head, (0.34, 0.34, 0.34), "BlackPlate", bevel=0.06)
            for v in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, -1, 0)),
                      Vector((0, 0, 1)), Vector((0.7, 0.7, 0)), Vector((-0.7, 0.7, 0)), Vector((0, 0.7, 0.7))):
                spike(head + v * 0.16, head + v * 0.34, 0.05, "Steel", segments=4)

    def leg(s):
        box((0, 0.2, -0.42), (0.3, 0.06, 0.2), trim, bevel=0.01)

    return {"body": plate, "head": plate, "legs": plate, "feet": "BlackPlate", "forearm": plate, "fist": plate,
            "belt": "Leather", "cloth": cape, "eye": "Ember", "torso_extra": torso, "arm_extra": arm, "leg_extra": leg}


GIANTS = [
    ("sand_giant", sand_style("Sand", "Red", seed=11)),
    ("salt_giant", sand_style("Salt", "Navy", eye="BlueGlow", seed=12)),
    ("red_titan", sand_style("RedRock", "Dark", eye="Ember", seed=13)),
    ("treant_king", treant_style("DryBark", "Autumn")),
    ("ice_giant", ice_style("Ice", "Navy", "BlueGlow", seed=21)),
    ("night_beast", swamp_style("NightSkin", "Dark", "BlueGlow")),
    ("fire_demon", fire_style()),
    ("crystal_giant", ice_style("Crystal", "CrystalDark", "Ember", seed=22)),
    ("horde_warlord", warlord_style("BlackPlate", "Gold", "Red")),
    ("swamp_beast", swamp_style("SwampSkin", "Rag", "GreenGlow")),
    ("forest_treant", treant_style("Bark", "Moss")),
    ("warlord", warlord_style("Plate", "Leather", "Red")),
]


# --- сборка --------------------------------------------------------------------------------

def new_mesh(name, mats):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    for m in mats:
        mesh.materials.append(m)
    return mesh


def look_at(obj, loc, target):
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(Vector((0, 0, 1))).normalized()
    u = r.cross(f)
    obj.matrix_world = Matrix((r, u, -f)).transposed().to_4x4()
    obj.location = loc


def export_giant(name, st, x, y):
    global bm
    root = bpy.data.objects.new(name, None)
    scene.collection.objects.link(root)
    objs = {None: root}
    made = [root]
    tris = 0
    parts = [
        ("LegL", None, (-0.24, 0, HIP_G), lambda: giant_leg(st, -1)),
        ("LegR", None, (0.24, 0, HIP_G), lambda: giant_leg(st, 1)),
        ("Hips", None, (0, 0, HIP_G), lambda: giant_hips(st)),
        ("Torso", "Hips", (0, 0, WAIST_G), lambda: giant_torso(st)),
        ("ArmL", "Torso", (-SHOULDER_G[0], SHOULDER_G[1], SHOULDER_G[2]), lambda: giant_arm(st, -1)),
        ("ArmR", "Torso", SHOULDER_G, lambda: giant_arm(st, 1)),
    ]
    for part, parent, loc, build in parts:
        bm = bmesh.new()
        build()
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        tris += len(bm.faces)
        obj = bpy.data.objects.new(part, new_mesh(f"{name}_{part}", mats))
        bm.free()
        scene.collection.objects.link(obj)
        obj.parent = objs[parent]
        obj.location = loc
        objs[part] = obj
        made.append(obj)
    for o in bpy.data.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB", use_selection=True)
    root.location = (x, y, 0)
    for o in made[1:]:
        o.name = f"{name}_{o.name}"
    print("BUILT", name, "triangles:", tris)


bpy.ops.wm.read_homefile(use_empty=True)
mats = make_materials()
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)
scene = bpy.context.scene
for k, (name, st) in enumerate(GIANTS):
    export_giant(name, st, (k % 6) * 3.2, -(k // 6) * 6.0)

world = bpy.data.worlds.new("W")
world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb_to_lin("3A3A42")
scene.world = world
scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 520
scene.render.resolution_y = 560
for name, energy, rot in (("Key", 2.8, (50, 15, -30)), ("Fill", 1.0, (60, 0, 150))):
    light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    light.data.energy = energy
    light.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(light)
# Превью: каждый великан отдельно, три четверти спереди
for k, (name, _st) in enumerate(GIANTS):
    gx, gy = (k % 6) * 3.2, -(k // 6) * 6.0
    cam = bpy.data.objects.new(f"Cam_{name}", bpy.data.cameras.new(f"Cam_{name}"))
    cam.data.lens = 42
    scene.collection.objects.link(cam)
    look_at(cam, (gx + 1.6, gy + 3.6, 1.9), (gx, gy, 1.1))
    scene.camera = cam
    scene.render.filepath = os.path.join(PREVIEW_DIR, f"giant_{name}.png")
    bpy.ops.render.render(write_still=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
