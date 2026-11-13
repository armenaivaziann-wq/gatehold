extends RefCounted
## Модели турелей — по листу эскизов пользователя (три турели со всех сторон), свои, из простых
## форм (low-poly, грани плоские). Общее у всех: тёмная бронированная база на четырёх опорах-
## башмаках с цветными накладками и светящимися окошками, тумба с воротником и стойка. Голова
## (узел Head) поворачивается, ствол (Gun) качается по высоте; сверху у головы — ручка-дуга.
##   gatling — миниган: тёмный корпус в жёлтой броне, широкий жёлтый воротник, шесть стволов в
##     обойме (Barrels — крутится), сбоку свисает патронная лента;
##   flame — огнемёт: жёлтая броня со светящимися окошками, короткий толстый ствол с огнём в
##     дуле, сзади — красный топливный бак;
##   laser — лазер: тёмный корпус в красной броне, большой излучатель с красной линзой,
##     красные светящиеся полосы; луч — красный (turret.gd);
##   freeze — заморозка (на листе её нет — в том же стиле): тёмный корпус в голубой броне со
##     снежинками, широкий излучатель холода со светящимся диском, сзади баллон хладагента;
##   mortar — мортира (по листу пользователя): на общей базе массивная тёмная тумба с решёткой
##     сзади; по бокам оливковые стойки-рамы держат трубу за крупные тёмные цапфы, снаружи стоек —
##     тёмные блоки с вертикальными оранжевыми щелями; труба короткая и очень толстая, оливковая,
##     круто вверх (MORTAR_PITCH), с массивным тёмным кольцом на дуле и тёмным открытым жерлом.
## Узлы: Base (постамент), Head, Gun, Barrels (у пулемёта), Muzzle (дуло). Высота ~1.75 м
## (в игре турель ×MODEL_SCALE, turret.gd); голова — ×HEAD_SCALE.

const DARK := Color(0.25, 0.23, 0.26)
const DARKER := Color(0.17, 0.16, 0.18)
const SIDES := 8
const HEAD_Y := 0.98             # где голова сидит на стойке
const HEAD_SCALE := 1.4          # голова крупная — почти во всю ширину постамента, как на эскизе
const YELLOW := Color(0.95, 0.68, 0.14)
const RED := Color(0.82, 0.13, 0.1)
const ORANGE_GLOW := Color(1.0, 0.42, 0.05)
const OLIVE := Color(0.4, 0.46, 0.22)
## Угол трубы мортиры (рад, вверх от горизонта) — модель строится под него, turret.gd держит его.
const MORTAR_PITCH := 1.0
## Где у мортиры цапфы (ось качания трубы), в осях головы; длина трубы от цапф до дула.
const MORTAR_PIVOT := Vector3(0, 0.42, 0.0)
const MORTAR_LENGTH := 0.62
const COLORS := {
	"gatling": {"main": YELLOW, "plate": YELLOW, "glow": ORANGE_GLOW},
	"laser": {"main": RED, "plate": RED, "glow": Color(1.0, 0.2, 0.12)},
	"freeze": {"main": Color(0.36, 0.66, 0.96), "plate": Color(0.36, 0.66, 0.96), "glow": Color(0.45, 0.92, 1.0),
		"tank": Color(0.78, 0.92, 1.0)},
	"flame": {"main": YELLOW, "plate": YELLOW, "glow": ORANGE_GLOW, "tank": Color(0.85, 0.16, 0.12)},
	"mortar": {"main": OLIVE, "plate": OLIVE, "glow": ORANGE_GLOW, "tank": YELLOW},
}

static var _scenes := {}


