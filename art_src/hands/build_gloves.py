"""Руки от первого лица в средневековых кожаных перчатках и наручах — для арбалетчика.

Основа — CC0-модель «Low Poly Arms (Rigged)» (DevMops, art_src/hands/vendor): пять настоящих
пальцев на каждой руке и скелет, которым пальцы сгибаются в хват. Скрипт:
  * сгибает пальцы: левая рука поддерживает ложе снизу, правая держит пистолетную рукоять,
    большой палец противопоставлен остальным;
  * утолщает кисть под толстую кожу перчатки; светлые накладки на ладони и тыльной стороне;
  * раструб перчатки, толстый ремешок с железной заклёпкой и пряжкой, крупные стежки;
  * наруч: три кожаных пластины внахлёст (к локтю шире), два ремня с заклёпками и пряжкой.
Кожа нигде не видна. Затенение плоское, гладкое — только на плавных изгибах (по углу).

Объекты: Left_Glove, Right_Glove, Left_Forearm, Right_Forearm (трансформации применены).
У перчатки и наруча одной руки общее начало координат — центр хвата, оси (в Godot):
  +X — ось того, что рука держит (большой палец правой руки смотрит в -X, левой — в +X),
  +Y — тыльная сторона кисти, +Z — к локтю.
Радиус хвата и направление предплечья каждой руки печатаются в конце (нужны для постановки
рук на оружие в Godot).

Сохраняет art_src/hands/gloves.blend (с превью-сценой) и hero/models/gloves.glb,
превью — PNG в папку PREVIEW_DIR: спереди, сбоку, сзади и от первого лица.

Запуск (скрипты внутри .blend не выполняются):
  Blender -b --disable-autoexec art_src/hands/vendor/arms_low_poly.blend --python art_src/hands/build_gloves.py
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

PROJECT = os.environ.get("GATEHOLD_PROJECT", os.getcwd())  # корень проекта Godot
OUT_GLB = os.path.join(PROJECT, "hero/models/gloves.glb")
OUT_BLEND = os.path.join(PROJECT, "art_src/hands/gloves.blend")
PREVIEW_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gatehold_preview", "gloves")

# Модель вдвое крупнее человека: от запястья до кончика среднего пальца 0.34
SCALE = 0.55
# Позы: сгиб фаланг, повороты костей большого пальца (XYZ), отвод кисти.
# wrist > 0 — к большому пальцу, < 0 — к мизинцу.
POSES = {
    # Правая — пистолетная рукоять: плотный кулак, большой палец обхватывает рукоять с другой стороны
    "R": {"curl": (0.9, 0.95, 0.75), "thumb": ((0.0, 0.6, 0.0), (0.0, 0.0, 0.5), (0.0, 0.0, 0.4)), "wrist": 0.0},
    # Левая — снизу под ложем: пальцы обхватывают ложе сбоку, предплечье уходит назад к камере
    "L": {"curl": (0.72, 0.78, 0.58), "thumb": ((0.0, 0.45, 0.0), (0.0, 0.0, 0.35), (0.0, 0.0, 0.3)), "wrist": -0.35},
}
FINGERS = ("f_index", "f_middle", "f_ring", "f_pinky")

# Размеры в единицах модели (до SCALE)
CUT_Y = 0.2            # рука отрезается чуть выше локтя (срез закрыт)
WRIST_Y = -0.392
KNUCKLE_Y = -0.535     # линия костяшек
CUFF_LEN = 0.1         # раструб перчатки
SPLIT = WRIST_Y + CUFF_LEN - 0.01   # граница перчатки и наруча
SPLIT_OVERLAP = 0.04   # основа наруча заходит под раструб, чтобы на стыке не было щели
GLOVE_THICK = 0.009
CUFF_THICK = (0.016, 0.036)
SLEEVE_THICK = (0.010, 0.02)   # основа наруча: у запястья и у локтя (к локтю шире)
FINGER_HALF = 0.03

COLORS = {
    "Leather_DarkBrown": ("493020", 0.85),
    "Leather_LightBrown": ("65452F", 0.8),
    "Stitching_Tan": ("A17A4E", 0.9),
    "Iron_Dark": ("3A3A3E", 0.75),
    "Metal_Worn": ("665B4A", 0.75),
}
DARK, LIGHT, STITCH, IRON, WORN = range(5)

G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def srgb_to_lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def make_materials():
    mats = []
    for name, (hexc, rough) in COLORS.items():
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = srgb_to_lin(hexc)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = 0.6 if name in ("Iron_Dark", "Metal_Worn") else 0.0
        mats.append(m)
    return mats


# --- риг -----------------------------------------------------------------------------------

def prepare():
    """Убрать риг Rigify и посадить меш на простой метариг (у него нет констрейнтов)."""
    arm = bpy.data.objects["Arm"]
    meta = bpy.data.objects["metarig"]
    bpy.data.objects.remove(bpy.data.objects["rig"])
    groups = arm.vertex_groups
    for side in ("L", "R"):
        for bone in ("upper_arm", "forearm"):
            src = groups[f"DEF-{bone}.{side}.001"]
            dst = groups[f"DEF-{bone}.{side}"]
            for v in arm.data.vertices:
                for g in v.groups:
                    if g.group == src.index:
                        dst.add([v.index], g.weight, "ADD")
            groups.remove(src)
    for b in meta.data.bones:
        b.name = "DEF-" + b.name
    for mod in arm.modifiers:
        if mod.type == "ARMATURE":
            mod.object = meta
    arm.parent = None
    meta.data.pose_position = "POSE"
    return arm, meta


def set_pose(meta, side, pose, wrist_sign=1.0):
    pb = meta.pose.bones[f"DEF-hand.{side}"]
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (0, 0, abs(pose["wrist"]) * wrist_sign)
    for f in FINGERS:
        for k, a in enumerate(pose["curl"]):
            b = meta.pose.bones[f"DEF-{f}.0{k + 1}.{side}"]
            b.rotation_mode = "XYZ"
            b.rotation_euler = (a, 0, 0)
    for k, rot in enumerate(pose["thumb"]):
        b = meta.pose.bones[f"DEF-thumb.0{k + 1}.{side}"]
        b.rotation_mode = "XYZ"
        b.rotation_euler = rot
    bpy.context.view_layer.update()


def to_godot(v):
    """Направление в осях модели → оси Godot экспортированной руки."""
    return Vector((-v.x, v.z, v.y))


def hand_rest(meta, side):
    pb = meta.pose.bones[f"DEF-hand.{side}"]
    return (pb.matrix @ pb.bone.matrix_local.inverted()).inverted()


def forearm_dir(meta, side):
    inv = hand_rest(meta, side)
    pb = meta.pose.bones[f"DEF-forearm.{side}"]
    return to_godot(inv @ pb.head - inv @ pb.tail).normalized()


def circumcenter(a, b, c):
    ab, ac = b - a, c - a
    n = ab.cross(ac)
    return a + (n.cross(ab) * ac.length_squared + ac.cross(n) * ab.length_squared) / (2.0 * n.length_squared)


# --- детали --------------------------------------------------------------------------------

def slice_ellipse(body, y, half=0.03):
    vs = [v for v in body if abs(v.y - y) < half]
    while len(vs) < 6:
        half *= 1.5
        vs = [v for v in body if abs(v.y - y) < half]
    cx = sum(v.x for v in vs) / len(vs)
    cz = sum(v.z for v in vs) / len(vs)
    return cx, cz, max(abs(v.x - cx) for v in vs), max(abs(v.z - cz) for v in vs)


def ring_point(ell, y, angle, grow):
    cx, cz, rx, rz = ell
    p = Vector((cx + (rx + grow) * math.cos(angle), y, cz + (rz + grow) * math.sin(angle)))
    n = Vector((math.cos(angle) / (rx + grow), 0.0, math.sin(angle) / (rz + grow))).normalized()
    return p, n


def band(bm, body, y0, y1, grow0, grow1, mat, segments=12, bevel=0.003):
    """Замкнутая кожаная полоса вокруг руки от y0 до y1; у краёв — фаска.
    grow0/grow1 — насколько полоса выступает над рукой у каждого края (пластины к локтю шире)."""
    e0 = slice_ellipse(body, y0)
    e1 = slice_ellipse(body, y1)
    rings = []
    for ell, y, g in ((e0, y0, -0.004), (e0, y0, grow0), (e1, y1, grow1), (e1, y1, -0.004)):
        rings.append([bm.verts.new(ring_point(ell, y, math.tau * j / segments, g)[0]) for j in range(segments)])
    faces = []
    for k in range(4):
        r0, r1 = rings[k], rings[(k + 1) % 4]
        for j in range(segments):
            j2 = (j + 1) % segments
            f = bm.faces.new((r0[j], r1[j], r1[j2], r0[j2]))
            f.material_index = mat
            faces.append(f)
    if bevel > 0.0:
        # Фаска по двум внешним кольцевым рёбрам
        ring_edges = [e for e in bm.edges if (e.verts[0] in rings[1] and e.verts[1] in rings[1]) or
                      (e.verts[0] in rings[2] and e.verts[1] in rings[2])]
        bmesh.ops.bevel(bm, geom=ring_edges, offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    return e0, e1


def rivet(bm, pos, normal, radius, mat):
    """Заклёпка: приплюснутая полусфера, чуть утопленная в поверхность."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    z = normal.normalized()
    x = z.cross(Vector((0, 1, 0)) if abs(z.y) < 0.9 else Vector((1, 0, 0))).normalized()
    y = z.cross(x)
    basis = Matrix((x, y, z)).transposed().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(pos) @ basis @ Matrix.Diagonal((1, 1, 0.55, 1)), verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mat


