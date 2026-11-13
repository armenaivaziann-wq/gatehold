extends Node3D
## Боевой дрон (умение R): вылетает от героя к точке прицела и дальше воюет сам, независимо от
## героя, TIME секунд — висит над толпой, сдвигается к врагам, что ближе всех к туннелю, и бьёт
## короткими очередями по тем, кого видно (сквозь землю и скалы не стреляет). Время вышло —
## уходит свечой вверх и пропадает. Модель — по иконке умения: тёмный корпус-кубик, голубой
## глаз, четыре винта в кольцах, два сопла с огнём.

const GATLING_SOUND := preload("res://audio/sounds/gatling_loop.wav")

const TIME := 15.0
const HOVER := 7.0              # м над землёй
const RANGE := 20.0             # дальность стрельбы
const SEEK := 50.0              # так далеко ищет, куда лететь, если рядом никого
const RATE := 0.11              # с между выстрелами
const PIERCE := 2               # скольких на линии прошивает пуля
const SPEED := 10.0             # м/с
const RETARGET := 0.3
const SCALE := 1.4

var horde: Node3D
## Куда лететь сначала (точка прицела героя).
var start_goal := Vector3.ZERO
## Сколько воюет и как часто стреляет (умение задаёт с прокачкой).
var life_time := TIME
var rate := RATE

var _life := TIME
var _cool := 0.0
var _retarget := 0.0
var _goal := Vector3.ZERO
var _target := -1
var _target_uid := 0             # постоянный номер цели (horde.uid_of) — индекс после смертей сдвигается
var _rotors: Array[Node3D] = []
var _eye: Node3D
var _tracer: MeshInstance3D
var _tracer_time := 0.0
var _audio: AudioStreamPlayer3D
var _leaving := 0.0             # > 0 — улетает, секунд с начала ухода
var _map: Node3D


func _ready() -> void:
	_map = get_tree().get_first_node_in_group("map")
	_goal = start_goal + Vector3(0, HOVER, 0)
	_life = life_time
	_build_model()
	_audio = AudioStreamPlayer3D.new()
	var loop: AudioStreamWAV = GATLING_SOUND.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(GATLING_SOUND.get_length() * GATLING_SOUND.mix_rate)
	_audio.stream = loop
	_audio.pitch_scale = 1.7
	_audio.volume_db = -14.0
	_audio.unit_size = 14.0
	add_child(_audio)


func _process(delta: float) -> void:
	for k in _rotors.size():
		_rotors[k].rotation.y += (40.0 if k % 2 == 0 else -40.0) * delta
	_tracer_time -= delta
	_tracer.visible = _tracer_time > 0.0
	if _leaving > 0.0:
		_leaving += delta
		global_position += Vector3(0, 9.0 * delta, 0)
		scale = Vector3.ONE * SCALE * clampf(2.0 - _leaving, 0.0, 1.0)
		if _leaving > 2.0:
			queue_free()
		return
	_life -= delta
	if _life <= 0.0 or not horde:
		_leaving = 0.001
		_audio.stop()
		return
	_cool = maxf(_cool - delta, 0.0)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = RETARGET
		_pick()
	# Лететь к цели: держаться над землёй на HOVER, с наклоном по ходу
	var want := _goal
	if _map:
		want.y = maxf(want.y, _map.height(Vector2(want.x, want.z)) + HOVER)
	var to := want - global_position
	var step := to.limit_length(SPEED * delta)
	global_position += step
	var tilt := Vector3(step.z, 0, -step.x) / maxf(SPEED * delta, 0.0001) * 0.25
	rotation.x = lerpf(rotation.x, -tilt.x, minf(delta * 4.0, 1.0))
	rotation.z = lerpf(rotation.z, -tilt.z, minf(delta * 4.0, 1.0))
	var has: bool = horde.same(_target, _target_uid)
	if not has and _target >= 0:
		# Цель убита — следующую ищем сразу
		_target = -1
		_retarget = 0.0
	if has:
		var p: Vector3 = horde.position_of(_target)
		var d := p - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), minf(delta * 6.0, 1.0))
		if _cool == 0.0 and d.length() <= RANGE:
			_cool = rate
			_fire(p)
	if has and not _audio.playing:
		_audio.play()
	elif not has and _audio.playing:
		_audio.stop()