static func scene(kind: String) -> PackedScene:
	if _scenes.has(kind):
		return _scenes[kind]
	var c: Dictionary = COLORS[kind]
	var root := Node3D.new()
	root.name = "Turret"
	var base := _mesh_node("Base", _base_mesh(c), root)
	base.position = Vector3.ZERO
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, HEAD_Y, 0)
	head.scale = Vector3.ONE * HEAD_SCALE
	root.add_child(head)
	head.owner = root
	_mesh_node("Yoke", _mortar_mount(c) if kind == "mortar" else _yoke_mesh(), head, root)
	if kind == "mortar":
		_mesh_node("YokeGlow", _mortar_mount_glow(c), head, root, true, c["glow"])
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, 0.3, 0)
	if kind == "mortar":
		gun.position = MORTAR_PIVOT
		gun.rotation.x = MORTAR_PITCH
	head.add_child(gun)
	gun.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	match kind:
		"gatling":
			_mesh_node("Body", _gatling_body(c), gun, root)
			var barrels := Node3D.new()
			barrels.name = "Barrels"
			barrels.position = Vector3(0, 0, -0.36)
			gun.add_child(barrels)
			barrels.owner = root
			_mesh_node("Cluster", _gatling_barrels(), barrels, root)
			muzzle.position = Vector3(0, 0, -0.88)
		"laser":
			_mesh_node("Body", _laser_body(c), gun, root)
			_mesh_node("Glow", _laser_glow(c), gun, root, true, c["glow"])
			muzzle.position = Vector3(0, 0, -0.68)
		"freeze":
			_mesh_node("Body", _freeze_body(c), gun, root)
			_mesh_node("Glow", _freeze_glow(c), gun, root, true, c["glow"])
			muzzle.position = Vector3(0, 0, -0.72)
		"flame":
			_mesh_node("Body", _flame_body(c), gun, root)
			_mesh_node("Glow", _flame_glow(c), gun, root, true, c["glow"])
			muzzle.position = Vector3(0, 0, -0.82)
		"mortar":
			_mesh_node("Body", _mortar_body(c), gun, root)
			muzzle.position = Vector3(0, 0, -MORTAR_LENGTH - 0.03)
	gun.add_child(muzzle)
	muzzle.owner = root
	if c["glow"].a > 0.0:
		_mesh_node("BaseGlow", _base_glow(c), root, root, true, c["glow"])
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	_scenes[kind] = packed
	return packed


