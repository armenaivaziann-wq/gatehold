extends Node3D
## Снаряд турели: летит из from в to (по прямой или навесом, если arc > 0), смотрит по ходу
## полёта и по прилёте вызывает on_arrive. Модель — меш снаряда (болт, ядро). smoke — за снарядом
## тянется дымный след (ядро мортиры); после прилёта след ещё немного висит в воздухе и тает.

const FxBudget := preload("res://core/fx_budget.gd")
const TRAIL_LIFE := 0.7

var from := Vector3.ZERO
var to := Vector3.ZERO
var speed := 60.0
## Высота дуги над прямой, м (0 — летит прямо).
var arc := 0.0
var mesh: Mesh
var on_arrive: Callable
var smoke := false
static var _trail_mat: ParticleProcessMaterial
static var _trail_mesh: Mesh
var _trail: GPUParticles3D

var _t := 0.0
var _time := 1.0


func _ready() -> void:
	_time = maxf(from.distance_to(to) / speed, 0.05)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	global_position = from
	if smoke:
		_trail = FxBudget.cosmetic(GPUParticles3D.new())
		_trail.amount = FxBudget.amount(28)
		_trail.lifetime = TRAIL_LIFE
		_trail.local_coords = false
		_trail.process_material = _trail_material()
		_trail.draw_pass_1 = _trail_mesh
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
		add_child(_trail)


func _process(delta: float) -> void:
	_t = minf(_t + delta / _time, 1.0)
	var p := _point(_t)
	var ahead := _point(minf(_t + 0.02, 1.0)) if _t < 1.0 else p + (p - _point(0.98))
	global_position = p
	if p.distance_to(ahead) > 0.001:
		look_at(ahead, Vector3.UP if absf((ahead - p).normalized().y) < 0.98 else Vector3.FORWARD)
	if _t >= 1.0:
		if _trail:
			# След остаётся висеть и тает, хотя ядро уже упало
			var trail := _trail
			_trail = null
			trail.emitting = false
			var at := trail.global_transform
			remove_child(trail)
			get_parent().add_child(trail)
			trail.global_transform = at
			get_tree().create_timer(TRAIL_LIFE + 0.1).timeout.connect(trail.queue_free)
		queue_free()
		# Турель могли продать, пока снаряд летел: тогда звать её некого
		if on_arrive.is_valid() and is_instance_valid(on_arrive.get_object()):
			on_arrive.call(to)


## Дым следа: серо-бежевые клубы растут и тают (материал и меш общие на все ядра).
static func _trail_material() -> ParticleProcessMaterial:
	if _trail_mat:
		return _trail_mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.6, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 1.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(0.82, 0.78, 0.7, 0.75))
	grad.set_color(1, Color(0.75, 0.72, 0.66, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	pm.color_ramp = tex
	_trail_mat = pm
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 6
	sphere.rings = 3
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = m
	_trail_mesh = sphere
	return pm


func _point(t: float) -> Vector3:
	return from.lerp(to, t) + Vector3.UP * arc * 4.0 * t * (1.0 - t)
