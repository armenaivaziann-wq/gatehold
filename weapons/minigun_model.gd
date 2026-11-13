extends RefCounted
## Шестиствольный миниган — по концепту пользователя, своя модель из простых форм (low-poly):
## спереди блок из шести стволов с толстым дульным кольцом и средним кольцом, за ними жёлтый
## хомут; большой оливковый короб со скошенными рёбрами, тёмным низом и жёлтыми метками; сверху
## ручка для переноски; на заднем верху короба — поперечная ручка (за неё сверху держит правая
## рука). Слева из жёлтого хомута торчит короткая перекладина — за неё держит левая рука. Узлы: Body, Barrels (крутится вокруг Z), Muzzle (дуло). Ствол смотрит в -Z.

const Kit := preload("res://weapons/model_kit.gd")

const OLIVE := Color(0.38, 0.42, 0.22)
const DARK := Color(0.16, 0.16, 0.17)
const METAL := Color(0.27, 0.28, 0.3)
const BARREL := Color(0.22, 0.22, 0.24)
const YELLOW := Color(0.96, 0.66, 0.12)
const HOLE := Color(0.03, 0.03, 0.03)
const BARREL_R := 0.078           # радиус окружности, по которой стоят стволы
const COLLAR_Z := -0.27          # жёлтый хомут
## Боковая перекладина слева у хомута (левая рука) и задняя рукоять (правая рука): точки хвата
## для рук (как в weapon.gd: точка, ось хвата, радиус, куда уходит локоть).
const SIDE_DIR := Vector3(-0.9, 0.0, -0.44)
const SIDE_LEN := 0.26
const SIDE_GRIP := Vector3(-0.14, 0.0, COLLAR_Z) + SIDE_DIR * 0.18
## Задняя ручка сверху: центр перекладины (поперёк ствола) и её полудлина.
const REAR_GRIP := Vector3(0.06, 0.27, 0.19)
const REAR_HALF := 0.1
const REAR_DIR := Vector3(0.91, 0.0, -0.42)
const LEFT_HAND := [SIDE_GRIP, -SIDE_DIR, 0.025, Vector3(-0.25, -0.6, 0.85), 1.15]
const RIGHT_HAND := [REAR_GRIP, REAR_DIR, 0.024, Vector3(0.57, -0.50, 0.66), 1.0]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "Minigun"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh()
	root.add_child(body)
	body.owner = root
	var barrels := MeshInstance3D.new()
	barrels.name = "Barrels"
	barrels.mesh = _barrels_mesh()
	root.add_child(barrels)
	barrels.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -0.84)
	root.add_child(muzzle)
	muzzle.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


## Блок стволов: шесть стволов вокруг оси, толстое дульное кольцо с каналами, среднее и заднее
## кольца — всё крутится вместе.
static func _barrels_mesh() -> ArrayMesh:
	var st := Kit.begin()
	for k in 6:
		var a := TAU * k / 6.0 + PI / 6.0
		var c := Vector2(cos(a), sin(a)) * BARREL_R
		Kit.tube(st, c, -0.83, COLLAR_Z, 0.023, 0.023, BARREL, 10)
		Kit.ring(st, c, -0.841, 0.0, 0.015, HOLE, 10)
	Kit.tube(st, Vector2.ZERO, -0.8, COLLAR_Z, 0.035, 0.035, DARK, 10)
	Kit.ring(st, Vector2.ZERO, -0.835, 0.0, 0.02, HOLE, 10)
	# Дульное кольцо — толстое, гранёное; среднее и заднее — тоньше
	for z in [[-0.84, -0.77, 0.125], [-0.56, -0.52, 0.112], [-0.37, -0.33, 0.112]]:
		Kit.tube(st, Vector2.ZERO, z[0], z[1], z[2], z[2], METAL if z[2] < 0.12 else DARK, 10, false, false)
		Kit.ring(st, Vector2.ZERO, z[0], 0.1, z[2], DARK, 10, -1.0)
		Kit.ring(st, Vector2.ZERO, z[1], 0.1, z[2], DARK, 10, 1.0)
	return Kit.commit(st, 0.5)