static func _mesh_node(node_name: String, mesh: ArrayMesh, parent: Node, owner_node: Node = null,
		glow := false, glow_color := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mesh.surface_set_material(0, _glow_mat(glow_color) if glow else _mat())
	parent.add_child(mi)
	mi.owner = owner_node if owner_node else parent
	return mi


# --- постамент ------------------------------------------------------------------------------

## Точка на грани k восьмигранной тумбы: t — вдоль грани (0..1), y — высота; чуть снаружи.
static func _face_pt(k: int, t: float, y: float, out := 1.015) -> Vector3:
	var r := lerpf(0.5, 0.4, clampf((y - 0.1) / 0.32, 0.0, 1.0))
	var p0 := Vector3(cos(_ang(k)), 0, sin(_ang(k))) * r
	var p1 := Vector3(cos(_ang(k + 1)), 0, sin(_ang(k + 1))) * r
	var p := p0.lerp(p1, t) * out
	return Vector3(p.x, y, p.z)


## База: четыре опоры по диагоналям (наклонная балка и башмак с цветной накладкой), между ними
## восьмигранная тумба с цветными плитами на гранях, сверху воротник, цветное кольцо и стойка.
static func _base_mesh(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var plate: Color = c["plate"]
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var d := Vector3(cos(a), 0, sin(a))
		var b := Basis(Vector3.UP, -a)
		# Балка от тумбы вниз-наружу, башмак, носок, цветная накладка
		_obox(st, d * 0.55 + Vector3(0, 0.3, 0), Vector3(0.2, 0.08, 0.14), b * Basis(Vector3(0, 0, 1), -0.45), DARK.lightened(0.05))
		_obox(st, d * 0.8 + Vector3(0, 0.12, 0), Vector3(0.17, 0.12, 0.2), b, DARK)
		_obox(st, d * 1.0 + Vector3(0, 0.07, 0), Vector3(0.05, 0.07, 0.15), b, DARKER)
		_obox(st, d * 0.8 + Vector3(0, 0.255, 0), Vector3(0.13, 0.02, 0.16), b, plate)
	_prism_y(st, 0.0, 0.1, 0.5, 0.5, DARKER)
	_prism_y(st, 0.1, 0.42, 0.5, 0.4, DARK)
	# Цветные плиты на гранях между опорами
	for k in [1, 3, 5, 7]:
		var n := Vector3(cos(_ang(k) + PI / 8.0), 0.3, sin(_ang(k) + PI / 8.0)).normalized()
		_quad(st, _face_pt(k, 0.12, 0.13), _face_pt(k, 0.88, 0.13), _face_pt(k, 0.88, 0.39), _face_pt(k, 0.12, 0.39), plate, n)
	# Воротник, цветное кольцо и стойка
	_prism_y(st, 0.42, 0.6, 0.42, 0.36, DARK.lightened(0.05))
	_prism_y(st, 0.6, 0.66, 0.4, 0.4, DARKER)
	_prism_y(st, 0.66, 0.72, 0.33, 0.33, plate)
	_prism_y(st, 0.72, HEAD_Y, 0.26, 0.23, DARKER)
	return _end(st)


## Светящиеся окошки: посреди цветных плит тумбы и на накладках башмаков.
static func _base_glow(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var g: Color = c["glow"]
	for k in [1, 3, 5, 7]:
		var n := Vector3(cos(_ang(k) + PI / 8.0), 0.3, sin(_ang(k) + PI / 8.0)).normalized()
		_quad(st, _face_pt(k, 0.36, 0.19, 1.03), _face_pt(k, 0.64, 0.19, 1.03), _face_pt(k, 0.64, 0.33, 1.03),
			_face_pt(k, 0.36, 0.33, 1.03), g, n)
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var d := Vector3(cos(a), 0, sin(a))
		_obox(st, d * 0.8 + Vector3(0, 0.27, 0), Vector3(0.06, 0.012, 0.07), Basis(Vector3.UP, -a), g)
	return _end(st)


## Ручка-дуга сверху головы: две стойки и перекладина вдоль ствола.
static func _handle(st: SurfaceTool, col: Color) -> void:
	for z in [-0.16, 0.2]:
		_box(st, Vector3(0, 0.37, z), Vector3(0.07, 0.14, 0.07), col)
	_box(st, Vector3(0, 0.455, 0.02), Vector3(0.08, 0.05, 0.46), col)


## Вилка на стойке: поворотный диск и две щёки, между которыми качается ствол.
static func _yoke_mesh() -> ArrayMesh:
	var st := _begin()
	_prism_y(st, -0.04, 0.08, 0.3, 0.3, DARK)
	_box(st, Vector3(0, 0.05, 0.0), Vector3(0.5, 0.1, 0.4), DARK)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.27, 0.1, 0.0), Vector3(0.07, 0.2, 0.26), DARK)
	return _end(st)


# --- головы ---------------------------------------------------------------------------------

static func _gatling_body(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var y: Color = c["main"]
	# Тёмный корпус в жёлтой броне: верх и бока
	_prism_z(st, -0.22, 0.34, 0.3, 0.3, DARK)
	_box(st, Vector3(0, 0.285, 0.04), Vector3(0.34, 0.05, 0.5), y)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.285, 0.02, 0.06), Vector3(0.05, 0.26, 0.42), y)
		# Цапфы — тёмные диски по бокам (ось качания)
		_prism_x(st, sx * 0.3, sx * 0.4, 0.13, DARK)
		_prism_x(st, sx * 0.4, sx * 0.43, 0.07, DARKER)
	# Задний блок и широкий жёлтый воротник перед стволами
	_box(st, Vector3(0, 0.0, 0.42), Vector3(0.34, 0.32, 0.2), DARKER)
	_prism_z(st, -0.32, -0.22, 0.34, 0.34, y.darkened(0.04))
	_prism_z(st, -0.36, -0.32, 0.3, 0.3, DARK)
	# Патронная лента свисает слева: звенья через одно жёлтые и тёмные
	for i in 6:
		var t := i / 5.0
		_box(st, Vector3(-0.38 - 0.1 * sin(t * PI * 0.7), 0.0 - t * 0.42, 0.14), Vector3(0.1, 0.065, 0.15),
			y if i % 2 == 0 else DARKER)
	_handle(st, DARK.lightened(0.06))
	return _end(st)


