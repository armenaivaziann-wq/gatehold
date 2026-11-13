extends RefCounted
## Боевой молот — по листу пользователя, своя модель из простых форм (low-poly): серая гранёная
## голова — центральный пояс с выпуклым ромбом-пирамидой на лицевых сторонах и два массивных боковых
## бойка с квадратными заклёпками; под головой металлическая муфта; деревянная рукоять с кожаной
## обмоткой; снизу гранёное навершие. Начало координат — навершие, рукоять вдоль +Y, бойки
## смотрят в ±Z (ими и бьют). Хват двумя руками: левая — у навершия, правая — выше по рукояти.

const Kit := preload("res://weapons/model_kit.gd")

const STONE := Color(0.5, 0.49, 0.53)
const STONE_DARK := Color(0.38, 0.37, 0.41)
const METAL := Color(0.44, 0.44, 0.48)
const WOOD := Color(0.42, 0.24, 0.14)
const LEATHER := Color(0.62, 0.3, 0.15)
const HEAD_Y := 0.86             # центр головы
const GRIP_LOW := 0.13           # где правая рука
const GRIP_HIGH := 0.42          # где левая рука
const R_HANDLE := 0.028
# Правая — выше, ближе к голове (большой палец к бойку), левая — у навершия. Локти молот
# (hammer.gd) каждый кадр направляет к телу героя — здесь только начальное значение.
const RIGHT_HAND := [Vector3(0, GRIP_HIGH, 0), Vector3(0, -1, 0), R_HANDLE + 0.004, Vector3(0.6, -0.7, -0.4)]
const LEFT_HAND := [Vector3(0, GRIP_LOW, 0), Vector3(0, 1, 0), R_HANDLE + 0.004, Vector3(-0.5, -0.7, -0.5)]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "Hammer"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _mesh()
	root.add_child(body)
	body.owner = root
	# Торцы бойков, ромбы и заклёпки — отдельно: финалы ветки (hammer.gd) зажигают их свечением
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = _glow_mesh()
	root.add_child(glow)
	glow.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


## Труба вдоль Y: тот же Kit.tube, но ось — вертикальная (через поворот точек).
static func _tube_y(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, col: Color, sides := 8) -> void:
	for k in sides:
		var a0 := TAU * k / sides + PI / sides
		var a1 := TAU * (k + 1) / sides + PI / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := ((d0 + d1) * 0.5).normalized()
		Kit.quad(st, d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y1, 0),
			d0 * r1 + Vector3(0, y1, 0), col, n)
		Kit.quad(st, Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0), d1 * r1 + Vector3(0, y1, 0), d1 * r1 + Vector3(0, y1, 0),
			col, Vector3.UP)
		Kit.quad(st, Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0), d0 * r0 + Vector3(0, y0, 0), d0 * r0 + Vector3(0, y0, 0),
			col, Vector3.DOWN)


## Гранёный брусок вдоль Z (скошенные рёбра) с центром c.
static func _block(st: SurfaceTool, c: Vector3, hx: float, hy: float, hz: float, bevel: float, col: Color) -> void:
	Kit.chamfer_box(st, Vector2(c.x, c.y), hx, hy, c.z - hz, c.z + hz, bevel, col)


static func _mesh() -> ArrayMesh:
	var st := Kit.begin()
	var hy := HEAD_Y
	# Навершие: гранёный ком и металлическое кольцо над ним
	_tube_y(st, -0.06, 0.0, 0.05, 0.062, STONE_DARK)
	_tube_y(st, 0.0, 0.04, 0.062, 0.05, STONE)
	_tube_y(st, 0.04, 0.07, 0.04, 0.04, METAL)
	# Рукоять: дерево и кожаная обмотка кольцами
	_tube_y(st, 0.07, hy - 0.16, R_HANDLE, R_HANDLE, WOOD)
	var y := 0.08
	while y < hy - 0.24:
		_tube_y(st, y, y + 0.032, R_HANDLE + 0.006, R_HANDLE + 0.006, LEATHER)
		y += 0.05
	# Муфта под головой: два гранёных металлических кольца
	_tube_y(st, hy - 0.2, hy - 0.15, 0.045, 0.045, METAL)
	_tube_y(st, hy - 0.15, hy - 0.11, 0.055, 0.05, STONE_DARK)
	# Голова: центральный пояс и два боковых бойка (вдоль Z)
	_block(st, Vector3(0, hy, 0), 0.085, 0.12, 0.1, 0.02, STONE_DARK)
	for sz in [-1.0, 1.0]:
		var c := Vector3(0, hy, sz * 0.21)
		_block(st, c, 0.1, 0.11, 0.11, 0.03, STONE)
	# Полоски окантовки сверху и снизу пояса
	for yy in [hy + 0.12, hy - 0.12]:
		_block(st, Vector3(0, yy, 0), 0.09, 0.012, 0.105, 0.006, METAL)
	return Kit.commit(st, 0.8)


## Торцы-бойки, квадратные заклёпки и ромбы-пирамиды на поясе.
static func _glow_mesh() -> ArrayMesh:
	var st := Kit.begin()
	var hy := HEAD_Y
	for sz in [-1.0, 1.0]:
		var c := Vector3(0, hy, sz * 0.21)
		# Торец-боёк: чуть меньше, выступает
		_block(st, c + Vector3(0, 0, sz * 0.12), 0.085, 0.095, 0.015, 0.025, STONE_DARK)
		# Квадратные заклёпки на боках бойков
		for sx in [-1.0, 1.0]:
			Kit.box(st, Vector3(sx * 0.103, hy, sz * 0.21), Vector3(0.012, 0.03, 0.03), STONE_DARK)
	# Ромб-пирамида на поясе с обеих сторон (по X)
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * 0.087, hy, 0)
		var tip := Vector3(sx * 0.13, hy, 0)
		var pts := [Vector3(0, 0.06, 0), Vector3(0, 0, 0.055), Vector3(0, -0.06, 0), Vector3(0, 0, -0.055)]
		for k in 4:
			var a: Vector3 = base + pts[k]
			var b: Vector3 = base + pts[(k + 1) % 4]
			# Грань наружу: порядок вершин такой, чтобы нормаль смотрела от пояса
			var n := (b - a).cross(tip - a).normalized()
			if n.x * sx < 0.0:
				var t := a
				a = b
				b = t
				n = -n
			Kit.quad(st, a, b, tip, tip, STONE.lightened(0.08 if k % 2 == 0 else 0.0), n)
	return Kit.commit(st, 0.8)
