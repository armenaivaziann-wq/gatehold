"""Босс первой локации — Вождь гоблинов, по референсу art_src/bosses/ref_goblin_chief.webp:
коренастый зелёный орк в красном капюшоне и шарфе, с клыками и жёлтыми глазами, на левом плече —
огромный лиловый наплечник с костяными шипами, на правом — поменьше; кожаный ремень через грудь,
пояс с костяной пряжкой-черепом, красная набедренная повязка, тёмные штаны и сапоги, наручи;
в правой руке — тёмная дубина с костяными шипами.

Части — отдельные объекты, чтобы в игре (scripts/boss_view.gd) шагать, бить и падать:
Hips (таз; в нём Torso — корпус с головой и наплечниками; в Torso — ArmL и ArmR с дубиной),
LegL, LegR. Начало координат каждой части — её шарнир (бедро, плечо, поясница).
Тон каждой грани зависит от того, куда она смотрит (верх светлее, низ темнее) — как у турелей.

Вожак 5-й волны — гоблин-капитан верхом на огромном волке (своя модель, не по референсу):
тёмный волк с красными глазами, оскалом, шипастым ошейником и стальной налобной пластиной;
на нём в седле гоблин в кожаной броне с кирасой, в рогатом шлеме, с тесаком; за спиной —
шест с красным знаменем и костяным черепом. Части: Body (волк с наездником), LegFL, LegFR,
LegBL, LegBR (начало — в плече или бедре волка).

Оси Blender: +Y — вперёд (в Godot — -Z), +Z — вверх, +X — правая рука. Рост около 2 м
(у вожака — по макушку наездника; в игре масштаб под размер босса).
Запуск: Blender -b --factory-startup --python art_src/bosses/build_bosses.py
Пишет mobs/bosses/goblin_chief.glb и goblin_rider.glb, art_src/bosses/bosses.blend и превью
в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_DIR = os.path.join(PROJECT, "mobs/bosses")
OUT_BLEND = os.path.join(PROJECT, "art_src/bosses/bosses.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "bosses")

PALETTE = {
    "Skin": ("9CC24A", "80A836", "5E8226", 0.85, 0.0),
    "Red": ("D8413A", "B8302B", "86221F", 0.85, 0.0),
    "Leather": ("7A5236", "5E3D27", "41291A", 0.8, 0.0),
    "Dark": ("54423F", "3F3231", "2A2121", 0.85, 0.0),
    "Metal": ("847C9A", "675F7E", "4A4560", 0.65, 0.15),
    "Bone": ("F0DEBC", "D9C29C", "AE9672", 0.7, 0.0),
    "Club": ("514246", "3C3134", "2A2225", 0.8, 0.0),
    "Mouth": ("5A1A16", "45130F", "300C0A", 0.9, 0.0),
    "Eye": ("FFE45C", "FFD23A", "F0B020", 0.4, 0.0),
    "Fur": ("8C7E74", "6B5E56", "4A403B", 0.95, 0.0),
    "FurLight": ("C9BBA8", "AE9F8C", "8A7C6A", 0.95, 0.0),
    "Steel": ("D8DCE2", "B4B9C2", "8C929C", 0.35, 0.3),
    "Wood": ("9A6A40", "7A5030", "583820", 0.85, 0.0),
    "Ember": ("FF6A40", "FF4428", "D82A14", 0.4, 0.0),
}
GLOWS = {"Eye": 3.0, "Ember": 3.5}
TONES = ("Light", "", "Dark")
MAT_NAMES = [f"{b}_{t}" if t else b for b in PALETTE for t in TONES]
MAT = {name: i for i, name in enumerate(MAT_NAMES)}
HIP = 0.8             # высота шарниров бёдер
WAIST = 0.18          # поясница над тазом (Torso в Hips)
SHOULDER = (0.6, 0.0, 0.5)    # плечо в Torso

_rng = random.Random(7)
bm = None


def srgb_to_lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def make_materials():
    mats = []
    for base, (light, mid, dark, rough, metal) in PALETTE.items():
        for tone, hexc in zip(TONES, (light, mid, dark)):
            m = bpy.data.materials.new(f"{base}_{tone}" if tone else base)
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = srgb_to_lin(hexc)
            b.inputs["Roughness"].default_value = rough
            b.inputs["Metallic"].default_value = metal
            if base in GLOWS:
                b.inputs["Emission Color"].default_value = srgb_to_lin(hexc)
                b.inputs["Emission Strength"].default_value = GLOWS[base]
            mats.append(m)
    return mats


def _paint(faces, base):
    for f in faces:
        f.normal_update()
        nz = f.normal.z + _rng.uniform(-0.25, 0.25)
        tone = "Light" if nz > 0.45 else ("Dark" if nz < -0.35 else "")
        f.material_index = MAT[f"{base}_{tone}" if tone else base]


def _finish(verts, base, bevel=0.0):
    faces = list({f for v in verts for f in v.link_faces})
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    _paint(faces, base)
    if bevel > 0.0:
        edges = list({e for f in faces for e in f.edges})
        res = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
        _paint(res.get("faces", []), base)


def box(center, size, base, bevel=0.0, rot=None, top=None):
    """Брусок size (x, y, z); top — (x, y) верхней грани, если она уже или шире нижней."""
    res = bmesh.ops.create_cube(bm, size=1.0)
    if top:
        for v in res["verts"]:
            if v.co.z > 0:
                v.co.x *= top[0] / size[0]
                v.co.y *= top[1] / size[1]
    xf = Matrix.Translation(center) @ (rot.to_4x4() if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.transform(bm, matrix=xf, verts=res["verts"])
    _finish(res["verts"], base, bevel)


def _basis(d):
    z = Vector(d).normalized()
    x = z.cross(Vector((0, 0, 1)) if abs(z.z) < 0.9 else Vector((1, 0, 0))).normalized()
    return x, z.cross(x), z


def spike(a, b, radius, base, segments=5):
    """Конус от основания a (радиус radius) к острию b."""
    a, b = Vector(a), Vector(b)
    x, y, _ = _basis(b - a)
    ring = [bm.verts.new(a + (x * math.cos(t) + y * math.sin(t)) * radius)
            for t in (math.tau * k / segments for k in range(segments))]
    tip = bm.verts.new(b)
    bm.faces.new(list(reversed(ring)))
    for k in range(segments):
        bm.faces.new((ring[k], ring[(k + 1) % segments], tip))
    _finish(ring + [tip], base)


def bar(a, b, size, base, bevel=0.0, flare=1.0):
    """Брусок вдоль отрезка a→b с сечением size (w, h); flare — во сколько раз шире к концу b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    box((a + b) / 2, (size[0], size[1], d.length), base, bevel=bevel, rot=rot,
        top=(size[0] * flare, size[1] * flare) if flare != 1.0 else None)


