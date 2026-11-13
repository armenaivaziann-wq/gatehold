extends "res://weapons/weapon.gd"
## Электропушка от первого лица (дочерний узел камеры). Зажать ЛКМ — из дула бьёт молния: в
## ближайшего к прицелу врага, от него перескакивает на соседей — до CHAIN врагов за разряд,
## разряд каждые ZAP_INTERVAL секунд. Молния яркая, с изломами и отростками, на месте удара —
## вспышка света и искры. Тратит заряд; кончился — перегрев, пока заряд не поднимется до UNLOCK
## (восстанавливается сам, когда не стреляешь). Сквозь землю и скалы не бьёт.
## Модель — lightning_model.gd (по листу пользователя). Покупается за трофеи на вкладке «Оружие».

const LightningModel := preload("res://weapons/lightning_model.gd")
const Upgrades := preload("res://core/upgrades.gd")
const ZAP_SOUND := preload("res://audio/sounds/tesla_loop.wav")
const BallScript := preload("res://effects/ball_lightning.gd")
const StrikeScript := preload("res://effects/sky_strike.gd")

const REST_POS := Vector3(0.2, -0.27, -0.52)
const REST_ROT := Vector3(0.1, 0.22, -0.05)
const VIEW_SCALE := 0.56
const RANGE := 55.0
const AIM_RADIUS := 3.5          # первая цель — враг не дальше этого от точки прицела
const HOP := 4.5                 # м — так далеко молния перескакивает к следующему
const CHAIN := 5
const ZAP_INTERVAL := 0.12
const ENERGY_MAX := 100.0
const DRAIN := 20.0              # в секунду, пока бьёт
const REGEN := 18.0              # в секунду, когда не бьёт
const REGEN_DELAY := 0.6
const UNLOCK := 35.0             # после перегрева стрелять снова можно с этого заряда
const BOLT_LIFE := 0.09

var energy := ENERGY_MAX
## Ветка электропушки («Улучшения оружия»): длина цепи, заряд, темп, шок, финалы.
var chain := CHAIN
var energy_max := ENERGY_MAX
var regen := REGEN
var zap_interval := ZAP_INTERVAL
var stun := false
var ball := false
var storm := false
const BALL_EVERY := 2.5
const STORM_EVERY := 8
const BALL_GLOW := Color(0.85, 0.65, 1.0)
const STORM_GLOW := Color(1.0, 0.78, 0.25)
var _ball_timer := 0.0
var _discharges := 0
var _base_glow := Color.WHITE
## Держать огонь без мыши (для автоматических снимков).
var force_fire := false

var _muzzle: Node3D
var _glow_mat: StandardMaterial3D
var _firing := false
var _lock := false
var _idle := 0.0
var _zap := 0.0
var _kick := 0.0
var _bolt_core: MeshInstance3D
var _bolt_glow: MeshInstance3D
var _bolt_life := 0.0
var _bolt_points: Array = []
var _light: OmniLight3D
var _sparks: GPUParticles3D
var _audio: AudioStreamPlayer


func refresh_stats() -> void:
	chain = CHAIN + 2 * Upgrades.w("lt_chain")
	energy_max = ENERGY_MAX * (1.0 + 0.4 * Upgrades.w("lt_cap"))
	regen = REGEN * (1.0 + 0.4 * Upgrades.w("lt_cap"))
	zap_interval = ZAP_INTERVAL / (1.0 + 0.2 * Upgrades.w("lt_rate"))
	stun = Upgrades.w("lt_stun") > 0
	ball = Upgrades.w("lt_ball") > 0
	storm = Upgrades.w("lt_storm") > 0
	energy = minf(energy, energy_max)
	if _glow_mat:
		_glow_mat.emission = BALL_GLOW if ball else (STORM_GLOW if storm else _base_glow)


func _init() -> void:
	refresh_stats()
	energy = energy_max


func _ready() -> void:
	super()
	display_name = "Электропушка"
	ammo_kind = "energy"
	_setup_model(LightningModel.scene(), VIEW_SCALE, LightningModel.RIGHT_HAND, LightningModel.LEFT_HAND)
	_muzzle = _model.find_child("Muzzle")
	var glow: MeshInstance3D = _model.find_child("Glow")
	_glow_mat = glow.mesh.surface_get_material(0).duplicate()
	glow.material_override = _glow_mat
	_base_glow = _glow_mat.emission
	refresh_stats()
	_make_marker(AIM_RADIUS)
	_build_effects()
	_audio = AudioStreamPlayer.new()
	var loop: AudioStreamWAV = ZAP_SOUND.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(ZAP_SOUND.get_length() * ZAP_SOUND.mix_rate)
	_audio.stream = loop
	_audio.pitch_scale = 1.0
	_audio.volume_db = -7.0
	add_child(_audio)
	_update_pose(0.0)