static func _body_mesh() -> ArrayMesh:
	var st := Kit.begin()
	# Жёлтый хомут вокруг стволов перед коробом и тёмная втулка за ним
	Kit.tube(st, Vector2.ZERO, COLLAR_Z - 0.05, COLLAR_Z + 0.05, 0.13, 0.13, YELLOW, 8, true, false)
	Kit.tube(st, Vector2.ZERO, COLLAR_Z + 0.05, -0.16, 0.115, 0.11, DARK, 8, true, false)
	# Короб: большой оливковый, рёбра скошены; тёмное основание снизу
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.15, 0.15, -0.17, 0.27, 0.04, OLIVE)
	Kit.chamfer_box(st, Vector2(0, -0.17), 0.13, 0.03, -0.15, 0.25, 0.015, DARK)
	# Жёлтые метки на боках и тёмные болты по углам
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * 0.151, 0.06, 0.12), Vector3(0.006, 0.02, 0.1), YELLOW)
		Kit.box(st, Vector3(sx * 0.151, -0.09, -0.08), Vector3(0.006, 0.07, 0.035), YELLOW)
		for y in [-0.1, 0.1]:
			for z in [-0.12, 0.22]:
				Kit.box(st, Vector3(sx * 0.152, y, z), Vector3(0.006, 0.014, 0.014), DARK)
	# Тёмная полка над хомутом (связка короба и ручки)
	Kit.chamfer_box(st, Vector2(0, 0.155), 0.08, 0.02, -0.25, -0.1, 0.008, DARK)
	# Ручка для переноски сверху (над передом короба): две стойки и перекладина вдоль ствола
	for z in [-0.14, 0.06]:
		Kit.bar(st, Vector3(0, 0.14, z), Vector3(0, 0.29, z), 0.04, DARK)
	Kit.bar(st, Vector3(0, 0.29, -0.16), Vector3(0, 0.29, 0.08), 0.045, DARK)
	# Задняя ручка сверху (правая рука): тёмный блок-основание на заднем верху короба, из него —
	# стойки и поперечная перекладина, жёлтые торцы; под ней — гашетка
	var rg := REAR_GRIP
	Kit.chamfer_box(st, Vector2(0.03, 0.17), 0.09, 0.025, rg.z - 0.06, rg.z + 0.06, 0.01, DARK)
	# Перекладина развёрнута правым концом вперёд (REAR_DIR) — так правое предплечье уходит назад
	# вправо, к нижнему правому углу кадра, а не торчит вниз
	for end in [-1.0, 1.0]:
		var e: Vector3 = rg + REAR_DIR * REAR_HALF * end
		Kit.bar(st, Vector3(e.x, 0.17, e.z), e, 0.035, DARK)
		Kit.bar(st, e + REAR_DIR * end * 0.005, e + REAR_DIR * end * 0.04, 0.06, YELLOW)
	Kit.bar(st, rg - REAR_DIR * (REAR_HALF + 0.01), rg + REAR_DIR * (REAR_HALF + 0.01), 0.044, DARK)
	Kit.box(st, Vector3(rg.x, rg.y - 0.045, rg.z - 0.02), Vector3(0.025, 0.035, 0.015), METAL)
	# Затылок короба — тёмная плита
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.13, 0.13, 0.27, 0.3, 0.03, DARK)
	# Боковая перекладина слева у хомута (левая рука): кронштейн и рукоять
	# Перекладина смотрит влево и чуть вперёд (SIDE_DIR) — левое предплечье уходит назад влево
	var root := Vector3(-0.14, 0.0, COLLAR_Z)
	Kit.box(st, root, Vector3(0.05, 0.06, 0.06), YELLOW)
	Kit.bar(st, root, root + SIDE_DIR * SIDE_LEN, 0.046, DARK)
	Kit.bar(st, root + SIDE_DIR * SIDE_LEN, root + SIDE_DIR * (SIDE_LEN + 0.025), 0.064, DARK)
	return Kit.commit(st, 0.6)
