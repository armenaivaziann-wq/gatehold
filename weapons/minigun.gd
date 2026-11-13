extends "res://weapons/weapon.gd"
## Ручной пулемёт (миниган) от первого лица (дочерний узел камеры).
## Зажать ЛКМ — блок из шести стволов раскручивается и, раскрутившись, бьёт очередью: каждая пуля
## летит мгновенно в точку под прицелом (с небольшим разбросом) и валит первого врага на линии;
## трассеры, вспышка, гильзы, треск очереди. В ленте CLIP_SIZE патронов; кончились — перезарядка
## из запаса (сама или по R). Запас пополняется в начале волны.
## Модель — шестиствольный миниган по листу пользователя (minigun_model.gd): Barrels — блок
## стволов (крутится вокруг Z), Muzzle — дуло; руки: правая — задняя D-рукоять, левая — передняя.
## Покупается за трофеи на вкладке «Оружие» (upgrades.gd: WEAPONS).

const FxBudget := preload("res://core/fx_budget.gd")

const MinigunModel := preload("res://weapons/minigun_model.gd")
const LOOP_SOUND := preload("res://audio/sounds/gatling_loop.wav")
const FirePatch := preload("res://effects/fire_patch.gd")
const ExplosionScript := preload("res://effects/explosion.gd")
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")

# Положение в кадре (оси камеры): справа внизу, стволы смотрят к прицелу
const REST_POS := Vector3(0.15, -0.3, -0.45)
const REST_ROT := Vector3(0.29, 0.27, 0.0)
const VIEW_SCALE := 0.62
# Руки в осях модели: точка на оси, ось хвата, радиус там, куда уходит локоть
const RIGHT_HAND := MinigunModel.RIGHT_HAND
const LEFT_HAND := MinigunModel.LEFT_HAND

const RATE := 16.0               # пуль в секунду, раскрученный
const SPIN_UP := 0.45            # с раскрутки
const SPIN_SPEED := 32.0         # рад/с блока стволов
const CLIP_SIZE := 150
const START_RESERVE := 600
const RESUPPLY_RATE := 8.0      # пуль в секунду из обоза: запас в руках пополняется сам
const RELOAD_TIME := 2.6
const SPREAD := 0.25             # м разброса на 30 м — очередь кучно ложится в прицел
const AIM_ASSIST := 2.2          # м: так близко к прицелу враг — пуля летит прямо в него
const RANGE := 90.0
const TRACER_LIFE := 0.06
const MARKER_RADIUS := 1.2

## С мастерством (mastery.gd): темп, лента и запас, раскрутка, перезарядка, бронебой,
## зажигательные и разрывные пули.
var rate: float
var clip_size: int
var reserve_size: int
var spin_up: float
var reload_time: float
var pierce: int
var incendiary: bool
var explosive: bool
## Ветка минигана: урон пули, шанс рикошета, финалы «Огненный шквал» и «Свинцовая буря».
var damage := 1
var ricochet := 0.0
var fire_final := false
var storm := false
var _tracer_mat: StandardMaterial3D
var _heat_mat: StandardMaterial3D
## Патронов в ленте и в запасе.
var clip: int
var reserve: int
## Держать огонь без мыши (для автоматических снимков).
var force_fire := false

var _spin := 0.0
var _cool := 0.0
var _reload := 0.0
var _supply := 0.0
var _shots := 0
var _kick := 0.0
var _muzzle: Node3D
var _barrels: Node3D
var _flash: MeshInstance3D
var _light: OmniLight3D
var _casings: GPUParticles3D
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _tracer_to: Array[Vector3] = []
var _next_tracer := 0
var _audio: AudioStreamPlayer


