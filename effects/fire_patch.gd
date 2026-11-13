extends Node3D
## Горящее пятно на земле, куда била струя огнемёта: языки пламени и дым несколько секунд,
## жуки, заходящие в огонь, сгорают. Потом гаснет и остаётся обугленное пятно.

const RADIUS := 1.6
const BURN_TIME := 3.5
const TICK := 0.3
const KILLS_PER_TICK := 3
const SCORCH_TIME := 5.0
const FxBudget := preload("res://core/fx_budget.gd")

static var _process_mat: ParticleProcessMaterial
static var _flame_mesh: SphereMesh
static var _scorch_tex: GradientTexture2D

var horde: Node3D
## Чей огонь (опыт мастерства) и во сколько раз больше обычного; сколько горит.
var source := ""
var scale_size := 1.0
var burn_time := BURN_TIME
## Синее пламя (огнемёт «Синее Инферно»): синий огонь, жжёт и доспехи.
var blue := false
static var _blue_mat: ParticleProcessMaterial

var _age := 0.0
var _tick := 0.0
var _fire: GPUParticles3D
var _light: OmniLight3D
var _scorch: Decal


func _ready() -> void:
	if not _process_mat:
		_build_shared()
	_fire = GPUParticles3D.new()
	_fire.amount = FxBudget.amount(26)
	_fire.lifetime = 0.7
	_fire.local_coords = false
	_fire.process_material = _blue_mat if blue else _process_mat
	_fire.draw_pass_1 = _flame_mesh
	_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fire.position.y = 0.2
	# Пятно больше — и языки пламени крупнее и шире разбросаны
	_fire.scale = Vector3.ONE * scale_size
	add_child(_fire)
	if FxBudget.take_light():
		_light = OmniLight3D.new()
		_light.light_color = Color(0.35, 0.55, 1.0) if blue else Color(1.0, 0.55, 0.2)
		_light.omni_range = 4.0
		_light.position.y = 0.8
		add_child(_light)
	if FxBudget.take_decal():
		_scorch = Decal.new()
		_scorch.size = Vector3(RADIUS * 2.4, 3.0, RADIUS * 2.4) * Vector3(scale_size, 1.0, scale_size)
		_scorch.texture_albedo = _scorch_tex
		add_child(_scorch)


## Материал частиц, меш языка пламени и текстура пятна — общие для всех пятен.
static func _build_shared() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, 1.5, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = RADIUS * 0.7
	var curve := Curve.new()
	curve.max_value = 8.0  # по умолчанию кривая обрезана сверху единицей
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.45, 0.08, 0.85), Color(0.3, 0.1, 0.05, 0.0)])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	_process_mat = pm
	var bpm: ParticleProcessMaterial = pm.duplicate()
	var bgrad := Gradient.new()
	bgrad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	bgrad.colors = PackedColorArray([Color(0.8, 0.95, 1.0, 1.0), Color(0.25, 0.5, 1.0, 0.85), Color(0.05, 0.08, 0.3, 0.0)])
	var bgt := GradientTexture1D.new()
	bgt.gradient = bgrad
	bpm.color_ramp = bgt
	_blue_mat = bpm
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	_flame_mesh = mesh
	var sg := Gradient.new()
	sg.set_color(0, Color(0.07, 0.04, 0.02, 0.8))
	sg.set_color(1, Color(0.08, 0.05, 0.03, 0.0))
	_scorch_tex = GradientTexture2D.new()
	_scorch_tex.gradient = sg
	_scorch_tex.fill = GradientTexture2D.FILL_RADIAL
	_scorch_tex.fill_from = Vector2(0.5, 0.5)
	_scorch_tex.fill_to = Vector2(1.0, 0.5)


## Струя снова бьёт сюда — огонь горит дольше.
func refresh() -> void:
	_age = minf(_age, 0.5)
	_fire.emitting = true


func _process(delta: float) -> void:
	_age += delta
	var burning := _age < burn_time
	_fire.emitting = burning
	if _light:
		var t := Time.get_ticks_msec() / 1000.0
		_light.light_energy = (1.4 + 0.4 * sin(t * 23.0 + position.x)) * clampf(burn_time - _age, 0.0, 1.0)
		if not burning:
			# Огонь погас — лампа больше не нужна, отдаём её в общий бюджет
			_light.queue_free()
			_light = null
			FxBudget.free_light()
	if burning and horde:
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			horde.kill_area(global_position, RADIUS * scale_size, KILLS_PER_TICK, source, 2 if blue else 1)
	if _scorch:
		_scorch.modulate.a = clampf((burn_time + SCORCH_TIME - _age) / 2.0, 0.0, 1.0)
	if _age > burn_time + (SCORCH_TIME if _scorch else 1.0):
		queue_free()


func _exit_tree() -> void:
	if _light:
		FxBudget.free_light()
		_light = null
	if _scorch:
		FxBudget.free_decal()
		_scorch = null
