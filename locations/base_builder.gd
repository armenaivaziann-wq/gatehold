extends Node3D
## База за воротами — то, что игрок защищает: двор, обнесённый низкой глинобитной оградой,
## казарма и склад, две армейские палатки, ящики и бочки, флагшток посреди плаца.
## Без мелочей — крупные простые формы. Всё собирается в один меш с цветами вершин и плоским
## затенением (один вызов отрисовки); у зданий — простые твёрдые тела.

const MapBuilder := preload("res://locations/map_builder.gd")

const ADOBE := Color("d9a86e")
const ADOBE_DARK := Color("c4925a")
const YARD := Color("c99a62")
const DARK := Color("3a2416")
const WOOD := Color("6b4326")
const CANVAS := Color("cbb68a")
const RED := Color("c0392b")
const PALM_TRUNK := Color("8a6a45")
const PALM_LEAF := [Color("6f8f3a"), Color("5f7f31"), Color("84a34a")]
# Двор базы: от стены ворот на юг
const YARD_MIN := Vector2(-30, 103)
const YARD_MAX := Vector2(30, 142)

var _map: Node3D
var _st: SurfaceTool
var _rng := RandomNumberGenerator.new()
var _body: StaticBody3D


func setup(map: Node3D) -> void:
	_map = map


func _ready() -> void:
	_rng.seed = 404
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body = StaticBody3D.new()
	add_child(_body)
	_build_base()
	var mi := MeshInstance3D.new()
	mi.mesh = _st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)


## Высота земли: внутри карты — рельеф, за краем — плато.
func ground(x: float, z: float) -> float:
	if absf(x) < MapBuilder.HALF and absf(z) < MapBuilder.HALF:
		return _map.height(Vector2(x, z))
	return MapBuilder.PLATEAU - 0.1


func _build_base() -> void:
	var y := ground(0, 120)
	var mid := (YARD_MIN + YARD_MAX) / 2
	var size := YARD_MAX - YARD_MIN
	# Утоптанный плац
	_box(Vector3(mid.x, y + 0.02, mid.y), Vector3(size.x, 0.4, size.y), YARD, 0.0)
	# Ограда: от башен ворот по бокам и сзади, сзади — проём
	var h := 2.6
	for s in [-1.0, 1.0]:
		_wall(Vector2(s * 19.5, YARD_MIN.y), Vector2(s * YARD_MAX.x, YARD_MIN.y), h)
		_wall(Vector2(s * YARD_MAX.x, YARD_MIN.y), Vector2(s * YARD_MAX.x, YARD_MAX.y), h)
		_wall(Vector2(s * YARD_MAX.x, YARD_MAX.y), Vector2(s * 5.0, YARD_MAX.y), h)
		_box(Vector3(s * 5.0, y + h / 2 + 0.6, YARD_MAX.y), Vector3(1.6, h + 1.2, 1.6), ADOBE_DARK, 0.0)
	# Казарма (запад) и склад (восток): дверь и окна смотрят во двор
	_building(Vector3(-20, y, 126), Vector2(9, 20), 4.2, 1.0, 3)
	_building(Vector3(21, y, 129), Vector2(8, 12), 4.8, -1.0, 1)
	# Армейские палатки
	_tent(Vector3(-12, y, 111), 6.0, 7.0, PI / 2, CANVAS, CANVAS.darkened(0.08))
	_tent(Vector3(13, y, 112), 6.0, 7.0, PI / 2, CANVAS, CANVAS.darkened(0.08))
	# Ящики и бочки у склада и у стены
	for spot in [Vector3(13, y, 121), Vector3(-6, y, 135), Vector3(23, y, 138)]:
		for k in 3:
			var c := 1.2
			_box(spot + Vector3((k % 2) * 1.35, c / 2 + (k / 2) * c, 0), Vector3(c, c, c), WOOD.lightened(0.15 * (k % 2)), 0.0)
		for k in 2:
			_cylinder(spot + Vector3(-1.5, 0, k * 1.1), 0.45, 1.1, WOOD.lightened(0.1), 8)
	# Флагшток посреди плаца
	_pole(Vector3(0, y, 124), 9.0)
	_flag(Vector3(0, y + 8.8, 124), 3.0, 1.8, RED, 1.0)
	# Пара пальм у казармы
	_palm(Vector3(-11, y, 133))
	_palm(Vector3(-25, y, 139))


