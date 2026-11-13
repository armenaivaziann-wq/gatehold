extends Node3D
## Шаровая молния (финальная форма электропушки): бело-фиолетовый светящийся шар плывёт над
## толпой вперёд по dir и каждые ZAP_EVERY секунд бьёт короткими молниями до ZAPS ближайших
## врагов в радиусе RADIUS. Живёт LIFE секунд, потом гаснет.

const FxBudget := preload("res://core/fx_budget.gd")

const LIFE := 5.0
const SPEED := 2.5
const HOVER := 2.6               # м над землёй
const RADIUS := 5.5
const ZAP_EVERY := 0.3
const ZAPS := 3
const BOLT_LIFE := 0.1
const CORE := Color(0.95, 0.9, 1.0)
const HALO := Color(0.7, 0.4, 1.0)

var horde: Node3D
var dir := Vector3.FORWARD

var _age := 0.0
var _zap := 0.0
var _orb: MeshInstance3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _bolts: MeshInstance3D
var _bolt_life := 0.0
var _light: OmniLight3D
var _map: Node3D


func _ready() -> void:
	_map = get_tree().get_first_node_in_group("map")
	_orb = _sphere(0.42, _unshaded(CORE, 1.0, false))
	_halo_mat = _unshaded(HALO, 0.35, true)
	_halo = _sphere(0.95, _halo_mat)
	_bolts = MeshInstance3D.new()
	_bolts.top_level = true
	_bolts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolts.material_override = _unshaded(Color(0.85, 0.75, 1.0), 0.9, true)
	add_child(_bolts)
	if FxBudget.take_light():
		_light = OmniLight3D.new()
		_light.light_color = HALO
		_light.light_energy = 3.0
		_light.omni_range = 8.0
		add_child(_light)
	scale = Vector3.ONE * 0.1


func _process(delta: float) -> void:
	_age += delta
	var grow := clampf(_age / 0.25, 0.0, 1.0) * clampf((LIFE - _age) / 0.4, 0.0, 1.0)
	scale = Vector3.ONE * maxf(grow, 0.05)
	# Плывёт вперёд, покачиваясь над землёй
	var p := global_position + dir * SPEED * delta
	if _map:
		p.y = _map.height(Vector2(p.x, p.z)) + HOVER + sin(_age * 3.0) * 0.25
	global_position = p
	var pulse := 1.0 + 0.15 * sin(_age * 23.0)
	_halo.scale = Vector3.ONE * pulse
	_halo_mat.albedo_color.a = 0.25 + 0.15 * sin(_age * 17.0)
	if _light:
		_light.light_energy = (2.5 + 1.5 * randf()) * grow
	_zap -= delta
	if _zap <= 0.0 and grow > 0.5:
		_zap = ZAP_EVERY
		_zap_now()
	if _bolt_life > 0.0:
		_bolt_life -= delta
		_bolts.visible = _bolt_life > 0.0
	if _age >= LIFE:
		if _light:
			FxBudget.free_light()
			_light = null
		queue_free()


## Удар: до ZAPS ближайших врагов под шаром — молнии к каждому, все валятся.
func _zap_now() -> void:
	if not horde:
		return
	var ids: PackedInt32Array = horde.pick_targets(global_position, RADIUS, 0.0, ZAPS)
	if ids.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hits: Array[Vector2] = []
	for k in ids.size():
		var to: Vector3 = horde.position_of(ids[k]) + Vector3(0, 0.45, 0)
		hits.append(Vector2(k, ids[k]))
		var prev := global_position
		var steps := 5
		for s in steps:
			var q := global_position.lerp(to, float(s + 1) / steps)
			if s < steps - 1:
				q += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.4
			_strip(st, prev, q, 0.05)
			prev = q
	horde._kill_sorted(hits, hits.size(), "lightning")
	_bolts.mesh = st.commit()
	_bolts.global_transform = Transform3D.IDENTITY
	_bolts.visible = true
	_bolt_life = BOLT_LIFE


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	for side in [Vector3.UP, d.cross(Vector3.UP).normalized()]:
		var o: Vector3 = side * w
		for v in [a - o, a + o, b + o, a - o, b + o, b - o]:
			st.add_vertex(v)


func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _unshaded(col: Color, alpha: float, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m
