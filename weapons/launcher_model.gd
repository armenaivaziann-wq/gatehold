extends RefCounted
## Базука героя — по эскизу пользователя, своя модель из простых форм: круглый (16 граней,
## гладкое освещение) оливковый ствол, тёмные обоймы, сзади широкий раструб с чёрным нутром,
## сверху ручка для переноски, снизу пистолетная рукоять со спусковой скобой и передняя
## рукоять, на обоих боках — бежевый череп. Спереди из ствола торчит заряженная ракета: красная
## круглая боеголовка и бежевые стабилизаторы (узел Warhead — прячется на перезарядке).
## Ствол смотрит в -Z, узел Muzzle — у носа ракеты. Хват рук — RIGHT_HAND, LEFT_HAND (как в
## blunderbuss.gd: [точка, ось хвата, радиус, направление локтя]).

const OLIVE := Color(0.42, 0.44, 0.23)
const DARK := Color(0.24, 0.2, 0.21)
const HOLE := Color(0.06, 0.05, 0.05)
const RED := Color(0.8, 0.22, 0.19)
const CREAM := Color(0.86, 0.8, 0.69)
const R := 0.09                  # радиус ствола (до вершин восьмигранника)
const SIDES := 16
## Правая рука — на пистолетной рукояти (большой палец вверх), левая — на передней рукояти.
## Базука лежит на правом плече: локти вниз и назад.
const RIGHT_HAND := [Vector3(0.0, -0.17, 0.115), Vector3(0.0, -1.0, 0.27), 0.024, Vector3(0.45, -0.75, 0.5)]
const LEFT_HAND := [Vector3(0.0, -0.15, -0.21), Vector3(0.0, 1.0, 0.2), 0.022, Vector3(-0.45, -0.8, 0.4)]

static var _scene: PackedScene


static func scene() -> PackedScene:
	if _scene:
		return _scene
	var root := Node3D.new()
	root.name = "Launcher"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh()
	root.add_child(body)
	body.owner = root
	var warhead := MeshInstance3D.new()
	warhead.name = "Warhead"
	warhead.mesh = warhead_mesh()
	root.add_child(warhead)
	warhead.owner = root
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -0.72)
	root.add_child(muzzle)
	muzzle.owner = root
	_scene = PackedScene.new()
	_scene.pack(root)
	root.free()
	return _scene


static func _body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Раструб сзади: расширяется назад, внутри — чёрное нутро
	_prism(st, 0.307, 0.43, 0.1, 0.128, DARK)
	_ring(st, 0.43, 0.1, 0.128, DARK.darkened(0.15))
	_prism(st, 0.2, 0.429, 0.098, 0.098, HOLE, true)
	_disc(st, 0.2, 0.098, HOLE, 1.0)
	# Широкая обойма за раструбом
	_prism(st, 0.23, 0.307, 0.106, 0.106, DARK)
	# Оливковый ствол
	_prism(st, -0.311, 0.23, R, R, OLIVE)
	_prism(st, -0.482, -0.406, R, R, OLIVE)
	# Обоймы: средняя и передняя
	_prism(st, -0.406, -0.311, 0.104, 0.104, DARK)
	_prism(st, -0.55, -0.482, 0.104, 0.104, DARK)
	# Шов посередине ствола (чуть темнее)
	_prism(st, -0.12, -0.105, R * 1.01, R * 1.01, OLIVE.darkened(0.12))
	# Ручка для переноски сверху: две стойки и перекладина
	var top := R * cos(PI / SIDES)
	for z in [0.03, -0.14]:
		_box(st, Vector3(0, top + 0.035, z), Vector3(0.024, 0.07, 0.024), DARK)
	_box(st, Vector3(0, top + 0.07, -0.055), Vector3(0.03, 0.022, 0.2), DARK)
	# Пистолетная рукоять (наклонена назад), спусковая скоба и крючок
	var bottom := -R * cos(PI / SIDES)
	_slanted(st, Vector3(0, bottom - 0.005, 0.085), Vector3(0, bottom - 0.2, 0.135), Vector3(0.045, 0.0, 0.07), DARK)
	_box(st, Vector3(0, bottom - 0.012, 0.09), Vector3(0.05, 0.03, 0.11), DARK)
	_box(st, Vector3(0, bottom - 0.065, 0.025), Vector3(0.016, 0.012, 0.075), DARK)
	_box(st, Vector3(0, bottom - 0.04, -0.01), Vector3(0.016, 0.06, 0.012), DARK)
	_box(st, Vector3(0, bottom - 0.032, 0.035), Vector3(0.01, 0.035, 0.01), DARK.darkened(0.2))
	# Передняя рукоять (наклонена вперёд)
	_slanted(st, Vector3(0, bottom - 0.005, -0.19), Vector3(0, bottom - 0.14, -0.225), Vector3(0.036, 0.0, 0.05), DARK)
	# Черепа на обоих боках
	for side in [1.0, -1.0]:
		_skull(st, side, -0.03)
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat())
	return mesh


