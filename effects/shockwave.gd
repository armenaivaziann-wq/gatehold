extends Node3D
## Ударная волна молота: по земле от точки удара разбегается светлое кольцо, взлетает пыль и
## комья земли, остаётся трещина-опалина. Всех в радиусе radius валит (до kills врагов, урон
## damage), уцелевших рядом оглушает — почти стоят секунду. Тряска камеры по силе удара.
## Ставить в точку на земле до добавления в сцену.

const FxBudget := preload("res://core/fx_budget.gd")
const SOUND := preload("res://audio/sounds/hammer_slam.wav")

const LIFE := 0.55

var horde: Node3D
var radius := 5.0
var kills := 25
var damage := 3
## 0..1 — насколько сильный удар (размер пыли, тряска, громкость).
var power := 0.5
## Сколько секунд уцелевшие рядом стоят оглушённые.
var stun_time := 1.0
## Сколько врагов задело (после _ready).
var killed := 0

static var _ring_mesh: ArrayMesh
static var _dust_mat: ParticleProcessMaterial
static var _dust_mesh: SphereMesh
static var _rock_mat: ParticleProcessMaterial
static var _rock_mesh: BoxMesh
static var _crack_tex: GradientTexture2D

var _age := 0.0
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _crack: Decal


func _ready() -> void:
	if horde:
		killed = horde.kill_area(global_position, radius, kills, "hammer", damage)
		horde.chill(global_position, radius * 1.5, 0.2, stun_time)
	_build_shared()
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.vertex_color_use_as_albedo = true
	_ring_mat.albedo_color = Color(1.0, 0.92, 0.75, 0.8)
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.2
	add_child(_ring)
	# Пыль кольцом по земле и комья вверх
	var dust := FxBudget.cosmetic(GPUParticles3D.new())
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.amount = int(lerpf(24, 60, power))
	dust.lifetime = 1.4
	dust.process_material = _dust_mat
	dust.draw_pass_1 = _dust_mesh
	dust.scale = Vector3.ONE * lerpf(0.8, 1.6, power)
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	dust.emitting = true
	var rocks := FxBudget.cosmetic(GPUParticles3D.new())
	rocks.one_shot = true
	rocks.explosiveness = 1.0
	rocks.amount = int(lerpf(14, 36, power))
	rocks.lifetime = 1.2
	rocks.process_material = _rock_mat
	rocks.draw_pass_1 = _rock_mesh
	rocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rocks)
	rocks.emitting = true
	if FxBudget.take_decal():
		_crack = Decal.new()
		_crack.size = Vector3(radius * 1.3, 3.0, radius * 1.3)
		_crack.texture_albedo = _crack_tex
		_crack.rotation.y = randf() * TAU
		add_child(_crack)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = SOUND
	audio.unit_size = 20.0
	audio.volume_db = lerpf(-4.0, 3.0, power)
	audio.pitch_scale = randf_range(0.92, 1.05) * lerpf(1.1, 0.8, power)
	add_child(audio)
	audio.play()
	get_tree().call_group("player", "shake", lerpf(0.35, 1.0, power))


func _process(delta: float) -> void:
	_age += delta
	var f := clampf(_age / LIFE, 0.0, 1.0)
	var r := lerpf(0.4, radius, ease(f, 0.35))
	_ring.scale = Vector3(r, 1.0 + 1.5 * (1.0 - f), r)
	_ring_mat.albedo_color.a = 0.8 * (1.0 - f)
	if _crack:
		_crack.modulate.a = clampf(1.0 - (_age - 3.0) / 2.0, 0.0, 1.0)
	if _age > (5.0 if _crack else 1.6):
		queue_free()


func _exit_tree() -> void:
	if _crack:
		FxBudget.free_decal()
		_crack = null


## Общие для всех волн сетки и материалы.
static func _build_shared() -> void:
	if _ring_mesh:
		return
	# Кольцо — низкая лента радиуса 1 (масштабируется), к низу ярче
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		for v in [[p0, 0.0, 1.0], [p1, 0.0, 1.0], [p1 * 1.08 + Vector3(0, 0.6, 0), 1.0, 0.0],
				[p0, 0.0, 1.0], [p1 * 1.08 + Vector3(0, 0.6, 0), 1.0, 0.0], [p0 * 1.08 + Vector3(0, 0.6, 0), 1.0, 0.0]]:
			st.set_color(Color(1, 1, 1, v[2]))
			st.add_vertex(v[0])
	_ring_mesh = st.commit()
	# Пыль: песочные клубы разлетаются по кругу у земли
	_dust_mat = ParticleProcessMaterial.new()
	_dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_dust_mat.emission_ring_axis = Vector3.UP
	_dust_mat.emission_ring_radius = 0.8
	_dust_mat.emission_ring_inner_radius = 0.2
	_dust_mat.emission_ring_height = 0.1
	_dust_mat.direction = Vector3(0, 0.25, 0)
	_dust_mat.spread = 90.0
	_dust_mat.flatness = 0.8
	_dust_mat.initial_velocity_min = 5.0
	_dust_mat.initial_velocity_max = 9.0
	_dust_mat.radial_accel_min = 2.0
	_dust_mat.radial_accel_max = 4.0
	_dust_mat.damping_min = 4.0
	_dust_mat.damping_max = 6.0
	_dust_mat.gravity = Vector3(0, 0.5, 0)
	var curve := Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 2.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	_dust_mat.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.82, 0.68, 0.5, 0.75))
	grad.set_color(1, Color(0.75, 0.65, 0.52, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	_dust_mat.color_ramp = gt
	_dust_mesh = SphereMesh.new()
	_dust_mesh.radius = 0.35
	_dust_mesh.height = 0.7
	_dust_mesh.radial_segments = 6
	_dust_mesh.rings = 3
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 1.0
	_dust_mesh.material = dm
	# Комья земли и камешки — вверх и в стороны, падают
	_rock_mat = ParticleProcessMaterial.new()
	_rock_mat.direction = Vector3(0, 1, 0)
	_rock_mat.spread = 55.0
	_rock_mat.initial_velocity_min = 5.0
	_rock_mat.initial_velocity_max = 11.0
	_rock_mat.gravity = Vector3(0, -18.0, 0)
	_rock_mat.angular_velocity_min = -400.0
	_rock_mat.angular_velocity_max = 400.0
	_rock_mat.scale_min = 0.6
	_rock_mat.scale_max = 1.5
	_rock_mesh = BoxMesh.new()
	_rock_mesh.size = Vector3(0.14, 0.12, 0.16)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.36, 0.27, 0.2)
	rm.roughness = 1.0
	_rock_mesh.material = rm
	# Трещина-опалина: тёмное пятно с рваным краем
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	cg.colors = PackedColorArray([Color(0.12, 0.09, 0.07, 0.8), Color(0.2, 0.15, 0.1, 0.45), Color(0.2, 0.15, 0.1, 0.0)])
	_crack_tex = GradientTexture2D.new()
	_crack_tex.gradient = cg
	_crack_tex.fill = GradientTexture2D.FILL_RADIAL
	_crack_tex.fill_from = Vector2(0.5, 0.5)
	_crack_tex.fill_to = Vector2(1.0, 0.5)
	_crack_tex.width = 128
	_crack_tex.height = 128