## Параметры из мастерства и общего древа; заново — если прокачку докупили посреди боя (main.gd).
func refresh_stats() -> void:
	rate = RATE * Mastery.mult("minigun", "rate")
	clip_size = CLIP_SIZE + int(Mastery.add("minigun", "clip"))
	reserve_size = int((START_RESERVE + Mastery.add("minigun", "reserve")) * Upgrades.ammo_mult())
	spin_up = SPIN_UP * Mastery.mult("minigun", "spin")
	reload_time = RELOAD_TIME * Mastery.mult("minigun", "reload") * Upgrades.reload_mult()
	pierce = 1 + int(Mastery.add("minigun", "pierce"))
	incendiary = Mastery.flag("minigun", "fire")
	explosive = Mastery.flag("minigun", "blast")
	spin_up *= pow(0.7, Upgrades.w("mg_spin"))
	pierce += Upgrades.w("mg_pierce")
	clip_size = int(clip_size * (1.0 + 0.5 * Upgrades.w("mg_belt")))
	ricochet = 0.25 * Upgrades.w("mg_ricochet")
	fire_final = Upgrades.w("mg_fire") > 0
	storm = Upgrades.w("mg_storm") > 0
	damage = 2 if fire_final else 1
	if fire_final:
		incendiary = true
	if storm:
		rate *= 1.6
		# Лента под темп — чтобы буря не тратила полжизни на перезарядку
		clip_size = int(clip_size * 1.6)
		explosive = true
	if is_inside_tree():
		_apply_colors()


## Цвет трассеров и накал стволов под выбранный финал.
func _apply_colors() -> void:
	if not _tracer_mat:
		return
	if fire_final:
		_tracer_mat.albedo_color = Color(1.0, 0.22, 0.08)
	elif storm:
		_tracer_mat.albedo_color = Color(1.0, 1.0, 1.0)
	else:
		_tracer_mat.albedo_color = Color(1.0, 0.75, 0.35)
	(_barrels as MeshInstance3D).material_overlay = _heat_mat if fire_final else null


func _init() -> void:
	refresh_stats()
	clip = clip_size
	reserve = reserve_size


func _ready() -> void:
	super()
	display_name = "Миниган"
	ammo_kind = "shells"
	_setup_model(MinigunModel.scene(), VIEW_SCALE, RIGHT_HAND, LEFT_HAND)
	_muzzle = _model.find_child("Muzzle")
	_barrels = _model.find_child("Barrels")
	_make_marker(MARKER_RADIUS)
	_build_effects()
	_apply_colors()
	_audio = AudioStreamPlayer.new()
	var loop: AudioStreamWAV = LOOP_SOUND.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(LOOP_SOUND.get_length() * LOOP_SOUND.mix_rate)
	_audio.stream = loop
	_audio.volume_db = -6.0
	_audio.pitch_scale = 1.15
	add_child(_audio)
	_update_pose(0.0)


func _process(delta: float) -> void:
	var can_shoot := _can_shoot()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_supply += delta * RESUPPLY_RATE
	if _supply >= 1.0:
		reserve = mini(reserve + int(_supply), reserve_size)
		_supply -= int(_supply)
	if captured and Input.is_action_just_pressed("reload"):
		start_reload()
	if _reload > 0.0:
		_reload = maxf(_reload - delta, 0.0)
		if _reload == 0.0:
			var take := mini(clip_size - clip, reserve)
			clip += take
			reserve -= take
	var want := (force_fire or can_shoot and Input.is_action_pressed("fire")) and _reload == 0.0 and clip > 0
	# Стволы раскручиваются, пока держишь огонь, и медленно останавливаются
	_spin = move_toward(_spin, 1.0 if want else 0.0, delta / (spin_up if want else 1.0))
	_barrels.rotation.z += SPIN_SPEED * _spin * delta
	var firing := want and _spin >= 1.0
	_cool -= delta
	if firing:
		while _cool <= 0.0 and clip > 0:
			_cool += 1.0 / rate
			_shoot()
		if clip == 0:
			start_reload()
	else:
		_cool = maxf(_cool, 0.0)
	if firing and not _audio.playing:
		_audio.play()
	elif not firing and _audio.playing:
		_audio.stop()
	_casings.emitting = firing
	_flash.visible = firing and _shots % 2 == 0
	_light.light_energy = 1.8 if firing else 0.0
	_kick = move_toward(_kick, 1.0 if firing else 0.0, delta * 8.0)
	if fire_final:
		# Стволы раскаляются, пока крутятся, и медленно остывают
		_heat_mat.albedo_color.a = 0.15 + 0.5 * _spin
	for i in _tracers.size():
		_tracer_life[i] -= delta
		_tracers[i].visible = _tracer_life[i] > 0.0
		# Начало трассера — всегда у дула: в полёте пули не «отстают» от минигана
		if _tracers[i].visible:
			_place_tracer(i, _muzzle.global_position, _tracer_to[i])
	_update_pose(delta)
	_update_marker(MARKER_RADIUS, RANGE, _reload > 0.0)


