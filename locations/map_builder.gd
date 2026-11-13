extends Node3D
## Локация: плато, изрезанное извилистыми каналами-лабиринтами. Из пещер на севере каналы
## петляют, переплетаются перемычками и сходятся к воротам на юге. Всё строится кодом по
## описанию локации (levels.gd): раскладка каналов, цвета, детали вокруг, особенности (вода в
## каналах, светящиеся трещины и кристаллы). Рельеф с плоским затенением и цветами по граням
## (вершины сетки прилегают к краям каналов, поэтому края ровные, без «лесенки»), трещины,
## детали, пещеры и ворота.

const HALF := 120.0        # половина стороны карты, м
const CELL := 0.75         # шаг сетки рельефа, м
const PLATEAU := 2.0       # высота плато над дном каналов: низкие стенки, орду видно
const WALL := 1.4          # ширина откоса стенки канала
const EDGE_WOBBLE := 1.3   # неровность края каналов
const RIM_W := 0.9         # ширина светлой кромки по краю канала
const CRACK_W := 0.22      # полуширина трещины (у начала; к концу сужается)
const HASH := 16.0         # ячейка пространственной сетки отрезков

const Levels := preload("res://locations/levels.gd")
const GATE_Z := 100.0
# Слои столкновений: мир и ограждения на стене (см. _box)
const WORLD_LAYER := 1
const WALL_RAIL_LAYER := 2
## Слой отрисовки деталей на плато (деревья, камни): декали прицела на них не ложатся.
const PROPS_LAYER := 2
# Где появляется игрок: на боевом ходу посередине стены, лицом к пещерам (на север)
## Верх стены (боевой ход) и верх башен: стена невысокая — орду у ворот видно сверху
const WALL_TOP := PLATEAU + 2.2
const TOWER_TOP := WALL_TOP + 4.0
const PLAYER_SPAWN := Vector3(0, WALL_TOP + 0.1, GATE_Z + 0.6)
## Локации с туннелем вместо крепости (level "gate": "tunnel"): смотровая вышка героя у входа.
const LOOKOUT_XZ := Vector2(-15.0, GATE_Z - 3.0)
const LOOKOUT_H := 7.0

## Описание локации (элемент Levels.LEVELS); задать до добавления в сцену.
var level: Dictionary = Levels.get_level(0)

var _channels: Array = []      # [a, b, half_width]
var _channel_hash := {}
var _cracks: Array = []      # [a, b]
var _noise := FastNoiseLite.new()
var _pal: Dictionary
var _paths: Array = []
## Детали на плато (камни, деревья, хижины): x, z и примерный радиус — турель на них не ставится.
var props: Array[Vector3] = []
## Крупное, что заслоняет линию огня (деревья, хижины, столбы): x, z, радиус кроны, верх по высоте.
var blockers: Array[Vector4] = []


func _ready() -> void:
	_pal = level["palette"]
	_noise.seed = 11
	_noise.frequency = 0.08
	_paths = Levels.make_paths(level)
	for path in _paths:
		var pts := _smooth(path["pts"])
		for i in pts.size() - 1:
			_add_segment(_channels, _channel_hash, pts[i], pts[i + 1], path["w"], path["w"] + WALL + EDGE_WOBBLE + 2.0)
	_make_cracks()
	_build_terrain()
	_build_cracks()
	_build_scatter()
	_build_horizon(level.get("horizon", "mesas"))
	if level.has("water"):
		_build_water(level["water"])
	for cave in caves():
		_build_cave(cave[0], cave[1])
	if is_tunnel():
		_build_tunnel()
		_build_lookout()
	else:
		_build_gate()
	if level.get("valley", false):
		_build_cliffs()


## Пещеры: начало канала и следующая точка (куда смотрит выход).
func caves() -> Array:
	var out := []
	for i in level["caves"]:
		var pts: Array = _paths[i]["pts"]
		out.append([pts[0], pts[1]])
	return out


## Свет и небо локации: sky, ambient, ambient_energy, sun, sun_energy, sun_rot, fog_begin, fog_end.
func light() -> Dictionary:
	return level["light"]


# --- рельеф --------------------------------------------------------------------------------

## Расстояние от точки до края дна ближайшего канала (меньше нуля — внутри канала).
func channel_dist(p: Vector2) -> float:
	var best := 99.0
	for idx in _channel_hash.get(_hash_key(p), []):
		var s: Array = _channels[idx]
		best = minf(best, _seg_dist(p, s[0], s[1]) - s[2])
	return best + _noise.get_noise_2d(p.x * 1.6, p.y * 1.6) * EDGE_WOBBLE


## Двор базы за воротами (base_builder.gd): там ни камней, ни трещин.
static func in_base(p: Vector2) -> bool:
	return absf(p.x) < 33.0 and p.y > GATE_Z - 1.0