## Шесть стволов в обойме вокруг оси Z (узел Barrels крутится): задняя ступица, ось,
## переднее кольцо — из него торчат дула.
static func _gatling_barrels() -> ArrayMesh:
	var st := _begin()
	_prism_z(st, -0.06, 0.02, 0.23, 0.23, DARK)
	_prism_z(st, -0.46, -0.4, 0.23, 0.23, DARK.lightened(0.04))
	_prism_z(st, -0.26, -0.22, 0.2, 0.2, DARKER)
	for k in 6:
		var a := k * TAU / 6.0
		var off := Vector3(cos(a), sin(a), 0) * 0.135
		_tube_z(st, off + Vector3(0, 0, -0.52), off + Vector3(0, 0, -0.04), 0.058, DARKER.lightened(0.08))
	_tube_z(st, Vector3(0, 0, -0.48), Vector3(0, 0, -0.04), 0.05, DARK)
	return _end(st)


static func _laser_body(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var r: Color = c["main"]
	# Тёмный корпус в красной броне, сзади тёмная крышка
	_prism_z(st, -0.3, 0.34, 0.3, 0.3, DARK)
	_box(st, Vector3(0, 0.285, 0.02), Vector3(0.3, 0.05, 0.48), r)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.285, 0.0, 0.02), Vector3(0.05, 0.3, 0.46), r)
		_prism_x(st, sx * 0.31, sx * 0.4, 0.12, DARK)
	_prism_z(st, 0.34, 0.46, 0.27, 0.22, DARKER)
	# Излучатель: широкий тёмный кожух, красное кольцо, бленда линзы
	_prism_z(st, -0.46, -0.3, 0.33, 0.33, DARK.lightened(0.03))
	_prism_z(st, -0.52, -0.46, 0.3, 0.3, r)
	_prism_z(st, -0.64, -0.52, 0.25, 0.25, DARKER)
	_handle(st, DARK.lightened(0.06))
	return _end(st)


## Красная линза спереди, полосы на боковой броне и на кожухе — светятся.
static func _laser_glow(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	_disc_z(st, -0.645, 0.18, c["glow"], -1.0)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.312
		_quad(st, Vector3(x, 0.06, -0.16), Vector3(x, 0.06, 0.2), Vector3(x, -0.02, 0.2), Vector3(x, -0.02, -0.16),
			c["glow"], Vector3(sx, 0, 0))
	_box(st, Vector3(0, 0.315, 0.02), Vector3(0.06, 0.012, 0.3), c["glow"])
	return _end(st)


static func _freeze_body(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var b: Color = c["main"]
	var frost: Color = c["tank"]
	# Тёмный корпус в голубой броне: верх и бока
	_prism_z(st, -0.3, 0.3, 0.3, 0.3, DARK)
	_box(st, Vector3(0, 0.285, 0.0), Vector3(0.34, 0.05, 0.5), b)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.285, 0.0, 0.0), Vector3(0.05, 0.3, 0.46), b)
		_prism_x(st, sx * 0.31, sx * 0.4, 0.1, DARK)
	# Голубой воротник, короткий ствол и широкий излучатель холода
	_prism_z(st, -0.4, -0.3, 0.33, 0.33, b.darkened(0.06))
	_prism_z(st, -0.5, -0.4, 0.2, 0.2, DARK.lightened(0.05))
	_prism_z(st, -0.62, -0.5, 0.2, 0.3, DARKER)
	_prism_z(st, -0.68, -0.62, 0.32, 0.32, frost)
	# Баллон хладагента сзади: светлый, с тёмными обручами и колпаком
	_prism_z(st, 0.3, 0.36, 0.2, 0.25, DARK)
	_prism_z(st, 0.36, 0.64, 0.25, 0.25, frost)
	for z in [0.42, 0.56]:
		_prism_z(st, z, z + 0.04, 0.265, 0.265, DARKER)
	_prism_z(st, 0.64, 0.72, 0.25, 0.14, frost.darkened(0.1))
	_prism_z(st, 0.72, 0.77, 0.08, 0.08, DARKER)
	# Снежинки на боковой броне — белые лучи с веточками
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.312
		var center := Vector3(x, 0.02, 0.15)
		for k in 3:
			var a := k * PI / 3.0
			var d := Vector3(0, cos(a), sin(a))
			_flat_bar(st, center - d * 0.08, center + d * 0.08, 0.026, Color(0.96, 0.98, 1.0), Vector3(sx, 0, 0))
			for end in [-1.0, 1.0]:
				var tip: Vector3 = center + d * 0.055 * end
				for bend in [-0.7, 0.7]:
					var dd: Vector3 = (d * end).rotated(Vector3(sx, 0, 0), bend)
					_flat_bar(st, tip, tip + dd * 0.035, 0.018, Color(0.96, 0.98, 1.0), Vector3(sx, 0, 0))
	_handle(st, DARK.lightened(0.06))
	return _end(st)