## Одна пуля: в точку прицела с разбросом, валит первых на линии.
func _shoot() -> void:
	clip -= 1
	_shots += 1
	var aim := _aim()
	var from := _muzzle.global_position
	var target: Vector3 = aim["point"]
	var dist := from.distance_to(target)
	# Точно по врагам: ближайший к прицелу видимый враг (в пределах AIM_ASSIST) — пуля летит в
	# него; никого рядом — в точку прицела с небольшим разбросом
	var locked := false
	if horde and aim["hit"]:
		var best := AIM_ASSIST * maxf(dist / 30.0, 0.6)
		for i in horde.pick_targets(target, best, 0.0, 12):
			var p: Vector3 = horde.position_of(i)
			var d := p.distance_to(target)
			if d < best and _clear_shot(from, p):
				best = d
				target = p + Vector3(0, 0.15, 0)
				locked = true
		dist = from.distance_to(target)
	var spread := SPREAD * dist / 30.0 * (0.4 if locked else 1.0)
	target += Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
	if horde and aim["hit"]:
		# Пуля и чуть за точку — по тем, кто за первым
		var past := target + (target - from).normalized() * 1.0
		horde.kill_line(from, past, 0.55, pierce, "minigun", damage)
		if storm and _shots % 8 == 0:
			# Разрывные: каждая 8-я пуля — видимый мини-взрыв (тихий, иначе грохот без пауз)
			var boom := ExplosionScript.new()
			boom.horde = horde
			boom.radius = 1.6
			boom.max_kills = 6
			boom.source = "minigun"
			boom.silent = true
			boom.position = target
			get_tree().current_scene.add_child(boom)
		elif explosive:
			horde.kill_area(target, 1.4 if storm else 1.1, 3 if storm else 2, "minigun")
		if ricochet > 0.0 and randf() < ricochet:
			var a := randf() * TAU
			horde.kill_area(target + Vector3(cos(a), 0.0, sin(a)) * 1.5, 1.2, 1, "minigun", damage)
		if incendiary and _shots % (4 if fire_final else 6) == 0:
			var patch := FirePatch.new()
			patch.horde = horde
			patch.source = "minigun"
			patch.scale_size = 0.7
			patch.position = target
			get_tree().current_scene.add_child(patch)
	_show_tracer(from, target)