def block(bm, pos, along, normal, size, mat):
    """Брусок на поверхности: стежок, пряжка."""
    z = normal.normalized()
    y = (along - z * along.dot(z)).normalized()
    x = y.cross(z)
    basis = Matrix((x, y, z)).transposed().to_4x4()
    res = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(pos + z * size[2] * 0.2) @ basis @ Matrix.Diagonal((*size, 1.0)),
                        verts=res["verts"])
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.material_index = mat


def stitch(bm, pos, along, normal):
    block(bm, pos, along, normal, (0.009, 0.026, 0.008), STITCH)


def surface_hit(tree, p):
    hit = tree.ray_cast(Vector((p.x, p.y, p.z + 0.3)), Vector((0, 0, -1)))
    return hit[0], hit[1]


def dress(bm, meta, side):
    """Толщина кожи, раскраска граней и все детали перчатки и наруча (оси модели)."""
    bm.normal_update()
    cuff_end = WRIST_Y + CUFF_LEN
    for v in bm.verts:
        y = v.co.y
        if y < WRIST_Y - 0.01:
            off = GLOVE_THICK
        elif y < cuff_end:
            t = max((y - WRIST_Y) / CUFF_LEN, 0.0)
            off = CUFF_THICK[0] + (CUFF_THICK[1] - CUFF_THICK[0]) * t
        else:
            t = min(max((y - cuff_end) / (CUT_Y - cuff_end), 0.0), 1.0)
            off = SLEEVE_THICK[0] + (SLEEVE_THICK[1] - SLEEVE_THICK[0]) * t
        v.co += v.normal * off
    bm.normal_update()
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y < WRIST_Y - 0.005:
            # Накладки: тыльная сторона и ладонь между запястьем и костяшками — светлая кожа
            panel = KNUCKLE_Y + 0.015 < c.y and abs(f.normal.z) > 0.55
            f.material_index = LIGHT if panel else DARK
        elif c.y > cuff_end - 0.025 and c.y < cuff_end:
            f.material_index = LIGHT   # кант раструба
        else:
            f.material_index = DARK
    tree = BVHTree.FromBMesh(bm)
    # Сечения берём только по предплечью: вершины кисти при отводе кисти сдвинуты
    body = [v.co.copy() for v in bm.verts if v.co.y > WRIST_Y + 0.015]
    outer = 0.0 if side == "L" else math.pi   # наружная сторона руки (L — в +X модели, R — в -X)
    top = math.pi / 2
    bottom = -math.pi / 2

    # Сначала все полосы: ремешок раструба, три пластины наруча внахлёст (к локтю шире), два ремня
    ys = WRIST_Y + 0.04
    band(bm, body, ys - 0.016, ys + 0.016, 0.012, 0.012, DARK)
    plate_len = 0.18
    starts = [SPLIT + 0.003 + k * 0.145 for k in range(3)]
    plates = []
    for k, y0 in enumerate(starts):
        # Последняя пластина кончается до среза — торец руки ровный, не «труба»
        y1 = min(y0 + plate_len, CUT_Y - 0.08)
        band(bm, body, y0, y1, 0.008, 0.024, LIGHT if k != 1 else DARK, segments=12, bevel=0.004)
        plates.append((y0, y1))
    straps = (starts[0] + 0.09, starts[2] + 0.07)
    for ym in straps:
        band(bm, body, ym - 0.02, ym + 0.02, 0.034, 0.036, DARK, bevel=0.003)

    # Детали сажаем лучом на готовую поверхность — всегда вплотную, без зазоров
    surface = BVHTree.FromBMesh(bm)

    def attach(y, angle):
        cx, cz, _, _ = slice_ellipse(body, y)
        d = Vector((math.cos(angle), 0.0, math.sin(angle)))
        hit = surface.ray_cast(Vector((cx, y, cz)) + d * 0.6, -d)
        return hit[0], hit[1]

    def tangent(angle):
        return Vector((-math.sin(angle), 0.0, math.cos(angle)))

    # Ремешок раструба: заклёпки сверху и снизу, пряжка снаружи
    for a in (top - 0.5, top + 0.5, bottom - 0.5, bottom + 0.5):
        p, n = attach(ys, a)
        if p is not None:
            rivet(bm, p, n, 0.011, IRON)
    p, n = attach(ys, outer)
    if p is not None:
        block(bm, p, Vector((0, 1, 0)), n, (0.026, 0.04, 0.012), WORN)
    # Стежки по кромке раструба — по кругу
    for k in range(12):
        a = math.tau * (k + 0.5) / 12
        if abs(math.cos(a - outer)) > 0.9:
            continue   # снаружи — пряжка
        p, n = attach(WRIST_Y + CUFF_LEN - 0.012, a)
        if p is not None:
            stitch(bm, p, tangent(a), n)
    # Стежки у края каждой пластины — сверху и снизу
    for y0, y1 in plates:
        for a0 in (top, bottom):
            for j in range(3):
                a = a0 + (j - 1) * 0.42
                p, n = attach(y1 - 0.03, a)
                if p is not None:
                    stitch(bm, p, tangent(a), n)
    # Ремни: по четыре заклёпки, на первом — пряжка
    for k, ym in enumerate(straps):
        for a in (top - 0.55, top + 0.55, bottom - 0.55, bottom + 0.55):
            p, n = attach(ym, a)
            if p is not None:
                rivet(bm, p, n, 0.012, IRON)
        if k == 0:
            p, n = attach(ym, outer)
            if p is not None:
                block(bm, p, Vector((0, 1, 0)), n, (0.03, 0.05, 0.014), WORN)

    # Тыльная накладка: стежки от запястья к костяшкам и две заклёпки у запястья
    wrist = meta.pose.bones[f"DEF-hand.{side}"].head
    for f in ("f_index", "f_middle", "f_ring"):
        knuckle = meta.pose.bones[f"DEF-{f}.01.{side}"].head
        for k in range(3):
            q = wrist.lerp(knuckle, 0.25 + 0.2 * k)
            hp, hn = surface_hit(tree, q)
            if hp is not None:
                stitch(bm, hp, knuckle - wrist, hn)
    for f in ("f_index", "f_pinky"):
        knuckle = meta.pose.bones[f"DEF-{f}.01.{side}"].head
        hp, hn = surface_hit(tree, wrist.lerp(knuckle, 0.12))
        if hp is not None:
            rivet(bm, hp, hn, 0.01, IRON)