## Холодное свечение: диск излучателя и полосы на броне под снежинками.
static func _freeze_glow(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	_disc_z(st, -0.685, 0.2, c["glow"].darkened(0.15), -1.0)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.312
		_quad(st, Vector3(x, -0.09, -0.17), Vector3(x, -0.09, -0.05), Vector3(x, -0.13, -0.05), Vector3(x, -0.13, -0.17),
			c["glow"], Vector3(sx, 0, 0))
	_box(st, Vector3(0, 0.315, 0.0), Vector3(0.06, 0.012, 0.3), c["glow"])
	return _end(st)


static func _flame_body(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var y: Color = c["main"]
	var red: Color = c["tank"]
	# Тёмный корпус в жёлтой броне: верх и бока
	_prism_z(st, -0.3, 0.3, 0.3, 0.3, DARK)
	_box(st, Vector3(0, 0.285, 0.0), Vector3(0.34, 0.05, 0.5), y)
	for sx in [-1.0, 1.0]:
		_box(st, Vector3(sx * 0.285, 0.0, 0.0), Vector3(0.05, 0.3, 0.46), y)
	# Жёлтый воротник и короткий толстый ствол с раструбом
	_prism_z(st, -0.4, -0.3, 0.33, 0.33, y.darkened(0.04))
	_prism_z(st, -0.46, -0.4, 0.27, 0.27, DARK)
	_prism_z(st, -0.74, -0.46, 0.2, 0.2, DARK.lightened(0.05))
	_prism_z(st, -0.8, -0.74, 0.25, 0.25, DARKER)
	# Красный топливный бак сзади: тёмное основание, обруч, скошенное дно с пробкой
	_prism_z(st, 0.3, 0.36, 0.2, 0.27, DARK)
	_prism_z(st, 0.36, 0.66, 0.27, 0.27, red)
	_prism_z(st, 0.48, 0.54, 0.285, 0.285, DARKER)
	_prism_z(st, 0.66, 0.74, 0.27, 0.17, red.darkened(0.12))
	_prism_z(st, 0.74, 0.79, 0.1, 0.1, DARKER)
	# Трубка от бака к стволу
	_tube_z(st, Vector3(0.2, -0.22, -0.44), Vector3(0.2, -0.24, 0.4), 0.035, DARKER)
	_handle(st, DARK.lightened(0.06))
	return _end(st)


## Огонь в дуле и окошки на боковой броне — светятся оранжевым.
static func _flame_glow(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	_disc_z(st, -0.805, 0.14, c["glow"], -1.0)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.312
		_quad(st, Vector3(x, 0.09, -0.14), Vector3(x, 0.09, 0.1), Vector3(x, -0.07, 0.1), Vector3(x, -0.07, -0.14),
			c["glow"], Vector3(sx, 0, 0))
	return _end(st)


## Труба мортиры (узел Gun, ось — цапфы): короткая толстая оливковая труба вдоль -Z, тёмный
## бандаж у цапф, массивное тёмное кольцо на дуле с тёмным жерлом, скруглённый тёмный казённик.
static func _mortar_body(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var o: Color = c["main"]
	var L := MORTAR_LENGTH
	_prism_z(st, -L + 0.16, 0.2, 0.215, 0.215, o)
	_prism_z(st, -0.07, 0.07, 0.232, 0.232, DARK)
	_prism_z(st, -L + 0.22, -L + 0.3, 0.228, 0.228, o.darkened(0.12))
	# Дуло: массивное тёмное кольцо, ободок, тёмное жерло (дыра)
	_prism_z(st, -L, -L + 0.17, 0.27, 0.27, DARK)
	_prism_z(st, -L - 0.03, -L + 0.01, 0.285, 0.285, DARK.lightened(0.06))
	_disc_z(st, -L - 0.032, 0.19, Color(0.05, 0.05, 0.06), -1.0)
	_prism_z(st, -L - 0.02, -L + 0.12, 0.19, 0.19, Color(0.08, 0.08, 0.09))
	# Цапфы: крупные тёмные диски с болтами по бокам (ось качания)
	for sx in [-1.0, 1.0]:
		_prism_x(st, sx * 0.21, sx * 0.37, 0.12, DARK)
		_prism_x(st, sx * 0.37, sx * 0.41, 0.065, DARKER)
	# Казённик: скруглённый тёмный торец
	_prism_z(st, 0.2, 0.3, 0.215, 0.15, DARK)
	_prism_z(st, 0.3, 0.34, 0.09, 0.09, DARKER)
	return _end(st)


## Голова мортиры: поворотный диск, массивная тёмная тумба с решёткой сзади, по бокам оливковые
## рамы-стойки (по две ноги к цапфе; сами цапфы — на трубе), снаружи — тёмные боковые блоки.
static func _mortar_mount(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	var o: Color = c["main"]
	var t := MORTAR_PIVOT
	_prism_y(st, -0.04, 0.06, 0.34, 0.34, DARK)
	# Тумба: массивный блок, тёмная крышка, решётка сзади
	_box(st, Vector3(0, 0.15, 0.02), Vector3(0.46, 0.2, 0.5), DARK)
	_box(st, Vector3(0, 0.265, 0.02), Vector3(0.4, 0.04, 0.44), DARKER)
	_box(st, Vector3(0, 0.27, 0.27), Vector3(0.3, 0.3, 0.1), DARK.lightened(0.03))
	for k in 4:
		_box(st, Vector3(0, 0.17 + k * 0.065, 0.325), Vector3(0.24, 0.025, 0.02), DARKER)
	# Оливковые рамы: две ноги от тумбы к цапфе с каждой стороны, поперечина, гидроцилиндр
	for sx in [-1.0, 1.0]:
		var hub := Vector3(sx * 0.3, t.y, t.z)
		_bar(st, Vector3(sx * 0.3, 0.07, 0.2), hub, 0.11, o)
		_bar(st, Vector3(sx * 0.3, 0.07, -0.2), hub, 0.11, o)
		_box(st, Vector3(sx * 0.3, 0.08, 0.0), Vector3(0.12, 0.07, 0.5), o.darkened(0.1))
		_box(st, Vector3(sx * 0.3, hub.y, hub.z), Vector3(0.12, 0.16, 0.16), o)
		# Боковой блок: тёмный корпус с оливковой рамкой (щель светится — _mortar_mount_glow)
		_box(st, Vector3(sx * 0.47, 0.38, 0.02), Vector3(0.12, 0.26, 0.2), DARK)
		_box(st, Vector3(sx * 0.47, 0.38, 0.02), Vector3(0.125, 0.28, 0.06), o)
		_box(st, Vector3(sx * 0.42, 0.38, 0.02), Vector3(0.04, 0.1, 0.1), DARKER)
	return _end(st)


## Светящиеся вертикальные щели на боковых блоках мортиры.
static func _mortar_mount_glow(c: Dictionary) -> ArrayMesh:
	var st := _begin()
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.534
		for z in [-0.045, 0.085]:
			_quad(st, Vector3(x, 0.47, z - 0.02), Vector3(x, 0.47, z + 0.02), Vector3(x, 0.29, z + 0.02),
				Vector3(x, 0.29, z - 0.02), c["glow"], Vector3(sx, 0, 0))
	return _end(st)


## Брусок-стержень от a до b (ноги двуноги, винт): квадратное сечение thick.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, thick: float, col: Color) -> void:
	var d := b - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.FORWARD)
	_obox(st, (a + b) * 0.5, Vector3(thick * 0.5, thick * 0.5, d.length() * 0.5), basis, col)


## Гранёный цилиндр вдоль Z со смещённым центром (бак сбоку).
static func _prism_z_at(st: SurfaceTool, center: Vector3, z0: float, z1: float, r: float, col: Color) -> void:
	for k in SIDES:
		var a0 := _ang(k)
		var a1 := _ang(k + 1)
		var p0 := center + Vector3(cos(a0) * r, sin(a0) * r, z0)
		var p1 := center + Vector3(cos(a1) * r, sin(a1) * r, z0)
		var p2 := center + Vector3(cos(a1) * r, sin(a1) * r, z1)
		var p3 := center + Vector3(cos(a0) * r, sin(a0) * r, z1)
		var mid := (a0 + a1) * 0.5
		_quad(st, p0, p1, p2, p3, col, Vector3(cos(mid), sin(mid), 0))
	for z in [z0, z1]:
		for k in SIDES:
			var a0 := _ang(k)
			var a1 := _ang(k + 1)
			_tri(st, center + Vector3(0, 0, z), center + Vector3(cos(a0) * r, sin(a0) * r, z),
				center + Vector3(cos(a1) * r, sin(a1) * r, z), col, Vector3(0, 0, signf(z - center.z) if z != 0.0 else 1.0))


# --- помощники ------------------------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _end(st: SurfaceTool) -> ArrayMesh:
	return st.commit()


static func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := _mat()
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.2
	return m


static func _ang(k: int) -> float:
	return PI / SIDES + k * TAU / SIDES


## Восьмигранник вдоль Y (постамент, стойка): радиус r0 внизу, r1 вверху, с крышками.
static func _prism_y(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, col: Color) -> void:
	for k in SIDES:
		var a0 := _ang(k)
		var a1 := _ang(k + 1)
		var mid := (a0 + a1) * 0.5
		var n := Vector3(cos(mid), (r0 - r1) / maxf(y1 - y0, 0.001), sin(mid)).normalized()
		_quad(st, Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
			Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1), col, n)
		_tri(st, Vector3(0, y1, 0), Vector3(cos(a0) * r1, y1, sin(a0) * r1), Vector3(cos(a1) * r1, y1, sin(a1) * r1), col, Vector3.UP)
		_tri(st, Vector3(0, y0, 0), Vector3(cos(a1) * r0, y0, sin(a1) * r0), Vector3(cos(a0) * r0, y0, sin(a0) * r0), col.darkened(0.3), Vector3.DOWN)


## Восьмигранник вдоль Z (корпуса, кожухи): от z0 до z1, с торцами.
static func _prism_z(st: SurfaceTool, z0: float, z1: float, r0: float, r1: float, col: Color) -> void:
	for k in SIDES:
		var a0 := _ang(k)
		var a1 := _ang(k + 1)
		var mid := (a0 + a1) * 0.5
		var n := Vector3(cos(mid), sin(mid), 0)
		var shade := col.darkened(0.15 if n.y < -0.5 else 0.0)
		_quad(st, Vector3(cos(a0) * r0, sin(a0) * r0, z0), Vector3(cos(a1) * r0, sin(a1) * r0, z0),
			Vector3(cos(a1) * r1, sin(a1) * r1, z1), Vector3(cos(a0) * r1, sin(a0) * r1, z1), shade, n)
	_disc_z(st, z0, r0, col, -1.0)
	_disc_z(st, z1, r1, col, 1.0)


## Короткий восьмигранник вдоль X (цапфы по бокам): от x0 до x1.
static func _prism_x(st: SurfaceTool, x0: float, x1: float, r: float, col: Color) -> void:
	for k in SIDES:
		var a0 := _ang(k)
		var a1 := _ang(k + 1)
		var mid := (a0 + a1) * 0.5
		_quad(st, Vector3(x0, cos(a0) * r, sin(a0) * r), Vector3(x0, cos(a1) * r, sin(a1) * r),
			Vector3(x1, cos(a1) * r, sin(a1) * r), Vector3(x1, cos(a0) * r, sin(a0) * r), col, Vector3(0, cos(mid), sin(mid)))
		_tri(st, Vector3(x1, 0, 0), Vector3(x1, cos(a0) * r, sin(a0) * r), Vector3(x1, cos(a1) * r, sin(a1) * r),
			col, Vector3(signf(x1), 0, 0))


## Труба-ствол вдоль Z (6 граней).
static func _tube_z(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	for k in 6:
		var a0 := k * TAU / 6.0
		var a1 := (k + 1) * TAU / 6.0
		var d0 := Vector3(cos(a0), sin(a0), 0) * r
		var d1 := Vector3(cos(a1), sin(a1), 0) * r
		_quad(st, a + d0, a + d1, b + d1, b + d0, col, Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0))
	# Чёрное дуло спереди
	for k in 6:
		var a0 := k * TAU / 6.0
		var a1 := (k + 1) * TAU / 6.0
		_tri(st, a, a + Vector3(cos(a0), sin(a0), 0) * r * 0.6, a + Vector3(cos(a1), sin(a1), 0) * r * 0.6,
			Color(0.05, 0.05, 0.05), Vector3(0, 0, -1))


static func _disc_z(st: SurfaceTool, z: float, r: float, col: Color, facing: float) -> void:
	for k in SIDES:
		_tri(st, Vector3(0, 0, z), Vector3(cos(_ang(k)) * r, sin(_ang(k)) * r, z),
			Vector3(cos(_ang(k + 1)) * r, sin(_ang(k + 1)) * r, z), col, Vector3(0, 0, facing))


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for i in 8:
		v.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for q in [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]:
		var n: Vector3 = (v[q[1]] - v[q[0]]).cross(v[q[2]] - v[q[0]]).normalized()
		_quad(st, v[q[0]], v[q[1]], v[q[2]], v[q[3]], col.darkened(0.15 if n.y < -0.5 else 0.0), n)


## Брусок с центром c и полуразмерами half, повёрнутый базисом b (опоры базы).
static func _obox(st: SurfaceTool, c: Vector3, half: Vector3, b: Basis, col: Color) -> void:
	var v := []
	for i in 8:
		v.append(c + b * Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
	for q in [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]:
		var n: Vector3 = (v[q[1]] - v[q[0]]).cross(v[q[2]] - v[q[0]]).normalized()
		_quad(st, v[q[0]], v[q[1]], v[q[2]], v[q[3]], col.darkened(0.15 if n.y < -0.5 else 0.0), n)


## Плоская полоска на поверхности (луч снежинки): от a до b шириной w, лицом в n.
static func _flat_bar(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color, n: Vector3) -> void:
	var side := (b - a).cross(n).normalized() * w * 0.5
	var lift := n * 0.004
	_quad(st, a - side + lift, b - side + lift, b + side + lift, a + side + lift, col, n)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	_tri(st, a, b, c, col, n)
	_tri(st, a, c, d, col, n)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