## Видно ли врага из дула: земля и скалы (луч физики), деревья и хижины (карта).
func _clear_shot(from: Vector3, p: Vector3) -> bool:
	var to := p + Vector3(0, 0.4, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if _player():
		query.exclude = [_player().get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	var map := get_tree().get_first_node_in_group("map")
	return not (map and map.line_blocked(from, to))


## Перезарядка из запаса (если есть что заряжать и что брать).
func start_reload() -> void:
	if _reload > 0.0 or clip >= clip_size or reserve <= 0:
		return
	_reload = reload_time


func restock() -> void:
	reserve = reserve_size
	clip = clip_size
	_reload = 0.0


func reload_progress() -> float:
	if _reload > 0.0:
		return 1.0 - _reload / reload_time
	return 1.0 if clip > 0 else 0.0


func ammo_text() -> String:
	return "%d / %d" % [clip, reserve]


func ammo_note() -> String:
	if _reload > 0.0:
		return "перезарядка…"
	if clip == 0 and reserve == 0:
		return "нет патронов"
	if clip < clip_size and reserve > 0:
		return "T — перезарядить"
	return ""


func ammo_empty() -> bool:
	return clip == 0


func _update_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	# Очередь трясёт пулемёт, перезарядка опускает его и заваливает на бок
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.004 * _kick
	var r := sin(clampf(1.0 - _reload / reload_time, 0.0, 1.0) * PI) if _reload > 0.0 else 0.0
	var breath := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.002, 0.0)
	position = REST_POS + breath + shake + Vector3(0.0, -0.08 * r - 0.4 * lower, 0.025 * _kick)
	rotation = REST_ROT + Vector3(0.03 * _kick - 0.35 * r - 0.6 * lower, 0.0, 0.4 * r)
	_point_at_crosshair(REST_POS, REST_ROT, delta)


func _place_tracer(i: int, from: Vector3, to: Vector3) -> void:
	if from.distance_squared_to(to) < 0.01:
		return
	var basis := Basis.looking_at(to - from, Vector3.UP).scaled_local(Vector3(1, 1, from.distance_to(to)))
	_tracers[i].global_transform = Transform3D(basis, (from + to) / 2.0)


func _show_tracer(from: Vector3, to: Vector3) -> void:
	var i := _next_tracer
	_next_tracer = (_next_tracer + 1) % _tracers.size()
	var basis := Basis.looking_at(to - from, Vector3.UP).scaled_local(Vector3(1, 1, from.distance_to(to)))
	_tracers[i].global_transform = Transform3D(basis, (from + to) / 2.0)
	_tracer_to[i] = to
	_tracer_life[i] = TRACER_LIFE
	_tracers[i].visible = true


func _build_effects() -> void:
	# Трассеры — тонкие светящиеся бруски в мировых координатах
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.05, 0.05, 1.0)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.albedo_color = Color(1.0, 0.75, 0.35)
	tracer_mesh.material = tm
	_tracer_mat = tm
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_heat_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_heat_mat.albedo_color = Color(1.0, 0.25, 0.05, 0.15)
	for k in 10:
		var tr := MeshInstance3D.new()
		tr.mesh = tracer_mesh
		tr.top_level = true
		tr.visible = false
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tr)
		_tracers.append(tr)
		_tracer_life.append(0.0)
		_tracer_to.append(Vector3.ZERO)
	# Вспышка — светящаяся звезда у дула
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := TAU * k / 6.0
		var tip := Vector3(cos(a), sin(a), 0.0) * (0.16 if k % 2 == 0 else 0.1)
		var side := Vector3(cos(a + PI / 2), sin(a + PI / 2), 0.0) * 0.03
		st.set_color(Color(1.0, 0.95, 0.6))
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1.0, 0.5, 0.1, 0.2))
		st.add_vertex(tip + side)
		st.add_vertex(tip - side)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash = MeshInstance3D.new()
	_flash.mesh = st.commit()
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_muzzle.add_child(_flash)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	# Свет вспышки — чуть впереди дула: освещает всё перед стволами, а не красит сам миниган
	_light.position = Vector3(0, 0, -5.0)
	_muzzle.add_child(_light)
	# Гильзы летят вправо из короба
	_casings = FxBudget.cosmetic(GPUParticles3D.new())
	_casings.amount = 24
	_casings.lifetime = 0.6
	_casings.emitting = false
	_casings.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0.6, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -9.0, 0)
	_casings.process_material = pm
	var casing := BoxMesh.new()
	casing.size = Vector3(0.012, 0.012, 0.03)
	casing.material = _flat(Color(0.85, 0.65, 0.3))
	_casings.draw_pass_1 = casing
	_casings.position = Vector3(0.1, 0.02, 0.0)
	_model.add_child(_casings)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.6
	m.roughness = 0.4
	return m
