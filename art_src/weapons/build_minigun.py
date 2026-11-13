"""Ручной пулемёт (миниган) по референсу (art_src/weapons/ref_minigun.webp): стилизованный low-poly.

Тёмный гранёный короб со светлыми поясами и оранжевыми накладками, сверху две ручки-дуги,
сзади оранжевая рукоять, на боках светятся синие экраны. Спереди — блок из шести стволов с
раскалёнными оранжевыми срезами и прорезями, неподвижный кожух из колец; снизу — патронный
барабан с оранжевыми светящимися окнами и передняя рукоять под левую руку.
Тон каждой грани зависит от того, куда она смотрит (верх светлее, низ темнее).

Оси Blender: +Y — к дулу, +Z — вверх, +X — вправо (в Godot дуло смотрит в -Z).
Объекты: «Minigun» (корпус) и «Barrels» (блок стволов, крутится вокруг своей оси — в Godot
вокруг Z); пустышки: Muzzle — дуло, Grip_Right — задняя рукоять, Grip_Left — передняя.

Запуск: Blender -b --factory-startup --python art_src/weapons/build_minigun.py
Сохраняет art_src/weapons/minigun.blend и weapons/models/minigun.glb, превью — в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_GLB = os.path.join(PROJECT, "weapons/models/minigun.glb")
OUT_BLEND = os.path.join(PROJECT, "art_src/weapons/minigun.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "minigun")

# Три тона на материал (светлый, основной, тёмный), шероховатость, металличность
PALETTE = {
    "Body": ("4A4850", "37353C", "24232A", 0.55, 0.45),
    "Plate": ("C9C7CC", "A9A7AD", "85838A", 0.5, 0.3),
    "Orange": ("FF9A3C", "F07A1E", "C25A12", 0.5, 0.1),
    "Glow": ("FFC060", "FF9A20", "F07A10", 0.4, 0.0),
    "Screen": ("8FD8FF", "40B0FF", "2080E0", 0.3, 0.0),
    "Bore": ("1A1A1A", "121212", "0A0A0A", 1.0, 0.0),
}
GLOWS = {"Glow": 2.5, "Screen": 2.5}
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
            if base in GLOWS:
                # Оранжевые окна и каналы стволов, синий экран светятся сами
                b.inputs["Emission Color"].default_value = srgb_to_lin(hexc)
                b.inputs["Emission Strength"].default_value = GLOWS[base]
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

AXIS_Z = 0.02          # ось блока стволов
BARRELS_Y = 0.22       # где начинается кожух блока стволов
DRUM = Vector((0, -0.08, -0.15))


def drum_ring(x0, x1, r, base, segments=10):
    """Цилиндр вдоль оси X (патронный барабан) от x0 до x1 радиуса r, с крышками."""
    rings = []
    for x in (x0, x1):
        rings.append([bm.verts.new((x, DRUM.y + r * math.cos(math.tau * (k + 0.5) / segments),
                                    DRUM.z + r * math.sin(math.tau * (k + 0.5) / segments))) for k in range(segments)])
    for k in range(segments):
        k2 = (k + 1) % segments
        bm.faces.new((rings[0][k], rings[0][k2], rings[1][k2], rings[1][k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[1])))
    _finish(rings[0] + rings[1], base, 0.003)


loft([(-0.3, section(0.15, 0.1, -0.06, 0.3)), (-0.22, section(0.17, 0.12, -0.08)),
      (0.12, section(0.17, 0.12, -0.08)), (0.2, section(0.15, 0.1, -0.06))], "Body", bevel=0.005)
# Светлый пояс и оранжевые накладки
loft([(0.12, section(0.18, 0.125, -0.085)), (0.2, section(0.18, 0.125, -0.085))], "Plate", bevel=0.005)
box((0, -0.02, 0.128), (0.12, 0.16, 0.016), "Orange", bevel=0.004)
for s in (-1.0, 1.0):
    box((s * 0.088, -0.02, 0.05), (0.012, 0.16, 0.07), "Orange", bevel=0.004)
    box((s * 0.088, -0.16, -0.02), (0.012, 0.1, 0.05), "Plate", bevel=0.003)
# Синие светящиеся экраны на обоих боках (левый виден от первого лица), в тёмной рамке
for s in (-1.0, 1.0):
    box((s * 0.094, -0.17, 0.06), (0.012, 0.09, 0.06), "Body", bevel=0.003)
    box((s * 0.101, -0.17, 0.06), (0.004, 0.065, 0.038), "Screen")
    for k in range(2):
        box((s * 0.1035, -0.17, 0.052 + k * 0.016), (0.002, 0.05, 0.004), "Body")
# Две ручки-дуги сверху
strip([(-0.02, 0.13), (-0.01, 0.2), (0.12, 0.2), (0.14, 0.13)], 0.026, 0.03, "Body", bevel=0.004)
strip([(-0.27, 0.1), (-0.25, 0.17), (-0.13, 0.17), (-0.12, 0.12)], 0.024, 0.028, "Body", bevel=0.004)
box((0, -0.19, 0.172), (0.034, 0.08, 0.014), "Orange", bevel=0.003)
# Задняя оранжевая рукоять (правая рука) и светлый затыльник
strip([(-0.24, -0.06), (-0.27, -0.12), (-0.3, -0.19)], 0.05, 0.044, "Orange", bevel=0.005)
box((0, -0.31, -0.2), (0.05, 0.06, 0.02), "Body", bevel=0.004)
loft([(-0.34, section(0.13, 0.09, -0.04, 0.3)), (-0.3, section(0.14, 0.1, -0.05))], "Plate", bevel=0.004)
# Патронный барабан снизу: тёмный цилиндр вдоль X со светлым поясом и оранжевыми окнами
drum_ring(-0.085, 0.085, 0.095, "Body")
drum_ring(-0.03, 0.03, 0.1, "Plate")
for s in (-1.0, 1.0):
    drum_ring(s * 0.085, s * 0.093, 0.07, "Body")
    # Светящиеся окна на торце и светящийся пояс по окружности
    for k in range(3):
        box((s * 0.096, DRUM.y, DRUM.z - 0.035 + k * 0.035), (0.004, 0.07, 0.02), "Glow")
    drum_ring(s * 0.045, s * 0.055, 0.098, "Glow")
box((0, DRUM.y - 0.097, DRUM.z), (0.05, 0.004, 0.06), "Glow")
# Крепление барабана
box((0, -0.06, -0.075), (0.06, 0.08, 0.04), "Body", bevel=0.004)
# Передняя рукоять под стволами (левая рука) с оранжевой накладкой
strip([(0.1, -0.07), (0.12, -0.13), (0.13, -0.19)], 0.04, 0.04, "Body", bevel=0.004)
box((0, 0.125, -0.13), (0.044, 0.02, 0.05), "Orange", bevel=0.003, rot=Matrix.Rotation(-0.3, 3, "X"))
# Неподвижный кожух вокруг блока стволов: тёмное кольцо, широкий светлый пояс, тёмная обойма
lathe([(BARRELS_Y, 0.0), (BARRELS_Y, 0.14), (BARRELS_Y + 0.06, 0.148), (BARRELS_Y + 0.06, 0.0)], "Body",
      segments=18, center=(0, AXIS_Z), bevel=0.006)
lathe([(0.35, 0.11), (0.35, 0.155), (0.44, 0.155), (0.44, 0.11)], "Plate", segments=18, center=(0, AXIS_Z), bevel=0.007)
lathe([(0.45, 0.11), (0.45, 0.145), (0.49, 0.145), (0.49, 0.11)], "Body", segments=18, center=(0, AXIS_Z), bevel=0.005)
body_bm = bm

# --- блок стволов (крутится): координаты от начала узла Barrels --------------------------------

BARREL_LEN = 0.56
BARREL_R = 0.034
CLUSTER_R = 0.08
bm = bmesh.new()
lathe([(0.0, 0.0), (0.0, 0.042), (BARREL_LEN, 0.042), (BARREL_LEN, 0.0)], "Body", segments=12)
for k in range(6):
    a = math.tau * k / 6
    c = (math.cos(a) * CLUSTER_R, math.sin(a) * CLUSTER_R)
    lathe([(0.0, 0.0), (0.0, BARREL_R), (BARREL_LEN, BARREL_R), (BARREL_LEN, 0.0)], "Body", segments=14, center=c)
    # Дульный срез: тёмная муфта, раскалённое оранжевое кольцо и тёмный канал
    lathe([(BARREL_LEN, 0.0), (BARREL_LEN, 0.042), (BARREL_LEN + 0.035, 0.042), (BARREL_LEN + 0.035, 0.0)], "Body",
          segments=14, center=c, bevel=0.004)
    lathe([(BARREL_LEN + 0.036, 0.017), (BARREL_LEN + 0.036, 0.034), (BARREL_LEN + 0.038, 0.034),
           (BARREL_LEN + 0.038, 0.017)], "Glow", segments=14, center=c)
    lathe([(BARREL_LEN + 0.037, 0.0), (BARREL_LEN + 0.037, 0.017), (BARREL_LEN + 0.038, 0.017),
           (BARREL_LEN + 0.038, 0.0)], "Bore", segments=14, center=c)
    # Светящиеся прорези между стволами
    am = a + math.tau / 12
    box((math.cos(am) * 0.07, 0.3, math.sin(am) * 0.07), (0.016, 0.18, 0.016), "Glow",
        rot=Matrix.Rotation(-am, 3, "Y"))
# Круглые обоймы на стволах
for y0 in (0.06, 0.44):
    lathe([(y0, 0.0), (y0, 0.125), (y0 + 0.04, 0.125), (y0 + 0.04, 0.0)], "Body", segments=18, bevel=0.005)
barrels_bm = bm


# --- сборка, экспорт, превью ----------------------------------------------------------------

def look_at(obj, loc, target, up=(0, 0, 1)):
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(Vector(up)).normalized()
    u = r.cross(f)
    obj.matrix_world = Matrix((r, u, -f)).transposed().to_4x4()
    obj.location = loc


def make_object(name, source, mats):
    mesh = bpy.data.meshes.new(name)
    source.to_mesh(mesh)
    for m in mats:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    mats = make_materials()
    gun = make_object("Minigun", body_bm, mats)
    barrels = make_object("Barrels", barrels_bm, mats)
    barrels.parent = gun
    barrels.location = (0, BARRELS_Y + 0.03, AXIS_Z)
    for name, loc in {"Muzzle": (0, BARRELS_Y + 0.66, AXIS_Z), "Grip_Right": (0, -0.27, -0.12),
                      "Grip_Left": (0, 0.12, -0.13)}.items():
        e = bpy.data.objects.new(name, None)
        e.location = loc
        e.empty_display_size = 0.03
        e.parent = gun
        bpy.context.scene.collection.objects.link(e)
    return gun


def preview():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = srgb_to_lin("B9B9BD")
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    for name, energy, rot, color in (("Key", 2.4, (50, 15, -60), (1.0, 0.96, 0.9)),
                                     ("Fill", 1.0, (60, 0, 130), (0.9, 0.93, 1.0))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        light.data.energy = energy
        light.data.color = color
        light.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(light)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    center = (0, 0.15, -0.02)
    views = {
        "1_three_quarter": (1.1, 1.15, 0.45),
        "2_side_right": (1.7, 0.15, 0.0),
        "3_side_left": (-1.7, 0.15, 0.0),
        "4_front": (0.05, 1.7, 0.03),
        "5_rear": (0.3, -1.5, 0.2),
    }
    for name, loc in views.items():
        cam = bpy.data.objects.new("Cam_" + name, bpy.data.cameras.new("Cam_" + name))
        cam.data.lens = 50
        scene.collection.objects.link(cam)
        look_at(cam, loc, center)
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"minigun_{name}.png")
        bpy.ops.render.render(write_still=True)


os.makedirs(PREVIEW_DIR, exist_ok=True)
gun = build()
tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
for o in bpy.data.objects:
    o.select_set(True)
os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True)
preview()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("STATS tris", tris, "size", tuple(round(d, 3) for d in gun.dimensions))
print("EXPORTED", OUT_GLB)