# --- части ----------------------------------------------------------------------------------

def build_leg(s):
    # Бедро в тёмных штанах, наколенник, голень, сапог с носком вперёд
    box((0, 0, -0.2), (0.32, 0.34, 0.36), "Dark", bevel=0.02, top=(0.34, 0.36))
    box((0, 0.17, -0.42), (0.2, 0.06, 0.16), "Metal", bevel=0.015)
    box((0, 0, -0.42), (0.3, 0.32, 0.1), "Leather", bevel=0.01)
    box((0, 0.01, -0.58), (0.27, 0.29, 0.26), "Dark", bevel=0.02)
    box((0, 0.06, -0.73), (0.34, 0.46, 0.15), "Leather", bevel=0.02, top=(0.32, 0.4))
    box((0, 0.0, -0.64), (0.31, 0.33, 0.07), "Leather", bevel=0.01)


def build_hips():
    # Таз в штанах, широкий пояс, пряжка-череп, красная повязка спереди и сзади
    box((0, 0, 0.02), (0.74, 0.44, 0.26), "Dark", bevel=0.02, top=(0.76, 0.46))
    box((0, 0, 0.17), (0.82, 0.5, 0.12), "Leather", bevel=0.015)
    box((0, 0.26, 0.17), (0.22, 0.05, 0.18), "Bone", bevel=0.015)
    for x in (-0.05, 0.05):
        box((x, 0.29, 0.19), (0.05, 0.02, 0.05), "Mouth")
    box((0, 0.29, 0.12), (0.08, 0.02, 0.03), "Mouth")
    for y, sign in ((0.25, 1), (-0.25, -1)):
        box((0, y, -0.12), (0.36, 0.04, 0.36), "Red", bevel=0.01)
        for x, drop in ((-0.12, 0.1), (0.0, 0.16), (0.12, 0.08)):
            box((x, y + sign * 0.005, -0.3 - drop / 2), (0.11, 0.04, drop), "Red")