func set_active(on: bool) -> void:
	super(on)
	if not on:
		_set_firing(false)


func _process(delta: float) -> void:
	var can_shoot := _can_shoot()
	var want := (force_fire or can_shoot and Input.is_action_pressed("fire")) and not _lock and energy > 0.0
	if want != _firing:
		_set_firing(want)
	var aim := _update_marker(AIM_RADIUS, RANGE, _lock)
	if _firing:
		energy = maxf(energy - DRAIN * delta, 0.0)
		_idle = 0.0
		if energy <= 0.0:
			_lock = true
			_set_firing(false)
		_zap -= delta
		if _zap <= 0.0 and _firing:
			_zap = zap_interval
			_discharge(aim)
		if ball:
			_ball_timer += delta
			if _ball_timer >= BALL_EVERY:
				_ball_timer = 0.0
				_spawn_ball(aim["point"])
	else:
		_idle += delta
		if _idle > REGEN_DELAY:
			energy = minf(energy + regen * delta, energy_max)
		if _lock and energy >= UNLOCK:
			_lock = false
	_update_bolt(delta)
	_kick = move_toward(_kick, 0.0, delta * 5.0)
	# Кольца и ядро пульсируют, пока бьёт; перегрев — тускнеют
	var t := Time.get_ticks_msec() / 1000.0
	_glow_mat.emission_energy_multiplier = (4.0 + 2.0 * sin(t * 40.0)) if _firing else (0.6 if _lock else 2.2)
	_update_pose(delta)


func reload_progress() -> float:
	return energy / energy_max


func ammo_text() -> String:
	return "%d%%" % int(round(energy / energy_max * 100.0))


func ammo_note() -> String:
	return "перегрев…" if _lock else ""


func ammo_empty() -> bool:
	return _lock


func restock() -> void:
	energy = energy_max
	_lock = false


func _set_firing(on: bool) -> void:
	_firing = on
	if on:
		_zap = 0.0
		if not _audio.playing:
			_audio.play()
	else:
		_audio.stop()
		_sparks.emitting = false


## Разряд: первая цель — ближайший к точке прицела враг, которого видно из дула; дальше молния
## прыгает к ближайшему ещё не задетому соседу не дальше HOP. Бьёт всех по разу.
func _discharge(aim: Dictionary) -> void:
	var from := _muzzle.global_position
	var at: Vector3 = aim["point"]
	if from.distance_to(at) > RANGE:
		at = from + (at - from).normalized() * RANGE
	var points: Array = [from]
	var hits: Array[Vector2] = []
	var first := -1
	_discharges += 1
	# «Гроза»: каждый STORM_EVERY-й разряд — удар молнии с неба в точку прицела
	if storm and _discharges % STORM_EVERY == 0 and aim["hit"]:
		var strike := StrikeScript.new()
		strike.horde = horde
		strike.position = at
		get_tree().current_scene.add_child(strike)
	if horde and aim["near"]:
		var best := 1e9
		for i in horde.pick_targets(at, AIM_RADIUS, 0.0, 20):
			var p: Vector3 = horde.position_of(i)
			var d := p.distance_to(at)
			if d < best and _clear(from, p):
				best = d
				first = i
	if first < 0:
		# Никого рядом — молния бьёт в землю под прицелом
		points.append(at + Vector3(0, 0.2, 0))
		_show_bolt(points, at)
		return
	var cur: Vector3 = horde.position_of(first)
	points.append(cur + Vector3(0, 0.45, 0))
	hits.append(Vector2(0, first))
	var used := {first: true}
	for n in chain - 1:
		var next := -1
		var best_d := HOP
		for i in horde.pick_targets(cur, HOP, 0.0, 16):
			if used.has(i):
				continue
			var d: float = horde.position_of(i).distance_to(cur)
			if d < best_d:
				best_d = d
				next = i
		if next < 0:
			break
		used[next] = true
		cur = horde.position_of(next)
		points.append(cur + Vector3(0, 0.45, 0))
		hits.append(Vector2(hits.size(), next))
	horde._kill_sorted(hits, hits.size(), "lightning")
	if stun:
		# «Шок»: вокруг первого удара толпа почти застывает на секунду
		horde.chill(points[1], 3.0, 0.15, 1.0)
	_kick = 1.0
	_show_bolt(points, points[1])


