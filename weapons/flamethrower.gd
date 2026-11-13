extends "res://weapons/weapon.gd"
## Огнемёт от первого лица (дочерний узел камеры).
## Зажать ЛКМ — из раструба-клетки бьёт струя огня в точку под прицелом (не дальше RANGE):
## жуки на пути струи и вокруг места, куда она бьёт, сгорают, а на земле остаются горящие
## пятна (fire_patch.gd). Струя жжёт топливо; когда огонь не горит — бак понемногу
## наполняется, а пустой бак сначала заправляется до порога. В начале волны бак полный.
## Модель — огнемёт по концепту пользователя (flamer_model.gd): левая рука на передней рукояти под
## стволом, правая — на задней у короба; ствол всегда смотрит в прицел. Покупается за трофеи на
## вкладке «Оружие» (upgrades.gd: WEAPONS).

const FlamerModel := preload("res://weapons/flamer_model.gd")
const FirePatch := preload("res://effects/fire_patch.gd")
const FireTornado := preload("res://effects/fire_tornado.gd")
const TORNADO_EVERY := 3.0       # с горения между смерчами («Огненный торнадо»)
const TORNADO_MAX := 2           # сколько смерчей одновременно
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")
const LOOP_SOUND := preload("res://audio/sounds/flame_loop.wav")
const IGNITE_SOUND := preload("res://audio/sounds/flame_ignite.wav")

const REST_POS := Vector3(0.2, -0.27, -0.52)
const REST_ROT := Vector3(0.1, 0.22, -0.05)
const VIEW_SCALE := 0.56
const RIGHT_HAND := FlamerModel.RIGHT_HAND
const LEFT_HAND := FlamerModel.LEFT_HAND

const RANGE := 30.0              # дальность струи, м (со стены до дна каналов внизу)
const FLAME_LIFE := 0.5          # сколько живёт язык пламени, с
const BURN_INTERVAL := 0.1
const CONE_KILLS := 3            # за тик: сгорает на пути струи
const SPLASH_RADIUS := 2.2
const SPLASH_KILLS := 5          # за тик: сгорает там, куда бьёт струя
const PATCH_INTERVAL := 0.3
const PATCH_SPACING := 2.4
const MAX_PATCHES := 8
const FUEL_MAX := 100.0
const FUEL_BURN := 9.0           # в секунду, пока горит
const FUEL_REGEN := 6.0          # в секунду, когда не горит
const REGEN_DELAY := 1.2
const REFUEL_UNLOCK := 30.0      # пустой бак: стрелять снова можно с этого уровня

## С мастерством (mastery.gd) и «Оружейником»: дальность, бак, заправка, расход, область огня,
## сколько сжигает; напалм — лужи огня дольше и шире, огненный вал — луж вдвое больше.
var range_max: float
var fuel_max: float
var fuel_regen: float
var fuel_burn: float
var splash_radius: float
var cone_kills: int
var splash_kills: int
var napalm: bool
var patch_interval: float
var max_patches: int
var fuel: float
## Держать огонь без мыши (для автоматических снимков).
var force_fire := false

var _muzzle: Node3D
var _firing := false
var _empty_lock := false
var _idle := 0.0
var _burn_timer := 0.0
var _patch_timer := 0.0
var _shake := 0.0
var _flame: GPUParticles3D
var _core: GPUParticles3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _loop: AudioStreamPlayer
var _ignite: AudioStreamPlayer
var _patches: Array[Node3D] = []
## Ветка огнемёта (вкладка «Улучшения оружия»): синее пламя и огненные смерчи.
var inferno := false
var tornado := false
var _damage := 1
var _tornado_timer := 1.0
var _tornados: Array[Node3D] = []


