extends Node3D
## Цепная молния от точки удара («Молот грома»): от места удара молния прыгает по ближайшим
## врагам — до count штук в радиусе radius, каждый следующий — ближайший к предыдущему. Всех
## задетых валит. Голубые ломаные гаснут за LIFE секунд. Ставить в точку удара до добавления.

const LIFE := 0.18
const HOP := 4.5

var horde: Node3D
var count := 4
var radius := 7.0
## Сколько свалило (после _ready).
var killed := 0

var _age := 0.0
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _points: Array[Vector3] = []


func _ready() -> void:
	_core = _node(Color(0.85, 0.95, 1.0), 1.0)
	_glow = _node(Color(0.3, 0.6, 1.0), 0.45)
	if not horde:
		return
	var cur := global_position
	_points.append(cur)
	var used := {}
	var hits: Array[Vector2] = []
	for n in count:
		var best := -1
		var best_d := HOP if n > 0 else radius
		for i in horde.pick_targets(cur, best_d, 0.0, 16):
			if used.has(i):
				continue
			var d: float = horde.position_of(i).distance_to(cur)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		used[best] = true
		cur = horde.position_of(best)
		_points.append(cur + Vector3(0, 0.45, 0))
		hits.append(Vector2(hits.size(), best))
	if not hits.is_empty():
		killed = horde._kill_sorted(hits, hits.size(), "hammer")
	_rebuild()


func _process(delta: float) -> void:
	_age += delta
	if randf() < 0.6:
		_rebuild()
	var a := 1.0 - _age / LIFE
	(_core.material_override as StandardMaterial3D).albedo_color.a = a
	(_glow.material_override as StandardMaterial3D).albedo_color.a = 0.45 * a
	if _age >= LIFE:
		queue_free()


func _rebuild() -> void:
	if _points.size() < 2:
		return
	var core := SurfaceTool.new()
	core.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in _points.size() - 1:
		var a := _points[k] - global_position
		var b := _points[k + 1] - global_position
		var steps := clampi(int(a.distance_to(b) / 0.9), 2, 8)
		var prev := a
		for s in steps:
			var p := a.lerp(b, float(s + 1) / steps)
			if s < steps - 1:
				p += Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)) * 0.4
			_strip(core, prev, p, 0.045)
			_strip(glow, prev, p, 0.18)
			prev = p
	_core.mesh = core.commit()
	_glow.mesh = glow.commit()


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	for side in [Vector3.UP, d.cross(Vector3.UP).normalized()]:
		var o: Vector3 = side * w
		for v in [a - o, a + o, b + o, a - o, b + o, b - o]:
			st.add_vertex(v)


func _node(col: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col, alpha)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
