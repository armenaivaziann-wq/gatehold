"""Турели: пулемёт, мортира, жаровня, лазер — стилизованный low-poly в стиле мушкетона и огнемёта.
Лазер — по референсу art_src/turrets/ref_laser.webp: тёмный стальной корпус со светло-серой бронёй,
красные светящиеся полосы, по бокам восьмигранные барабаны-цапфы, сверху дуга-ручка, спереди
толстый восьмигранный излучатель с раскалённой красной линзой.

У мортиры и жаровни — каменный восьмигранный постамент с деревянным поворотным кругом,
у пулемёта — свой стальной постамент-ступень с оранжевыми накладками (по референсу
art_src/turrets/ref_gatling.webp). Объект Base стоит на месте; Head в игре поворачивается к
цели вокруг вертикали (начало координат — ось поворота). У пулемёта в Head ещё Gun — качается
вверх-вниз на цапфах, а в Gun — Barrels, блок из шести стволов, крутится при стрельбе.
Пустышка Muzzle — откуда вылетает снаряд или бьёт огонь. Тон каждой грани зависит от того, куда она смотрит (верх светлее,
низ темнее) — как рисованные текстуры.

Оси Blender: +Y — вперёд (в Godot — -Z), +Z — вверх. Высота турели около 2.3 м.
Запуск: Blender -b --factory-startup --python art_src/turrets/build_turrets.py
Пишет turrets/models/<имя>.glb, art_src/turrets/turrets.blend и превью в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_DIR = os.path.join(PROJECT, "turrets/models")
OUT_BLEND = os.path.join(PROJECT, "art_src/turrets/turrets.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "turrets")

PALETTE = {
    "Stone": ("D2BE9C", "B9A384", "8F7B60", 0.9, 0.0),
    "Wood": ("A85A32", "8A4526", "68321B", 0.8, 0.0),
    "Iron": ("6E6E74", "4E4E54", "38383D", 0.55, 0.7),
    "Brass": ("F0C366", "D9A441", "A87A2E", 0.4, 0.35),
    "Rope": ("E8D6AE", "D6C08F", "B39E70", 0.95, 0.0),
    "Glow": ("FFB347", "FF8C2E", "F06A1E", 0.4, 0.0),
    "Gunmetal": ("57545A", "403E43", "2C2A2E", 0.6, 0.5),
    "Orange": ("FFB04A", "F0952E", "C2701E", 0.55, 0.1),
    "Bore": ("1A1A1A", "121212", "0A0A0A", 1.0, 0.0),
    "Plate": ("D2D0D4", "B3B1B6", "8C8A90", 0.5, 0.3),
    "Red": ("FF5A50", "FF2A2A", "D81818", 0.4, 0.0),
    "Lens": ("FFF0EC", "FFD6D0", "FFB0A8", 0.2, 0.0),
}
GLOWS = {"Glow": 1.5, "Red": 3.0, "Lens": 6.0}
TONES = ("Light", "", "Dark")
MAT_NAMES = [f"{b}_{t}" if t else b for b in PALETTE for t in TONES]
MAT = {name: i for i, name in enumerate(MAT_NAMES)}
PIVOT = 0.66          # высота оси поворота головы (верх поворотного круга)

_rng = random.Random(9)
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


def box(center, size, base, bevel=0.0, rot=None):
    res = bmesh.ops.create_cube(bm, size=1.0)
    xf = Matrix.Translation(center) @ (rot.to_4x4() if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.transform(bm, matrix=xf, verts=res["verts"])
    _finish(res["verts"], base, bevel)


def lathe(profile, base, segments=8, axis="Z", center=(0.0, 0.0, 0.0), rot=None, bevel=0.0):
    """Тело вращения: profile — (вдоль оси, радиус). axis Z — вертикальное, Y — вперёд."""
    rings = []
    for h, r in profile:
        ring = []
        count = 1 if r <= 0.0 else segments
        for k in range(count):
            a = math.tau * (k + 0.5) / segments
            if axis == "Z":
                p = Vector((r * math.cos(a), r * math.sin(a), h))
            else:
                p = Vector((r * math.cos(a), h, r * math.sin(a)))
            if rot:
                p = rot @ p
            ring.append(bm.verts.new(Vector(center) + p))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segments):
            k2 = (k + 1) % segments
            if len(r0) == 1:
                bm.faces.new((r0[0], r1[k2], r1[k]))
            elif len(r1) == 1:
                bm.faces.new((r0[k], r0[k2], r1[0]))
            else:
                bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
    _finish([v for r in rings for v in r], base, bevel)


def strip(points, width, thick, base, bevel=0.004):
    """Брусок по ломаной (точки x, y, z), сечение width × thick."""
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        d = b - a
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix()
        box((a + b) / 2, (thick, d.length + width * 0.6, width), base, bevel=bevel, rot=rot)


def rivet(pos, normal, radius=0.025, base="Iron"):
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    z = Vector(normal).normalized()
    x = z.cross(Vector((0, 1, 0)) if abs(z.y) < 0.9 else Vector((1, 0, 0))).normalized()
    basis = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(pos) @ basis @ Matrix.Diagonal((1, 1, 0.6, 1)), verts=res["verts"])
    _finish(res["verts"], base)


# --- постамент (общий) ----------------------------------------------------------------------

def build_base():
    # Каменный восьмигранник: шире внизу, с карнизом
    lathe([(0.0, 0.0), (0.0, 0.92), (0.08, 0.92), (0.12, 0.84), (0.44, 0.78), (0.48, 0.86), (0.54, 0.86), (0.54, 0.0)],
          "Stone", segments=8, bevel=0.012)
    # Кладка: тёмные швы-пояса на боках
    lathe([(0.27, 0.0), (0.27, 0.815), (0.29, 0.815), (0.29, 0.0)], "Stone", segments=8)
    # Деревянный поворотный круг с железным ободом
    lathe([(0.54, 0.0), (0.54, 0.62), (PIVOT, 0.62), (PIVOT, 0.0)], "Wood", segments=12, bevel=0.01)
    lathe([(0.55, 0.0), (0.55, 0.645), (0.6, 0.645), (0.6, 0.0)], "Iron", segments=12)
    for k in range(8):
        a = math.tau * (k + 0.5) / 8
        rivet(Vector((math.cos(a) * 0.645, math.sin(a) * 0.645, 0.575)), (math.cos(a), math.sin(a), 0))


# --- головы (координаты от оси поворота) ----------------------------------------------------

# --- пулемёт ---------------------------------------------------------------------------------

METAL_PIVOT = 0.6     # верх стального постамента
GUN_HINGE = 0.86      # высота цапф от оси поворота
BARREL_START = 0.42   # начало блока стволов от цапф


def build_metal_base():
    """Стальной постамент: широкая восьмигранная ступень со скатами, оранжевый пояс и накладки
    на скатах, заклёпки, четыре опоры по диагоналям."""
    lathe([(0.0, 0.0), (0.0, 0.98), (0.1, 0.98), (0.36, 0.8), (0.42, 0.8), (0.5, 0.64), (METAL_PIVOT, 0.62),
           (METAL_PIVOT, 0.0)], "Gunmetal", segments=8, bevel=0.012)
    lathe([(0.4, 0.0), (0.4, 0.82), (0.47, 0.82), (0.47, 0.0)], "Orange", segments=8)
    slope = math.atan2(0.98 - 0.8, 0.36 - 0.1)
    for k in range(8):
        a = math.tau * (k + 0.5) / 8
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rot = Matrix.Rotation(a - math.pi / 2, 3, "Z") @ Matrix.Rotation(slope, 3, "X")
        if k % 2 == 0:
            box(out * 0.885 + Vector((0, 0, 0.23)), (0.36, 0.05, 0.2), "Orange", bevel=0.008, rot=rot)
        rivet(out * 0.81 + Vector((0, 0, 0.44)), out, 0.022)
    for k in range(4):
        a = math.tau * k / 4 + math.pi / 4
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rot = Matrix.Rotation(a - math.pi / 2, 3, "Z")
        box(out * 0.98 + Vector((0, 0, 0.12)), (0.3, 0.32, 0.24), "Gunmetal", bevel=0.02, rot=rot)
        box(out * 1.05 + Vector((0, 0, 0.25)), (0.22, 0.12, 0.04), "Orange", bevel=0.006, rot=rot)


def build_gatling_head():
    """Поворотная часть: восьмигранная колонна с воротником и вилка с двумя щеками и цапфами."""
    lathe([(0.0, 0.0), (0.0, 0.34), (0.08, 0.34), (0.1, 0.28), (0.46, 0.28), (0.46, 0.0)], "Gunmetal",
          segments=8, bevel=0.008)
    box((0, 0.0, 0.5), (0.92, 0.42, 0.14), "Gunmetal", bevel=0.02)
    for s in (-1.0, 1.0):
        box((s * 0.4, 0.0, 0.72), (0.13, 0.36, 0.42), "Gunmetal", bevel=0.02)
        box((s * 0.47, 0.0, 0.72), (0.03, 0.24, 0.26), "Orange", bevel=0.006)
        lathe([(0.0, 0.0), (0.0, 0.09), (0.16, 0.09), (0.16, 0.0)], "Iron", segments=8,
              axis="Y", center=(s * 0.38, 0.0, GUN_HINGE), rot=Matrix.Rotation(-s * math.pi / 2, 3, "Z"))


def build_gatling_gun():
    """Качающаяся часть: короб затвора с ручкой, оранжевые пояса, боковые барабаны, задняя
    восьмигранная крышка, передняя обойма; справа — патронный ящик и лента из него в короб."""
    box((0, -0.06, 0.02), (0.52, 0.74, 0.42), "Gunmetal", bevel=0.03)
    for y in (0.16, -0.24):
        box((0, y, 0.02), (0.56, 0.09, 0.46), "Orange", bevel=0.012)
    lathe([(-0.52, 0.0), (-0.52, 0.2), (-0.46, 0.27), (-0.36, 0.27), (-0.36, 0.0)], "Gunmetal", axis="Y", bevel=0.01)
    lathe([(-0.47, 0.0), (-0.47, 0.275), (-0.41, 0.275), (-0.41, 0.0)], "Orange", axis="Y")
    lathe([(0.3, 0.0), (0.3, 0.23), (BARREL_START, 0.21), (BARREL_START, 0.0)], "Gunmetal", axis="Y", bevel=0.008)
    strip([(0, -0.24, 0.22), (0, -0.24, 0.38), (0, 0.12, 0.38), (0, 0.12, 0.22)], 0.07, 0.08, "Gunmetal", bevel=0.01)
    for s in (-1.0, 1.0):
        lathe([(0.0, 0.0), (0.0, 0.17), (0.12, 0.17), (0.12, 0.0)], "Gunmetal", axis="Y",
              center=(s * 0.27, -0.08, 0.0), rot=Matrix.Rotation(-s * math.pi / 2, 3, "Z"), bevel=0.008)
        lathe([(0.02, 0.0), (0.02, 0.18), (0.07, 0.18), (0.07, 0.0)], "Orange", axis="Y",
              center=(s * 0.27, -0.08, 0.0), rot=Matrix.Rotation(-s * math.pi / 2, 3, "Z"))
    # Патронный ящик справа и лента в короб
    box((0.5, -0.22, -0.3), (0.34, 0.4, 0.36), "Gunmetal", bevel=0.025)
    box((0.67, -0.22, -0.3), (0.02, 0.26, 0.22), "Orange", bevel=0.005)
    for y in (-0.36, -0.08):
        for z in (-0.42, -0.18):
            rivet(Vector((0.675, y, z)), (1, 0, 0), 0.02)
    belt = [Vector((0.45, -0.14, -0.1)), Vector((0.42, -0.06, 0.0)), Vector((0.36, 0.0, 0.06)), Vector((0.28, 0.02, 0.08))]
    for a, b in zip(belt, belt[1:]):
        for t in (0.0, 0.5):
            p = a.lerp(b, t)
            d = (b - a).normalized()
            rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix()
            box(p, (0.12, 0.05, 0.05), "Brass", bevel=0.004, rot=rot)
            box(p + Vector((0, 0, 0.0)), (0.06, 0.055, 0.055), "Gunmetal", rot=rot)


def build_gatling_barrels():
    """Блок из шести стволов вокруг центрального стержня, два оранжевых пояса, передняя пластина."""
    lathe([(0.0, 0.0), (0.0, 0.05), (0.98, 0.05), (0.98, 0.0)], "Iron", axis="Y", segments=6)
    for k in range(6):
        a = math.tau * k / 6
        c = Vector((math.cos(a) * 0.11, 0.0, math.sin(a) * 0.11))
        lathe([(0.0, 0.0), (0.0, 0.048), (1.0, 0.048), (1.0, 0.0)], "Gunmetal", axis="Y", segments=8, center=c)
        lathe([(1.001, 0.0), (1.001, 0.026), (1.002, 0.026), (1.002, 0.0)], "Bore", axis="Y", segments=6, center=c)
    for y0, y1 in ((0.26, 0.36), (0.8, 0.9)):
        lathe([(y0, 0.0), (y0, 0.185), (y1, 0.185), (y1, 0.0)], "Orange", axis="Y", segments=8, bevel=0.008)
    lathe([(0.55, 0.0), (0.55, 0.17), (0.58, 0.17), (0.58, 0.0)], "Gunmetal", axis="Y", segments=8)
    return Vector((0, 1.0, 0))


def build_mortar():
    """Приземистая железная мортира на деревянном лафете, ствол задран вверх."""
    # Лафет: две боковые щеки и днище
    for s in (-1.0, 1.0):
        pts = [(s * 0.27, -0.4, 0.05), (s * 0.27, 0.4, 0.05), (s * 0.27, 0.25, 0.42), (s * 0.27, -0.15, 0.42)]
        a = [bm.verts.new((s * 0.22, y, z)) for _, y, z in pts]
        b = [bm.verts.new((s * 0.33, y, z)) for _, y, z in pts]
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
        _finish(a + b, "Wood", bevel=0.015)
        rivet(Vector((s * 0.335, 0.05, 0.3)), (s, 0, 0), 0.035)
        rivet(Vector((s * 0.335, -0.2, 0.2)), (s, 0, 0), 0.03)
    box((0, 0.0, 0.06), (0.56, 0.8, 0.1), "Wood", bevel=0.012)
    # Ствол под углом 50°: толстый, с кольцами и раструбом
    tilt = Matrix.Rotation(math.radians(50), 3, "X")
    c = Vector((0, 0.02, 0.36))
    lathe([(-0.32, 0.0), (-0.32, 0.2), (-0.25, 0.27), (0.25, 0.25), (0.42, 0.24), (0.47, 0.29), (0.55, 0.29),
           (0.55, 0.0)], "Iron", segments=10, axis="Y", center=c, rot=tilt, bevel=0.008)
    lathe([(0.551, 0.0), (0.551, 0.19), (0.552, 0.19), (0.552, 0.0)], "Bore", segments=10, axis="Y", center=c, rot=tilt)
    for h in (-0.1, 0.18):
        lathe([(h - 0.035, 0.0), (h - 0.035, 0.275), (h + 0.035, 0.275), (h + 0.035, 0.0)], "Brass", segments=10,
              axis="Y", center=c, rot=tilt)
    # Цапфы — ось, на которой лежит ствол
    lathe([(0.0, 0.0), (0.0, 0.07), (0.2, 0.07), (0.2, 0.0)], "Iron", segments=8, axis="Y",
          center=(-0.34, 0.02, 0.36), rot=Matrix.Rotation(-math.pi / 2, 3, "Z"))
    lathe([(0.0, 0.0), (0.0, 0.07), (0.2, 0.07), (0.2, 0.0)], "Iron", segments=8, axis="Y",
          center=(0.34, 0.02, 0.36), rot=Matrix.Rotation(math.pi / 2, 3, "Z"))
    # Ядра рядом
    for x, y in ((0.18, -0.3), (-0.16, -0.32)):
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.08)
        bmesh.ops.transform(bm, matrix=Matrix.Translation((x, y, 0.19)), verts=res["verts"])
        _finish(res["verts"], "Iron")
    return c + tilt @ Vector((0, 0.56, 0))


def build_brazier():
    """Огненная жаровня: латунный бак на опоре, сверху клетка с горящим ядром,
    вперёд смотрит сопло, от бака к соплу — трубка."""
    lathe([(0.0, 0.0), (0.0, 0.16), (0.3, 0.12), (0.3, 0.0)], "Iron", segments=8)            # опора
    lathe([(0.3, 0.0), (0.3, 0.2), (0.34, 0.26), (0.78, 0.26), (0.84, 0.2), (0.84, 0.0)], "Brass", segments=10,
          bevel=0.008)                                                                      # бак
    for h in (0.42, 0.66):
        lathe([(h - 0.03, 0.25), (h - 0.03, 0.28), (h + 0.03, 0.28), (h + 0.03, 0.25)], "Iron", segments=10)
    # Клетка с огнём сверху
    lathe([(0.84, 0.0), (0.84, 0.17), (0.9, 0.17), (0.9, 0.0)], "Iron", segments=8)
    lathe([(0.9, 0.0), (0.9, 0.13), (1.12, 0.15), (1.2, 0.08), (1.24, 0.0)], "Glow", segments=8)
    for k in range(6):
        a = math.tau * (k + 0.5) / 6
        strip([(math.cos(a) * 0.17, math.sin(a) * 0.17, 0.88), (math.cos(a) * 0.19, math.sin(a) * 0.19, 1.2),
               (math.cos(a) * 0.05, math.sin(a) * 0.05, 1.32)], 0.04, 0.04, "Iron", bevel=0.005)
    # Сопло вперёд и трубка
    lathe([(0.0, 0.0), (0.0, 0.09), (0.55, 0.07), (0.62, 0.1), (0.68, 0.1), (0.68, 0.0)], "Iron", segments=8,
          axis="Y", center=(0, 0.2, 0.55), bevel=0.006)
    lathe([(0.681, 0.0), (0.681, 0.06), (0.682, 0.06), (0.682, 0.0)], "Bore", segments=8, axis="Y", center=(0, 0.2, 0.55))
    strip([(0.0, 0.0, 1.0), (0.0, 0.35, 0.98), (0.0, 0.5, 0.62)], 0.05, 0.05, "Iron", bevel=0.005)
    for s in (-1.0, 1.0):
        rivet(Vector((s * 0.3, 0.0, 0.54)), (s, 0, 0), 0.03, "Iron")
    return Vector((0, 0.9, 0.55))


# --- лазер ----------------------------------------------------------------------------------

LASER_PIVOT = 0.58    # верх постамента лазера
LASER_HINGE = 0.78    # высота цапф корпуса от оси поворота


def build_laser_base():
    """Тёмный восьмигранный постамент-ступень, на скатах — светлая броня и красные полосы,
    по диагоналям — четыре массивные опоры."""
    lathe([(0.0, 0.0), (0.0, 0.96), (0.12, 0.96), (0.34, 0.78), (0.4, 0.78), (0.48, 0.6), (LASER_PIVOT, 0.56),
           (LASER_PIVOT, 0.0)], "Gunmetal", segments=8, bevel=0.012)
    lathe([(0.38, 0.0), (0.38, 0.8), (0.42, 0.8), (0.42, 0.0)], "Red", segments=8)
    slope = math.atan2(0.96 - 0.78, 0.34 - 0.12)
    for k in range(8):
        a = math.tau * (k + 0.5) / 8
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rot = Matrix.Rotation(a - math.pi / 2, 3, "Z") @ Matrix.Rotation(slope, 3, "X")
        if k % 2 == 0:
            box(out * 0.875 + Vector((0, 0, 0.23)), (0.38, 0.06, 0.22), "Plate", bevel=0.01, rot=rot)
        else:
            box(out * 0.9 + Vector((0, 0, 0.21)), (0.3, 0.03, 0.08), "Red", rot=rot)
    for k in range(4):
        a = math.tau * k / 4 + math.pi / 4
        out = Vector((math.cos(a), math.sin(a), 0.0))
        rot = Matrix.Rotation(a - math.pi / 2, 3, "Z")
        box(out * 0.98 + Vector((0, 0, 0.13)), (0.32, 0.34, 0.26), "Gunmetal", bevel=0.025, rot=rot)
        box(out * 1.0 + Vector((0, 0, 0.27)), (0.26, 0.26, 0.04), "Plate", bevel=0.008, rot=rot)


def build_laser_head():
    """Поворотная часть: восьмигранная шея с воротником и вилка — две щеки с красными полосами."""
    lathe([(0.0, 0.0), (0.0, 0.3), (0.06, 0.3), (0.08, 0.24), (0.38, 0.24), (0.38, 0.0)], "Gunmetal",
          segments=8, bevel=0.008)
    lathe([(0.12, 0.0), (0.12, 0.25), (0.16, 0.25), (0.16, 0.0)], "Red", segments=8)
    box((0, 0.0, 0.43), (0.86, 0.4, 0.12), "Gunmetal", bevel=0.02)
    for s in (-1.0, 1.0):
        box((s * 0.38, 0.0, 0.62), (0.12, 0.34, 0.36), "Gunmetal", bevel=0.02)
        box((s * 0.445, 0.0, 0.62), (0.02, 0.06, 0.24), "Red")


def _side_drum(x, y, z, r, thick):
    """Восьмигранный барабан на боку (ось — X): светлая броня, красное кольцо, тёмный центр."""
    s = 1.0 if x > 0 else -1.0
    rot = Matrix.Rotation(-s * math.pi / 2, 3, "Z")
    lathe([(0.0, 0.0), (0.0, r), (thick, r), (thick, 0.0)], "Plate", segments=8, axis="Y",
          center=(x, y, z), rot=rot, bevel=0.012)
    lathe([(thick + 0.001, r * 0.62), (thick + 0.001, r * 0.78), (thick + 0.012, r * 0.78), (thick + 0.012, r * 0.62)],
          "Red", segments=8, axis="Y", center=(x, y, z), rot=rot)
    lathe([(thick, 0.0), (thick, r * 0.55), (thick + 0.02, r * 0.5), (thick + 0.02, 0.0)], "Gunmetal",
          segments=8, axis="Y", center=(x, y, z), rot=rot)


def build_laser_gun():
    """Корпус на цапфах: тёмный короб со светлой бронёй, красные шевроны и полосы, боковые
    барабаны, сверху дуга-ручка с красной вставкой, сзади восьмигранная крышка; спереди —
    восьмигранный ствол, обойма и излучатель с раскалённой линзой."""
    box((0, -0.08, 0.0), (0.5, 0.86, 0.44), "Gunmetal", bevel=0.035)
    # Светлая броня: верхняя плита и боковые щитки
    box((0, -0.02, 0.24), (0.42, 0.62, 0.06), "Plate", bevel=0.02)
    for s in (-1.0, 1.0):
        box((s * 0.26, 0.04, 0.04), (0.04, 0.5, 0.3), "Plate", bevel=0.015)
        box((s * 0.285, 0.2, 0.1), (0.012, 0.04, 0.14), "Red", rot=Matrix.Rotation(0.5, 3, "X"))
        for k in range(2):
            box((s * 0.285, -0.08 - k * 0.07, -0.06), (0.012, 0.035, 0.12), "Gunmetal",
                rot=Matrix.Rotation(0.6, 3, "X"))
        # Барабаны-цапфы — снаружи щёк вилки, на оси качания
        _side_drum(s * 0.44, 0.0, 0.0, 0.25, 0.1)
    # Красные полосы по верху и шеврон
    box((0, 0.2, 0.275), (0.3, 0.05, 0.012), "Red")
    for d in (-1.0, 1.0):
        box((d * 0.08, 0.3, 0.275), (0.16, 0.035, 0.012), "Red", rot=Matrix.Rotation(-d * 0.6, 3, "Z"))
    # Дуга-ручка сверху с красной вставкой
    strip([(0, -0.44, 0.18), (0, -0.44, 0.44), (0, -0.05, 0.5), (0, 0.12, 0.3)], 0.07, 0.1, "Gunmetal", bevel=0.012)
    strip([(0.052, -0.42, 0.3), (0.052, -0.36, 0.43), (0.052, -0.08, 0.47)], 0.03, 0.01, "Red", bevel=0.0)
    strip([(-0.052, -0.42, 0.3), (-0.052, -0.36, 0.43), (-0.052, -0.08, 0.47)], 0.03, 0.01, "Red", bevel=0.0)
    # Задняя восьмигранная крышка с красным кольцом
    lathe([(-0.56, 0.0), (-0.56, 0.18), (-0.5, 0.22), (-0.44, 0.22), (-0.44, 0.0)], "Gunmetal", axis="Y", bevel=0.01)
    lathe([(-0.561, 0.1), (-0.561, 0.14), (-0.562, 0.14), (-0.562, 0.1)], "Red", axis="Y")
    # Ствол, обойма, излучатель
    lathe([(0.3, 0.0), (0.3, 0.17), (0.86, 0.17), (0.86, 0.0)], "Gunmetal", axis="Y", segments=8, bevel=0.008)
    lathe([(0.46, 0.0), (0.46, 0.2), (0.62, 0.2), (0.62, 0.0)], "Plate", axis="Y", segments=8, bevel=0.012)
    lathe([(0.5, 0.199), (0.5, 0.205), (0.58, 0.205), (0.58, 0.199)], "Red", axis="Y", segments=8)
    lathe([(0.84, 0.0), (0.84, 0.25), (1.06, 0.25), (1.08, 0.2), (1.08, 0.0)], "Gunmetal", axis="Y", segments=8,
          bevel=0.012)
    lathe([(0.88, 0.0), (0.88, 0.262), (0.94, 0.262), (0.94, 0.0)], "Plate", axis="Y", segments=8, bevel=0.008)
    lathe([(1.081, 0.0), (1.081, 0.17), (1.09, 0.16), (1.09, 0.0)], "Red", axis="Y", segments=12)
    lathe([(1.09, 0.0), (1.09, 0.1), (1.11, 0.08), (1.12, 0.0)], "Lens", axis="Y", segments=12)
    return Vector((0, 1.14, 0))


# Турель: постамент, высота оси поворота и части [имя, родитель, положение в родителе, построение].
# Построение заполняет меш в осях своей части; если возвращает точку — там пустышка Muzzle.
TURRETS = {
    "gatling": {"base": build_metal_base, "parts": [
        ("Head", None, (0, 0, METAL_PIVOT), build_gatling_head),
        ("Gun", "Head", (0, 0, GUN_HINGE), build_gatling_gun),
        ("Barrels", "Gun", (0, BARREL_START, 0), build_gatling_barrels)]},
    "mortar": {"base": build_base, "parts": [("Head", None, (0, 0, PIVOT), build_mortar)]},
    "brazier": {"base": build_base, "parts": [("Head", None, (0, 0, PIVOT), build_brazier)]},
    "laser": {"base": build_laser_base, "parts": [
        ("Head", None, (0, 0, LASER_PIVOT), build_laser_head),
        ("Gun", "Head", (0, 0, LASER_HINGE), build_laser_gun)]},
}


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


bpy.ops.wm.read_homefile(use_empty=True)
mats = make_materials()
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)
scene = bpy.context.scene
built = {}
for k, (name, spec) in enumerate(TURRETS.items()):
    coll = bpy.data.collections.new(name)
    scene.collection.children.link(coll)
    root = bpy.data.objects.new(name.capitalize(), None)
    coll.objects.link(root)
    bm = bmesh.new()
    spec["base"]()
    base = bpy.data.objects.new("Base", new_mesh(name + "_Base", mats))
    bm.free()
    coll.objects.link(base)
    base.parent = root
    objs = {"": root}
    made = [base]
    for part, parent, loc, build in spec["parts"]:
        bm = bmesh.new()
        muzzle_at = build()
        obj = bpy.data.objects.new(part, new_mesh(f"{name}_{part}", mats))
        bm.free()
        coll.objects.link(obj)
        obj.parent = objs[parent or ""]
        obj.location = loc
        objs[part] = obj
        made.append(obj)
        if muzzle_at is not None:
            muzzle = bpy.data.objects.new("Muzzle", None)
            coll.objects.link(muzzle)
            # Дуло не крутится вместе со стволами — вешаем на родителя блока стволов
            holder = objs[parent] if part == "Barrels" else obj
            muzzle.parent = holder
            muzzle.location = Vector(loc) + muzzle_at if part == "Barrels" else muzzle_at
            made.append(muzzle)
    # Экспорт: только эта турель
    for o in bpy.data.objects:
        o.select_set(o in made or o == root)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB", use_selection=True)
    root.location.x = (k - 1) * 2.8
    # Имена объектов в .blend уникальны: убрать «Head», «Base»... с дороги следующей турели
    for o in made:
        o.name = f"{name}_{o.name}"
    built[name] = sum(len(p.vertices) - 2 for o in made if o.type == "MESH" for p in o.data.polygons)

# Превью: все три в ряд
world = bpy.data.worlds.new("W")
world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb_to_lin("C9C9CB")
scene.world = world
scene.render.engine = "BLENDER_EEVEE"
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 1500
scene.render.resolution_y = 750
for name, energy, rot in (("Key", 2.6, (50, 15, -60)), ("Fill", 1.0, (60, 0, 130))):
    light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    light.data.energy = energy
    light.rotation_euler = tuple(math.radians(a) for a in rot)
    scene.collection.objects.link(light)
GX = -2.8   # где в превью стоит пулемёт
LX = 5.6    # где в превью стоит лазер
for view, loc, target, lens in (("front", (3.2, 5.6, 2.8), (0, 0, 0.8), 38),
                                ("back", (-3.6, -5.2, 3.2), (0, 0, 0.8), 38),
                                ("gatling", (GX + 2.4, 3.0, 1.9), (GX, 0.2, 1.0), 45),
                                ("gatling_side", (GX - 3.4, 0.4, 1.4), (GX, 0.3, 1.0), 45),
                                ("laser", (LX + 2.6, 3.2, 2.2), (LX, 0.2, 1.1), 45),
                                ("laser_side", (LX + 3.8, -0.2, 1.4), (LX, 0.2, 1.1), 45),
                                ("laser_front", (LX + 0.3, 4.0, 1.6), (LX, 0.0, 1.2), 45)):
    cam = bpy.data.objects.new("Cam_" + view, bpy.data.cameras.new("Cam_" + view))
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    look_at(cam, loc, target)
    scene.camera = cam
    scene.render.filepath = os.path.join(PREVIEW_DIR, f"turrets_{view}.png")
    bpy.ops.render.render(write_still=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("BUILT", built)