## Мешает ли деталь на плато поставить что-то радиусом r в точке p.
## Заслоняет ли что-то крупное (дерево, хижину) отрезок от a до b — турели и дрон сквозь кроны и
## стены хижин не стреляют. Земля и скалы проверяются лучом физики отдельно.
func line_blocked(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - a2
	var len2 := maxf(ab.length_squared(), 0.0001)
	var lo := a2.min(a2 + ab)
	var hi := a2.max(a2 + ab)
	for q in blockers:
		if q.x < lo.x - q.z or q.x > hi.x + q.z or q.y < lo.y - q.z or q.y > hi.y + q.z:
			continue
		var c := Vector2(q.x, q.y)
		var t := clampf((c - a2).dot(ab) / len2, 0.0, 1.0)
		# У самого конца (цель) и начала (дуло) не считаем — дерево рядом с целью не прячет её целиком
		if t < 0.04 or t > 0.96:
			continue
		if (a2 + ab * t).distance_squared_to(c) < q.z * q.z and lerpf(a.y, b.y, t) < q.w:
			return true
	return false


func prop_near(p: Vector2, r: float) -> bool:
	for q in props:
		if Vector2(q.x, q.y).distance_to(p) < q.z + r:
			return true
	return false


func height(p: Vector2) -> float:
	var d := channel_dist(p)
	if d <= 0.0:
		return _noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.12
	if d < WALL:
		return PLATEAU * d / WALL
	return PLATEAU + _noise.get_noise_2d(p.x * 0.6, p.y * 0.6) * 0.15


## Сдвинуть вершину сетки точно на ближайшую линию рельефа (дно, верх стенки, край кромки),
## если она рядом: так края каналов получаются ровными линиями, а не ступеньками клеток.
func _snap(p: Vector2) -> Vector2:
	var d := channel_dist(p)
	for target in [0.0, WALL, WALL + RIM_W]:
		if absf(d - target) < CELL * 0.5:
			for i in 2:
				var g := Vector2(channel_dist(p + Vector2(0.05, 0)) - channel_dist(p - Vector2(0.05, 0)),
					channel_dist(p + Vector2(0, 0.05)) - channel_dist(p - Vector2(0, 0.05))) / 0.1
				if g.length_squared() < 0.04:
					break
				p -= g * (channel_dist(p) - target) / g.length_squared()
			break
	return p


func _build_terrain() -> void:
	var n := int(HALF * 2.0 / CELL)
	var verts := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			var p := Vector2(-HALF + ix * CELL, -HALF + iz * CELL)
			# Край карты не двигаем — к нему примыкает плато за картой
			if ix > 0 and iz > 0 and ix < n and iz < n:
				p = _snap(p)
			verts[iz * (n + 1) + ix] = Vector3(p.x, height(p), p.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var v00 := verts[iz * (n + 1) + ix]
			var v10 := verts[iz * (n + 1) + ix + 1]
			var v01 := verts[(iz + 1) * (n + 1) + ix]
			var v11 := verts[(iz + 1) * (n + 1) + ix + 1]
			# Диагональ клетки чередуется — рельеф без «ёлочки»
			if (ix + iz) % 2 == 0:
				_tri(st, v00, v10, v11)
				_tri(st, v00, v11, v01)
			else:
				_tri(st, v00, v10, v01)
				_tri(st, v10, v11, v01)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _vertex_color_material()
	# Земля тень не отбрасывает: зубчатые края каналов при низком солнце давали на дне длинные
	# «пилы» теней, которые дрожали и ползли за камерой в полёте. Стенки и так темнее по освещению,
	# а тени от деревьев, вышек и турелей на землю ложатся как прежде.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	# Плато продолжается за краем карты до горизонта: четыре полосы вокруг карты
	var m := StandardMaterial3D.new()
	m.albedo_color = _pal["top"]
	m.roughness = 1.0
	var far := 1500.0
	for strip in [[Vector2(2.0 * (HALF + far), far), Vector2(0, -HALF - far / 2)],
			[Vector2(2.0 * (HALF + far), far), Vector2(0, HALF + far / 2)],
			[Vector2(far, 2.0 * HALF), Vector2(-HALF - far / 2, 0)],
			[Vector2(far, 2.0 * HALF), Vector2(HALF + far / 2, 0)]]:
		var plane := PlaneMesh.new()
		plane.size = strip[0]
		var outer := MeshInstance3D.new()
		outer.mesh = plane
		outer.position = Vector3(strip[1].x, PLATEAU - 0.1, strip[1].y)
		outer.material_override = m
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(outer)
		var floor_body := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(strip[0].x, 0.4, strip[0].y)
		floor_shape.shape = slab
		floor_body.add_child(floor_shape)
		floor_body.position = Vector3(strip[1].x, PLATEAU - 0.3, strip[1].y)
		add_child(floor_body)


## Треугольник с плоской нормалью; цвет — по тому, где он лежит: дно, стенка, кромка, плато.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	var center := (a + b + c) / 3.0
	var p := Vector2(center.x, center.z)
	var col: Color
	var d := channel_dist(p)
	# Крутые грани — всегда стенка, даже если центр попал на кромку (без светлых «зубцов»)
	if (d < WALL and center.y > 0.15) or (normal.y < 0.75 and center.y > 0.15):
		# Стенка: к дну темнее
		col = _pal["wall"].darkened(0.2 * (1.0 - center.y / PLATEAU))
	elif d < WALL:
		col = _shade(_pal["floor"], p, 0.06)
	elif d < WALL + RIM_W:
		# Светлая кромка вдоль края канала
		col = _pal["rim"]
	else:
		col = _shade(_pal["top"], p, 0.05)
	st.set_color(col)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _make_cracks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var count := 0
	while count < int(level.get("cracks", 90)):
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		if channel_dist(p) < WALL + 3.0 or in_base(p):
			continue
		count += 1
		var dir := rng.randf() * TAU
		for step in rng.randi_range(3, 8):
			dir += rng.randf_range(-0.9, 0.9)
			var q := p + Vector2.from_angle(dir) * rng.randf_range(3.0, 8.0)
			if channel_dist(q) < WALL + 1.5 or absf(q.x) > HALF or absf(q.y) > HALF or in_base(q):
				break
			_cracks.append([p, q])
			# Иногда трещина ветвится
			if rng.randf() < 0.3:
				var side := q + Vector2.from_angle(dir + rng.randf_range(0.8, 1.6) * signf(rng.randf() - 0.5)) * rng.randf_range(2.0, 5.0)
				if channel_dist(side) > WALL + 1.5 and not in_base(side):
					_cracks.append([q, side])
			p = q


## Трещины — тонкие сужающиеся полоски поверх плато (чёткие линии, независимо от сетки).
func _build_cracks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(_pal["crack"])
	st.set_normal(Vector3.UP)
	for s in _cracks:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var side := (b - a).orthogonal().normalized()
		# Делим на куски по ~1 м, чтобы полоска шла по неровностям плато
		var pieces := maxi(int(a.distance_to(b)), 1)
		for k in pieces:
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			var w0 := CRACK_W * lerpf(1.0, 0.45, float(k) / pieces)
			var w1 := CRACK_W * lerpf(1.0, 0.45, float(k + 1) / pieces)
			var q := [_on_top(p0 + side * w0), _on_top(p1 + side * w1), _on_top(p1 - side * w1), _on_top(p0 - side * w0)]
			for i in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# Лава и кристаллы — трещины светятся
	mi.material_override = _glow_material(level.get("crack_glow", 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _on_top(p: Vector2) -> Vector3:
	return Vector3(p.x, height(p) + 0.05, p.y)


# --- детали ----------------------------------------------------------------------------------

## Детали локации на плато и на дне каналов (список props в описании локации).
func _build_scatter() -> void:
	var rules := {
		"top": func(d: float) -> bool: return d > WALL + 4.0,
		"edge": func(d: float) -> bool: return d > WALL + RIM_W + 0.3 and d < WALL + 5.0,
		"floor": func(d: float) -> bool: return d < -1.0 and d > -2.6,
		"top_floor": func(d: float) -> bool: return d > WALL + 4.0 or (d < -1.0 and d > -2.6),
		"any": func(d: float) -> bool: return d > WALL + RIM_W + 0.5 or d < -0.3,
	}
	var meshes := {}
	var seed := 23
	for prop: Dictionary in level["props"]:
		var key := "%s_%.2f" % [prop["mesh"], prop.get("glow", 0.0)]
		if not meshes.has(key):
			meshes[key] = _prop_mesh(prop["mesh"], prop.get("glow", 0.0))
		# Камни сплющены, остальное — в полный рост
		var squash := Vector2(0.5, 0.9) if prop["mesh"] == "rock" else Vector2(0.85, 1.2)
		# Тени — только у крупного: деревья, хижины, столбы; мелочь без теней (дешевле)
		var shadow: bool = prop["mesh"] in ["oak", "pine", "dead_tree", "pillar", "mound", "hut", "cactus"]
		_scatter(meshes[key], prop["count"], seed, rules[prop["where"]], prop["min"], prop["max"], squash, prop["color"], shadow,
			shadow)
		seed += 8


## Горизонт: кольцо крупных форм за краем карты — у каждой локации своё (столовые горы, скалы-иглы,
## дюны, холмы, снежные пики, вулкан с дымом, гигантские кристаллы, ульи, луна в небе). Так
## локации не похожи друг на друга даже со стены, а карта не обрывается в пустоту.
func _build_horizon(kind: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	glow.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + absi(kind.hash() % 1000)
	var top: Color = _pal["top"]
	var wall: Color = _pal["wall"]
	var rock: Color = _pal["rock"]
	var count := 30
	for k in count:
		var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / count
		var r := rng.randf_range(190.0, 290.0)
		var c := Vector3(cos(a) * r, -2.0, sin(a) * r)
		var sz := rng.randf_range(0.7, 1.3)
		match kind:
			"mesas", "moon":
				# Столовая гора: крутые бока, плоская вершина светлее
				var h := rng.randf_range(18.0, 34.0) * sz
				_frustum(st, c, c + Vector3(0, h, 0), 34.0 * sz, 27.0 * sz, 7, wall.darkened(0.15))
				_frustum(st, c + Vector3(0, h, 0), c + Vector3(0, h + 3.0, 0), 27.0 * sz, 25.0 * sz, 7, top.darkened(0.1))
			"spires":
				for j in 3:
					var o := c + Vector3(rng.randf_range(-22, 22), 0, rng.randf_range(-22, 22))
					var h := rng.randf_range(35.0, 75.0) * sz
					_frustum(st, o, o + Vector3(0, h * 0.7, 0), 9.0 * sz, 6.0 * sz, 6, wall.darkened(0.1))
					_frustum(st, o + Vector3(0, h * 0.7, 0), o + Vector3(0, h, 0), 6.0 * sz, 1.5, 6, rock)
			"dunes":
				_frustum(st, c, c + Vector3(0, 15.0 * sz, 0), 55.0 * sz, 24.0 * sz, 9, top.darkened(0.22))
				_frustum(st, c + Vector3(0, 15.0 * sz, 0), c + Vector3(0, 21.0 * sz, 0), 24.0 * sz, 0.0, 9, top.darkened(0.1))
			"hills":
				var green := top.darkened(0.12)
				_frustum(st, c, c + Vector3(0, 10.0 * sz, 0), 50.0 * sz, 38.0 * sz, 9, green)
				_frustum(st, c + Vector3(0, 10.0 * sz, 0), c + Vector3(0, 19.0 * sz, 0), 38.0 * sz, 20.0 * sz, 9, green.lightened(0.05))
				_frustum(st, c + Vector3(0, 19.0 * sz, 0), c + Vector3(0, 23.0 * sz, 0), 20.0 * sz, 0.0, 9, green.lightened(0.1))
			"peaks", "volcano":
				# Пик: тёмный камень, сверху снег (у вулкана — без снега, пепел)
				var h := rng.randf_range(55.0, 95.0) * sz
				var cap := Color(0.95, 0.97, 1.0) if kind == "peaks" else rock.darkened(0.3)
				_frustum(st, c, c + Vector3(0, h * 0.55, 0), 40.0 * sz, 18.0 * sz, 7, rock.darkened(0.2))
				_frustum(st, c + Vector3(0, h * 0.55, 0), c + Vector3(0, h, 0), 18.0 * sz, 0.0, 7, cap)
			"crystals":
				# Гигантские светящиеся кристаллы пучками, наклонены в разные стороны
				var tint: Color = [Color(0.4, 0.9, 1.0), Color(1.0, 0.45, 0.95), Color(0.65, 0.55, 1.0)][k % 3]
				for j in 3:
					var tilt := Vector3(rng.randf_range(-0.35, 0.35), 1.0, rng.randf_range(-0.35, 0.35)).normalized()
					var o := c + Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))
					var h := rng.randf_range(40.0, 100.0) * sz
					_frustum(glow, o, o + tilt * h, rng.randf_range(7.0, 13.0) * sz, 0.0, 6, tint)
				_frustum(st, c, c + Vector3(0, 6.0, 0), 30.0 * sz, 18.0 * sz, 7, rock.darkened(0.2))
			"hive":
				# Гигантский улей: ярусы купола и тёмные летки
				var hh := rng.randf_range(30.0, 60.0) * sz
				_frustum(st, c, c + Vector3(0, hh * 0.4, 0), 30.0 * sz, 24.0 * sz, 8, wall)
				_frustum(st, c + Vector3(0, hh * 0.4, 0), c + Vector3(0, hh * 0.8, 0), 24.0 * sz, 12.0 * sz, 8, wall.lightened(0.06))
				_frustum(st, c + Vector3(0, hh * 0.8, 0), c + Vector3(0, hh, 0), 12.0 * sz, 0.0, 8, wall.darkened(0.08))
				for j in 3:
					var ang := rng.randf() * TAU
					var y := hh * rng.randf_range(0.2, 0.6)
					var rad := lerpf(30.0, 12.0, y / hh) * sz
					var out := Vector3(cos(ang), 0, sin(ang))
					_frustum(st, c + out * (rad - 2.0) + Vector3(0, y, 0), c + out * (rad + 1.0) + Vector3(0, y, 0),
						4.0 * sz, 3.5 * sz, 6, Color(0.12, 0.08, 0.06))
	if kind == "moon":
		# Огромная бледная луна в небе на севере
		# Плоский диск, повёрнутый к стене (ось — вдоль Z), чтобы со стены был круглым
		var moon := Vector3(90, 150, -520)
		_frustum(glow, moon + Vector3(0, 0, -2), moon, 42.0, 42.0, 24, Color(0.95, 0.95, 0.85))
		_frustum(glow, moon + Vector3(-12, 10, 1), moon + Vector3(-12, 10, 1.5), 9.0, 9.0, 12, Color(0.8, 0.8, 0.72))
		_frustum(glow, moon + Vector3(14, -8, 1), moon + Vector3(14, -8, 1.5), 6.0, 6.0, 12, Color(0.8, 0.8, 0.72))
	if kind == "volcano":
		# Великан-вулкан на севере: конус, светящийся кратер и столб дыма над ним
		var v := Vector3(-40, -2, -360)
		_frustum(st, v, v + Vector3(0, 95, 0), 170.0, 42.0, 10, rock.darkened(0.25))
		_frustum(st, v + Vector3(0, 95, 0), v + Vector3(0, 100, 0), 42.0, 36.0, 10, rock.darkened(0.35))
		_frustum(glow, v + Vector3(0, 99, 0), v + Vector3(0, 101, 0), 34.0, 30.0, 10, Color(1.0, 0.45, 0.1))
		for j in 7:
			var y := 112.0 + j * 22.0
			var o := v + Vector3(j * 6.0, y, -j * 3.0)
			var rr := 18.0 + j * 5.0
			_frustum(st, o - Vector3(0, rr * 0.6, 0), o + Vector3(0, rr * 0.6, 0), rr, rr * 0.8, 8,
				Color(0.18, 0.15, 0.15).lightened(j * 0.03))
	for item in [[st, _vertex_color_material()], [glow, _glow_material(1.6)]]:
		var tool: SurfaceTool = item[0]
		tool.generate_normals()
		var mesh := tool.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = item[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = PROPS_LAYER
		add_child(mi)


## Вода в каналах (болото): ровная гладь чуть выше дна, на плато её не видно.
func _build_water(color: Color) -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0, HALF * 2.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.8
	plane.material = m
	water.mesh = plane
	water.position.y = 0.38
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


## Разбросать копии меша по карте там, где rule(расстояние до канала) разрешает.
func _scatter(mesh: Mesh, count: int, rng_seed: int, rule: Callable, s_min: float, s_max: float,
		squash: Vector2, color: Color, shadow := true, blocks := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while xforms.size() < count and tries < count * 40:
		tries += 1
		var p := Vector2(rng.randf_range(-HALF + 4, HALF - 4), rng.randf_range(-HALF + 4, HALF - 4))
		if not rule.call(channel_dist(p)) or in_base(p):
			continue
		# В замкнутой долине за скалами ничего не ставим — там пусто и не видно
		if level.has("bounds") and not (level["bounds"] as Rect2).grow(-3.0).has_point(p):
			continue
		var s := rng.randf_range(s_min, s_max)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s * rng.randf_range(0.9, 1.4), s * rng.randf_range(squash.x, squash.y), s))
		xforms.append(Transform3D(basis, Vector3(p.x, height(p) - 0.15 * s, p.y)))
		if channel_dist(p) > 0.0:
			props.append(Vector3(p.x, p.y, s * 0.8))
		if blocks:
			var aabb := mesh.get_aabb()
			blockers.append(Vector4(p.x, p.y, maxf(aabb.size.x, aabb.size.z) * 0.42 * s,
				height(p) + aabb.end.y * s * 0.95))
		var v := rng.randf_range(-0.08, 0.08)
		colors.append(color.lightened(v) if v > 0.0 else color.darkened(-v))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Свой слой отрисовки: метка прицела (декаль) деревья и камни не красит
	mmi.layers = PROPS_LAYER
	add_child(mmi)


## Меш детали по имени (см. levels.gd), светящийся, если glow > 0.
func _prop_mesh(kind: String, glow: float) -> ArrayMesh:
	var mesh: ArrayMesh
	match kind:
		"rock":
			mesh = _rock_mesh()
		"shrub":
			mesh = _shrub_mesh()
		_:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_smooth_group(-1)
			call("_build_" + kind, st)
			st.generate_normals()
			mesh = st.commit()
			mesh.surface_set_material(0, _vertex_color_material())
	if glow > 0.0:
		mesh.surface_set_material(0, _glow_material(glow))
	return mesh


## Гранёный усечённый конус от a до b (радиусы r0 → r1), лицом наружу, с крышками.
func _frustum(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var up := axis.cross(side)
	var inside := (a + b) / 2.0
	var ring0 := []
	var ring1 := []
	for k in segs:
		var ang := TAU * k / segs
		var o := side * cos(ang) + up * sin(ang)
		ring0.append(a + o * r0)
		ring1.append(b + o * r1)
	for k in segs:
		var k2 := (k + 1) % segs
		_tri_out(st, ring0[k], ring0[k2], ring1[k2], col, inside)
		if r1 > 0.001:
			_tri_out(st, ring0[k], ring1[k2], ring1[k], col, inside)
		_tri_out(st, a, ring0[k2], ring0[k], col.darkened(0.1), inside + axis * 0.01)
		if r1 > 0.001:
			_tri_out(st, b, ring1[k], ring1[k2], col.lightened(0.06), inside - axis * 0.01)


func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - inside) > 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Кристаллы, соль, лёд, обсидиан: пучок гранёных шипов, наклонённых наружу.
func _build_spike(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 5:
		var ang := TAU * k / 5.0 + rng.randf() * 0.6
		var tilt := 0.0 if k == 0 else rng.randf_range(0.25, 0.6)
		var dir := Vector3(sin(tilt) * cos(ang), cos(tilt), sin(tilt) * sin(ang))
		var base := Vector3(cos(ang), 0, sin(ang)) * (0.0 if k == 0 else 0.15)
		var h := rng.randf_range(1.0, 1.5) if k == 0 else rng.randf_range(0.5, 0.95)
		_frustum(st, base, base + dir * h, rng.randf_range(0.12, 0.2), 0.0, 5, Color.WHITE.darkened(rng.randf_range(0.0, 0.2)))


## Кактус-сагуаро: ствол и две загнутые вверх руки.
func _build_cactus(st: SurfaceTool) -> void:
	var c := Color.WHITE
	_frustum(st, Vector3.ZERO, Vector3(0, 1.6, 0), 0.18, 0.15, 8, c)
	_frustum(st, Vector3(0, 1.6, 0), Vector3(0, 1.75, 0), 0.15, 0.0, 8, c)
	for s in [-1.0, 1.0]:
		var y := 0.6 if s < 0 else 0.85
		_frustum(st, Vector3(0, y, 0), Vector3(s * 0.4, y, 0), 0.1, 0.1, 6, c.darkened(0.08))
		_frustum(st, Vector3(s * 0.4, y - 0.05, 0), Vector3(s * 0.4, y + 0.55, 0), 0.11, 0.09, 6, c)
		_frustum(st, Vector3(s * 0.4, y + 0.55, 0), Vector3(s * 0.4, y + 0.65, 0), 0.09, 0.0, 6, c)


## Ель: короткий ствол и три яруса хвои.
func _build_pine(st: SurfaceTool) -> void:
	_frustum(st, Vector3.ZERO, Vector3(0, 0.45, 0), 0.08, 0.07, 6, Color(0.55, 0.4, 0.3))
	for layer in [[0.3, 0.6, 0.75], [0.75, 0.46, 0.6], [1.15, 0.32, 0.55]]:
		_frustum(st, Vector3(0, layer[0], 0), Vector3(0, layer[0] + layer[2], 0), layer[1], 0.0, 7, Color.WHITE)


## Мёртвое дерево: кривой ствол и голые ветви.
func _build_dead_tree(st: SurfaceTool) -> void:
	var c := Color.WHITE
	var top := Vector3(0.12, 1.4, 0.05)
	_frustum(st, Vector3.ZERO, Vector3(0.05, 0.7, 0), 0.1, 0.08, 6, c)
	_frustum(st, Vector3(0.05, 0.7, 0), top, 0.08, 0.05, 6, c)
	for br in [[Vector3(0.05, 0.75, 0), Vector3(-0.45, 1.15, 0.1)], [Vector3(0.1, 1.05, 0), Vector3(0.5, 1.4, -0.15)],
			[top, Vector3(0.05, 1.85, 0.2)], [Vector3(0.08, 0.9, 0), Vector3(0.1, 1.2, 0.45)]]:
		_frustum(st, br[0], br[1], 0.045, 0.015, 5, c.darkened(0.1))


## Гриб: светлая ножка и красная шляпка.
func _build_mushroom(st: SurfaceTool) -> void:
	_frustum(st, Vector3.ZERO, Vector3(0, 0.6, 0), 0.1, 0.08, 7, Color(0.92, 0.88, 0.78))
	var cap := Color(0.72, 0.24, 0.18)
	_frustum(st, Vector3(0, 0.55, 0), Vector3(0, 0.72, 0), 0.48, 0.34, 9, cap)
	_frustum(st, Vector3(0, 0.72, 0), Vector3(0, 0.86, 0), 0.34, 0.0, 9, cap.lightened(0.08))


## Камыш: пучок тонких стеблей с бурыми початками.
func _build_reed(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 8:
		var ang := rng.randf() * TAU
		var base := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.0, 0.25)
		var tip := base + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.8, 1.3), rng.randf_range(-0.15, 0.15))
		_frustum(st, base, tip, 0.03, 0.01, 4, Color.WHITE)
		if k % 2 == 0:
			var head := base.lerp(tip, 0.75)
			_frustum(st, head, base.lerp(tip, 0.92), 0.05, 0.05, 5, Color(0.6, 0.38, 0.22))


## Каменный столб-останец: ярусы, сужающиеся кверху, сверху плоская «шляпа».
func _build_pillar(st: SurfaceTool) -> void:
	_frustum(st, Vector3.ZERO, Vector3(0, 0.6, 0), 0.5, 0.42, 7, Color.WHITE)
	_frustum(st, Vector3(0, 0.6, 0), Vector3(0, 1.3, 0), 0.4, 0.3, 7, Color.WHITE.darkened(0.12))
	_frustum(st, Vector3(0, 1.3, 0), Vector3(0, 1.75, 0), 0.32, 0.28, 7, Color.WHITE)
	_frustum(st, Vector3(0.05, 1.75, 0), Vector3(0.05, 1.95, 0), 0.48, 0.42, 7, Color.WHITE.lightened(0.1))


## Лиственное дерево: ствол и пышная крона из трёх гранёных шаров.
func _build_oak(st: SurfaceTool) -> void:
	_frustum(st, Vector3.ZERO, Vector3(0.05, 1.1, 0), 0.17, 0.11, 6, Color(0.42, 0.3, 0.19))
	var leaf := Color(0.34, 0.55, 0.2)
	_ball(st, Vector3(0, 1.6, 0), 0.75, leaf)
	_ball(st, Vector3(0.48, 1.3, 0.15), 0.5, leaf.darkened(0.08))
	_ball(st, Vector3(-0.38, 1.38, -0.22), 0.55, leaf.lightened(0.06))


## Гоблинская хижина: круглая стена из жердей, соломенная крыша-конус, тёмный вход.
func _build_hut(st: SurfaceTool) -> void:
	var wall := Color(0.5, 0.36, 0.22)
	_frustum(st, Vector3.ZERO, Vector3(0, 0.75, 0), 0.8, 0.74, 9, wall)
	var straw := Color(0.78, 0.66, 0.36)
	_frustum(st, Vector3(0, 0.7, 0), Vector3(0, 1.0, 0), 1.02, 0.7, 9, straw.darkened(0.06))
	_frustum(st, Vector3(0, 1.0, 0), Vector3(0, 1.75, 0), 0.7, 0.0, 9, straw)
	# Торчащая из макушки жердь и вход
	_frustum(st, Vector3(0, 1.6, 0), Vector3(0.05, 2.0, 0.03), 0.04, 0.02, 4, wall.darkened(0.2))
	_frustum(st, Vector3(0, 0.0, 0.7), Vector3(0, 0.0, 0.84), 0.3, 0.3, 6, Color(0.1, 0.07, 0.04))


## Заострённые колья частокола, вбитые с наклоном наружу.
func _build_stakes(st: SurfaceTool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 5:
		var x := -0.8 + k * 0.4 + rng.randf_range(-0.06, 0.06)
		var h := rng.randf_range(0.9, 1.3)
		var top := Vector3(x + rng.randf_range(-0.08, 0.08), h, rng.randf_range(-0.25, -0.1))
		_frustum(st, Vector3(x, 0, 0), top - (top - Vector3(x, 0, 0)).normalized() * 0.25, 0.07, 0.07, 5, Color.WHITE)
		_frustum(st, top - (top - Vector3(x, 0, 0)).normalized() * 0.25, top, 0.07, 0.0, 5, Color.WHITE.lightened(0.15))
	_frustum(st, Vector3(-0.9, 0.45, -0.04), Vector3(0.9, 0.45, -0.07), 0.04, 0.04, 4, Color.WHITE.darkened(0.25))


## Гранёный шар (крона дерева) из трёх поясов.
func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	_frustum(st, c + Vector3(0, -r, 0), c + Vector3(0, -r * 0.35, 0), r * 0.3, r * 0.95, 7, col.darkened(0.12))
	_frustum(st, c + Vector3(0, -r * 0.35, 0), c + Vector3(0, r * 0.35, 0), r * 0.95, r * 0.9, 7, col)
	_frustum(st, c + Vector3(0, r * 0.35, 0), c + Vector3(0, r, 0), r * 0.9, 0.0, 7, col.lightened(0.08))


## Улей роя: купол из песка и смолы с тёмными летками.
func _build_mound(st: SurfaceTool) -> void:
	var c := Color.WHITE
	_frustum(st, Vector3.ZERO, Vector3(0, 0.45, 0), 0.95, 0.78, 9, c)
	_frustum(st, Vector3(0, 0.45, 0), Vector3(0, 0.9, 0), 0.78, 0.52, 9, c.lightened(0.05))
	_frustum(st, Vector3(0, 0.9, 0), Vector3(0, 1.25, 0), 0.52, 0.22, 9, c)
	_frustum(st, Vector3(0, 1.25, 0), Vector3(0, 1.4, 0), 0.22, 0.0, 9, c.darkened(0.05))
	var dark := Color(0.15, 0.1, 0.08)
	for hole in [[0.3, 0.0], [0.7, 2.1], [0.55, 4.0], [1.05, 1.0]]:
		var y: float = hole[0]
		var ang: float = hole[1]
		var r := 0.86 - y * 0.42
		var out := Vector3(cos(ang), 0, sin(ang))
		_frustum(st, out * (r - 0.05) + Vector3(0, y, 0), out * (r + 0.07) + Vector3(0, y, 0), 0.13, 0.11, 6, dark)


## Сухой куст: пучок тонких наклонных шипов.
func _shrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for k in 7:
		var dir := Vector3.UP.rotated(Vector3.FORWARD, rng.randf_range(0.3, 0.9)).rotated(Vector3.UP, k * TAU / 7.0 + rng.randf() * 0.5)
		var tip := dir * rng.randf_range(0.7, 1.1)
		var side := dir.cross(Vector3.UP).normalized() * 0.06
		var fwd := dir.cross(side).normalized() * 0.06
		var base := [side, fwd, -side, -fwd]
		for i in 4:
			st.add_vertex(base[i])
			st.add_vertex(tip)
			st.add_vertex(base[(i + 1) % 4])
	st.generate_normals()
	var mesh := st.commit()
	var m := _vertex_color_material()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh


## Камень: икосаэдр со сдвинутыми вершинами, плоское затенение.
func _rock_mesh() -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized() * rng.randf_range(0.75, 1.15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		# Цвет задаётся у каждой копии (MultiMesh), меш — белый
		st.set_color(Color.WHITE)
		# Обход по часовой стрелке снаружи — лицевая сторона в Godot
		for p in [a, c, b]:
			st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _vertex_color_material())
	return mesh


## Пещера у начала канала: скала над плато, в ней тёмный проём с каменной рамой.
func _build_cave(start: Vector2, next: Vector2) -> void:
	if level.get("monster", "bug") == "goblin":
		_build_camp(start, next)
		return
	var dir := (next - start).normalized()
	var w: float = minf(_paths[0]["w"], 5.5)
	var root := Node3D.new()
	root.position = Vector3(start.x, 0, start.y)
	# Локальная -Z смотрит от канала в скалу
	root.rotation.y = atan2(dir.x, dir.y)
	add_child(root)
	var mouth := w * 1.4
	# Скала, из которой выходит канал
	var rock := MeshInstance3D.new()
	rock.mesh = _rock_mesh()
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = _pal["rock"].lightened(0.1)
	rock_mat.roughness = 1.0
	rock.material_override = rock_mat
	rock.scale = Vector3(mouth * 0.75, 3.6, 4.5)
	rock.position = Vector3(0, 0.6, -w - 2.0)
	root.add_child(rock)
	var rock_body := StaticBody3D.new()
	var rock_shape := CollisionShape3D.new()
	rock_shape.shape = rock.mesh.create_convex_shape()
	rock_body.add_child(rock_shape)
	rock_body.transform = rock.transform
	root.add_child(rock_body)
	# Тёмный проём и рама из грубых камней
	_box(root, Vector3(mouth, 3.4, 3.0), Vector3(0, 1.7, -w + 0.4), _pal["cave"], WORLD_LAYER, level.get("crack_glow", 0.0) > 2.0)
	_box(root, Vector3(1.4, 3.8, 1.6), Vector3(-mouth / 2 - 0.5, 1.9, -w + 2.0), _pal["stone"])
	_box(root, Vector3(1.4, 3.8, 1.6), Vector3(mouth / 2 + 0.5, 1.9, -w + 2.0), _pal["stone"])
	_box(root, Vector3(mouth + 3.0, 1.0, 1.8), Vector3(0, 4.1, -w + 2.0), _pal["stone"])


## Гоблинский лагерь вместо пещеры: частокол из брёвен поперёк тропы, в нём ворота с
## перекладиной и тёмный проход, по бокам две сторожевые вышки.
func _build_camp(start: Vector2, next: Vector2) -> void:
	var dir := (next - start).normalized()
	var w: float = minf(_paths[0]["w"], 5.5)
	var root := Node3D.new()
	root.position = Vector3(start.x, 0, start.y)
	root.rotation.y = atan2(dir.x, dir.y)
	add_child(root)
	var wood: Color = _pal["wood"]
	var mouth := w * 1.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# Частокол: брёвна с заострёнными верхушками, в середине — проход
	var rng := RandomNumberGenerator.new()
	rng.seed = int(start.x * 7.0 + start.y)
	var x := -w - 7.0
	while x < w + 7.0:
		if absf(x) > mouth / 2.0:
			var h := rng.randf_range(3.2, 3.9)
			var col := wood.lightened(rng.randf_range(0.0, 0.18))
			var base := Vector3(x, 0, -w + 0.5)
			_frustum(st, base, base + Vector3(0, h, 0), 0.32, 0.3, 6, col)
			_frustum(st, base + Vector3(0, h, 0), base + Vector3(0, h + 0.7, 0), 0.3, 0.0, 6, col.lightened(0.08))
		x += 0.62
	# Сторожевые вышки у прохода: четыре столба и площадка с навесом
	for s in [-1.0, 1.0]:
		var c := Vector3(s * (mouth / 2.0 + 1.2), 0, -w + 1.6)
		for corner in [Vector3(-0.6, 0, -0.6), Vector3(0.6, 0, -0.6), Vector3(-0.6, 0, 0.6), Vector3(0.6, 0, 0.6)]:
			_frustum(st, c + corner, c + corner * 0.8 + Vector3(0, 5.0, 0), 0.12, 0.1, 5, wood.darkened(0.1))
		_frustum(st, c + Vector3(0, 4.9, 0), c + Vector3(0, 5.15, 0), 0.95, 0.95, 4, wood.lightened(0.1))
		_frustum(st, c + Vector3(0, 5.8, 0), c + Vector3(0, 6.7, 0), 1.05, 0.0, 4, Color(0.78, 0.66, 0.36))
		for post in [Vector3(-0.55, 5.1, -0.55), Vector3(0.55, 5.1, 0.55)]:
			_frustum(st, c + post, c + post + Vector3(0, 0.75, 0), 0.06, 0.06, 4, wood.darkened(0.1))
	# Перекладина над проходом
	_frustum(st, Vector3(-mouth / 2.0 - 0.6, 3.6, -w + 0.5), Vector3(mouth / 2.0 + 0.6, 3.6, -w + 0.5), 0.26, 0.26, 6, wood.darkened(0.05))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vertex_color_material()
	root.add_child(mi)
	# Тёмный проход в лагерь
	_box(root, Vector3(mouth, 3.4, 1.0), Vector3(0, 1.7, -w - 0.3), _pal["cave"])


## Ворота поперёк широкого канала у южного края: невысокая стена, две башни и створки.
## По верху стены — боевой ход: спереди только низкий бортик (жуков под самой стеной видно),
## сзади перила. Упасть нельзя: со всех сторон невидимые ограждения.
func _build_gate() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, 0, GATE_Z)
	add_child(root)
	var stone: Color = _pal["stone"]
	var top := WALL_TOP - 0.3
	for s in [-1.0, 1.0]:
		_box(root, Vector3(11.0, top, 3.0), Vector3(s * 9.5, top / 2, 0), stone)
		# Башня
		_box(root, Vector3(6.0, TOWER_TOP - 1.0, 6.0), Vector3(s * 16.5, (TOWER_TOP - 1.0) / 2, 0), stone.darkened(0.05))
		_box(root, Vector3(7.0, 1.0, 7.0), Vector3(s * 16.5, TOWER_TOP - 0.5, 0), stone.darkened(0.15))
	# Створки и перемычка над ними
	_box(root, Vector3(8.0, 3.2, 1.0), Vector3(0, 1.6, 0), _pal["wood"])
	_box(root, Vector3(8.0, top - 3.2, 3.0), Vector3(0, 3.2 + (top - 3.2) / 2, 0), stone)
	# Боевой ход: верх стены и деревянный настил за ней
	_box(root, Vector3(30.0, 0.3, 3.0), Vector3(0, WALL_TOP - 0.15, 0), stone.darkened(0.12))
	_box(root, Vector3(27.0, 0.3, 1.6), Vector3(0, WALL_TOP - 0.15, 2.3), _pal["wood"].lightened(0.15))
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		_box(root, Vector3(0.3, 0.3, 1.6), Vector3(x, WALL_TOP - 0.45, 2.3), _pal["wood"].darkened(0.15))
	# Бортик спереди — по щиколотку: под стеной всё видно; зубцы только у башен
	_box(root, Vector3(27.0, 0.22, 0.25), Vector3(0, WALL_TOP + 0.11, -1.375), stone, WALL_RAIL_LAYER)
	for x in [-12.6, 12.6]:
		_box(root, Vector3(1.2, 0.8, 0.5), Vector3(x, WALL_TOP + 0.4, -1.25), stone.darkened(0.08), WALL_RAIL_LAYER)
	# Перила сзади: брус на столбиках
	_box(root, Vector3(27.0, 0.16, 0.2), Vector3(0, WALL_TOP + 0.95, 3.0), _pal["wood"], WALL_RAIL_LAYER)
	for k in 12:
		_box(root, Vector3(0.16, 0.95, 0.16), Vector3(-13.2 + k * 2.4, WALL_TOP + 0.47, 3.0), _pal["wood"].darkened(0.1), WALL_RAIL_LAYER)
	# Невидимые ограждения вокруг хода (только для игрока): не перепрыгнуть ни вперёд, ни назад
	for fence in [[Vector3(27.0, 3.0, 0.2), Vector3(0, WALL_TOP + 1.5, -1.55)],
			[Vector3(27.0, 3.0, 0.3), Vector3(0, WALL_TOP + 1.5, 3.15)],
			[Vector3(0.3, 3.0, 5.0), Vector3(-13.5, WALL_TOP + 1.5, 0.8)],
			[Vector3(0.3, 3.0, 5.0), Vector3(13.5, WALL_TOP + 1.5, 0.8)]]:
		var body := StaticBody3D.new()
		body.collision_layer = WALL_RAIL_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = fence[0]
		shape.shape = box
		body.add_child(shape)
		body.position = fence[1]
		root.add_child(body)


# --- долина: скалы по краю, туннель, вышка героя ---------------------------------------------

func is_tunnel() -> bool:
	return level.get("gate", "") == "tunnel"


## Где можно летать (за скалами — нельзя); без bounds — вся карта.
func bounds() -> Rect2:
	return level.get("bounds", Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0))


## Где появляется герой: на стене у ворот или на смотровой вышке у туннеля.
func player_spawn() -> Vector3:
	if is_tunnel():
		return Vector3(LOOKOUT_XZ.x, height(LOOKOUT_XZ) + LOOKOUT_H + 0.15, LOOKOUT_XZ.y)
	return PLAYER_SPAWN


## Скальное кольцо — край карты: три ряда валунов вдоль контура долины (bounds): внутренний
## пониже, наружные — отвесная стена 15–24 м. На юге посередине — место под туннель. У каждого
## камня — твёрдое тело (герой не пролетит, ракеты взрываются), турели на них не ставятся.
func _build_cliffs() -> void:
	var b := bounds()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var shapes: Array = []
	for k in 6:
		shapes.append(_boulder(200 + k))
	var mat := _vertex_color_material()
	var west := b.position.x - 4.0
	var east := b.end.x + 4.0
	var north := b.position.y - 4.0
	var south := GATE_Z + 5.0
	var sides := [[Vector2(west, north), Vector2(east, north), Vector2(0, -1)],
		[Vector2(east, north), Vector2(east, south), Vector2(1, 0)],
		[Vector2(east, south), Vector2(west, south), Vector2(0, 1)],
		[Vector2(west, south), Vector2(west, north), Vector2(-1, 0)]]
	for side in sides:
		var a: Vector2 = side[0]
		var c: Vector2 = side[1]
		var out: Vector2 = side[2]
		var length := a.distance_to(c)
		for row in 3:
			var t := 0.0
			while t < length + 6.0:
				var p: Vector2 = a.lerp(c, minf(t / length, 1.0)) + out * (row * 7.0 + rng.randf_range(-2.0, 2.0))
				t += rng.randf_range(5.5, 8.0)
				if out.y > 0.5 and absf(p.x) < 9.0 and row == 0:
					continue
				var sy: float = [rng.randf_range(4.5, 7.0), rng.randf_range(10.0, 15.0), rng.randf_range(16.0, 24.0)][row]
				if out.y > 0.5 and absf(p.x) < 12.0:
					sy = maxf(sy, 10.0)
				var scale := Vector3(rng.randf_range(6.5, 9.5), sy, rng.randf_range(6.0, 8.5))
				var pos := Vector3(p.x, height(p) + sy * 0.22, p.y)
				_place_boulder(shapes[rng.randi() % shapes.size()], mat, pos, scale, rng.randf() * TAU)
				props.append(Vector3(p.x, p.y, maxf(scale.x, scale.z) * 0.9))


## Валун с твёрдым телом: меш с поворотом и масштабом, форма — те же вершины, уже повёрнутые и
## растянутые (неравномерный масштаб у тел физики не поддерживается).
func _place_boulder(shape: Array, mat: Material, pos: Vector3, scale: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = shape[0]
	mi.material_override = mat
	mi.scale = scale
	mi.rotation.y = yaw
	mi.position = pos
	add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	for v: Vector3 in shape[1]:
		pts.append(basis * v)
	convex.points = pts
	col.shape = convex
	body.add_child(col)
	body.position = pos
	add_child(body)


## Валун: икосаэдр, вершины сдвинуты по радиусу, грани плоские; сверху — мох, снизу — тень.
## Возвращает [меш, вершины].
func _boulder(seed_value: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized() * rng.randf_range(0.72, 1.12)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone: Color = _pal["rock"].lerp(Color(0.47, 0.45, 0.42), 0.5)
	var moss: Color = _pal["top"].darkened(0.1)
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(a + b + c) < 0.0:
			n = -n
		var col := stone.darkened(rng.randf_range(0.0, 0.15)) if n.y > -0.2 else stone.darkened(0.3)
		if n.y > 0.75:
			col = moss
		for p in [a, c, b]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)
	var pts: Array[Vector3] = []
	for p in v:
		pts.append(p)
	return [st.commit(), pts]


## Вход в туннель в южном хребте: столбы из тёсаного камня, арка из клиньев с замковым камнем,
## внутри — тёмная глубина и деревянные крепи, по бокам — факелы с тёплым светом; сверху и по
## бокам — скала, в которой туннель прорублен.
func _build_tunnel() -> void:
	var root := Node3D.new()
	var floor_y := height(Vector2(0, GATE_Z - 2.0))
	root.position = Vector3(0, floor_y, GATE_Z - 0.5)
	add_child(root)
	var stone_a: Color = _pal["stone"].lerp(Color(0.55, 0.52, 0.48), 0.5)
	var stone_b := stone_a.darkened(0.12)
	var wood: Color = _pal["wood"]
	var dark := Color(0.05, 0.045, 0.04)
	var span := 5.6
	var spring := 6.0
	for sx in [-1.0, 1.0]:
		for k in 3:
			_box(root, Vector3(2.2 - 0.1 * (k % 2), 1.9, 3.0), Vector3(sx * (span + 1.0), k * 2.0 + 1.0, 0), stone_a if k % 2 == 0 else stone_b)
		_box(root, Vector3(2.8, 0.5, 3.6), Vector3(sx * (span + 1.0), 0.15, 0), stone_b)
	# Арка: клинья по полуокружности без щелей, замковый камень крупнее и светлее
	var segs := 9
	for k in segs:
		var a0 := PI * k / segs + 0.012
		var a1 := PI * (k + 1) / segs - 0.012
		var is_key := k == segs / 2
		var mi := MeshInstance3D.new()
		mi.mesh = _wedge(a0, a1, span - 0.05, span + (2.35 if is_key else 2.0), 3.3 if is_key else 3.0, spring)
		var m := StandardMaterial3D.new()
		m.albedo_color = stone_a.lightened(0.1) if is_key else (stone_a if k % 2 == 0 else stone_b)
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		root.add_child(mi)
	# Глубина туннеля и крепи
	_box(root, Vector3(span * 2.1, 11.0, 0.5), Vector3(0, 5.5, 8.0), dark)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.6, 10.5, 8.0), Vector3(sx * (span + 0.3), 5.0, 4.0), dark)
	_box(root, Vector3(span * 2.1, 0.6, 8.0), Vector3(0, spring + span - 0.2, 4.0), dark)
	for d in [2.0, 5.0]:
		for sx in [-1.0, 1.0]:
			_box(root, Vector3(0.45, 6.8, 0.45), Vector3(sx * (span - 0.8), 3.4, d), wood)
		_box(root, Vector3(span * 2.0 - 0.6, 0.5, 0.5), Vector3(0, 6.9, d), wood)
	# Факелы
	for sx in [-1.0, 1.0]:
		var base := Vector3(sx * (span + 1.0), 4.4, -1.65)
		_box(root, Vector3(0.18, 0.9, 0.18), base, wood)
		var flame := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.28
		fm.height = 0.7
		fm.radial_segments = 6
		fm.rings = 3
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.6, 0.2)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.55, 0.15)
		glow.emission_energy_multiplier = 4.0
		fm.material = glow
		flame.mesh = fm
		flame.position = base + Vector3(0, 0.75, 0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(flame)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.3)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = base + Vector3(0, 0.9, -0.4)
		root.add_child(light)
	# Скала над входом и по бокам
	var mat := _vertex_color_material()
	for cap in [[Vector3(0, 13.5, 4.5), Vector3(11.0, 6.0, 7.5), 304], [Vector3(-10.5, 6.0, 4.0), Vector3(7.0, 9.0, 7.0), 301],
			[Vector3(10.5, 6.0, 4.0), Vector3(7.0, 9.5, 7.0), 302], [Vector3(-6.0, 12.0, 6.5), Vector3(6.0, 6.0, 6.0), 303],
			[Vector3(6.5, 12.5, 6.5), Vector3(6.5, 6.5, 6.0), 300]]:
		_place_boulder(_boulder(cap[2]), mat, root.position + cap[0], cap[1], cap[2] * 0.7)
	props.append(Vector3(0, GATE_Z + 3.0, 12.0))