# --- сборка руки ---------------------------------------------------------------------------

def bake_side(arm, meta, side, mats):
    pose = POSES[side]
    set_pose(meta, side, pose)
    # Отвод кисти: знак подбирается так, чтобы кисть ушла к нужному пальцу
    if pose["wrist"]:
        thumb = -1.0 if side == "R" else 1.0
        want = thumb if pose["wrist"] > 0 else -thumb
        if forearm_dir(meta, side).x * want < 0.0:
            set_pose(meta, side, pose, -1.0)
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(arm.evaluated_get(dg))
    sign = -1.0 if side == "R" else 1.0
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.x * sign < 0.05 or v.co.y > CUT_Y], context="VERTS")
    base = bm.faces.layers.int.new("base")
    for f in bm.faces:
        f.material_index = DARK
        f[base] = 1
    dress(bm, meta, side)

    # Центр хвата — центр изгиба среднего пальца; кисть возвращаем в положение покоя
    inv = hand_rest(meta, side)
    pb = meta.pose.bones
    k1 = inv @ pb[f"DEF-f_middle.01.{side}"].head
    k2 = inv @ pb[f"DEF-f_middle.02.{side}"].head
    k3 = inv @ pb[f"DEF-f_middle.03.{side}"].tail
    center = circumcenter(k1, k2, k3)
    radius = ((k1 - center).length + (k3 - center).length) / 2 - FINGER_HALF - GLOVE_THICK
    xf = Matrix.Diagonal((SCALE, SCALE, SCALE, 1)) @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation(-center) @ inv

    # Перчатка (кисть и раструб) и наруч — отдельные объекты; наруч заходит под раструб
    parts = {}
    for name, keep in (("Glove", lambda y: y < SPLIT), ("Forearm", lambda y: y >= SPLIT - SPLIT_OVERLAP)):
        part = bm.copy()
        layer = part.faces.layers.int["base"]
        # Руку режем по граням; детали (ремни, стежки, заклёпки) — целиком, по их центру
        drop = [f for f in part.faces if f[layer] == 1 and not keep(f.calc_center_median().y)]
        for island in _islands([f for f in part.faces if f[layer] == 0]):
            center = sum((f.calc_center_median() for f in island), Vector()) / len(island)
            if not keep(center.y):
                drop.extend(island)
        bmesh.ops.delete(part, geom=drop, context="FACES")
        bmesh.ops.delete(part, geom=[v for v in part.verts if not v.link_faces], context="VERTS")
        cap = bmesh.ops.holes_fill(part, edges=[e for e in part.edges if e.is_boundary], sides=0)
        for f in cap["faces"]:
            f.material_index = DARK
        bmesh.ops.transform(part, matrix=xf, verts=part.verts)
        bmesh.ops.recalc_face_normals(part, faces=part.faces)
        m = bpy.data.meshes.new(("Left_" if side == "L" else "Right_") + name)
        part.to_mesh(m)
        part.free()
        for mat in mats:
            m.materials.append(mat)
        m.shade_smooth()
        # Гладко только на плавных изгибах, острые рёбра пластин и пальцев — гранями
        if hasattr(m, "set_sharp_from_angle"):
            m.set_sharp_from_angle(angle=math.radians(38))
        obj = bpy.data.objects.new(m.name, m)
        parts[name] = obj
    bm.free()
    return parts, radius * SCALE, forearm_dir(meta, side)