## Участок ограды от a до b (по земле), высотой h; сверху светлый край.
func _wall(a: Vector2, b: Vector2, h: float) -> void:
	var mid := (a + b) / 2
	var y := ground(mid.x, mid.y) - 0.2
	var yaw := atan2(b.x - a.x, b.y - a.y)
	var length := a.distance_to(b) + 1.2
	_box(Vector3(mid.x, y + h / 2, mid.y), Vector3(1.2, h, length), ADOBE, yaw)
	_box(Vector3(mid.x, y + h + 0.12, mid.y), Vector3(1.4, 0.24, length), ADOBE.lightened(0.08), yaw)
	_collide_rot(Vector3(mid.x, y + h / 2, mid.y), Vector3(1.2, h, length), yaw)


## Простое здание: коробка с плоской крышей-плитой, дверь и окна на стороне facing (+1 — восток).
func _building(base: Vector3, footprint: Vector2, h: float, facing: float, windows: int) -> void:
	var w := footprint.x
	var d := footprint.y
	var y := base.y - 0.2
	_box(Vector3(base.x, y + h / 2, base.z), Vector3(w, h, d), ADOBE, 0.0)
	_box(Vector3(base.x, y + h + 0.15, base.z), Vector3(w + 0.6, 0.3, d + 0.6), ADOBE.lightened(0.08), 0.0)
	_collide(Vector3(base.x, y + h / 2, base.z), Vector3(w, h, d))
	var face := base.x + facing * w / 2
	_box(Vector3(face, y + 1.25, base.z), Vector3(0.3, 2.5, 1.8), DARK, 0.0)
	for k in windows:
		var z := base.z + (k - (windows - 1) / 2.0) * d / (windows + 1) * 1.6
		if absf(z - base.z) > 1.8:
			_box(Vector3(face, y + 2.6, z), Vector3(0.3, 0.9, 1.1), DARK, 0.0)


func _collide_rot(center: Vector3, size: Vector3, yaw: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	_body.add_child(shape)


# --- элементы ------------------------------------------------------------------------------

## Пальма: изогнутый ствол из сегментов, корона из листьев-«перьев».
func _palm(base: Vector3) -> void:
	var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.6, 1.6)
	var h := _rng.randf_range(6.0, 8.5)
	var prev := base
	for k in 6:
		var t := float(k + 1) / 6
		var p := base + Vector3(0, h * t, 0) + lean * t * t
		_cylinder_between(prev, p, lerpf(0.32, 0.2, t), PALM_TRUNK.darkened(0.08 * (k % 2)))
		prev = p
	for k in 8:
		var a := TAU * k / 8.0 + _rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var leaf_len := _rng.randf_range(3.0, 4.2)
		var tip := prev + dir * leaf_len + Vector3(0, -_rng.randf_range(1.2, 2.2), 0)
		var mid := prev + dir * leaf_len * 0.5 + Vector3(0, 0.4, 0)
		var col: Color = PALM_LEAF[k % 3]
		_leaf(prev, mid, tip, col)


