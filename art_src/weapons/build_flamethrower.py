"""Огнемёт по референсу (art_src/weapons/ref_flamethrower.webp): стилизованный low-poly.

Тёмный оружейный металл с оранжевыми накладками: гранёный корпус, сверху ручка для переноски
на оранжевом основании, спереди — ствол с оранжевым кольцом и раструб-клетка из прутьев,
внутри которой светится огненное ядро. Под корпусом — оранжевый восьмигранный баллон с
топливом на двух тёмных хомутах и трубка от баллона к стволу. Пистолетная рукоять с
оранжевым спуском и скобой, рамочный приклад с оранжевым затыльником и накладкой.
Тон каждой грани зависит от того, куда она смотрит (верх светлее, низ темнее), — как рисованные
текстуры.

Оси Blender: +Y — к дулу, +Z — вверх, +X — вправо (в Godot дуло смотрит в -Z).
Один меш «Flamethrower» + пустышки: Muzzle — центр клетки (отсюда бьёт пламя);
Grip_Right — пистолетная рукоять; Grip_Left — баллон снизу (левая рука).

Запуск: Blender -b --factory-startup --python art_src/weapons/build_flamethrower.py
Сохраняет art_src/weapons/flamethrower.blend и weapons/models/flamethrower.glb, превью — в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_GLB = os.path.join(PROJECT, "weapons/models/flamethrower.glb")
OUT_BLEND = os.path.join(PROJECT, "art_src/weapons/flamethrower.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "flamethrower")

# Три тона на материал (светлый, основной, тёмный), шероховатость, металличность
PALETTE = {
    "Gunmetal": ("57545A", "403E43", "2C2A2E", 0.6, 0.5),
    "Steel": ("7C7980", "625F66", "4A474D", 0.5, 0.6),
    "Orange": ("FF9A4A", "EE7A2E", "C25A1E", 0.55, 0.1),
    "Glow": ("FFB347", "FF8C2E", "F06A1E", 0.4, 0.0),
    "Bore": ("1A1A1A", "121212", "0A0A0A", 1.0, 0.0),
}
TONES = ("Light", "", "Dark")
MAT_NAMES = [f"{base}_{tone}" if tone else base for base in PALETTE for tone in TONES]
MAT = {name: i for i, name in enumerate(MAT_NAMES)}


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
            if base == "Glow":
                # Огненное ядро светится само
                b.inputs["Emission Color"].default_value = srgb_to_lin(hexc)
                b.inputs["Emission Strength"].default_value = 1.2
            mats.append(m)
    return mats


bm = bmesh.new()
_rng = random.Random(5)


def _paint(faces, base):
    """Тон грани по нормали: смотрит вверх — светлее, вниз — темнее; немного случайности."""
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


def section(w, top, bot, chamfer=0.25):
    """Гранёное сечение: прямоугольник со срезанными углами (точки x, z), 8 вершин."""
    hw, hh = w / 2.0, (top - bot) / 2.0
    zc = (top + bot) / 2.0
    cx, cz = hw * chamfer * 2.0, hh * chamfer * 2.0
    c = min(cx, cz)
    return [(hw, zc - hh + c), (hw, zc + hh - c), (hw - c, zc + hh), (-hw + c, zc + hh),
            (-hw, zc + hh - c), (-hw, zc - hh + c), (-hw + c, zc - hh), (hw - c, zc - hh)]


def loft(sections, base, bevel=0.0):
    """Протянуть сечения вдоль Y: sections — (y, [(x, z), ...]) с одинаковым числом точек."""
    rings = [[bm.verts.new((x, y, z)) for x, z in pts] for y, pts in sections]
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    _finish([v for r in rings for v in r], base, bevel)


def lathe(profile, base, segments=8, center=(0.0, 0.0), bevel=0.0):
    """Тело вращения вокруг оси Y через center (x, z); profile — (y, r)."""
    rings = []
    for y, r in profile:
        if r <= 0.0:
            rings.append([bm.verts.new((center[0], y, center[1]))])
        else:
            rings.append([bm.verts.new((center[0] + r * math.cos(math.tau * (k + 0.5) / segments), y,
                                         center[1] + r * math.sin(math.tau * (k + 0.5) / segments)))
                          for k in range(segments)])
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


def box(center, size, base, bevel=0.0, rot=None):
    res = bmesh.ops.create_cube(bm, size=1.0)
    xf = Matrix.Translation(center) @ (rot.to_4x4() if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.transform(bm, matrix=xf, verts=res["verts"])
    _finish(res["verts"], base, bevel)


def strip(points_yz, width, thick_x, base, x=0.0, bevel=0.002):
    """Брусок по ломаной в плоскости Y-Z (ручка, скоба, рама приклада)."""
    for (y0, z0), (y1, z1) in zip(points_yz, points_yz[1:]):
        d = Vector((0, y1 - y0, z1 - z0))
        mid = Vector((x, (y0 + y1) / 2, (z0 + z1) / 2))
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix()
        box(mid, (thick_x, d.length + width * 0.9, width), base, bevel=bevel, rot=rot)


def tube(points, radius, base, segments=6):
    """Трубка по ломаной (точки x, y, z)."""
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        axis = b - a
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius,
                                    depth=axis.length + radius)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=res["verts"])
        _finish(res["verts"], base)


def rivet(pos, normal, radius=0.006, base="Steel"):
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    z = Vector(normal).normalized()
    x = z.cross(Vector((0, 1, 0)) if abs(z.y) < 0.9 else Vector((1, 0, 0))).normalized()
    basis = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(pos) @ basis @ Matrix.Diagonal((1, 1, 0.6, 1)), verts=res["verts"])
    _finish(res["verts"], base)


# --- корпус ---------------------------------------------------------------------------------

# Задняя часть корпуса — выше и шире, передняя — сужается к стволу
loft([(-0.13, section(0.084, 0.058, -0.034)), (0.07, section(0.086, 0.062, -0.036)),
      (0.2, section(0.078, 0.052, -0.03)), (0.25, section(0.066, 0.04, -0.022))], "Gunmetal", bevel=0.003)
# Верхняя планка и боковые вставки
box((0, 0.02, 0.068), (0.05, 0.3, 0.014), "Steel", bevel=0.003)
for s in (-1.0, 1.0):
    box((s * 0.044, 0.1, 0.012), (0.006, 0.12, 0.04), "Steel", bevel=0.002)
    # Оранжевая накладка на заднем борту
    box((s * 0.045, -0.06, 0.02), (0.008, 0.08, 0.05), "Orange", bevel=0.003)
    rivet(Vector((s * 0.05, -0.085, 0.036)), (s, 0, 0))
    rivet(Vector((s * 0.05, -0.035, 0.036)), (s, 0, 0))
# Оранжевое кольцо-обойма на передней части корпуса
loft([(0.15, section(0.092, 0.066, -0.04)), (0.19, section(0.092, 0.066, -0.04))], "Orange", bevel=0.003)
for s in (-1.0, 1.0):
    rivet(Vector((s * 0.047, 0.17, 0.035)), (s, 0, 0))

# --- ручка для переноски на оранжевом основании -------------------------------------------

box((0, 0.045, 0.084), (0.056, 0.08, 0.026), "Orange", bevel=0.004)
strip([(-0.02, 0.09), (-0.005, 0.15), (0.11, 0.15), (0.13, 0.09)], 0.022, 0.024, "Gunmetal")

# --- ствол и раструб-клетка ----------------------------------------------------------------

BARREL_Z = 0.012
lathe([(0.24, 0.0), (0.24, 0.033), (0.47, 0.033), (0.47, 0.0)], "Gunmetal", center=(0, BARREL_Z), bevel=0.002)
lathe([(0.3, 0.0), (0.3, 0.04), (0.34, 0.04), (0.34, 0.0)], "Orange", center=(0, BARREL_Z), bevel=0.003)
CAGE = (0.47, 0.6)
CAGE_R = 0.056
# Кольца клетки: заднее, среднее, переднее
for y0, y1 in ((0.465, 0.485), (0.53, 0.542), (0.585, 0.6)):
    lathe([(y0, 0.0), (y0, CAGE_R + 0.006), (y1, CAGE_R + 0.006), (y1, 0.0)] if y0 == 0.465 else
          [(y0, CAGE_R - 0.012), (y0, CAGE_R + 0.006), (y1, CAGE_R + 0.006), (y1, CAGE_R - 0.012)],
          "Gunmetal", center=(0, BARREL_Z), bevel=0.002)
# Прутья клетки
for k in range(8):
    a = math.tau * (k + 0.5) / 8
    pos = Vector((math.cos(a) * CAGE_R, (CAGE[0] + CAGE[1]) / 2, BARREL_Z + math.sin(a) * CAGE_R))
    rot = Matrix.Rotation(a + math.pi / 2, 3, "Y")
    box(pos, (0.012, CAGE[1] - CAGE[0], 0.012), "Gunmetal", bevel=0.002, rot=rot)
# Огненное ядро внутри клетки и тёмный канал впереди
lathe([(0.485, 0.0), (0.485, 0.034), (0.5, 0.042), (0.565, 0.042), (0.58, 0.034), (0.58, 0.0)], "Glow",
      segments=8, center=(0, BARREL_Z))
lathe([(0.5805, 0.0), (0.5805, 0.016), (0.581, 0.016), (0.581, 0.0)], "Bore", segments=8, center=(0, BARREL_Z))

# --- баллон с топливом под корпусом ---------------------------------------------------------

TANK_Z = -0.09
TANK_R = 0.052
lathe([(-0.03, 0.0), (-0.03, TANK_R * 0.75), (-0.012, TANK_R), (0.215, TANK_R), (0.233, TANK_R * 0.75),
       (0.233, 0.0)], "Orange", segments=8, center=(0, TANK_Z), bevel=0.002)
for y in (0.025, 0.165):
    lathe([(y, TANK_R - 0.004), (y, TANK_R + 0.006), (y + 0.022, TANK_R + 0.006), (y + 0.022, TANK_R - 0.004)],
          "Gunmetal", segments=8, center=(0, TANK_Z), bevel=0.0015)
# Крепление баллона к корпусу
box((0, 0.1, -0.042), (0.03, 0.17, 0.03), "Gunmetal", bevel=0.003)
# Клапан и трубка от баллона к стволу
lathe([(0.233, 0.0), (0.233, 0.014), (0.25, 0.014), (0.25, 0.0)], "Steel", segments=6, center=(0, TANK_Z))
tube([(0, 0.25, TANK_Z), (0, 0.29, TANK_Z + 0.004), (0, 0.33, -0.05), (0, 0.38, -0.028), (0, 0.44, -0.024)], 0.009, "Steel")
# Скоба-держатель трубки
lathe([(0.4, 0.033), (0.4, 0.038), (0.415, 0.038), (0.415, 0.033)], "Steel", segments=8, center=(0, BARREL_Z))

# --- пистолетная рукоять, спуск, скоба ------------------------------------------------------

loft([(-0.075, section(0.042, -0.025, -0.06)), (-0.11, section(0.04, -0.06, -0.06)),
      (-0.13, section(0.038, -0.06, -0.06))], "Gunmetal", bevel=0.002)
strip([(-0.085, -0.03), (-0.1, -0.09), (-0.115, -0.16)], 0.045, 0.04, "Gunmetal", bevel=0.004)
box((0, -0.122, -0.165), (0.044, 0.05, 0.016), "Gunmetal", bevel=0.004)
box((0, -0.045, -0.055), (0.008, 0.012, 0.032), "Orange", bevel=0.002, rot=Matrix.Rotation(0.3, 3, "X"))
strip([(-0.072, -0.034), (-0.075, -0.08), (-0.03, -0.085), (-0.012, -0.045)], 0.008, 0.012, "Gunmetal", bevel=0.0015)

# --- рамочный приклад -----------------------------------------------------------------------

strip([(-0.13, 0.03), (-0.43, 0.03)], 0.04, 0.04, "Gunmetal", bevel=0.004)
strip([(-0.15, -0.04), (-0.27, -0.06), (-0.43, -0.11)], 0.036, 0.04, "Gunmetal", bevel=0.004)
# Оранжевый затыльник и накладка под щёку
box((0, -0.455, -0.035), (0.05, 0.05, 0.2), "Orange", bevel=0.006)
box((0, -0.455, -0.035), (0.054, 0.012, 0.15), "Gunmetal", bevel=0.002)
box((0, -0.33, 0.052), (0.046, 0.12, 0.016), "Orange", bevel=0.004)
for y in (-0.37, -0.29):
    rivet(Vector((0, y, 0.061)), (0, 0, 1))


# --- сборка, экспорт, превью ----------------------------------------------------------------

def look_at(obj, loc, target, up=(0, 0, 1)):
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(Vector(up)).normalized()
    u = r.cross(f)
    obj.matrix_world = Matrix((r, u, -f)).transposed().to_4x4()
    obj.location = loc


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    mats = make_materials()
    mesh = bpy.data.meshes.new("Flamethrower")
    bm.to_mesh(mesh)
    for m in mats:
        mesh.materials.append(m)
    gun = bpy.data.objects.new("Flamethrower", mesh)
    bpy.context.scene.collection.objects.link(gun)
    for name, loc in {"Muzzle": (0, 0.53, BARREL_Z), "Grip_Right": (0, -0.1, -0.1),
                      "Grip_Left": (0, 0.1, TANK_Z)}.items():
        e = bpy.data.objects.new(name, None)
        e.location = loc
        e.empty_display_size = 0.03
        e.parent = gun
        bpy.context.scene.collection.objects.link(e)
    return gun


def preview(gun):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = srgb_to_lin("C9C9CB")
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    for name, energy, rot, color in (("Key", 2.4, (50, 15, -60), (1.0, 0.96, 0.9)),
                                     ("Fill", 1.0, (60, 0, 130), (0.9, 0.93, 1.0))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        light.data.energy = energy
        light.data.color = color
        light.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(light)
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 700
    center = (0, 0.07, -0.03)
    views = {
        "1_side_left": ((-1.9, 0.07, -0.03), (0, 0, 1)),
        "2_top": ((0, 0.07, 1.9), (-1, 0, 0)),
        "3_three_quarter": ((-1.15, 1.05, 0.6), (0, 0, 1)),
        "4_side_right": ((1.9, 0.07, -0.03), (0, 0, 1)),
    }
    for name, (loc, up) in views.items():
        cam = bpy.data.objects.new("Cam_" + name, bpy.data.cameras.new("Cam_" + name))
        cam.data.lens = 50
        scene.collection.objects.link(cam)
        look_at(cam, loc, center, up)
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"flamethrower_{name}.png")
        bpy.ops.render.render(write_still=True)
    scene.render.resolution_x = 700
    scene.render.resolution_y = 700
    cam = bpy.data.objects.new("Cam_front", bpy.data.cameras.new("Cam_front"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    look_at(cam, (0.12, 1.45, 0.06), (0, 0.4, -0.03))
    scene.camera = cam
    scene.render.filepath = os.path.join(PREVIEW_DIR, "flamethrower_5_front.png")
    bpy.ops.render.render(write_still=True)


os.makedirs(PREVIEW_DIR, exist_ok=True)
gun = build()
stats = (len(gun.data.vertices), sum(len(p.vertices) - 2 for p in gun.data.polygons))
for o in bpy.data.objects:
    o.select_set(True)
os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True)
preview(gun)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("STATS verts", stats[0], "tris", stats[1], "size", tuple(round(d, 3) for d in gun.dimensions))
print("EXPORTED", OUT_GLB)