## Клин арки: от угла a0 до a1 между радиусами r_in и r_out, толщиной depth; центр дуги на cy.
func _wedge(a0: float, a1: float, r_in: float, r_out: float, depth: float, cy: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0, cy, 0)
	var d0 := Vector3(cos(a0), sin(a0), 0)
	var d1 := Vector3(cos(a1), sin(a1), 0)
	var hz := Vector3(0, 0, depth * 0.5)
	var v := [c + d0 * r_in - hz, c + d1 * r_in - hz, c + d1 * r_out - hz, c + d0 * r_out - hz,
		c + d0 * r_in + hz, c + d1 * r_in + hz, c + d1 * r_out + hz, c + d0 * r_out + hz]
	var center := c + (d0 + d1) * 0.5 * (r_in + r_out) * 0.5
	for q in [[0, 1, 2, 3], [7, 6, 5, 4], [3, 2, 6, 7], [4, 5, 1, 0], [1, 5, 6, 2], [4, 0, 3, 7]]:
		var a: Vector3 = v[q[0]]
		var b: Vector3 = v[q[1]]
		var cc: Vector3 = v[q[2]]
		var n := (b - a).cross(cc - a).normalized()
		if n.dot((a + b + cc) / 3.0 - center) < 0.0:
			n = -n
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.add_vertex(v[q[i]])
	return st.commit()


