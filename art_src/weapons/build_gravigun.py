"""Гравипушка по референсу (art_src/weapons/ref_gravigun.webp): стилизованный low-poly.

Тёмный угловатый корпус из гранёных плит с фиолетовыми светящимися полосами, серый шеврон
на боку, сверху ручка для переноски, снизу пистолетная рукоять и передняя «лапа» под стволом.
Толстый ствол с фиолетовыми прорезями ведёт к излучателю: кольцо из восьми массивных дуг
со стальными зажимами, внутри — светящийся фиолетовый обод и чёрное ядро (чёрная дыра).
Тон каждой грани зависит от того, куда она смотрит (верх светлее, низ темнее).

Оси Blender: +Y — к дулу, +Z — вверх, +X — вправо (в Godot дуло смотрит в -Z).
Один меш «Gravigun» + пустышки: Muzzle — центр излучателя (отсюда летит заряд);
Grip_Right — пистолетная рукоять; Grip_Left — передняя лапа под стволом (левая рука).

Запуск: Blender -b --factory-startup --python art_src/weapons/build_gravigun.py
Сохраняет art_src/weapons/gravigun.blend и weapons/models/gravigun.glb, превью — в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_GLB = os.path.join(PROJECT, "weapons/models/gravigun.glb")
OUT_BLEND = os.path.join(PROJECT, "art_src/weapons/gravigun.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "gravigun")

# Три тона на материал (светлый, основной, тёмный), шероховатость, металличность
PALETTE = {
    "Body": ("4A4752", "36343D", "24232A", 0.55, 0.45),
    "Steel": ("8A8790", "6C6972", "4E4C54", 0.45, 0.6),
    "Glow": ("B07CFF", "9447FF", "7330E0", 0.4, 0.0),
    "Core": ("0C0A10", "08070B", "040306", 1.0, 0.0),
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
                # Фиолетовые полосы и кольцо излучателя светятся сами
                b.inputs["Emission Color"].default_value = srgb_to_lin(hexc)
                b.inputs["Emission Strength"].default_value = 2.0
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


def arc(y0, y1, r_in, r_out, a0, a1, base, steps=3, center=(0.0, 0.0), bevel=0.0):
    """Дуга кольца вокруг оси Y: от угла a0 до a1, радиусы r_in..r_out, по Y от y0 до y1."""
    rings = []
    for k in range(steps + 1):
        a = a0 + (a1 - a0) * k / steps
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((center[0] + r * c, y, center[1] + r * s))
                      for r, y in ((r_in, y0), (r_out, y0), (r_out, y1), (r_in, y1))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    _finish([v for r in rings for v in r], base, bevel)


# --- корпус ---------------------------------------------------------------------------------

BODY_Z = 0.0
# Задняя часть выше, к стволу сужается; снизу скос под рукоять
loft([(-0.3, section(0.092, 0.07, -0.035, 0.3)), (-0.24, section(0.1, 0.085, -0.05)),
      (0.02, section(0.104, 0.088, -0.055)), (0.1, section(0.094, 0.07, -0.045)),
      (0.14, section(0.08, 0.06, -0.03))], "Body", bevel=0.004)
# Наборные плиты по бокам и сверху — ступеньками, как на референсе
for s in (-1.0, 1.0):
    box((s * 0.054, -0.17, 0.02), (0.01, 0.1, 0.07), "Body", bevel=0.003)
    box((s * 0.054, -0.04, 0.026), (0.01, 0.1, 0.05), "Body", bevel=0.003)
    # Фиолетовые полосы-прорези
    box((s * 0.06, -0.17, 0.0), (0.004, 0.08, 0.012), "Glow")
    box((s * 0.06, -0.04, 0.012), (0.004, 0.08, 0.01), "Glow")
    box((s * 0.054, 0.075, -0.034), (0.006, 0.05, 0.01), "Glow")
    # Стальной шеврон «>» на боку
    for d in (-1.0, 1.0):
        rot = Matrix.Rotation(d * 0.75, 3, "X")
        box((s * 0.059, 0.055, 0.025 + d * 0.017), (0.008, 0.055, 0.016), "Steel", bevel=0.002, rot=rot)
box((0, -0.12, 0.092), (0.07, 0.24, 0.014), "Body", bevel=0.003)
box((0, -0.12, 0.1), (0.02, 0.2, 0.004), "Glow")
# Задний торец — тёмная плита с полосой
box((0, -0.305, 0.015), (0.08, 0.016, 0.08), "Body", bevel=0.003)
box((0, -0.314, 0.015), (0.01, 0.004, 0.05), "Glow")

# --- ручка для переноски --------------------------------------------------------------------

strip([(-0.24, 0.095), (-0.215, 0.15), (-0.05, 0.15), (-0.025, 0.095)], 0.024, 0.026, "Body", bevel=0.003)
box((0, -0.13, 0.152), (0.03, 0.12, 0.006), "Steel", bevel=0.002)

# --- ствол ----------------------------------------------------------------------------------

BARREL_Z = 0.018
lathe([(0.12, 0.0), (0.12, 0.05), (0.33, 0.05), (0.33, 0.0)], "Body", segments=8, center=(0, BARREL_Z), bevel=0.003)
# Стальные обоймы и фиолетовые прорези вдоль ствола
for y0 in (0.15, 0.27):
    lathe([(y0, 0.046), (y0, 0.058), (y0 + 0.025, 0.058), (y0 + 0.025, 0.046)], "Steel", segments=8,
          center=(0, BARREL_Z), bevel=0.002)
for k in range(4):
    a = math.tau * k / 4 + math.pi / 4
    pos = Vector((math.cos(a) * 0.05, 0.225, BARREL_Z + math.sin(a) * 0.05))
    box(pos, (0.008, 0.07, 0.008), "Glow", rot=Matrix.Rotation(-a, 3, "Y"))

# --- излучатель: кольцо из дуг с зажимами, светящийся обод и чёрное ядро --------------------

EMIT_Y = 0.385
RING_IN, RING_OUT = 0.1, 0.13
for k in range(8):
    a0 = math.tau * k / 8 + 0.07
    a1 = math.tau * (k + 1) / 8 - 0.07
    arc(EMIT_Y - 0.03, EMIT_Y + 0.03, RING_IN, RING_OUT, a0, a1, "Body", center=(0, BARREL_Z), bevel=0.003)
# Массивные зажимы на четырёх дугах (по диагоналям) — сталь, выступают вперёд и наружу
for k in range(4):
    a = math.tau * k / 4 + math.pi / 4
    c, s = math.cos(a), math.sin(a)
    pos = Vector((c * 0.118, EMIT_Y, BARREL_Z + s * 0.118))
    box(pos, (0.07, 0.085, 0.03), "Steel", bevel=0.004, rot=Matrix.Rotation(-a + math.pi / 2, 3, "Y"))
# Внешнее разорванное кольцо — тонкие дуги позади, как на референсе
for k in range(4):
    a0 = math.tau * k / 4 + 0.35
    a1 = math.tau * (k + 1) / 4 - 0.35
    arc(EMIT_Y - 0.075, EMIT_Y - 0.05, 0.13, 0.15, a0, a1, "Body", center=(0, BARREL_Z), bevel=0.002)
# Раструб от ствола к кольцу
lathe([(0.33, 0.05), (0.36, 0.085), (0.37, 0.1), (0.37, 0.0)], "Body", segments=8, center=(0, BARREL_Z))
# Светящийся обод и чёрное ядро внутри кольца
arc(EMIT_Y - 0.015, EMIT_Y + 0.015, 0.068, 0.1, 0.0, math.tau, "Glow", steps=12, center=(0, BARREL_Z))
lathe([(EMIT_Y - 0.03, 0.0), (EMIT_Y - 0.03, 0.05), (EMIT_Y, 0.068), (EMIT_Y + 0.02, 0.05), (EMIT_Y + 0.03, 0.0)],
      "Core", segments=10, center=(0, BARREL_Z))

# --- пистолетная рукоять, спуск, скоба ------------------------------------------------------

strip([(-0.13, -0.04), (-0.155, -0.11), (-0.18, -0.175)], 0.05, 0.042, "Body", bevel=0.004)
box((0, -0.19, -0.18), (0.046, 0.06, 0.016), "Body", bevel=0.004)
box((0, -0.15, -0.1), (0.044, 0.008, 0.05), "Glow", rot=Matrix.Rotation(0.38, 3, "X"))
box((0, -0.085, -0.06), (0.008, 0.012, 0.03), "Steel", bevel=0.002, rot=Matrix.Rotation(0.3, 3, "X"))
strip([(-0.115, -0.05), (-0.115, -0.095), (-0.05, -0.095), (-0.04, -0.055)], 0.008, 0.012, "Body", bevel=0.0015)

# --- передняя лапа под стволом (левая рука): вниз и вперёд, с фиолетовой полосой ------------

strip([(0.04, -0.05), (0.06, -0.12), (0.21, -0.12)], 0.034, 0.05, "Body", bevel=0.004)
box((0, 0.15, -0.135), (0.054, 0.12, 0.012), "Body", bevel=0.003)
for s in (-1.0, 1.0):
    box((s * 0.027, 0.15, -0.12), (0.004, 0.08, 0.008), "Glow")
box((0, 0.11, -0.065), (0.03, 0.08, 0.05), "Body", bevel=0.003)


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
    mesh = bpy.data.meshes.new("Gravigun")
    bm.to_mesh(mesh)
    for m in mats:
        mesh.materials.append(m)
    gun = bpy.data.objects.new("Gravigun", mesh)
    bpy.context.scene.collection.objects.link(gun)
    for name, loc in {"Muzzle": (0, EMIT_Y + 0.04, BARREL_Z), "Grip_Right": (0, -0.155, -0.11),
                      "Grip_Left": (0, 0.14, -0.12)}.items():
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
    center = (0, 0.05, 0.0)
    views = {
        "1_side_left": ((-1.6, 0.05, 0.0), (0, 0, 1)),
        "2_three_quarter": ((-1.0, 1.05, 0.45), (0, 0, 1)),
        "3_side_right": ((1.6, 0.05, 0.0), (0, 0, 1)),
        "4_rear": ((0.5, -1.4, 0.35), (0, 0, 1)),
    }
    for name, (loc, up) in views.items():
        cam = bpy.data.objects.new("Cam_" + name, bpy.data.cameras.new("Cam_" + name))
        cam.data.lens = 50
        scene.collection.objects.link(cam)
        look_at(cam, loc, center, up)
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"gravigun_{name}.png")
        bpy.ops.render.render(write_still=True)
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    cam = bpy.data.objects.new("Cam_front", bpy.data.cameras.new("Cam_front"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    look_at(cam, (0.0, 1.35, 0.02), (0, 0.3, 0.0))
    scene.camera = cam
    scene.render.filepath = os.path.join(PREVIEW_DIR, "gravigun_5_front.png")
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