def _islands(faces):
    """Связные куски из граней (соседство по рёбрам)."""
    todo = set(faces)
    out = []
    while todo:
        seed = todo.pop()
        island = [seed]
        stack = [seed]
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g in todo:
                        todo.remove(g)
                        island.append(g)
                        stack.append(g)
        out.append(island)
    return out


# --- превью ---------------------------------------------------------------------------------

def place_basis(axis, elbow, forearm):
    """Как Hands.place в Godot: X руки — по оси хвата, предплечье — к локтю (оси Godot)."""
    x = Vector(axis).normalized()
    f_perp = Vector((0.0, forearm.y, forearm.z)).normalized()
    local = Matrix((Vector((1, 0, 0)), f_perp, Vector((1, 0, 0)).cross(f_perp))).transposed()
    e = Vector(elbow)
    e_perp = (e - x * x.dot(e)).normalized()
    target = Matrix((x, e_perp, x.cross(e_perp))).transposed()
    return target @ local.inverted()


def godot_to_blender(basis, origin):
    m = basis.to_4x4()
    m.translation = Vector(origin)
    return G2B @ m @ G2B.inverted()


def build_preview(objs, info, gloves):
    scene = bpy.context.scene
    # Исходные руки стоят в начале координат — на превью их заменяют копии
    gloves.hide_render = True
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("PreviewWorld")
    world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb_to_lin("D4D4D4")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world
    coll = bpy.data.collections.new("Preview")
    scene.collection.children.link(coll)
    for name, energy, rot, color in (("Key", 3.2, (50, -20, 35), (1.0, 0.95, 0.88)), ("Fill", 1.0, (-40, 30, -140), (0.85, 0.9, 1.0))):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
        light.data.energy = energy
        light.data.color = color
        light.rotation_euler = tuple(math.radians(a) for a in rot)
        coll.objects.link(light)
    # Разворот: обе руки рядом (оси экспорта), камеры спереди, сбоку, сзади
    turn = bpy.data.collections.new("Preview_Turnaround")
    fp = bpy.data.collections.new("Preview_FirstPerson")
    coll.children.link(turn)
    coll.children.link(fp)
    for obj in objs.values():
        dup = obj.copy()
        dup.location.x += 0.16 if obj.name.startswith("Right") else -0.16
        turn.objects.link(dup)
    # От первого лица: руки держат воображаемый арбалет (оси камеры Godot)
    poses = {
        "L": {"at": (0.03, -0.17, -0.6), "axis": (0.1, 0.03, -1.0), "elbow": (-0.7, -0.6, 0.4)},
        "R": {"at": (0.16, -0.22, -0.36), "axis": (0.0, -0.95, 0.3), "elbow": (0.7, -0.5, 0.5)},
    }
    for side, p in poses.items():
        radius, forearm = info[side]
        mw = godot_to_blender(place_basis(p["axis"], p["elbow"], forearm), p["at"])
        prefix = "Left_" if side == "L" else "Right_"
        for part in ("Glove", "Forearm"):
            dup = objs[prefix + part].copy()
            dup.matrix_world = mw
            fp.objects.link(dup)
    cams = {
        "1_front": ((0, 0.75, 0.05), (90, 0, 180), 35, turn),
        "2_side": ((0.85, 0.05, 0.05), (90, 0, 90), 35, turn),
        "3_back": ((0, -0.95, 0.35), (70, 0, 0), 35, turn),
        "4_first_person": ((0, 0, 0), (90, 0, 0), None, fp),
    }
    for name, (loc, rot, lens, show) in cams.items():
        cam = bpy.data.objects.new("Cam_" + name, bpy.data.cameras.new("Cam_" + name))
        cam.location = loc
        cam.rotation_euler = tuple(math.radians(a) for a in rot)
        if lens is None:
            cam.data.sensor_fit = "VERTICAL"
            cam.data.angle_y = math.radians(72)
            cam.data.clip_start = 0.02
        else:
            cam.data.lens = lens
        coll.objects.link(cam)
        turn.hide_render = show is not turn
        fp.hide_render = show is not fp
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"gloves_{name}.png")
        bpy.ops.render.render(write_still=True)
    turn.hide_render = False
    fp.hide_render = True
    gloves.hide_render = False


