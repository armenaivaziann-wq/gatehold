"""Мушкетон по референсу (art_src/weapons/ref_blunderbuss.webp): стилизованный low-poly.

Формы — гранёные сечения, протянутые вдоль оружия (а не бруски): широкий полый раструб из
тёмного железа, восьмигранный ствол, деревянное цевьё, обнимающее нижнюю половину ствола,
латунное и железное кольца с заклёпками, латунная замочная доска с курком и огнивом на левом
боку, угловатая железная скоба со спуском, шейка приклада в кожаной обмотке, расширяющийся
приклад с латунной оковкой. Тон каждой грани зависит от того, куда она смотрит (верх светлее,
низ темнее) с лёгким разбросом — как рисованные от руки текстуры.

Оси Blender: +Y — к дулу, +Z — вверх, +X — вправо (замок на левом боку, -X; в Godot дуло — -Z).
Один меш «Blunderbuss» + пустышки: Muzzle — срез дула; Grip_Right — хват правой руки на шейке
приклада; Grip_Left — хват левой руки снизу под цевьём.

Запуск: Blender -b --factory-startup --python art_src/weapons/build_blunderbuss.py
Сохраняет art_src/weapons/blunderbuss.blend и weapons/models/blunderbuss.glb, превью — в PREVIEW_DIR.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_GLB = os.path.join(PROJECT, "weapons/models/blunderbuss.glb")
OUT_BLEND = os.path.join(PROJECT, "art_src/weapons/blunderbuss.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "blunderbuss")

# Каждый материал — три тона (светлый, основной, тёмный): грань получает тон по своей нормали
PALETTE = {
    "Wood": ("A85A32", "8A4526", "68321B", 0.8, 0.0),
    "Iron": ("6E6E74", "4E4E54", "38383D", 0.55, 0.7),
    "Brass": ("F0C366", "D9A441", "A87A2E", 0.4, 0.35),
    "Leather": ("5E3823", "4A2A1A", "331C11", 0.85, 0.0),
    "Bore": ("1A1A1A", "121212", "0A0A0A", 1.0, 0.0),
}
TONES = ("Light", "", "Dark")
MAT_NAMES = [f"{base}_{tone}" if tone else base for base in PALETTE for tone in TONES]
MAT = {name: i for i, name in enumerate(MAT_NAMES)}

BARREL_R = 0.041


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
            mats.append(m)
    return mats


bm = bmesh.new()
_rng = random.Random(7)


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
    # Красим до фаски: фаска пересоздаёт грани, и новые наследуют материал старых
    _paint(faces, base)
    if bevel > 0.0:
        edges = list({e for f in faces for e in f.edges})
        res = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
        _paint(res.get("faces", []), base)


def section(w, top, bot, n=12, power=2.6):
    """Сечение-«суперэллипс»: прямоугольник со скруглёнными гранёными углами (точки x, z)."""
    hw, zc, hh = w / 2.0, (top + bot) / 2.0, (top - bot) / 2.0
    pts = []
    for k in range(n):
        a = math.tau * (k + 0.5) / n
        c, s = math.cos(a), math.sin(a)
        pts.append((hw * math.copysign(abs(c) ** (2.0 / power), c), zc + hh * math.copysign(abs(s) ** (2.0 / power), s)))
    return pts


def loft(sections, base, bevel=0.0, cap=True):
    """Протянуть сечения вдоль Y: sections — список (y, [(x, z), ...]) с одинаковым числом точек."""
    rings = [[bm.verts.new((x, y, z)) for x, z in pts] for y, pts in sections]
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
    if cap:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    _finish([v for r in rings for v in r], base, bevel)


def lathe(profile, base, segments=12, center=(0.0, 0.0), bores=()):
    """Тело вращения вокруг оси Y; profile — (y, r); участки из bores красятся как канал ствола."""
    rings = []
    for y, r in profile:
        if r <= 0.0:
            rings.append([bm.verts.new((center[0], y, center[1]))])
        else:
            rings.append([bm.verts.new((center[0] + r * math.cos(math.tau * (k + 0.5) / segments), y,
                                         center[1] + r * math.sin(math.tau * (k + 0.5) / segments)))
                          for k in range(segments)])
    groups = {}
    for i, (r0, r1) in enumerate(zip(rings, rings[1:])):
        faces = []
        for k in range(segments):
            k2 = (k + 1) % segments
            if len(r0) == 1:
                faces.append(bm.faces.new((r0[0], r1[k2], r1[k])))
            elif len(r1) == 1:
                faces.append(bm.faces.new((r0[k], r0[k2], r1[0])))
            else:
                faces.append(bm.faces.new((r0[k], r0[k2], r1[k2], r1[k])))
        groups.setdefault("Bore" if i in bores else base, []).extend(faces)
    allf = [f for fs in groups.values() for f in fs]
    bmesh.ops.recalc_face_normals(bm, faces=allf)
    for mat, faces in groups.items():
        _paint(faces, mat)


def box(center, size, base, bevel=0.0, rot=None):
    res = bmesh.ops.create_cube(bm, size=1.0)
    xf = Matrix.Translation(center) @ (rot.to_4x4() if rot else Matrix.Identity(4)) @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.transform(bm, matrix=xf, verts=res["verts"])
    _finish(res["verts"], base, bevel)


def plate(points_yz, x0, x1, base, bevel=0.0):
    """Плоская деталь (контур в плоскости Y-Z), выдавленная по X."""
    a = [bm.verts.new((x0, y, z)) for y, z in points_yz]
    b = [bm.verts.new((x1, y, z)) for y, z in points_yz]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(points_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    _finish(a + b, base, bevel)


def strip(points_yz, width, thick_x, base, x=0.0):
    """Полоса по ломаной в плоскости Y-Z (скоба спуска, курок): брусок на каждом отрезке."""
    for (y0, z0), (y1, z1) in zip(points_yz, points_yz[1:]):
        d = Vector((0, y1 - y0, z1 - z0))
        mid = Vector((x, (y0 + y1) / 2, (z0 + z1) / 2))
        rot = Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix()
        box(mid, (thick_x, d.length + width * 0.9, width), base, bevel=0.0015, rot=rot)


def rivet(pos, normal, radius, base):
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    z = Vector(normal).normalized()
    x = z.cross(Vector((0, 1, 0)) if abs(z.y) < 0.9 else Vector((1, 0, 0))).normalized()
    basis = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(pos) @ basis @ Matrix.Diagonal((1, 1, 0.6, 1)), verts=res["verts"])
    _finish(res["verts"], base)


# --- ствол и раструб (тёмное железо, полый раструб) -------------------------------------------

BARREL_PROFILE = [
    (-0.07, 0.0), (-0.07, 0.036), (-0.05, BARREL_R), (0.355, BARREL_R + 0.002),
    (0.40, 0.05), (0.445, 0.061), (0.485, 0.076), (0.508, 0.087), (0.522, 0.093),   # раструб
    (0.528, 0.093), (0.531, 0.087),                                                  # кромка
    (0.531, 0.078), (0.505, 0.067), (0.465, 0.053), (0.43, 0.036), (0.415, 0.0),      # канал
]
lathe(BARREL_PROFILE, "Iron", segments=12, bores=set(range(11, 15)))

# --- деревянное цевьё: обнимает нижнюю половину ствола ---------------------------------------

FORE = [(y, section(0.1, 0.01, -0.054)) for y in (0.335, 0.2, 0.05, -0.055)]
loft(FORE, "Wood", bevel=0.003)

# --- ложе и приклад -------------------------------------------------------------------------

STOCK = [
    (-0.052, section(0.098, 0.013, -0.052)),
    (-0.095, section(0.088, 0.013, -0.086)),    # «брюшко» под спуском
    (-0.135, section(0.066, 0.018, -0.064)),    # шейка
    (-0.215, section(0.062, 0.021, -0.058)),
    (-0.275, section(0.076, 0.021, -0.088)),
    (-0.4, section(0.09, 0.019, -0.135)),
    (-0.432, section(0.092, 0.017, -0.142)),    # торец приклада
]
loft(STOCK, "Wood", bevel=0.003)

# Кожаная обмотка шейки: витки внахлёст с наклоном
for k in range(6):
    y = -0.142 + k * 0.0135
    tilt = 0.2 if k % 2 else -0.2
    pts = section(0.072, 0.026, -0.069)
    rot = Matrix.Rotation(tilt, 3, "X")
    sec0 = [(rot @ Vector((x, -0.008, z)))[:] for x, z in pts]
    sec1 = [(rot @ Vector((x, 0.008, z)))[:] for x, z in pts]
    rings = [[bm.verts.new((v[0], v[1] + y, v[2])) for v in sec] for sec in (sec0, sec1)]
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[1])))
    _finish(rings[0] + rings[1], "Leather", bevel=0.002)

# Латунная оковка у торца приклада
loft([(-0.398, section(0.097, 0.024, -0.141)), (-0.418, section(0.098, 0.023, -0.146))], "Brass", bevel=0.002)

# --- кольца: латунное у раструба и железное посередине, с заклёпками --------------------------

def surface_point(w, top, bot, z, power, side):
    """Точка на боку сечения-суперэллипса на высоте z (чтобы заклёпка сидела вплотную)."""
    hw, zc, hh = w / 2.0, (top + bot) / 2.0, (top - bot) / 2.0
    t = min(abs((z - zc) / hh), 0.999)
    x = hw * (1.0 - t ** power) ** (1.0 / power)
    return Vector((side * x, 0.0, z))


RINGS = [  # (y0, y1, ширина, верх, низ, форма, металл кольца, металл заклёпок)
    (0.322, 0.36, 0.11, BARREL_R + 0.013, -0.062, 2.2, "Brass", "Iron"),
    (0.155, 0.188, 0.108, BARREL_R + 0.009, -0.06, 2.4, "Iron", "Brass"),
]
for y0, y1, w, top, bot, pw, mat, rivet_mat in RINGS:
    loft([(y0, section(w, top, bot, n=12, power=pw)), (y1, section(w, top, bot, n=12, power=pw))], mat, bevel=0.003)
    ym = (y0 + y1) / 2
    for side in (-1.0, 1.0):
        for z in (top - 0.016, bot + 0.016):
            p = surface_point(w, top, bot, z, pw, side)
            rivet(Vector((p.x, ym, p.z)), Vector((side, 0, 0)), 0.0065, rivet_mat)
    rivet(Vector((0, ym, top)), Vector((0, 0, 1)), 0.0065, rivet_mat)

# --- замок на левом боку (-X): латунная доска, болт, курок, огниво ------------------------------

LOCK_X = -0.049
plate([(0.135, 0.0), (0.105, 0.021), (-0.025, 0.023), (-0.058, 0.002), (-0.03, -0.021), (0.105, -0.019)],
      LOCK_X, LOCK_X - 0.007, "Brass", bevel=0.002)
# Курок — цельная S-образная полоса от болта вверх с губками на конце; огниво с полкой
COCK_X = LOCK_X - 0.012
strip([(0.03, 0.006), (0.014, 0.03), (0.016, 0.055), (0.03, 0.075), (0.05, 0.082)], 0.014, 0.01, "Brass", x=COCK_X)
box((COCK_X, 0.05, 0.076), (0.012, 0.012, 0.014), "Iron", bevel=0.002)   # кремень в губках
strip([(0.075, 0.012), (0.078, 0.045), (0.07, 0.062)], 0.012, 0.008, "Brass", x=LOCK_X - 0.006)
box((LOCK_X - 0.004, 0.075, 0.02), (0.016, 0.03, 0.006), "Brass", bevel=0.0015)
# Хвост ствола на шейке
box((0, -0.08, 0.014), (0.03, 0.06, 0.006), "Iron", bevel=0.0015)

# --- скоба и спуск ---------------------------------------------------------------------------

strip([(0.055, -0.05), (0.04, -0.077), (0.012, -0.09), (-0.05, -0.09), (-0.078, -0.07), (-0.088, -0.074)],
      0.009, 0.011, "Iron")
box((0, -0.012, -0.058), (0.006, 0.008, 0.03), "Brass", bevel=0.0015, rot=Matrix.Rotation(0.4, 3, "X"))

# --- мушка и целик ---------------------------------------------------------------------------

box((0, 0.465, 0.074), (0.006, 0.018, 0.016), "Iron", bevel=0.0015)
box((0, -0.04, BARREL_R + 0.004), (0.022, 0.01, 0.014), "Iron", bevel=0.0015)


# --- сборка, экспорт, превью ----------------------------------------------------------------

def bolt():
    """Круглый болт замка — поперечный цилиндр на латунной доске."""
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.011, radius2=0.009, depth=0.008)
    xf = Matrix.Translation((LOCK_X - 0.011, 0.035, 0.0)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    bmesh.ops.transform(bm, matrix=xf, verts=res["verts"])
    _finish(res["verts"], "Iron", 0.0015)


def look_at(obj, loc, target, up=(0, 0, 1)):
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(Vector(up)).normalized()
    u = r.cross(f)
    obj.matrix_world = Matrix((r, u, -f)).transposed().to_4x4()
    obj.location = loc


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    mats = make_materials()
    bolt()
    mesh = bpy.data.meshes.new("Blunderbuss")
    bm.to_mesh(mesh)
    for m in mats:
        mesh.materials.append(m)
    gun = bpy.data.objects.new("Blunderbuss", mesh)
    bpy.context.scene.collection.objects.link(gun)
    for name, loc in {"Muzzle": (0, 0.531, 0.0), "Grip_Right": (0, -0.175, -0.02), "Grip_Left": (0, 0.25, -0.05)}.items():
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
    center = (0, 0.05, -0.03)
    views = {
        "1_side_left": ((-1.7, 0.05, -0.03), (0, 0, 1)),     # дуло слева, виден замок — как на референсе
        "2_top": ((0, 0.05, 1.7), (-1, 0, 0)),
        "3_three_quarter": ((-1.05, 0.95, 0.55), (0, 0, 1)),
        "4_side_right": ((1.7, 0.05, -0.03), (0, 0, 1)),
    }
    for name, (loc, up) in views.items():
        cam = bpy.data.objects.new("Cam_" + name, bpy.data.cameras.new("Cam_" + name))
        cam.data.lens = 50
        scene.collection.objects.link(cam)
        look_at(cam, loc, center, up)
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"blunderbuss_{name}.png")
        bpy.ops.render.render(write_still=True)
    # Дуло спереди
    scene.render.resolution_x = 700
    scene.render.resolution_y = 700
    cam = bpy.data.objects.new("Cam_front", bpy.data.cameras.new("Cam_front"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    look_at(cam, (0.15, 1.35, 0.08), (0, 0.4, -0.02))
    scene.camera = cam
    scene.render.filepath = os.path.join(PREVIEW_DIR, "blunderbuss_5_front.png")
    bpy.ops.render.render(write_still=True)
    # От первого лица: камера игрока (вертикальный угол 72°), ружьё справа внизу, дуло к прицелу
    cam = bpy.data.objects.new("Cam_fp", bpy.data.cameras.new("Cam_fp"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(72)
    cam.data.clip_start = 0.02
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam)
    bg.inputs["Color"].default_value = srgb_to_lin("E8C48A")
    old = gun.matrix_world.copy()
    # Как на референсе: ружьё по диагонали из правого нижнего угла, виден левый бок с замком
    gun.matrix_world = (Matrix.Translation((0.2, 0.42, -0.22)) @ Matrix.Rotation(0.32, 4, "Z")
                        @ Matrix.Rotation(0.12, 4, "X") @ Matrix.Rotation(-0.25, 4, "Y"))
    scene.camera = cam
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.filepath = os.path.join(PREVIEW_DIR, "blunderbuss_6_first_person.png")
    bpy.ops.render.render(write_still=True)
    gun.matrix_world = old


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
