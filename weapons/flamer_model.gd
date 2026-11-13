extends RefCounted
## Огнемёт — по листу пользователя, своя модель из простых форм (low-poly): белый корпус с
## тёмными поясами; спереди белый восьмигранный насадок с тёмным жерлом и оранжевыми светящимися
## окнами по бокам и снизу; на боках корпуса — длинная светящаяся оранжевая полоса; сверху тёмная
## ручка для переноски, переходящая сзади в угловой упор; снизу сзади — белая изогнутая петля,
## её передний участок — рукоять (правая рука); под корпусом красный бак (левая рука держит снизу).
## Хват — как у электропушки. Узлы: Body, Glow (светится), Muzzle (жерло). Ствол смотрит в -Z.

const Kit := preload("res://weapons/model_kit.gd")

const WHITE := Color(0.86, 0.86, 0.88)
const DARK := Color(0.2, 0.2, 0.22)
const DARKER := Color(0.12, 0.12, 0.13)
const RED := Color(0.76, 0.15, 0.14)
const ORANGE := Color(1.0, 0.55, 0.1)
const GLOW := Color(1.0, 0.5, 0.08)
const HOLE := Color(0.03, 0.03, 0.03)
const TANK := Vector3(0.0, -0.15, -0.18)   # центр красного бака
const GRIP_TOP := Vector3(0.0, -0.09, 0.04)
const GRIP_BOTTOM := Vector3(0.0, -0.29, 0.12)
## Как у электропушки: правая — на рукояти (большой палец вверх), левая — снизу под баком.
const RIGHT_HAND := [Vector3(0.0, -0.19, 0.08), Vector3(0.0, -0.93, 0.37), 0.025, Vector3(0.7, -0.7, 0.3)]
const LEFT_HAND := [Vector3(-0.02, -0.215, -0.24), Vector3(1.0, 0.0, 0.25), 0.03, Vector3(-0.35, -0.85, 0.4)]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "Flamer"
	for part in [["Body", _body_mesh()], ["Glow", _glow_mesh()]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = part[1]
		root.add_child(mi)
		mi.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.0, -0.63)
	root.add_child(muzzle)
	muzzle.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


static func _body_mesh() -> ArrayMesh:
	var st := Kit.begin()
	# Насадок: белый восьмигранник, тёмное кольцо по краю жерла, чёрное нутро
	Kit.tube(st, Vector2.ZERO, -0.63, -0.5, 0.105, 0.105, WHITE, 8, false, false)
	Kit.ring(st, Vector2.ZERO, -0.63, 0.075, 0.105, WHITE, 8, -1.0)
	Kit.tube(st, Vector2.ZERO, -0.635, -0.6, 0.075, 0.075, DARK, 8, false, false)
	Kit.ring(st, Vector2.ZERO, -0.635, 0.055, 0.075, DARK, 8, -1.0)
	Kit.tube(st, Vector2.ZERO, -0.63, -0.55, 0.055, 0.055, HOLE, 8, false, false)
	Kit.ring(st, Vector2.ZERO, -0.55, 0.0, 0.055, HOLE, 8, -1.0)
	Kit.ring(st, Vector2.ZERO, -0.5, 0.06, 0.105, WHITE, 8, 1.0)
	# Тёмная шейка за насадком
	Kit.tube(st, Vector2.ZERO, -0.5, -0.43, 0.075, 0.075, DARK, 8, false, false)
	# Корпус: белый, рёбра скошены; тёмные пояса спереди и сзади
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.09, 0.085, -0.43, 0.13, 0.03, WHITE)
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.095, 0.09, -0.43, -0.38, 0.03, DARK)
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.095, 0.09, 0.07, 0.13, 0.03, DARK)
	# Тёмные рамки вокруг светящихся полос и болты
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * 0.091, 0.012, -0.19), Vector3(0.008, 0.055, 0.3), DARK)
		Kit.box(st, Vector3(sx * 0.093, 0.06, 0.03), Vector3(0.008, 0.016, 0.016), DARKER)
	# Сзади тёмный блок
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.075, 0.075, 0.13, 0.2, 0.025, DARK)
	# Ручка для переноски сверху и угловой упор сзади (тёмные)
	Kit.bar(st, Vector3(0, 0.08, -0.2), Vector3(0, 0.19, -0.2), 0.035, DARKER)
	Kit.bar(st, Vector3(0, 0.19, -0.22), Vector3(0, 0.19, 0.12), 0.04, DARKER)
	Kit.bar(st, Vector3(0, 0.19, 0.12), Vector3(0, 0.13, 0.2), 0.04, DARKER)
	Kit.bar(st, Vector3(0, 0.13, 0.2), Vector3(0, 0.16, 0.33), 0.04, DARKER)
	Kit.bar(st, Vector3(0, 0.16, 0.33), Vector3(0, 0.08, 0.36), 0.04, DARKER)
	Kit.bar(st, Vector3(0, 0.05, 0.2), Vector3(0, 0.1, 0.33), 0.035, DARKER)
	# Белая петля снизу сзади: от затылка вниз и вперёд, передний участок — рукоять
	Kit.bar(st, Vector3(0, -0.06, 0.19), Vector3(0, -0.24, 0.25), 0.05, WHITE)
	Kit.bar(st, Vector3(0, -0.24, 0.25), GRIP_BOTTOM, 0.05, WHITE)
	Kit.bar(st, GRIP_BOTTOM, GRIP_TOP, 0.052, WHITE)
	Kit.box(st, GRIP_BOTTOM + Vector3(0, -0.012, 0.0), Vector3(0.056, 0.024, 0.06), DARK)
	# Спуск перед рукоятью
	Kit.box(st, Vector3(0, -0.11, 0.0), Vector3(0.014, 0.04, 0.012), DARK)
	# Тёмная планка под корпусом, к ней — бак
	Kit.box(st, Vector3(0, -0.09, TANK.z), Vector3(0.05, 0.03, 0.26), DARK)
	# Красный бак: скошенный, с тёмными хомутами
	Kit.chamfer_box(st, Vector2(TANK.x, TANK.y), 0.075, 0.065, TANK.z - 0.12, TANK.z + 0.11, 0.025, RED)
	for z in [TANK.z - 0.08, TANK.z + 0.07]:
		Kit.chamfer_box(st, Vector2(TANK.x, TANK.y), 0.078, 0.068, z - 0.012, z + 0.012, 0.025, DARK)
	return Kit.commit(st, 0.55)


## Светится оранжевым: окна насадка (по бокам и снизу), длинные полосы на боках корпуса.
static func _glow_mesh() -> ArrayMesh:
	var st := Kit.begin()
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * 0.105, 0.0, -0.565), Vector3(0.008, 0.045, 0.05), ORANGE)
		Kit.box(st, Vector3(sx * 0.095, 0.012, -0.19), Vector3(0.006, 0.035, 0.26), ORANGE)
	for x in [-0.035, 0.0, 0.035]:
		Kit.box(st, Vector3(x, -0.1, -0.565), Vector3(0.022, 0.008, 0.05), ORANGE)
	return Kit.commit_glow(st, GLOW, 3.0)