# --- запуск ---------------------------------------------------------------------------------

os.makedirs(PREVIEW_DIR, exist_ok=True)
mats = make_materials()
arm, meta = prepare()
objs, info = {}, {}
for side in ("L", "R"):
    parts, radius, forearm = bake_side(arm, meta, side, mats)
    prefix = "Left_" if side == "L" else "Right_"
    for name, obj in parts.items():
        objs[prefix + name] = obj
    info[side] = (radius, forearm)
# Чистая сцена: только готовые руки
keep = set(objs.values())
for o in list(bpy.data.objects):
    if o not in keep:
        bpy.data.objects.remove(o)
gloves = bpy.data.collections.new("Gloves")
bpy.context.scene.collection.children.link(gloves)
for name in ("Left_Glove", "Left_Forearm", "Right_Glove", "Right_Forearm"):
    gloves.objects.link(objs[name])

# Проверки геометрии
report = []
for name, obj in objs.items():
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    open_list = [e for e in bm.edges if e.is_boundary]
    open_edges = len(open_list)
    for e in open_list:
        print("OPEN", name, tuple(round(c, 3) for c in (e.verts[0].co + e.verts[1].co) / 2), len(e.link_faces))
    nonmanifold = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    print("NONMANIFOLD", name, nonmanifold)
    report.append(f"{name}: verts {len(bm.verts)}, tris {sum(len(f.verts) - 2 for f in bm.faces)}, open edges {open_edges}, "
                  f"size {tuple(round(d, 3) for d in obj.dimensions)}")
    bm.free()

# Экспорт только рук (превью-сцена в glb не попадает)
for o in bpy.data.objects:
    o.select_set(o.name in objs)
os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True)
build_preview(objs, info, gloves)
# Без резервной копии .blend1 рядом
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for line in report:
    print("CHECK", line)
for side, (radius, forearm) in info.items():
    print("POSE", side, "radius", round(radius, 4), "forearm", tuple(round(c, 3) for c in forearm))
print("EXPORTED", OUT_GLB, OUT_BLEND)