## Цель — ближайший к туннелю враг в досягаемости, которого видно; рядом никого — лететь к
## ближайшим к туннелю врагам поодаль.
func _pick() -> void:
	_target = -1
	for i in horde.pick_targets(global_position, RANGE, 0.0, 10):
		var p: Vector3 = horde.position_of(i)
		if _visible(p):
			_target = i
			_target_uid = horde.uid_of(i)
			# Висеть чуть в стороне от цели, а не прямо над ней — так видно, куда стреляет
			var back := (global_position - p)
			back.y = 0.0
			back = back.normalized() * 6.0 if back.length_squared() > 0.01 else Vector3(0, 0, 6)
			_goal = p + back + Vector3(0, HOVER, 0)
			return
	var far: PackedInt32Array = horde.pick_targets(global_position, SEEK, 0.0, 1)
	if not far.is_empty():
		_goal = horde.position_of(far[0]) + Vector3(0, HOVER, 0)


func _visible(p: Vector3) -> bool:
	var to := p + Vector3(0, 0.4, 0)
	var query := PhysicsRayQueryParameters3D.create(_eye.global_position, to, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	return not (_map and _map.line_blocked(_eye.global_position, to))


func _fire(p: Vector3) -> void:
	var from := _eye.global_position
	# В тело врага, а не в землю у ног
	var to := p + Vector3(randf_range(-0.15, 0.15), 0.3 + randf_range(-0.08, 0.08), randf_range(-0.15, 0.15))
	horde.kill_line(from, to, 0.5, PIERCE, "drone")
	var basis := Basis.looking_at(to - from, Vector3.UP).scaled_local(Vector3(1, 1, from.distance_to(to)))
	_tracer.global_transform = Transform3D(basis, (from + to) / 2.0)
	_tracer_time = 0.05


# --- модель -----------------------------------------------------------------------------------

func _build_model() -> void:
	scale = Vector3.ONE * SCALE
	var body_col := Color(0.36, 0.31, 0.28)
	var metal := Color(0.52, 0.45, 0.38)
	var body := _box(Vector3(0.62, 0.5, 0.62), body_col)
	add_child(body)
	# Голубой глаз спереди — из него и стреляет
	var eye := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.radial_segments = 10
	sphere.rings = 5
	eye.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.4, 0.85, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.8, 1.0)
	glow.emission_energy_multiplier = 3.0
	eye.material_override = glow
	eye.position = Vector3(0, 0.02, -0.32)
	add_child(eye)
	_eye = eye
	# Четыре луча с винтами в кольцах
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var tip := Vector3(sx * 0.72, 0.12, sz * 0.72)
			var arm := _box(Vector3(0.1, 0.08, 0.95), metal)
			arm.position = tip * 0.5 + Vector3(0, 0.06, 0)
			arm.rotation.y = atan2(sx, sz)
			add_child(arm)
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.3
			torus.outer_radius = 0.38
			torus.rings = 16
			torus.ring_segments = 6
			ring.mesh = torus
			ring.material_override = _mat(metal)
			ring.position = tip
			add_child(ring)
			var rotor := Node3D.new()
			rotor.position = tip
			add_child(rotor)
			var blade := _box(Vector3(0.58, 0.03, 0.08), Color(0.2, 0.18, 0.17))
			rotor.add_child(blade)
			_rotors.append(rotor)
	# Два сопла снизу с огнём
	for sx in [-1.0, 1.0]:
		var nozzle := _box(Vector3(0.14, 0.2, 0.14), Color(0.25, 0.22, 0.2))
		nozzle.position = Vector3(sx * 0.18, -0.32, 0.12)
		add_child(nozzle)
		var flame := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.08
		cone.bottom_radius = 0.0
		cone.height = 0.45
		cone.radial_segments = 6
		cone.rings = 1
		flame.mesh = cone
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.62, 0.2)
		flame.material_override = fm
		flame.position = Vector3(sx * 0.18, -0.62, 0.12)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
	# Трассер очереди — тонкий светящийся брусок в мировых координатах
	_tracer = MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.06, 0.06, 1.0)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(0.55, 0.9, 1.0)
	bar.material = tm
	_tracer.mesh = bar
	_tracer.top_level = true
	_tracer.visible = false
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracer)


func _box(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	return mi


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	return m