## Параметры из мастерства и общего древа; заново — если прокачку докупили посреди боя (main.gd).
func refresh_stats() -> void:
	range_max = RANGE * Mastery.mult("flamer", "range")
	fuel_max = FUEL_MAX * Mastery.mult("flamer", "tank")
	fuel_regen = FUEL_REGEN * Mastery.mult("flamer", "regen")
	fuel_burn = FUEL_BURN * Mastery.mult("flamer", "burn")
	splash_radius = SPLASH_RADIUS * Mastery.mult("flamer", "radius") * Upgrades.weapon_radius()
	cone_kills = int(round(CONE_KILLS * Mastery.mult("flamer", "kills")))
	splash_kills = int(round(SPLASH_KILLS * Mastery.mult("flamer", "kills")))
	napalm = Mastery.flag("flamer", "napalm")
	patch_interval = PATCH_INTERVAL * (0.5 if Mastery.flag("flamer", "wall") else 1.0)
	max_patches = MAX_PATCHES + (6 if Mastery.flag("flamer", "wall") else 0)
	# Ветка огнемёта
	range_max *= 1.0 + 0.25 * Upgrades.w("fl_range")
	splash_radius *= 1.0 + 0.2 * Upgrades.w("fl_wide")
	splash_kills += 2 * Upgrades.w("fl_heat")
	cone_kills += Upgrades.w("fl_heat")
	patch_interval /= 1.0 + 0.5 * Upgrades.w("fl_burn")
	inferno = Upgrades.w("fl_inferno") > 0
	tornado = Upgrades.w("fl_tornado") > 0
	_damage = 2 if inferno else 1
	if inferno:
		cone_kills *= 2
		splash_kills *= 2
	if is_inside_tree():
		_apply_colors()


func _init() -> void:
	refresh_stats()
	fuel = fuel_max


func _ready() -> void:
	super()
	display_name = "Огнемёт"
	ammo_kind = "fuel"
	_setup_model(FlamerModel.scene(), VIEW_SCALE, RIGHT_HAND, LEFT_HAND)
	_muzzle = _model.find_child("Muzzle")
	_make_marker(splash_radius)
	_build_effects()
	_apply_colors()
	_update_pose(0.0)


func set_active(on: bool) -> void:
	super(on)
	if not on and _firing:
		_set_firing(false)


func _process(delta: float) -> void:
	var can_shoot := _can_shoot()
	var want := (force_fire or can_shoot and Input.is_action_pressed("fire")) and not _empty_lock and fuel > 0.0
	if want != _firing:
		_set_firing(want)
	var aim := _update_marker(splash_radius, range_max, not _firing and _empty_lock)
	var target := _stream_end(aim)
	if _firing:
		fuel = maxf(fuel - fuel_burn * delta, 0.0)
		_idle = 0.0
		if fuel <= 0.0:
			_empty_lock = true
			_set_firing(false)
		_burn_timer -= delta
		if _burn_timer <= 0.0:
			_burn_timer = BURN_INTERVAL
			_burn(target, aim["near"])
		_patch_timer -= delta
		if _patch_timer <= 0.0 and aim["near"]:
			_patch_timer = patch_interval
			_add_patch(target)
		# «Огненный торнадо»: пока жжёшь, каждые TORNADO_EVERY с в точке удара встаёт смерч
		if tornado and aim["near"]:
			_tornado_timer -= delta
			if _tornado_timer <= 0.0:
				_tornado_timer = TORNADO_EVERY
				_spawn_tornado(target)
	else:
		_idle += delta
		if _idle > REGEN_DELAY:
			fuel = minf(fuel + fuel_regen * delta, fuel_max)
		if _empty_lock and fuel >= REFUEL_UNLOCK:
			_empty_lock = false
	_update_stream(target, delta)
	_update_pose(delta)


func reload_progress() -> float:
	return fuel / fuel_max


func ammo_text() -> String:
	return "%d%%" % int(round(fuel / fuel_max * 100.0))


func ammo_note() -> String:
	if _empty_lock:
		return "заправка…"
	return ""


func ammo_empty() -> bool:
	return _empty_lock


func restock() -> void:
	fuel = fuel_max
	_empty_lock = false


## Куда бьёт струя: точка прицела, но не дальше RANGE от раструба.
func _stream_end(aim: Dictionary) -> Vector3:
	var from := _muzzle.global_position
	var to: Vector3 = aim["point"]
	if from.distance_to(to) > range_max:
		to = from + (to - from).normalized() * range_max
	return to


func _set_firing(on: bool) -> void:
	_firing = on
	_flame.emitting = on
	_core.emitting = on
	_smoke.emitting = on
	if on:
		_ignite.play()
		_loop.play()
	else:
		_loop.stop()