def build_torso():
    # Грудь намного шире живота, мощные плечи и трапеции — голова «утоплена» между ними
    box((0, 0.02, 0.3), (0.76, 0.5, 0.6), "Skin", bevel=0.03, top=(1.12, 0.62))
    for x in (-0.22, 0.22):
        box((x, 0.28, 0.42), (0.4, 0.1, 0.28), "Skin", bevel=0.03)
    for x in (-0.1, 0.1):
        box((x, 0.27, 0.14), (0.16, 0.06, 0.16), "Skin", bevel=0.02)
    box((0, -0.06, 0.62), (0.9, 0.5, 0.2), "Skin", bevel=0.04, top=(0.6, 0.4))
    # Ремень через грудь (с левого плеча к правому боку) — спереди и сзади
    for y in (0.32, -0.28):
        bar((-0.44, y, 0.62), (0.36, y, 0.02), (0.11, 0.04), "Leather", bevel=0.008)
    # Голова: вперёд и вниз (сутулый), выпирающая нижняя челюсть
    hy, hz = 0.27, 0.8
    box((0, hy, hz), (0.42, 0.38, 0.32), "Skin", bevel=0.03, top=(0.38, 0.34))
    box((0, hy + 0.12, hz - 0.14), (0.44, 0.26, 0.16), "Skin", bevel=0.025)
    box((0, hy + 0.25, hz - 0.1), (0.3, 0.03, 0.08), "Mouth")
    for x in (-0.14, 0.14):
        spike((x, hy + 0.23, hz - 0.12), (x * 1.1, hy + 0.27, hz + 0.05), 0.045, "Bone")
    for x in (-0.05, 0.05):
        spike((x, hy + 0.25, hz - 0.05), (x, hy + 0.26, hz - 0.1), 0.022, "Bone", segments=4)
    box((0, hy + 0.21, hz), (0.13, 0.1, 0.1), "Skin", bevel=0.02)
    box((0, hy + 0.18, hz + 0.09), (0.44, 0.08, 0.07), "Skin", bevel=0.015)
    for x in (-0.1, 0.1):
        rot = Matrix.Rotation(-0.35 if x < 0 else 0.35, 3, "Y")
        box((x, hy + 0.195, hz + 0.045), (0.09, 0.02, 0.045), "Eye", rot=rot)
    for s in (-1, 1):
        spike((s * 0.2, hy - 0.02, hz + 0.04), (s * 0.46, hy - 0.12, hz + 0.12), 0.065, "Skin")
    # Красный капюшон: козырёк над бровями, бока, спина и драпировка на плечи; шарф на шее
    box((0, hy - 0.02, hz + 0.2), (0.52, 0.46, 0.1), "Red", bevel=0.025, top=(0.46, 0.4))
    for s in (-1, 1):
        box((s * 0.245, hy - 0.04, hz + 0.04), (0.07, 0.38, 0.3), "Red", bevel=0.012)
    box((0, hy - 0.22, hz), (0.54, 0.12, 0.44), "Red", bevel=0.02)
    box((0, -0.08, 0.6), (0.7, 0.42, 0.14), "Red", bevel=0.025, top=(0.56, 0.36))
    spike((0, hy - 0.16, hz + 0.22), (0, hy - 0.42, hz + 0.24), 0.1, "Red")
    bar((0.1, 0.3, 0.6), (0.14, 0.34, 0.36), (0.13, 0.04), "Red")
    box((0.14, 0.345, 0.3), (0.13, 0.04, 0.1), "Red")
    # Левый наплечник — огромный, лиловый, с костяными шипами; правый — тёмный, поменьше
    tilt = Matrix.Rotation(0.42, 3, "Y")
    box((-0.74, 0.0, 0.62), (0.6, 0.68, 0.38), "Metal", bevel=0.04, rot=tilt, top=(0.52, 0.6))
    box((-0.72, 0.0, 0.42), (0.62, 0.7, 0.07), "Leather", rot=tilt)
    for a, b in (((-0.62, 0.16, 0.84), (-0.64, 0.2, 1.16)), ((-0.82, -0.16, 0.78), (-0.96, -0.2, 1.06)),
                 ((-0.98, 0.14, 0.58), (-1.26, 0.16, 0.68)), ((-0.92, -0.22, 0.48), (-1.18, -0.3, 0.46)),
                 ((-0.72, 0.36, 0.62), (-0.8, 0.6, 0.66))):
        spike(a, b, 0.085, "Bone")
    for p in ((-0.54, 0.3, 0.7), (-0.84, 0.3, 0.56), (-0.56, 0.3, 0.5), (-0.86, 0.3, 0.74)):
        box(p, (0.06, 0.04, 0.06), "Dark")
    tilt = Matrix.Rotation(-0.38, 3, "Y")
    box((0.64, 0.0, 0.6), (0.42, 0.5, 0.26), "Dark", bevel=0.03, rot=tilt, top=(0.36, 0.44))
    box((0.64, 0.26, 0.6), (0.3, 0.03, 0.06), "Metal", rot=tilt)
    spike((0.7, 0.08, 0.72), (0.8, 0.1, 0.96), 0.06, "Bone")
    spike((0.76, -0.12, 0.66), (0.92, -0.16, 0.86), 0.055, "Bone")