## Смотровая вышка героя у туннеля: четыре столба с подкосами, настил (по нему ходят), перила
## (держат героя, но не снаряды), флажок.
func _build_lookout() -> void:
	var root := Node3D.new()
	root.position = Vector3(LOOKOUT_XZ.x, height(LOOKOUT_XZ), LOOKOUT_XZ.y)
	add_child(root)
	var wood: Color = _pal["wood"].lightened(0.15)
	var dark: Color = _pal["wood"]
	var h := LOOKOUT_H
	var c := 1.8
	var corners: Array[Vector3] = [Vector3(-c, 0, -c), Vector3(c, 0, -c), Vector3(c, 0, c), Vector3(-c, 0, c)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		_beam_mesh(root, a * 1.2, a + Vector3(0, h, 0), 0.32, wood)
		_beam_mesh(root, a * 1.15 + Vector3(0, 0.5, 0), b * 1.05 + Vector3(0, h * 0.6, 0), 0.16, dark)
		_beam_mesh(root, b * 1.15 + Vector3(0, 0.5, 0), a * 1.05 + Vector3(0, h * 0.6, 0), 0.16, dark)
		_beam_mesh(root, a * 1.25 + Vector3(0, h + 1.0, 0), b * 1.25 + Vector3(0, h + 1.0, 0), 0.12, wood)
		_beam_mesh(root, a * 1.25 + Vector3(0, h, 0), a * 1.25 + Vector3(0, h + 1.05, 0), 0.14, wood)
	# Настил — твёрдый: на нём стоят
	_box(root, Vector3(c * 2.7, 0.25, c * 2.7), Vector3(0, h - 0.1, 0), wood.lightened(0.05))
	# Невидимые перила — только для героя (слой ограждений): с вышки не свалиться случайно
	for side in [[Vector3(c * 2.7, 1.2, 0.2), Vector3(0, h + 0.6, -c * 1.3)], [Vector3(c * 2.7, 1.2, 0.2), Vector3(0, h + 0.6, c * 1.3)],
			[Vector3(0.2, 1.2, c * 2.7), Vector3(-c * 1.3, h + 0.6, 0)], [Vector3(0.2, 1.2, c * 2.7), Vector3(c * 1.3, h + 0.6, 0)]]:
		var body := StaticBody3D.new()
		body.collision_layer = WALL_RAIL_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[0]
		shape.shape = box
		body.add_child(shape)
		body.position = side[1]
		root.add_child(body)
	# Флажок на заднем углу (к туннелю) — не закрывает герою вид на долину
	var pole_base: Vector3 = corners[2] * 1.25 + Vector3(0, h, 0)
	_beam_mesh(root, pole_base, pole_base + Vector3(0, 3.0, 0), 0.08, dark)
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 0.8)
	flag.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.68, 0.12, 0.09)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fm
	flag.position = pole_base + Vector3(0.62, 2.6, 0)
	root.add_child(flag)
	props.append(Vector3(LOOKOUT_XZ.x, LOOKOUT_XZ.y, 3.5))