## Сжечь жуков: вдоль струи (конус от раструба) и вокруг места, куда она бьёт.
func _burn(target: Vector3, landed: bool) -> void:
	if not horde:
		return
	var from := _muzzle.global_position
	var to := target - from
	horde.kill_cone(from, to.normalized(), to.length() + 1.0, 0.09, cone_kills, "flamer", _damage)
	if landed:
		horde.kill_area(target, splash_radius, splash_kills, "flamer", _damage)


## Огненный смерч в точке удара: ползёт дальше от героя, затягивает и сжигает толпу.
func _spawn_tornado(at: Vector3) -> void:
	_tornados.assign(_tornados.filter(func(t) -> bool: return is_instance_valid(t)))
	if _tornados.size() >= TORNADO_MAX:
		return
	var t := FireTornado.new()
	t.horde = horde
	var d := at - _camera.global_position
	d.y = 0.0
	t.dir = d.normalized() if d.length_squared() > 0.01 else Vector3.FORWARD
	t.position = at
	get_tree().current_scene.add_child(t)
	_tornados.append(t)


## Цвет струи, света и окон огнемёта: обычное пламя или синее («Синее Инферно»).
func _apply_colors() -> void:
	var flame_cols: Array = [Color(1.0, 0.72, 0.22, 1.0), Color(1.0, 0.42, 0.06, 0.95), Color(0.85, 0.18, 0.03, 0.8), Color(0.3, 0.08, 0.03, 0.0)]
	var core_cols: Array = [Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.6, 0.15, 0.85), Color(1.0, 0.35, 0.05, 0.0)]
	var glow := Color(1.0, 0.5, 0.08)
	if inferno:
		flame_cols = [Color(0.75, 0.9, 1.0, 1.0), Color(0.3, 0.55, 1.0, 0.95), Color(0.12, 0.25, 0.9, 0.8), Color(0.03, 0.05, 0.3, 0.0)]
		core_cols = [Color(0.95, 1.0, 1.0, 1.0), Color(0.5, 0.75, 1.0, 0.85), Color(0.2, 0.4, 1.0, 0.0)]
		glow = Color(0.25, 0.5, 1.0)
	for pair in [[_flame, flame_cols], [_core, core_cols]]:
		var p: GPUParticles3D = pair[0]
		if not p:
			continue
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array()
		grad.colors = PackedColorArray()
		var cols: Array = pair[1]
		for k in cols.size():
			grad.add_point(float(k) / (cols.size() - 1), cols[k])
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		(p.process_material as ParticleProcessMaterial).color_ramp = gt
	if _light:
		_light.light_color = glow
	var g: MeshInstance3D = _model.find_child("Glow") if _model else null
	if g:
		var m: StandardMaterial3D = g.mesh.surface_get_material(0).duplicate()
		m.emission = glow
		m.vertex_color_use_as_albedo = false
		m.albedo_color = glow
		g.material_override = m


## Горящее пятно там, куда бьёт струя (не ближе PATCH_SPACING к уже горящему).
func _add_patch(at: Vector3) -> void:
	# Без типа у аргумента: погасшие пятна уже освобождены, Node3D из них не получить
	_patches.assign(_patches.filter(func(p) -> bool: return is_instance_valid(p)))
	for p in _patches:
		if p.global_position.distance_to(at) < PATCH_SPACING:
			p.refresh()
			return
	if _patches.size() >= max_patches:
		_patches[0].queue_free()
		_patches.remove_at(0)
	var patch := FirePatch.new()
	patch.horde = horde
	patch.source = "flamer"
	patch.blue = inferno
	patch.burn_time = FirePatch.BURN_TIME * (1.0 + 0.5 * Upgrades.w("fl_burn"))
	if napalm:
		patch.scale_size = 1.4
		patch.burn_time = FirePatch.BURN_TIME * 2.0
	patch.position = at
	get_tree().current_scene.add_child(patch)
	_patches.append(patch)