def build_arm(s):
    # Плечо, мощное предплечье в наруче, большой кулак (s: 1 — правая, -1 — левая); руки чуть в стороны
    box((s * 0.08, 0, -0.2), (0.34, 0.34, 0.46), "Skin", bevel=0.035, top=(0.38, 0.38))
    box((s * 0.14, 0.04, -0.56), (0.36, 0.36, 0.36), "Skin", bevel=0.035)
    box((s * 0.14, 0.04, -0.6), (0.42, 0.42, 0.26), "Leather", bevel=0.025)
    box((s * 0.14, 0.04, -0.5), (0.44, 0.44, 0.05), "Metal", bevel=0.01)
    box((s * 0.14, 0.04, -0.7), (0.44, 0.44, 0.04), "Metal", bevel=0.01)
    for k in range(3):
        box((s * (0.14 + 0.22), 0.04 - 0.12 + k * 0.12, -0.6), (0.03, 0.05, 0.05), "Bone")
    box((s * 0.15, 0.07, -0.88), (0.34, 0.34, 0.28), "Skin", bevel=0.035)
    box((s * 0.15, 0.21, -0.88), (0.3, 0.08, 0.16), "Skin", bevel=0.02)
    if s > 0:
        # Дубина: рукоять из кулака вперёд-вверх и чуть наружу, тёмная головка с шипами
        fist = Vector((s * 0.15, 0.07, -0.88))
        d = Vector((0.3, 0.6, 0.74)).normalized()
        bar(fist - d * 0.18, fist + d * 0.38, (0.1, 0.1), "Leather", bevel=0.01)
        box(fist - d * 0.2, (0.13, 0.13, 0.08), "Club", bevel=0.01)
        a, b = fist + d * 0.32, fist + d * 1.08
        bar(a, b, (0.26, 0.26), "Club", bevel=0.03, flare=1.3)
        x, y, _ = _basis(d)
        for t, along in ((0.0, 0.4), (1.6, 0.55), (3.1, 0.38), (4.7, 0.65), (0.8, 0.82), (2.4, 0.78),
                         (3.9, 0.88), (5.5, 0.5), (1.2, 0.25), (4.2, 0.22)):
            c = a + (b - a) * along
            out = x * math.cos(t) + y * math.sin(t)
            w = 0.13 + 0.05 * along
            spike(c + out * w, c + out * (w + 0.16), 0.045, "Bone", segments=4)
        spike(b, b + d * 0.14, 0.055, "Bone", segments=4)


# --- вожак: гоблин на волке ---------------------------------------------------------------