## Шаровая молния: рождается над точкой прицела и плывёт от героя дальше в толпу.
func _spawn_ball(at: Vector3) -> void:
	var b := BallScript.new()
	b.horde = horde
	var d := at - global_position
	d.y = 0.0
	b.dir = d.normalized() if d.length_squared() > 0.01 else Vector3.FORWARD
	b.position = at + Vector3(0, BallScript.HOVER, 0)
	get_tree().current_scene.add_child(b)


## Видно ли цель из дула (земля и скалы — лучом физики, деревья и хижины — по карте).
func _clear(from: Vector3, p: Vector3) -> bool:
	var to := p + Vector3(0, 0.45, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if _player():
		query.exclude = [_player().get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	var map := get_tree().get_first_node_in_group("map")
	return not (map and map.line_blocked(from, to))


# --- молния -----------------------------------------------------------------------------------

func _show_bolt(points: Array, impact: Vector3) -> void:
	_bolt_points = points
	_bolt_life = BOLT_LIFE
	_rebuild_bolt()
	_light.global_position = impact + Vector3(0, 1.0, 0)
	_light.visible = true
	_sparks.global_position = impact + Vector3(0, 0.3, 0)
	_sparks.emitting = true


func _update_bolt(delta: float) -> void:
	if _bolt_life <= 0.0:
		return
	_bolt_life -= delta
	if _bolt_life <= 0.0:
		_bolt_core.visible = false
		_bolt_glow.visible = false
		_light.visible = false
		if not _firing:
			_sparks.emitting = false
		return
	# Каждый кадр — новые изломы: молния дрожит
	_rebuild_bolt()


## Ломаная молнии между точками: изломы, у дула тоньше; к каждому участку — короткие отростки.
## Две полоски крест-накрест на сегмент (видно с любой стороны); сердцевина и свечение — две
## сетки с разной толщиной.
func _rebuild_bolt() -> void:
	# Начало молнии — всегда у дула (в полёте не отстаёт)
	if not _bolt_points.is_empty():
		_bolt_points[0] = _muzzle.global_position
	var core := SurfaceTool.new()
	core.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in _bolt_points.size() - 1:
		var a: Vector3 = _bolt_points[k]
		var b: Vector3 = _bolt_points[k + 1]
		var steps := clampi(int(a.distance_to(b) / 1.2), 3, 14)
		var prev := a
		for s in steps:
			var t := float(s + 1) / steps
			var p := a.lerp(b, t)
			if s < steps - 1:
				p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.35 if k == 0 else 0.5)
			var w := lerpf(0.012, 0.045, t) if k == 0 else 0.05
			_strip(core, prev, p, w)
			_strip(glow, prev, p, w * 4.0)
			# Отросток вбок
			if randf() < 0.3 and k > 0 or (k == 0 and s > steps / 2 and randf() < 0.25):
				var fork := p + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)) * 0.9
				_strip(core, p, fork, w * 0.6)
			prev = p
	_bolt_core.mesh = core.commit()
	_bolt_glow.mesh = glow.commit()
	_bolt_core.visible = true
	_bolt_glow.visible = true


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	for side in [Vector3.UP, d.cross(Vector3.UP).normalized()]:
		var o: Vector3 = side * w
		for v in [a - o, a + o, b + o, a - o, b + o, b - o]:
			st.add_vertex(v)


func _build_effects() -> void:
	_bolt_core = _bolt_node(Color(0.85, 0.95, 1.0), 1.0)
	_bolt_glow = _bolt_node(Color(0.25, 0.55, 1.0), 0.45)
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.light_color = Color(0.45, 0.7, 1.0)
	_light.light_energy = 5.0
	_light.omni_range = 9.0
	_light.visible = false
	add_child(_light)
	_sparks = GPUParticles3D.new()
	_sparks.top_level = true
	_sparks.emitting = false
	_sparks.amount = 48
	_sparks.lifetime = 0.35
	_sparks.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -10.0, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.97, 1.0, 1.0))
	grad.set_color(1, Color(0.2, 0.5, 1.0, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	pm.color_ramp = tex
	_sparks.process_material = pm
	var dot := BoxMesh.new()
	dot.size = Vector3(0.06, 0.06, 0.06)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = dm
	_sparks.draw_pass_1 = dot
	add_child(_sparks)


func _bolt_node(col: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col, alpha)
	mi.material_override = m
	add_child(mi)
	return mi


func _update_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.003 * _kick
	var breath := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.002, 0.0)
	position = REST_POS + breath + shake + Vector3(0.0, -0.4 * lower, 0.02 * _kick)
	rotation = REST_ROT + Vector3(0.02 * _kick - 0.6 * lower, 0.0, 0.0)
