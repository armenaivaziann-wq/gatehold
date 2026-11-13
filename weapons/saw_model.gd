extends RefCounted
## Дискомёт — по листу пользователя, своя модель из простых форм (low-poly), массивная: спереди
## открытая пасть — широкая щель между верхней серой и нижней жёлтой челюстями, в ней плашмя
## лежит синий светящийся диск из зубчатых сегментов (узел Disc — крутится) и вылетает вперёд без
## помех; за пастью — серо-жёлтый кожух с тёмными решётками; дальше толстый тёмный пояс с голубым
## окном в рамке и жёлтая вставка с решёткой; сверху ручка; сзади тёмный блок с голубой полосой и
## красной кнопкой, жёлтый торец; снизу пистолетная рукоять и подствольный блок. Хват — как у
## электропушки. Узлы: Body, Glow, Disc, Muzzle (центр диска). Ствол смотрит в -Z.

const Kit := preload("res://weapons/model_kit.gd")

const DARK := Color(0.24, 0.24, 0.28)
const DARKER := Color(0.14, 0.14, 0.17)
const GREY := Color(0.68, 0.68, 0.72)
const YELLOW := Color(0.96, 0.7, 0.14)
const RED := Color(0.85, 0.12, 0.1)
const CYAN := Color(0.35, 0.85, 1.0)
const BLUE := Color(0.2, 0.45, 1.0)
const DISC_Z := -0.47
const HALF := 0.14               # полуширина и полувысота корпуса
const RIGHT_HAND := [Vector3(0.0, -0.22, 0.16), Vector3(0.0, -0.93, 0.37), 0.025, Vector3(0.7, -0.7, 0.3)]
const LEFT_HAND := [Vector3(-0.02, -0.235, -0.12), Vector3(1.0, 0.0, 0.25), 0.03, Vector3(-0.35, -0.85, 0.4)]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "SawGun"
	for part in [["Body", _body_mesh()], ["Glow", _glow_mesh()]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = part[1]
		root.add_child(mi)
		mi.owner = root
	# Диск лежит плашмя в пасти; его меш в плоскости XY — поворачиваем на 90° вокруг X
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = disc_mesh(0.24, 0.15, true)
	disc.position = Vector3(0, 0.0, DISC_Z)
	disc.rotation.x = PI / 2.0
	root.add_child(disc)
	disc.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.0, DISC_Z - 0.2)
	root.add_child(muzzle)
	muzzle.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


## Синий светящийся диск: кольцо из 12 зубчатых сегментов, внутреннее кольцо и голубая ступица
## (в плоскости XY, центр в 0). Его же запускает дискомёт.
## col — цвет сегментов (финалы ветки: «Рой» — оранжевый, «Бумеранг» — зелёный).
static func disc_mesh(r_out := 0.2, r_in := 0.12, inner := false, col := BLUE) -> ArrayMesh:
	var st := Kit.begin()
	if inner:
		Kit.ring(st, Vector2.ZERO, -0.016, r_in * 0.45, r_in * 0.85, col, 16, -1.0)
		Kit.ring(st, Vector2.ZERO, 0.016, r_in * 0.45, r_in * 0.85, col, 16, 1.0)
		Kit.tube(st, Vector2.ZERO, -0.025, 0.025, r_in * 0.3, r_in * 0.3, CYAN, 8)
	var n := 12
	for k in n:
		var a0 := TAU * k / n + 0.04
		var a1 := TAU * (k + 1) / n - 0.04
		var am := lerpf(a0, a1, 0.75)
		var pts := [Vector2.from_angle(a0) * r_in, Vector2.from_angle(a1) * r_in,
			Vector2.from_angle(a1) * r_out * 0.92, Vector2.from_angle(am) * r_out, Vector2.from_angle(a0) * r_out * 0.95]
		for z in [-0.018, 0.018]:
			var nz := Vector3(0, 0, signf(z))
			for t in [[0, 1, 2], [0, 2, 3], [0, 3, 4]]:
				Kit.quad(st, Vector3(pts[t[0]].x, pts[t[0]].y, z), Vector3(pts[t[1]].x, pts[t[1]].y, z),
					Vector3(pts[t[2]].x, pts[t[2]].y, z), Vector3(pts[t[2]].x, pts[t[2]].y, z), col, nz)
		for e in 5:
			var p: Vector2 = pts[e]
			var q: Vector2 = pts[(e + 1) % 5]
			var nn := Vector3((p + q).x, (p + q).y, 0).normalized()
			Kit.quad(st, Vector3(p.x, p.y, -0.018), Vector3(q.x, q.y, -0.018), Vector3(q.x, q.y, 0.018),
				Vector3(p.x, p.y, 0.018), col.lightened(0.15), nn)
	return Kit.commit_glow(st, col, 3.0)


