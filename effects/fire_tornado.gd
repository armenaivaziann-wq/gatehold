extends Node3D
## Огненный торнадо (финальная форма огнемёта): вращающаяся воронка огня — несколько вложенных
## конусов, крутятся в разные стороны, языки пламени взлетают по спирали, внизу горящий круг.
## Ползёт вперёд по направлению dir, держится над землёй и затягивает гоблинов в радиусе к себе;
## дошедших до сердцевины сжигает (horde.pull). Живёт LIFE секунд, потом опадает.

const FxBudget := preload("res://core/fx_budget.gd")

const LIFE := 6.0
const SPEED := 3.5               # м/с
const RADIUS := 6.0              # кого тянет
const CORE := 1.4                # кого сжигает
const PULL := 8.0                # м/с у ядра
const KILLS_PER_FRAME := 3
const HEIGHT := 6.0

var horde: Node3D
## Куда ползёт (по земле, единичный).
var dir := Vector3.FORWARD
## Синее пламя (если вдруг взяты оба — не бывает, но цвет задаётся снаружи).
var color := Color(1.0, 0.5, 0.1)

var _age := 0.0
var _funnels: Array[MeshInstance3D] = []
var _flames: GPUParticles3D
var _light: OmniLight3D
var _map: Node3D


func _ready() -> void:
	_map = get_tree().get_first_node_in_group("map")
	# Воронки: широкий верх, узкий низ; три слоя — наружный тусклее, внутренний ярче
	for k in 3:
		var mi := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 2.4 - k * 0.6
		cone.bottom_radius = 0.35 + k * 0.05
		cone.height = HEIGHT - k * 0.8
		cone.radial_segments = 9
		cone.rings = 4
		cone.cap_top = false
		cone.cap_bottom = false
		mi.mesh = cone
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c := color.lerp(Color(1.0, 0.75, 0.3), k * 0.4)
		m.albedo_color = Color(c, 0.22 + k * 0.12)
		mi.material_override = m
		mi.position.y = cone.height * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_funnels.append(mi)
	# Языки пламени взлетают вверх по кругу
	_flames = GPUParticles3D.new()
	_flames.amount = 90
	_flames.lifetime = 1.0
	_flames.local_coords = true
	_flames.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, HEIGHT + 3, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.9
	pm.emission_ring_inner_radius = 0.3
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 7.0
	pm.radial_accel_min = 1.5
	pm.radial_accel_max = 3.0
	pm.tangential_accel_min = 8.0
	pm.tangential_accel_max = 12.0
	pm.gravity = Vector3(0, 1.0, 0)
	var curve := Curve.new()
	curve.max_value = 4.0
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 2.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.7, 0.25, 1.0), Color(color, 0.85), Color(0.35, 0.06, 0.02, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_flames.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	mesh.radial_segments = 6
	mesh.rings = 3
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = fm
	_flames.draw_pass_1 = mesh
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flames)
	if FxBudget.take_light():
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 3.0
		_light.omni_range = 9.0
		_light.position.y = 2.0
		add_child(_light)
	scale = Vector3(0.2, 0.2, 0.2)


func _process(delta: float) -> void:
	_age += delta
	# Вырастает за 0.3 с, последние 0.6 с опадает
	var grow := clampf(_age / 0.3, 0.0, 1.0) * clampf((LIFE - _age) / 0.6, 0.0, 1.0)
	scale = Vector3(lerpf(0.2, 1.0, grow), lerpf(0.05, 1.0, grow), lerpf(0.2, 1.0, grow))
	for k in _funnels.size():
		_funnels[k].rotation.y += delta * (5.0 + k * 3.0) * (1.0 if k % 2 == 0 else -1.0)
		# Воронка чуть покачивается — живая
		_funnels[k].rotation.z = sin(_age * 3.0 + k) * 0.06
	if _light:
		_light.light_energy = (2.6 + 0.8 * sin(_age * 19.0)) * grow
	# Ползёт вперёд по земле
	var p := global_position + dir * SPEED * delta
	if _map:
		p.y = _map.height(Vector2(p.x, p.z))
	global_position = p
	if horde and grow > 0.5:
		horde.pull(global_position, RADIUS, PULL, CORE, delta, KILLS_PER_FRAME, "flamer")
	if _age >= LIFE:
		if _light:
			FxBudget.free_light()
		queue_free()