## Заряженная ракета: красная боеголовка перед стволом и стабилизаторы, торчащие из дула.
## nose — цвет носа, band — поясок за носом, fins — стабилизаторы (финалы ветки красят по-своему).
static func warhead_mesh(nose := RED, band := RED.darkened(0.08), fins := CREAM) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(st, -0.575, -0.55, 0.088, 0.088, band)
	for k in SIDES:
		var a0 := _angle(k)
		var a1 := _angle(k + 1)
		var mid := (a0 + a1) * 0.5
		_smooth_tri(st, [Vector3(cos(a0), sin(a0), 0) * 0.088 + Vector3(0, 0, -0.575),
			Vector3(cos(a1), sin(a1), 0) * 0.088 + Vector3(0, 0, -0.575), Vector3(0, 0, -0.72)],
			[Vector3(cos(a0), sin(a0), -0.6).normalized(), Vector3(cos(a1), sin(a1), -0.6).normalized(),
			Vector3(cos(mid), sin(mid), -0.6).normalized()], nose)
	# Стабилизаторы — четыре косых лопасти, отогнуты назад
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var d := Vector3(cos(a), sin(a), 0)
		var p0 := d * 0.095 + Vector3(0, 0, -0.545)
		var p1 := d * 0.165 + Vector3(0, 0, -0.5)
		var p2 := d * 0.15 + Vector3(0, 0, -0.455)
		var p3 := d * 0.095 + Vector3(0, 0, -0.47)
		_tri(st, p0, p1, p2, fins)
		_tri(st, p0, p2, p3, fins)
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat())
	return mesh


## Череп на боку ствола (на грани, что смотрит в ±X): свод, челюсть, глазницы, нос, зубы.
static func _skull(st: SurfaceTool, side: float, z: float) -> void:
	var out := Vector3(side, 0, 0)
	# Плоскость грани: «вверх» — +Y, «вперёд по стволу» — -Z (на правом боку череп смотрит вперёд)
	var big := 1.75               # череп крупный — почти во весь бок, как на эскизе
	# Череп облегает круглый ствол: высота на боку — дуга по окружности
	var p := func(u: float, v: float, lift: float) -> Vector3:
		var rr := R + 0.002 + lift
		var a := v * big / rr
		return Vector3(side * cos(a) * rr, sin(a) * rr, z - u * side * big)
	var w := 0.026
	# Свод черепа — восьмиугольник
	var crown: Array[Vector3] = []
	for k in 8:
		var a := k * TAU / 8.0
		crown.append(p.call(cos(a) * w, 0.008 + sin(a) * w * 0.95, 0.0))
	var c: Vector3 = p.call(0.0, 0.008, 0.0)
	for k in 8:
		_tri_n(st, c, crown[k], crown[(k + 1) % 8], CREAM, out)
	# Челюсть
	_quad_n(st, p.call(-0.016, -0.012, 0.0), p.call(0.016, -0.012, 0.0), p.call(0.014, -0.032, 0.0), p.call(-0.014, -0.032, 0.0), CREAM, out)
	# Глазницы и нос — тёмные, чуть над поверхностью черепа
	for eu in [-0.011, 0.011]:
		var e: Array[Vector3] = []
		for k in 6:
			var a := k * TAU / 6.0
			e.append(p.call(eu + cos(a) * 0.0075, 0.004 + sin(a) * 0.0075, 0.0008))
		var ec: Vector3 = p.call(eu, 0.004, 0.0008)
		for k in 6:
			_tri_n(st, ec, e[k], e[(k + 1) % 6], DARK, out)
	_tri_n(st, p.call(0.0, -0.006, 0.0008), p.call(-0.004, -0.014, 0.0008), p.call(0.004, -0.014, 0.0008), DARK, out)
	# Зубы — две прорези
	for tu in [-0.006, 0.006]:
		_quad_n(st, p.call(tu - 0.0015, -0.02, 0.0008), p.call(tu + 0.0015, -0.02, 0.0008),
			p.call(tu + 0.0015, -0.031, 0.0008), p.call(tu - 0.0015, -0.031, 0.0008), DARK, out)