FRONT = (0.21, 0.46, 0.78)   # плечи волка (передние ноги)
BACK = (0.21, -0.5, 0.8)     # бёдра волка (задние ноги)


def build_wolf_leg(front):
    # Мощное плечо или бедро, тонкая голень, широкая лапа с когтями
    box((0, 0.02 if front else -0.04, -0.2), (0.19, 0.26, 0.42), "Fur", bevel=0.02, top=(0.22, 0.3))
    box((0, 0.04 if front else 0.02, -0.54), (0.14, 0.15, 0.34), "Fur", bevel=0.015)
    box((0, 0.1, -0.74), (0.2, 0.28, 0.09), "Fur", bevel=0.015)
    for x in (-0.06, 0.0, 0.06):
        spike((x, 0.22, -0.75), (x, 0.31, -0.78), 0.022, "Bone", segments=4)


def build_rider_body():
    # Волк: мощная грудь, поджарый зад, загривок с шипастой шерстью, хвост
    box((0, -0.05, 0.86), (0.5, 1.2, 0.46), "Fur", bevel=0.03, top=(0.46, 1.05))
    box((0, 0.48, 0.86), (0.6, 0.46, 0.6), "Fur", bevel=0.04, top=(0.56, 0.4))
    box((0, 0.66, 0.72), (0.4, 0.14, 0.36), "FurLight", bevel=0.03)
    box((0, 0.0, 0.64), (0.36, 0.9, 0.06), "FurLight", bevel=0.02)
    # Грива: пучки шерсти вокруг шеи
    for t in range(7):
        a = math.pi * (0.1 + 0.8 * t / 6)
        c = Vector((math.cos(a) * 0.3, 0.6, 0.95 + math.sin(a) * 0.3))
        spike(c, c + Vector((math.cos(a) * 0.12, -0.24, math.sin(a) * 0.12)), 0.1, "Fur", segments=4)
    for k in range(6):
        y = 0.55 - k * 0.18
        spike((0, y, 1.08 + 0.02 * (k < 2)), (0, y - 0.12, 1.24 - 0.02 * k), 0.07, "Fur", segments=4)
    bar((0, -0.62, 0.98), (0, -1.12, 0.7), (0.16, 0.16), "Fur", bevel=0.02, flare=1.5)
    # Шея и голова: морда вперёд, раскрытая пасть с клыками, красные глаза, уши назад
    bar((0, 0.62, 0.98), (0, 0.92, 1.12), (0.36, 0.34), "Fur", bevel=0.03)
    box((0, 1.02, 1.12), (0.36, 0.38, 0.32), "Fur", bevel=0.03)
    box((0, 1.3, 1.08), (0.22, 0.32, 0.16), "FurLight", bevel=0.02)
    box((0, 1.28, 0.96), (0.2, 0.28, 0.07), "Fur", bevel=0.015)
    box((0, 1.27, 1.01), (0.17, 0.24, 0.04), "Mouth")
    box((0, 1.47, 1.12), (0.09, 0.05, 0.06), "Dark")
    for x in (-0.07, 0.07):
        spike((x, 1.38, 1.01), (x, 1.39, 0.92), 0.025, "Bone", segments=4)
        spike((x, 1.36, 0.97), (x, 1.37, 1.06), 0.022, "Bone", segments=4)
    for x in (-0.11, 0.11):
        box((x, 1.17, 1.19), (0.07, 0.03, 0.04), "Ember")
        spike((x, 0.96, 1.26), (x * 1.5, 0.84, 1.48), 0.07, "Fur", segments=4)
    box((0, 1.12, 1.29), (0.24, 0.3, 0.04), "Metal", bevel=0.01)
    # Шипастый ошейник
    box((0, 0.7, 1.0), (0.46, 0.14, 0.46), "Leather", bevel=0.02)
    for t in range(5):
        a = math.pi * (0.15 + 0.175 * t)
        c = Vector((math.cos(a) * 0.24, 0.7, 1.0 + math.sin(a) * 0.24))
        spike(c, c + Vector((math.cos(a), 0, math.sin(a))) * 0.14, 0.035, "Bone", segments=4)
    # Седло на красной попоне
    box((0, -0.02, 1.1), (0.64, 0.62, 0.05), "Red", bevel=0.01)
    box((0, -0.02, 1.15), (0.44, 0.46, 0.09), "Leather", bevel=0.02)
    box((0, 0.2, 1.22), (0.3, 0.06, 0.12), "Leather", bevel=0.01)
    # Наездник: ноги по бокам, кожаная броня и кираса, наплечники
    for s_ in (-1, 1):
        box((s_ * 0.24, 0.05, 1.18), (0.13, 0.3, 0.13), "Dark", bevel=0.015)
        box((s_ * 0.3, 0.14, 1.0), (0.11, 0.12, 0.3), "Dark", bevel=0.015)
        box((s_ * 0.3, 0.2, 0.86), (0.13, 0.2, 0.08), "Leather", bevel=0.01)
    box((0, -0.06, 1.44), (0.4, 0.28, 0.44), "Leather", bevel=0.025, top=(0.46, 0.3))
    box((0, 0.09, 1.47), (0.32, 0.05, 0.3), "Metal", bevel=0.012)
    bar((-0.2, 0.09, 1.62), (0.18, 0.09, 1.3), (0.07, 0.03), "Red")
    for s_ in (-1, 1):
        box((s_ * 0.25, -0.06, 1.63), (0.16, 0.22, 0.1), "Metal", bevel=0.015)
        spike((s_ * 0.3, -0.06, 1.66), (s_ * 0.38, -0.08, 1.8), 0.04, "Bone", segments=4)
    # Голова гоблина: уши в стороны, жёлтые глаза, нос; рогатый шлем
    box((0, 0.0, 1.82), (0.27, 0.25, 0.25), "Skin", bevel=0.025)
    for s_ in (-1, 1):
        spike((s_ * 0.13, -0.01, 1.84), (s_ * 0.42, -0.08, 1.92), 0.055, "Skin")
        box((s_ * 0.06, 0.125, 1.84), (0.06, 0.02, 0.03), "Eye")
        spike((s_ * 0.13, 0.0, 1.98), (s_ * 0.3, 0.06, 2.2), 0.045, "Bone", segments=5)
    spike((0, 0.12, 1.8), (0, 0.24, 1.76), 0.035, "Skin", segments=4)
    box((0, -0.01, 1.96), (0.31, 0.29, 0.09), "Metal", bevel=0.02, top=(0.24, 0.22))
    box((0, 0.12, 1.92), (0.31, 0.04, 0.04), "Metal")
    # Руки: левая держит поводья, правая — занесённый тесак
    bar((-0.25, -0.04, 1.58), (-0.2, 0.26, 1.34), (0.1, 0.1), "Skin", bevel=0.015)
    bar((-0.2, 0.26, 1.34), (0.0, 0.62, 1.04), (0.02, 0.02), "Leather")
    bar((0.25, -0.04, 1.58), (0.38, 0.12, 1.86), (0.1, 0.1), "Skin", bevel=0.015)
    box((0.38, 0.12, 1.86), (0.12, 0.12, 0.11), "Skin", bevel=0.015)
    blade = Matrix.Rotation(-0.5, 3, "X")
    box((0.38, 0.16, 1.97), (0.06, 0.06, 0.12), "Leather", rot=blade)
    box((0.38, 0.27, 2.2), (0.03, 0.09, 0.4), "Steel", bevel=0.006, rot=blade, top=(0.025, 0.17))
    # Знамя за спиной: шест, перекладина, красное полотнище с черепом
    bar((0, -0.22, 1.28), (0, -0.26, 2.75), (0.05, 0.05), "Wood", bevel=0.008)
    bar((0, -0.26, 2.66), (0, -0.82, 2.66), (0.04, 0.04), "Wood")
    box((0, -0.55, 2.3), (0.03, 0.54, 0.66), "Red", bevel=0.005)
    for k, y in enumerate((-0.4, -0.55, -0.7)):
        box((0, y, 1.92 - 0.06 * (k % 2)), (0.03, 0.12, 0.14), "Red")
    box((0.025, -0.55, 2.34), (0.02, 0.2, 0.18), "Bone")
    for y in (-0.6, -0.5):
        box((0.04, y, 2.36), (0.01, 0.05, 0.05), "Mouth")
    spike((0, -0.26, 2.75), (0, -0.26, 2.92), 0.04, "Bone", segments=4)


