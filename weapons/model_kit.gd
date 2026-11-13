extends RefCounted
## Набор простых форм для моделей оружия (миниган, электропушка): трубы вдоль Z, кольца,
## бруски, наклонные бруски. Цвет — в вершинах, грани плоские или гладкие. Ствол смотрит в -Z.


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func commit(st: SurfaceTool, roughness := 0.7) -> ArrayMesh:
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh


## Светящийся материал (голубые кольца, линзы): цвет из вершин, свечение — glow.
static func commit_glow(st: SurfaceTool, glow: Color, energy := 2.5) -> ArrayMesh:
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh


## Труба вдоль Z с осью в c (x, y), от z0 (радиус r0) до z1 (r1), sides граней; с торцами
## (caps), гладкая или гранёная.
static func tube(st: SurfaceTool, c: Vector2, z0: float, z1: float, r0: float, r1: float, col: Color,
		sides := 12, caps := true, smooth := true) -> void:
	var slope := (r1 - r0) / (z1 - z0) if z1 != z0 else 0.0
	for k in sides:
		var a0 := TAU * k / sides + PI / sides
		var a1 := TAU * (k + 1) / sides + PI / sides
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var o := Vector3(c.x, c.y, 0)
		var v0 := o + d0 * r0 + Vector3(0, 0, z0)
		var v1 := o + d1 * r0 + Vector3(0, 0, z0)
		var v2 := o + d1 * r1 + Vector3(0, 0, z1)
		var v3 := o + d0 * r1 + Vector3(0, 0, z1)
		if smooth:
			var n0 := (d0 - Vector3(0, 0, slope)).normalized()
			var n1 := (d1 - Vector3(0, 0, slope)).normalized()
			_vert(st, v0, n0, col)
			_vert(st, v1, n1, col)
			_vert(st, v2, n1, col)
			_vert(st, v0, n0, col)
			_vert(st, v2, n1, col)
			_vert(st, v3, n0, col)
		else:
			var n := ((d0 + d1) * 0.5 - Vector3(0, 0, slope)).normalized()
			quad(st, v0, v1, v2, v3, col, n)
		if caps:
			_tri(st, o + Vector3(0, 0, z0), v1, v0, col, Vector3(0, 0, -1))
			_tri(st, o + Vector3(0, 0, z1), v3, v2, col, Vector3(0, 0, 1))


## Плоское кольцо (торец) между радиусами r_in и r_out в плоскости z, ось в c.
static func ring(st: SurfaceTool, c: Vector2, z: float, r_in: float, r_out: float, col: Color, sides := 12,
		facing := -1.0) -> void:
	for k in sides:
		var a0 := TAU * k / sides + PI / sides
		var a1 := TAU * (k + 1) / sides + PI / sides
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var o := Vector3(c.x, c.y, z)
		quad(st, o + d0 * r_in, o + d1 * r_in, o + d1 * r_out, o + d0 * r_out, col, Vector3(0, 0, facing))


## Брусок с центром c и размерами size.
static func box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for i in 8:
		v.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	cuboid(st, v, col)


## Брусок вдоль отрезка a—b сечением w × w (балки рукоятей).
static func bar(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * w * 0.5
	var up := side.cross(d).normalized() * w * 0.5
	var v := []
	for i in 8:
		var base := b if i & 4 else a
		v.append(base + (side if i & 1 else -side) + (up if i & 2 else -up))
	cuboid(st, v, col)


static func cuboid(st: SurfaceTool, v: Array, col: Color) -> void:
	var center := Vector3.ZERO
	for p in v:
		center += p
	center /= 8.0
	for q in [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]:
		var a: Vector3 = v[q[0]]
		var n: Vector3 = (v[q[1]] - a).cross(v[q[2]] - a).normalized()
		if n.dot((a + v[q[2]]) * 0.5 - center) < 0.0:
			n = -n
		quad(st, v[q[0]], v[q[1]], v[q[2]], v[q[3]], col.darkened(0.15 if n.y < -0.5 else 0.0), n)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	_tri(st, a, b, c, col, n)
	_tri(st, a, c, d, col, n)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
	_vert(st, a, n, col)
	_vert(st, b, n, col)
	_vert(st, c, n, col)


static func _vert(st: SurfaceTool, p: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(p)


## Брусок со скошенными рёбрами вдоль Z: сечение — восьмиугольник (углы срезаны на bevel),
## от z0 до z1, центр сечения c (x, y), полуразмеры hx, hy; с торцами. Даёт объём без кубичности.
static func chamfer_box(st: SurfaceTool, c: Vector2, hx: float, hy: float, z0: float, z1: float, bevel: float,
		col: Color) -> void:
	var b := minf(bevel, minf(hx, hy) * 0.9)
	var pts := [Vector2(hx, -hy + b), Vector2(hx, hy - b), Vector2(hx - b, hy), Vector2(-hx + b, hy),
		Vector2(-hx, hy - b), Vector2(-hx, -hy + b), Vector2(-hx + b, -hy), Vector2(hx - b, -hy)]
	for k in 8:
		var p0: Vector2 = c + pts[k]
		var p1: Vector2 = c + pts[(k + 1) % 8]
		var mid: Vector2 = (pts[k] + pts[(k + 1) % 8]) * 0.5
		var n := Vector3(mid.x / hx, mid.y / hy, 0).normalized()
		var shade := col.darkened(0.12) if n.y < -0.5 else (col.lightened(0.06) if n.y > 0.5 else col)
		quad(st, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1), shade, n)
		_tri(st, Vector3(c.x, c.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p0.x, p0.y, z0), col, Vector3(0, 0, -1))
		_tri(st, Vector3(c.x, c.y, z1), Vector3(p0.x, p0.y, z1), Vector3(p1.x, p1.y, z1), col, Vector3(0, 0, 1))


## Круглая перекладина вдоль X: от точки a до x = x1, радиус r.
static func tube_x(st: SurfaceTool, a: Vector3, x1: float, r: float, col: Color, sides := 10) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(0, cos(a0), sin(a0))
		var d1 := Vector3(0, cos(a1), sin(a1))
		var b := Vector3(x1, a.y, a.z)
		_vert(st, a + d0 * r, d0, col)
		_vert(st, a + d1 * r, d1, col)
		_vert(st, b + d1 * r, d1, col)
		_vert(st, a + d0 * r, d0, col)
		_vert(st, b + d1 * r, d1, col)
		_vert(st, b + d0 * r, d0, col)