static func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Угол k-й вершины восьмигранника: грани смотрят ровно вбок, вверх и вниз.
static func _angle(k: int) -> float:
	return PI / SIDES + k * TAU / SIDES


## Восьмигранная призма вдоль Z от z0 до z1 (радиусы r0 у z0, r1 у z1), с торцами.
## inner — грани смотрят внутрь (нутро раструба).
static func _prism(st: SurfaceTool, z0: float, z1: float, r0: float, r1: float, col: Color, inner := false) -> void:
	for k in SIDES:
		var a0 := _angle(k)
		var a1 := _angle(k + 1)
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		# Гладко: нормаль в каждой вершине — по радиусу (с наклоном, если сечение меняется)
		var slope := (r1 - r0) / (z1 - z0)
		var flip := -1.0 if inner else 1.0
		var n0 := (d0 - Vector3(0, 0, slope)).normalized() * flip
		var n1 := (d1 - Vector3(0, 0, slope)).normalized() * flip
		var v0 := d0 * r0 + Vector3(0, 0, z0)
		var v1 := d1 * r0 + Vector3(0, 0, z0)
		var v2 := d1 * r1 + Vector3(0, 0, z1)
		var v3 := d0 * r1 + Vector3(0, 0, z1)
		_smooth_tri(st, [v0, v1, v2], [n0, n1, n1], col)
		_smooth_tri(st, [v0, v2, v3], [n0, n1, n0], col)
	if not inner:
		_disc(st, z0, r0, col, -1.0)
		_disc(st, z1, r1, col, 1.0)


## Торец-восьмиугольник; facing — куда смотрит (-1 — вперёд по стволу, 1 — назад).
static func _disc(st: SurfaceTool, z: float, r: float, col: Color, facing := 1.0) -> void:
	for k in SIDES:
		_tri_n(st, Vector3(0, 0, z), Vector3(cos(_angle(k)), sin(_angle(k)), 0) * r + Vector3(0, 0, z),
			Vector3(cos(_angle(k + 1)), sin(_angle(k + 1)), 0) * r + Vector3(0, 0, z), col, Vector3(0, 0, facing))


## Кольцо-торец между радиусами r_in и r_out (задний срез раструба).
static func _ring(st: SurfaceTool, z: float, r_in: float, r_out: float, col: Color) -> void:
	for k in SIDES:
		var d0 := Vector3(cos(_angle(k)), sin(_angle(k)), 0)
		var d1 := Vector3(cos(_angle(k + 1)), sin(_angle(k + 1)), 0)
		_quad_n(st, d0 * r_in + Vector3(0, 0, z), d1 * r_in + Vector3(0, 0, z), d1 * r_out + Vector3(0, 0, z),
			d0 * r_out + Vector3(0, 0, z), col, Vector3(0, 0, 1))


## Брусок с центром c и размерами size.
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for i in 8:
		v.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	_cuboid(st, v, col)


## Наклонный брусок от центра верхнего торца a к центру нижнего b; size.x — толщина, size.z —
## длина торца вдоль ствола.
static func _slanted(st: SurfaceTool, a: Vector3, b: Vector3, size: Vector3, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var v := []
	for i in 8:
		var base := b if i & 2 == 0 else a
		v.append(base + Vector3(hx if i & 1 else -hx, 0.0, hz if i & 4 else -hz))
	_cuboid(st, v, col)


static func _cuboid(st: SurfaceTool, v: Array, col: Color) -> void:
	for q in [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]:
		var n: Vector3 = (v[q[1]] - v[q[0]]).cross(v[q[2]] - v[q[0]]).normalized()
		_quad_n(st, v[q[0]], v[q[1]], v[q[2]], v[q[3]], col.darkened(0.15 if n.y < -0.5 else 0.0), n)


static func _quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	_tri_n(st, a, b, c, col, n)
	_tri_n(st, a, c, d, col, n)


static func _tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _smooth_tri(st: SurfaceTool, v: Array, n: Array, col: Color) -> void:
	for i in 3:
		st.set_color(col)
		st.set_normal(n[i])
		st.add_vertex(v[i])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_tri_n(st, a, b, c, col, (b - a).cross(c - a).normalized())