## Струя смотрит в точку удара; скорость языков пламени — чтобы они долетали ровно туда.
func _update_stream(target: Vector3, delta: float) -> void:
	var from := _muzzle.global_position
	var dist := maxf(from.distance_to(target), 1.0)
	for p: GPUParticles3D in [_flame, _core, _smoke]:
		p.global_position = from
		if from.distance_to(target) > 0.3:
			p.look_at(target, Vector3.UP)
	var speed := dist / FLAME_LIFE
	var pm: ParticleProcessMaterial = _flame.process_material
	pm.initial_velocity_min = speed * 0.92
	pm.initial_velocity_max = speed * 1.05
	var core_pm: ParticleProcessMaterial = _core.process_material
	core_pm.initial_velocity_min = speed * 0.95
	core_pm.initial_velocity_max = speed * 1.0
	var smoke_pm: ParticleProcessMaterial = _smoke.process_material
	smoke_pm.initial_velocity_min = speed * 0.7
	smoke_pm.initial_velocity_max = speed * 0.85
	# Свет у раструба пляшет вместе с огнём
	var t := Time.get_ticks_msec() / 1000.0
	var on := 1.0 if _firing else 0.0
	_light.light_energy = move_toward(_light.light_energy, on * (2.2 + 0.6 * sin(t * 31.0) * sin(t * 17.0)), delta * 30.0)
	_shake = move_toward(_shake, on, delta * 6.0)


func _update_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var breath := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.002, 0.0)
	# Пока горит — мелкая дрожь от напора
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.003 * _shake
	position = REST_POS + breath + jitter + Vector3(0.0, -0.4 * lower, 0.012 * _shake)
	rotation = REST_ROT + Vector3(-0.6 * lower + 0.015 * _shake, 0.0, 0.0)
	_point_at_crosshair(REST_POS, REST_ROT, delta)


# --- эффекты -------------------------------------------------------------------------------

func _build_effects() -> void:
	# Языки пламени: гранёные шарики, растут, желтеют → краснеют → гаснут
	_flame = _emitter(260, FLAME_LIFE, 0.13, 4.0, Vector3(0, 2.5, 0), 0.8, 5.0,
		[Color(1.0, 0.72, 0.22, 1.0), Color(1.0, 0.42, 0.06, 0.95), Color(0.85, 0.18, 0.03, 0.8), Color(0.3, 0.08, 0.03, 0.0)], true)
	# Горячая сердцевина струи — тоньше и ярче
	_core = _emitter(120, FLAME_LIFE * 0.75, 0.08, 1.5, Vector3.ZERO, 1.0, 2.2,
		[Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.6, 0.15, 0.85), Color(1.0, 0.35, 0.05, 0.0)], true)
	# Дым над струёй — появляется ближе к концу
	_smoke = _emitter(60, FLAME_LIFE * 2.0, 0.18, 8.0, Vector3(0, 3.0, 0), 0.8, 3.5,
		[Color(0.25, 0.2, 0.17, 0.0), Color(0.25, 0.2, 0.17, 0.55), Color(0.4, 0.37, 0.33, 0.0)], false)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	# Свет — впереди дула, у струи: не красит сам огнемёт в оранжевый
	_light.position = Vector3(0, 0, -6.0)
	_muzzle.add_child(_light)
	_loop = AudioStreamPlayer.new()
	var loop: AudioStreamWAV = LOOP_SOUND.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(LOOP_SOUND.get_length() * LOOP_SOUND.mix_rate)
	_loop.stream = loop
	_loop.volume_db = -7.0
	add_child(_loop)
	_ignite = AudioStreamPlayer.new()
	_ignite.stream = IGNITE_SOUND
	_ignite.volume_db = -5.0
	add_child(_ignite)


func _emitter(amount: int, lifetime: float, size: float, spread: float, gravity: Vector3,
		scale_from: float, scale_to: float, colors: Array, unshaded: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.top_level = true
	# Частицы летят через всю сцену — границы не должны отсекать струю
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = spread
	pm.gravity = gravity
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	var curve := Curve.new()
	curve.max_value = 8.0  # по умолчанию кривая обрезана сверху единицей
	curve.add_point(Vector2(0.0, scale_from))
	curve.add_point(Vector2(1.0, scale_to))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for k in colors.size():
		grad.add_point(float(k) / (colors.size() - 1), colors[k])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p