# --- сборка ---------------------------------------------------------------------------------

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


def export_model(file_name, root_name, parts, offset_x):
    """Собрать модель из частей (имя, родитель, шарнир, построитель), выгрузить в GLB и
    отодвинуть по X (для превью рядом)."""
    global bm
    root = bpy.data.objects.new(root_name, None)
    scene.collection.objects.link(root)
    objs = {None: root}
    made = [root]
    tris = 0
    for name, parent, loc, build in parts:
        bm = bmesh.new()
        build()
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        tris += len(bm.faces)
        obj = bpy.data.objects.new(name, new_mesh(f"{root_name}_{name}", mats))
        bm.free()
        scene.collection.objects.link(obj)
        obj.parent = objs[parent]
        obj.location = loc
        objs[name] = obj
        made.append(obj)
    for o in bpy.data.objects:
        o.select_set(o in made)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, file_name), export_format="GLB", use_selection=True)
    root.location.x = offset_x
    # Имена в .blend уникальны: части следующей модели называются так же
    for o in made[1:]:
        o.name = f"{root_name}_{o.name}"
    print("BUILT", file_name, "triangles:", tris)


bpy.ops.wm.read_homefile(use_empty=True)
mats = make_materials()
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)
scene = bpy.context.scene
export_model("goblin_chief.glb", "GoblinChief", [
    ("LegL", None, (-0.2, 0, HIP), lambda: build_leg(-1)),
    ("LegR", None, (0.2, 0, HIP), lambda: build_leg(1)),
    ("Hips", None, (0, 0, HIP), build_hips),
    ("Torso", "Hips", (0, 0, WAIST), build_torso),
    ("ArmL", "Torso", (-SHOULDER[0], SHOULDER[1], SHOULDER[2]), lambda: build_arm(-1)),
    ("ArmR", "Torso", SHOULDER, lambda: build_arm(1)),
], 0.0)
RX = 4.0   # где в превью стоит вожак
export_model("goblin_rider.glb", "GoblinRider", [
    ("Body", None, (0, 0, 0), build_rider_body),
    ("LegFL", None, (-FRONT[0], FRONT[1], FRONT[2]), lambda: build_wolf_leg(True)),
    ("LegFR", None, FRONT, lambda: build_wolf_leg(True)),
    ("LegBL", None, (-BACK[0], BACK[1], BACK[2]), lambda: build_wolf_leg(False)),
    ("LegBR", None, BACK, lambda: build_wolf_leg(False)),
], RX)

