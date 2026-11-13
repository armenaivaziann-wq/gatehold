extends Node3D
## Удар молнии с неба (финальная форма электропушки «Гроза»): толстая золотая молния бьёт сверху
## в точку, по земле расходится светящееся кольцо, всё в радиусе radius выжжено (до kills врагов,
## урон 2). Живёт LIFE секунд. Ставить в точку на земле до добавления в сцену.

const FxBudget := preload("res://core/fx_budget.gd")
const SOUND := preload("res://audio/sounds/explosion.wav")

const LIFE := 0.5
const HEIGHT := 32.0
const GOLD := Color(1.0, 0.82, 0.3)

var horde: Node3D
var radius := 4.0
var kills := 25

var _age := 0.0
var _bolt_core: MeshInstance3D
var _bolt_glow: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	if horde:
		horde.kill_area(global_position, radius, kills, "lightning", 2)
	_bolt_core = _node(Color(1.0, 0.97, 0.85), 1.0)
	_glow_mat = _bolt_glow_mat()
	_bolt_glow = MeshInstance3D.new()
	_bolt_glow.material_override = _glow_mat
	_bolt_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bolt_glow)
	_rebuild()
	# Кольцо по земле
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.08
	disc.radial_segments = 24
	disc.rings = 1
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(GOLD, 0.6)
	_ring = MeshInstance3D.new()
	_ring.mesh = disc
	_ring.material_override = _ring_mat
	_ring.position.y = 0.15
	_ring.scale = Vector3(0.2, 1.0, 0.2)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	if FxBudget.take_light():
		_light = OmniLight3D.new()
		_light.light_color = GOLD
		_light.light_energy = 14.0
		_light.omni_range = 22.0
		_light.position.y = 3.0
		add_child(_light)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = SOUND
	audio.unit_size = 30.0
	audio.pitch_scale = randf_range(1.3, 1.5)
	add_child(audio)
	audio.play()
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(global_position)
		get_tree().call_group("player", "shake", clampf(1.0 - d / 50.0, 0.1, 0.8))


func _process(delta: float) -> void:
	_age += delta
	var f := clampf(_age / LIFE, 0.0, 1.0)
	# Молния мерцает первые доли секунды и гаснет
	var on := _age < 0.08 or (_age < 0.3 and randf() < 0.6)
	_bolt_core.visible = on
	_bolt_glow.visible = on
	if on and randf() < 0.5:
		_rebuild()
	_glow_mat.albedo_color.a = 0.5 * (1.0 - f)
	_ring.scale = Vector3(lerpf(0.2, 1.0, ease(f, 0.3)), 1.0, lerpf(0.2, 1.0, ease(f, 0.3)))
	_ring_mat.albedo_color.a = 0.6 * (1.0 - f)
	if _light:
		_light.light_energy = 14.0 * (1.0 - f)
	if _age >= LIFE + 0.6:
		queue_free()


func _exit_tree() -> void:
	if _light:
		FxBudget.free_light()
		_light = null


## Ломаная сверху вниз с отростками; у земли — толще.
func _rebuild() -> void:
	var core := SurfaceTool.new()
	core.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(randf_range(-3, 3), HEIGHT, randf_range(-3, 3))
	var steps := 14
	var prev := top
	for s in steps:
		var t := float(s + 1) / steps
		var p := top.lerp(Vector3.ZERO, t)
		if s < steps - 1:
			p += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 1.3
		var w := lerpf(0.12, 0.28, t)
		_strip(core, prev, p, w)
		_strip(glow, prev, p, w * 4.0)
		if randf() < 0.35:
			var fork := p + Vector3(randf_range(-3, 3), randf_range(-2.5, 0.5), randf_range(-3, 3))
			_strip(core, p, fork, w * 0.5)
		prev = p
	_bolt_core.mesh = core.commit()
	_bolt_glow.mesh = glow.commit()


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var side := d.cross(Vector3.FORWARD)
	if side.length_squared() < 0.0001:
		side = d.cross(Vector3.RIGHT)
	for s in [side.normalized(), d.cross(side).normalized()]:
		var o: Vector3 = s * w
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


func _bolt_glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(GOLD, 0.5)
	return m
