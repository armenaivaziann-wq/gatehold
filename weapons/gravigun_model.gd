extends RefCounted
## Гравипушка — по листу пользователя, своя модель из простых форм (low-poly), массивная: спереди
## толстое кольцо излучателя из двух гранёных ободов с фиолетовым светящимся краем и чёрным
## жерлом; вокруг — четыре клешни из трёх звеньев с фиолетовыми вставками; за кольцом — пакет
## толстых поясов (тёмные и светло-серые, с фиолетовыми полосами и болтами); корпус широкий,
## гранёный, с серыми накладками и фиолетовыми окнами; сверху массивная ручка на опорах; сзади
## ступенчатый тёмный блок; снизу пистолетная рукоять и передняя рукоять. Хват — как у
## электропушки. Узлы: Body, Glow (светится), Muzzle (центр жерла). Ствол смотрит в -Z.

const Kit := preload("res://weapons/model_kit.gd")

const DARK := Color(0.22, 0.21, 0.25)
const DARKER := Color(0.13, 0.12, 0.15)
const GREY := Color(0.62, 0.62, 0.65)
const PURPLE := Color(0.64, 0.32, 1.0)
const GLOW := Color(0.55, 0.25, 1.0)
const HOLE := Color(0.02, 0.01, 0.04)
const RIGHT_HAND := [Vector3(0.0, -0.22, 0.12), Vector3(0.0, -0.93, 0.37), 0.025, Vector3(0.7, -0.7, 0.3)]
const LEFT_HAND := [Vector3(-0.02, -0.215, -0.16), Vector3(1.0, 0.0, 0.25), 0.03, Vector3(-0.35, -0.85, 0.4)]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "Gravigun"
	for part in [["Body", _body_mesh()], ["Glow", _glow_mesh()]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = part[1]
		root.add_child(mi)
		mi.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.0, -0.5)
	root.add_child(muzzle)
	muzzle.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


static func _body_mesh() -> ArrayMesh:
	var st := Kit.begin()
	# Кольцо излучателя: внешний толстый обод и внутренний поуже, чёрное жерло
	Kit.tube(st, Vector2.ZERO, -0.5, -0.38, 0.16, 0.16, DARK, 8, false, false)
	Kit.ring(st, Vector2.ZERO, -0.5, 0.115, 0.16, DARK, 8, -1.0)
	Kit.ring(st, Vector2.ZERO, -0.38, 0.11, 0.16, DARK, 8, 1.0)
	Kit.tube(st, Vector2.ZERO, -0.48, -0.4, 0.115, 0.115, DARKER, 10, false, false)
	Kit.tube(st, Vector2.ZERO, -0.47, -0.4, 0.085, 0.085, HOLE, 10, false, false)
	Kit.ring(st, Vector2.ZERO, -0.4, 0.0, 0.085, HOLE, 10, -1.0)
	# Болты-выступы на ободе (8 штук)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		Kit.box(st, Vector3(cos(a), sin(a), 0) * 0.163 + Vector3(0, 0, -0.44), Vector3(0.03, 0.03, 0.05), DARKER)
	# Клешни: четыре захвата из трёх звеньев, расходятся и загибаются вперёд к центру
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), sin(a), 0)
		var p0: Vector3 = d * 0.15 + Vector3(0, 0, -0.42)
		var p1: Vector3 = d * 0.25 + Vector3(0, 0, -0.5)
		var p2: Vector3 = d * 0.25 + Vector3(0, 0, -0.62)
		var p3: Vector3 = d * 0.17 + Vector3(0, 0, -0.7)
		Kit.bar(st, p0, p1, 0.065, DARK)
		Kit.box(st, p1, Vector3(0.075, 0.075, 0.075), DARKER)
		Kit.bar(st, p1, p2, 0.06, DARK)
		Kit.box(st, p2, Vector3(0.07, 0.07, 0.07), DARKER)
		Kit.bar(st, p2, p3, 0.055, DARK)
		Kit.box(st, p3, Vector3(0.06, 0.06, 0.06), DARKER)
	# Пакет поясов за кольцом
	Kit.tube(st, Vector2.ZERO, -0.38, -0.33, 0.125, 0.125, DARK, 8, false, false)
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.13, 0.13, -0.33, -0.23, 0.04, GREY)
	Kit.tube(st, Vector2.ZERO, -0.23, -0.19, 0.12, 0.12, DARK, 8, false, false)
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.128, 0.128, -0.19, -0.13, 0.04, DARKER)
	for sx in [-1.0, 1.0]:
		for z in [-0.3, -0.26]:
			Kit.box(st, Vector3(sx * 0.132, 0.05, z), Vector3(0.01, 0.02, 0.02), DARKER)
	# Корпус: широкий, гранёный, серые накладки по бокам и сверху
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.12, 0.12, -0.13, 0.22, 0.045, DARK)
	for sx in [-1.0, 1.0]:
		Kit.chamfer_box(st, Vector2(sx * 0.115, -0.04), 0.02, 0.05, -0.02, 0.16, 0.01, GREY)
	Kit.chamfer_box(st, Vector2(0, 0.115), 0.07, 0.02, -0.1, 0.18, 0.01, GREY)
	# Сзади ступенчатый блок
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.13, 0.13, 0.22, 0.3, 0.045, DARKER)
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.11, 0.11, 0.3, 0.38, 0.04, DARK)
	Kit.chamfer_box(st, Vector2(0, 0.0), 0.08, 0.08, 0.38, 0.42, 0.03, DARKER)
	# Ручка сверху: массивные опоры и толстая перекладина
	for z in [-0.08, 0.16]:
		Kit.bar(st, Vector3(0, 0.12, z), Vector3(0, 0.23, z), 0.05, DARKER)
	Kit.bar(st, Vector3(0, 0.23, -0.11), Vector3(0, 0.23, 0.19), 0.055, DARKER)
	# Пистолетная рукоять и спуск, передняя рукоять под корпусом
	Kit.bar(st, Vector3(0, -0.1, 0.08), Vector3(0, -0.31, 0.16), 0.055, DARKER)
	Kit.box(st, Vector3(0, -0.135, 0.03), Vector3(0.016, 0.045, 0.014), GREY)
	Kit.chamfer_box(st, Vector2(0, -0.15), 0.05, 0.05, -0.22, -0.1, 0.015, DARKER)
	return Kit.commit(st, 0.55)


## Светится фиолетовым: край жерла, полосы на поясах, окна корпуса, вставки на клешнях.
static func _glow_mesh() -> ArrayMesh:
	var st := Kit.begin()
	Kit.ring(st, Vector2.ZERO, -0.503, 0.085, 0.112, PURPLE, 10, -1.0)
	Kit.tube(st, Vector2.ZERO, -0.365, -0.345, 0.128, 0.128, PURPLE, 8, false, false)
	Kit.tube(st, Vector2.ZERO, -0.215, -0.2, 0.123, 0.123, PURPLE, 8, false, false)
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * 0.122, 0.05, 0.02), Vector3(0.006, 0.03, 0.14), PURPLE)
		Kit.box(st, Vector3(sx * 0.12, 0.05, 0.27), Vector3(0.006, 0.025, 0.05), PURPLE)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), sin(a), 0)
		Kit.box(st, d * 0.25 + Vector3(0, 0, -0.56), Vector3(0.07, 0.024, 0.06), PURPLE)
		Kit.box(st, d * 0.17 + Vector3(0, 0, -0.7) - d * 0.03, Vector3(0.03, 0.03, 0.03), PURPLE)
	return Kit.commit_glow(st, GLOW, 3.0)