# Превью: вождь — спереди, сбоку, сзади, три четверти и голова; вожак — три четверти и сбоку
world = bpy.data.worlds.new("W")
world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb_to_lin("8E8E94")
scene.world = world
scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
for name, energy, rot in (("Key", 2.8, (50, 15, -40)), ("Fill", 1.0, (60, 0, 150))):
    light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    light.data.energy = energy
    light.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(light)
for view, loc, target, lens in (("chief_three_quarter", (2.6, 4.2, 2.0), (0, 0, 1.05), 40),
                                ("chief_front", (0, 5.2, 1.3), (0, 0, 1.05), 40),
                                ("chief_side", (5.2, 0.2, 1.3), (0, 0, 1.05), 40),
                                ("chief_back", (-1.8, -4.8, 1.8), (0, 0, 1.05), 40),
                                ("chief_head", (0.8, 1.9, 1.95), (0, 0.25, 1.8), 50),
                                ("rider_three_quarter", (RX + 3.0, 4.4, 2.3), (RX, 0.0, 1.3), 40),
                                ("rider_side", (RX + 5.6, 0.0, 1.5), (RX, 0.0, 1.3), 40),
                                ("rider_front", (RX + 0.4, 5.4, 1.6), (RX, 0.0, 1.3), 40)):
    cam = bpy.data.objects.new("Cam_" + view, bpy.data.cameras.new("Cam_" + view))
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    look_at(cam, loc, target)
    scene.camera = cam
    scene.render.filepath = os.path.join(PREVIEW_DIR, f"{view}.png")
    bpy.ops.render.render(write_still=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