static func _body_mesh() -> ArrayMesh:
	var st := Kit.begin()
	var h := HALF
	# Пасть: верхняя серая и нижняя жёлтая челюсти, между ними открытая щель с диском
	Kit.chamfer_box(st, Vector2(0, 0.085), h, 0.05, -0.62, -0.3, 0.025, GREY)
	Kit.chamfer_box(st, Vector2(0, -0.085), h, 0.05, -0.62, -0.3, 0.025, YELLOW)
	# Тёмные кромки челюстей спереди и сверху/снизу
	Kit.chamfer_box(st, Vector2(0, 0.085), h + 0.005, 0.055, -0.64, -0.6, 0.025, DARKER)
	Kit.chamfer_box(st, Vector2(0, -0.085), h + 0.005, 0.055, -0.64, -0.6, 0.025, DARKER)
	Kit.chamfer_box(st, Vector2(0, 0.14), 0.07, 0.02, -0.58, -0.34, 0.01, DARK)
	# Задняя стенка щели и ось диска (сам диск торчит в стороны и вперёд)
	Kit.chamfer_box(st, Vector2(0, 0.0), h, 0.04, -0.32, -0.28, 0.015, DARKER)
	Kit.tube(st, Vector2(0, 0), DISC_Z - 0.01, -0.3, 0.025, 0.025, DARKER, 6, false, false)
	# Передний кожух: серый верх, жёлтый низ, тёмные решётки по бокам
	Kit.chamfer_box(st, Vector2(0, 0.0), h + 0.01, h + 0.01, -0.3, -0.14, 0.045, GREY)
	Kit.chamfer_box(st, Vector2(0, -0.1), h + 0.012, 0.05, -0.3, -0.14, 0.025, YELLOW)
	for sx in [-1.0, 1.0]:
		for y in [-0.005, 0.04]:
			Kit.box(st, Vector3(sx * (h + 0.012), y, -0.22), Vector3(0.01, 0.022, 0.11), DARKER)
	# Толстый тёмный пояс с рамкой окна
	Kit.chamfer_box(st, Vector2(0, 0.0), h + 0.015, h + 0.015, -0.14, 0.02, 0.05, DARK)
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * (h + 0.017), 0.01, -0.06), Vector3(0.01, 0.075, 0.13), DARKER)
	# Жёлтая вставка с решёткой
	Kit.chamfer_box(st, Vector2(0, 0.0), h + 0.005, h + 0.005, 0.02, 0.2, 0.045, YELLOW)
	for sx in [-1.0, 1.0]:
		for y in [-0.01, 0.03]:
			Kit.box(st, Vector3(sx * (h + 0.007), y, 0.11), Vector3(0.01, 0.018, 0.08), DARKER)
	# Задний тёмный блок, красная кнопка сверху, жёлтый торец
	Kit.chamfer_box(st, Vector2(0, 0.0), h, h, 0.2, 0.44, 0.045, DARK)
	Kit.box(st, Vector3(0, h + 0.008, 0.36), Vector3(0.06, 0.02, 0.06), RED)
	Kit.chamfer_box(st, Vector2(0, -0.02), h - 0.02, h - 0.03, 0.44, 0.5, 0.03, YELLOW)
	Kit.chamfer_box(st, Vector2(0, -h + 0.01), 0.07, 0.045, 0.34, 0.5, 0.015, DARKER)
	# Ручка для переноски сверху
	for z in [-0.05, 0.16]:
		Kit.bar(st, Vector3(0, h - 0.01, z), Vector3(0, h + 0.11, z), 0.045, DARK)
	Kit.bar(st, Vector3(0, h + 0.11, -0.07), Vector3(0, h + 0.11, 0.18), 0.055, DARK)
	# Пистолетная рукоять, спуск, подствольный блок
	Kit.bar(st, Vector3(0, -h + 0.03, 0.14), Vector3(0, -0.32, 0.21), 0.06, DARKER)
	Kit.box(st, Vector3(0, -h - 0.02, 0.09), Vector3(0.018, 0.045, 0.016), DARK)
	Kit.chamfer_box(st, Vector2(0, -h - 0.02), 0.07, 0.045, -0.2, 0.03, 0.015, DARKER)
	return Kit.commit(st, 0.55)


## Светится голубым: кромка щели, окно на боку, полоса на заднем блоке, окошко сзади.
static func _glow_mesh() -> ArrayMesh:
	var st := Kit.begin()
	var h := HALF
	Kit.box(st, Vector3(0, 0.032, -0.305), Vector3(h * 1.6, 0.008, 0.012), CYAN)
	Kit.box(st, Vector3(0, -0.032, -0.305), Vector3(h * 1.6, 0.008, 0.012), CYAN)
	for sx in [-1.0, 1.0]:
		Kit.box(st, Vector3(sx * (h + 0.022), 0.01, -0.06), Vector3(0.006, 0.05, 0.11), CYAN)
	Kit.box(st, Vector3(0, h + 0.004, 0.26), Vector3(0.07, 0.006, 0.12), CYAN)
	Kit.box(st, Vector3(0, -0.02, 0.502), Vector3(0.06, 0.05, 0.006), CYAN)
	return Kit.commit_glow(st, CYAN, 3.0)