func _leaf(a: Vector3, mid: Vector3, tip: Vector3, col: Color) -> void:
	for seg in [[a, mid], [mid, tip]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var along := (p1 - p0).normalized()
		var side := along.cross(Vector3.UP).normalized() * 0.55
		var c := (p0 + p1) / 2 - Vector3(0, 0.5, 0)
		_tri_out(p0 + side * 0.3, p1, p0 - side * 0.3, col, c)
		_tri_out(p0 + side * 0.3, p0 - side * 0.3, p1, col.darkened(0.15), c + Vector3(0, 1.0, 0))
		_tri_out((p0 + p1) / 2 + side, p1, p0, col.lightened(0.05), c)
		_tri_out((p0 + p1) / 2 - side, p0, p1, col.lightened(0.05), c)


## Шатёр: четыре столба и двускатный тент из полос двух цветов.
func _tent(base: Vector3, w: float, d: float, yaw: float, a: Color, b: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var h := 2.4
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(base + basis * Vector3(sx * w / 2, h / 2, sz * d / 2), Vector3(0.14, h, 0.14), WOOD, yaw)
	var ridge := 1.1
	var slope := atan2(ridge, w / 2)
	var panel := sqrt(ridge * ridge + w * w / 4) + 0.2
	var strips := 4
	for s in [-1.0, 1.0]:
		for k in strips:
			var z := -d / 2 - 0.2 + (k + 0.5) * (d + 0.4) / strips
			var center := base + basis * Vector3(s * w / 4, h + ridge / 2, z)
			var rot := basis * Basis(Vector3.FORWARD, -s * slope)
			_box_basis(center, Vector3(panel, 0.08, (d + 0.4) / strips), a if k % 2 == 0 else b, rot)


func _flag(top: Vector3, w: float, h: float, col: Color, dir: float) -> void:
	var inside := top + Vector3(0, -h / 2, 1.0)
	var a := top
	var b := top + Vector3(dir * w, -0.2, 0)
	var c := top + Vector3(dir * w * 0.85, -h * 0.55, 0)
	var e := top + Vector3(0, -h, 0)
	_tri_out(a, b, c, col, inside)
	_tri_out(a, c, e, col, inside)
	_tri_out(a, c, b, col.darkened(0.2), top + Vector3(0, -h / 2, -1.0))
	_tri_out(a, e, c, col.darkened(0.2), top + Vector3(0, -h / 2, -1.0))


func _pole(base: Vector3, h: float) -> void:
	_cylinder(base, 0.08, h, WOOD, 6)
	_sphere(base + Vector3(0, h, 0), 0.16, Color("d9a441"))


func _collide(center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	_body.add_child(shape)


# --- геометрия -----------------------------------------------------------------------------

func _box(center: Vector3, size: Vector3, col: Color, yaw: float) -> void:
	_box_basis(center, size, col, Basis(Vector3.UP, yaw))


func _box_basis(center: Vector3, size: Vector3, col: Color, basis: Basis) -> void:
	var h := size / 2
	var c := []
	for i in 8:
		var v := Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1))
		c.append(center + basis * v)
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_tri_out(c[f[0]], c[f[1]], c[f[2]], col, center)
		_tri_out(c[f[0]], c[f[2]], c[f[3]], col, center)


func _cylinder(base: Vector3, r: float, h: float, col: Color, seg: int) -> void:
	var inside := base + Vector3(0, h / 2, 0)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var shade := col.darkened(0.06 * (k % 2))
		_tri_out(base + p0, base + p1, base + p1 + Vector3(0, h, 0), shade, inside)
		_tri_out(base + p0, base + p1 + Vector3(0, h, 0), base + p0 + Vector3(0, h, 0), shade, inside)
		_tri_out(base + Vector3(0, h, 0), base + p0 + Vector3(0, h, 0), base + p1 + Vector3(0, h, 0), col.lightened(0.06), inside)


func _cylinder_between(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var up := axis.cross(side)
	var inside := (a + b) / 2
	var seg := 6
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var o0 := (side * cos(a0) + up * sin(a0)) * r
		var o1 := (side * cos(a1) + up * sin(a1)) * r
		_tri_out(a + o0, a + o1, b + o1, col, inside)
		_tri_out(a + o0, b + o1, b + o0, col, inside)


func _dome(base: Vector3, r: float, col: Color) -> void:
	var seg := 10
	var rings := 4
	for i in rings:
		var t0 := PI / 2 * i / rings
		var t1 := PI / 2 * (i + 1) / rings
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p := func(t: float, a: float) -> Vector3:
				return base + Vector3(cos(a) * cos(t) * r, sin(t) * r, sin(a) * cos(t) * r)
			var shade := col.lightened(0.05 * i)
			_tri_out(p.call(t0, a0), p.call(t0, a1), p.call(t1, a1), shade, base)
			if i < rings - 1:
				_tri_out(p.call(t0, a0), p.call(t1, a1), p.call(t1, a0), shade, base)


func _sphere(center: Vector3, r: float, col: Color) -> void:
	_dome(center, r, col)
	_dome_down(center, r, col.darkened(0.2))


func _dome_down(base: Vector3, r: float, col: Color) -> void:
	var seg := 8
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		_tri_out(base + Vector3(cos(a0) * r, 0, sin(a0) * r), base + Vector3(cos(a1) * r, 0, sin(a1) * r),
			base - Vector3(0, r, 0), col, base)


## Треугольник лицом наружу от точки inside, плоская нормаль.
func _tri_out(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - inside) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	_st.set_color(col)
	_st.set_normal(-n.normalized())
	_st.add_vertex(a)
	_st.add_vertex(b)
	_st.add_vertex(c)