## Брус-меш из a в b квадратного сечения w (без тела).
func _beam_mesh(parent: Node3D, a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var dir := b - a
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, dir.length(), w)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	mi.material_override = m
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(mi)


## Цветной блок с твёрдым телом (по нему можно ходить, сквозь него не пройти).
## layer — слой столкновений: 1 — мир (в него бьют снаряды и прицел), 2 — ограждения стены
## (останавливают игрока, но снаряды и прицел пролетают — ядро не взорвётся о парапет под носом).
func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, layer := 1, glow := false) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


# --- вспомогательное ------------------------------------------------------------------------

## Лёгкая пятнистость цвета по шуму — поверхность не выглядит заливкой.
func _shade(color: Color, p: Vector2, amount: float) -> Color:
	var v := _noise.get_noise_2d(p.x * 0.25 + 50.0, p.y * 0.25) * amount * 1.6
	return color.lightened(v) if v > 0.0 else color.darkened(-v)


static var _glow_shader: Shader


## Светящийся материал: цвет вершин горит сам (лава, кристаллы). glow <= 0 — обычный.
func _glow_material(glow: float) -> Material:
	if glow <= 0.0:
		return _vertex_color_material()
	if not _glow_shader:
		_glow_shader = Shader.new()
		_glow_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float glow = 1.0;
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c;
	ROUGHNESS = 0.45;
	EMISSION = c * glow;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("glow", glow)
	return m


func _vertex_color_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m


## Сглаживание ломаной сплайном Катмулла — Рома.
func _smooth(pts: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var steps := 6
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		for k in steps:
			var t := float(k) / steps
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[-1])
	return out


func _add_segment(list: Array, hash: Dictionary, a: Vector2, b: Vector2, w: float, reach: float) -> void:
	var idx := list.size()
	list.append([a, b, w])
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
	for cx in range(floori(lo.x / HASH), floori(hi.x / HASH) + 1):
		for cz in range(floori(lo.y / HASH), floori(hi.y / HASH) + 1):
			var key := Vector2i(cx, cz)
			if not hash.has(key):
				hash[key] = []
			hash[key].append(idx)


func _hash_key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / HASH), floori(p.y / HASH))


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
