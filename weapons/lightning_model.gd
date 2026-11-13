extends RefCounted
## Электропушка — по листу пользователя, своя модель из простых форм (low-poly): спереди
## «корона» из шести тёмных зубцов вокруг дула, внутри — светящееся голубое ядро, вокруг него
## клетка из стержней с тремя голубыми кольцами; дальше — массивный серый корпус с оранжевыми
## полосами, на боках светящееся табло, сзади конденсатор с голубым окном и оранжевым хомутом;
## сверху ручка для переноски, снизу пистолетная рукоять (оранжевый низ), сзади петля-приклад,
## спереди снизу — рукоять для второй руки. Узлы: Body, Glow (светится — пульсирует при
## стрельбе), Muzzle (дуло). Ствол смотрит в -Z.

const Kit := preload("res://weapons/model_kit.gd")

const GREY := Color(0.43, 0.44, 0.48)
const DARK := Color(0.2, 0.21, 0.24)
const DARKER := Color(0.12, 0.12, 0.14)
const ORANGE := Color(0.95, 0.6, 0.12)
const BLUE := Color(0.35, 0.65, 1.0)
const GLOW := Color(0.25, 0.55, 1.0)
const RIGHT_HAND := [Vector3(0.0, -0.2, 0.05), Vector3(0.0, -0.96, 0.28), 0.024, Vector3(0.7, -0.7, 0.3)]
const LEFT_HAND := [Vector3(-0.02, -0.17, -0.42), Vector3(1.0, 0.0, 0.25), 0.03, Vector3(-0.35, -0.85, 0.4)]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "LightningGun"
	for part in [["Body", _body_mesh()], ["Glow", _glow_mesh()]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = part[1]
		root.add_child(mi)
		mi.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -0.8)
	root.add_child(muzzle)
	muzzle.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


static func _body_mesh() -> ArrayMesh:
	var st := Kit.begin()
	# Корона у дула: шесть тёмных зубцов
	for k in 6:
		var a := TAU * k / 6.0
		var d := Vector3(cos(a), sin(a), 0)
		Kit.bar(st, d * 0.115 + Vector3(0, 0, -0.79), d * 0.12 + Vector3(0, 0, -0.62), 0.07, DARK)
		Kit.box(st, d * 0.155 + Vector3(0, 0, -0.7), Vector3(0.03, 0.03, 0.03), DARKER)
	Kit.tube(st, Vector2.ZERO, -0.66, -0.62, 0.14, 0.14, DARKER, 8, false, false)
	# Клетка из стержней вокруг ядра
	for k in 6:
		var a := TAU * k / 6.0 + PI / 6.0
		Kit.tube(st, Vector2(cos(a), sin(a)) * 0.098, -0.64, -0.3, 0.014, 0.014, DARKER, 6)
	# Кожух за клеткой
	Kit.tube(st, Vector2.ZERO, -0.34, -0.26, 0.135, 0.13, DARK, 8, true, false)
	# Корпус: серый восьмигранник, оранжевые хомуты, тёмная крышка сверху
	Kit.tube(st, Vector2.ZERO, -0.26, 0.1, 0.12, 0.12, GREY, 8, true, false)
	Kit.tube(st, Vector2.ZERO, -0.23, -0.18, 0.127, 0.127, ORANGE, 8, false, false)
	Kit.box(st, Vector3(0, 0.115, -0.08), Vector3(0.12, 0.03, 0.26), DARK)
	# Рамки табло на боках
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * 0.118, 0.01, -0.05), Vector3(0.012, 0.07, 0.15), DARKER)
		# Оранжевый знак-треугольник впереди табло
		Kit.box(st, Vector3(sx * 0.12, 0.01, -0.15), Vector3(0.008, 0.035, 0.035), ORANGE)
	# Конденсатор сзади: тёмная бочка, оранжевый хомут, торец
	Kit.tube(st, Vector2.ZERO, 0.1, 0.3, 0.104, 0.104, DARK, 8, true, false)
	Kit.tube(st, Vector2.ZERO, 0.24, 0.28, 0.11, 0.11, ORANGE, 8, false, false)
	Kit.box(st, Vector3(0, 0, 0.32), Vector3(0.17, 0.17, 0.05), DARKER)
	# Ручка для переноски сверху
	for z in [-0.2, 0.06]:
		Kit.bar(st, Vector3(0, 0.12, z), Vector3(0, 0.23, z), 0.035, DARK)
	Kit.bar(st, Vector3(0, 0.23, -0.24), Vector3(0, 0.23, 0.1), 0.04, DARK)
	Kit.box(st, Vector3(0, 0.23, -0.22), Vector3(0.046, 0.046, 0.035), ORANGE)
	# Пистолетная рукоять (наклон назад) с оранжевым низом, спуск
	Kit.bar(st, Vector3(0, -0.1, 0.02), Vector3(0, -0.29, 0.08), 0.055, DARK)
	Kit.box(st, Vector3(0, -0.3, 0.085), Vector3(0.06, 0.03, 0.065), ORANGE)
	Kit.box(st, Vector3(0, -0.14, -0.04), Vector3(0.016, 0.05, 0.014), ORANGE)
	# Петля-приклад сзади снизу
	Kit.bar(st, Vector3(0, -0.09, 0.2), Vector3(0, -0.2, 0.3), 0.035, DARK)
	Kit.bar(st, Vector3(0, -0.2, 0.3), Vector3(0, -0.12, 0.4), 0.035, DARK)
	Kit.bar(st, Vector3(0, -0.12, 0.4), Vector3(0, -0.03, 0.33), 0.035, DARK)
	# Передняя рукоять под кожухом
	Kit.bar(st, Vector3(0, -0.12, -0.31), Vector3(0, -0.26, -0.29), 0.042, DARK)
	return Kit.commit(st, 0.55)


## Всё, что светится голубым: ядро в клетке, три кольца, табло на боках, окно конденсатора.
static func _glow_mesh() -> ArrayMesh:
	var st := Kit.begin()
	Kit.tube(st, Vector2.ZERO, -0.74, -0.32, 0.06, 0.06, Color(0.75, 0.9, 1.0), 10)
	for z in [-0.58, -0.49, -0.4]:
		Kit.tube(st, Vector2.ZERO, z, z + 0.028, 0.118, 0.118, BLUE, 12, false)
		Kit.ring(st, Vector2.ZERO, z, 0.1, 0.118, BLUE, 12, -1.0)
		Kit.ring(st, Vector2.ZERO, z + 0.028, 0.1, 0.118, BLUE, 12, 1.0)
	for sx in [-1.0, 1.0]:
		for k in 3:
			Kit.box(st, Vector3(sx * 0.125, 0.01, -0.1 + k * 0.045), Vector3(0.006, 0.04, 0.03), BLUE)
	Kit.tube(st, Vector2.ZERO, 0.14, 0.2, 0.107, 0.107, BLUE, 8, false, false)
	return Kit.commit_glow(st, GLOW, 2.2)
