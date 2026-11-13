extends Node3D
## Турель на площадке. Голова поворачивается к врагу в радиусе, подобравшемуся ближе всех к
## воротам, и стреляет, когда навелась:
##   пулемёт — блок стволов раскручивается и бьёт очередью: каждый выстрел — трассер и первые
##     враги на линии огня; вспышка, гильзы, треск очереди;
##   лазер — заряжается, потом держит на цели красный луч: он прожигает врагов насквозь по
##     линии; на конце луча — искры и свет, гудение, пока горит;
##   заморозка — ледяная струя: все вокруг цели идут втрое медленнее (horde.chill), слабых
##     разбивает в осколки. Сама убивает мало — держит толпу под огнём пулемётов и лазеров;
##   огнемёт — струя огня бьёт по месту, где стоит толпа: жжёт всех вокруг цели и время от
##     времени поджигает землю (горит ещё несколько секунд). Бьёт близко;
##   мортира — труба задрана вверх, мина летит навесом через скалы и стенки каналов в самую
##     густую толпу (с упреждением) и рвётся там. Бьёт далеко, но не вплотную; отдача, вспышка.
## Модели — turret_models.gd (по эскизам): узлы Base, Head (поворачивается), Gun (качается),
## у пулемёта Barrels (крутится), Muzzle — дуло.

const FxBudget := preload("res://core/fx_budget.gd")

const ProjectileScript := preload("res://turrets/turret_projectile.gd")
const ExplosionScript := preload("res://effects/explosion.gd")
const TurretModels := preload("res://turrets/turret_models.gd")
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")
const FirePatch := preload("res://effects/fire_patch.gd")
const GATLING_SOUND := preload("res://audio/sounds/gatling_loop.wav")
const FLAME_SOUND := preload("res://audio/sounds/flame_loop.wav")
const LASER_SOUND := preload("res://audio/sounds/laser_loop.wav")
const MORTAR_SOUND := preload("res://audio/sounds/explosion.wav")

## Баланс: пулемёт — дёшево и много, бьёт ближних; лазер — дорого, дальше и прожигает линию;
## заморозка — урона мало, но тормозит толпу вокруг цели (там её дольше бьют остальные).
## Турель держит свой участок: бьёт только в секторе ±ARC от направления, куда её поставили
## (к ближайшему каналу), и только тех, кого видно — сквозь землю и скалы не стреляет.
const TYPES := {
	"gatling": {"name": "Пулемёт", "cost": 150, "range": 22.0, "min_range": 0.0, "reload": 0.15,
		"desc": "очередь по ближним врагам"},
	"laser": {"name": "Лазер", "cost": 260, "range": 27.0, "min_range": 0.0, "reload": 0.18,
		"desc": "луч прожигает врагов и броню насквозь"},
	"freeze": {"name": "Заморозка", "cost": 200, "range": 17.0, "min_range": 0.0, "reload": 0.3,
		"desc": "тормозит толпу втрое"},
	"flame": {"name": "Огнемёт", "cost": 180, "range": 13.0, "min_range": 0.0, "reload": 0.2,
		"desc": "жжёт толпу и землю под ней"},
	"mortar": {"name": "Мортира", "cost": 220, "range": 38.0, "min_range": 9.0, "reload": 1.3,
		"desc": "навесом бьёт по толпе издалека"},
}
const ARC := deg_to_rad(65.0)     # полуширина сектора огня
const ORDER := ["gatling", "freeze", "flame", "laser", "mortar"]
## Заморозка: радиус облака у цели, во сколько раз медленнее и сколько секунд; сколько
## слабых разбивает за выстрел.
const FREEZE_RADIUS := 3.2
const FREEZE_SLOW := 0.35
const FREEZE_TIME := 2.2
const FREEZE_KILLS := 1
## Мортира: радиус и предел взрыва, угол трубы, время полёта мины (с), сила тряски от взрыва.
const MORTAR_RADIUS := 4.0
const MORTAR_KILLS := 9
const MORTAR_SPLIT := 3.2        # м: на столько вперёд и назад по потоку падают малые заряды
const MORTAR_SPLIT_RADIUS := 2.6
const MORTAR_SPLIT_KILLS := 4
const MORTAR_PITCH := TurretModels.MORTAR_PITCH
const MORTAR_FLIGHT := 1.25
const MORTAR_RECOIL := 0.16      # м: на столько труба отскакивает назад при выстреле
## Огнемёт: радиус огня у цели, скольких жжёт за тик, каждый который тик поджигает землю.
const FLAME_RADIUS := 2.6
## Сила турелей подобрана после исправления прицела (11.11.2026): раньше после каждой смерти
## турель секунду стреляла «в чужого» врага за пределами дальности — эти выстрелы пропадали,
## и турели теперь бьют вдвое точнее; темп и прожиг урезаны, чтобы сила осталась прежней.
const FLAME_KILLS := 1
const FLAME_PATCH_EVERY := 16
const BASE_PIERCE := 1           # сколько врагов на линии прошивает пуля пулемёта (без прокачки)
const LASER_PIERCE := 2          # сколько врагов на линии прожигает луч за тик (без прокачки)
const LASER_REACH := 8.0         # м: луч бьёт и за целью — по толпе позади
const LASER_DAMAGE := 2          # луч прожигает и доспех: врага в доспехах — с одного раза
const MODEL_SCALE := 1.1
const TURN_SPEED := 3.5          # рад/с
const AIM_TOLERANCE := 0.08      # рад: стреляет, когда навелась точнее
const RETARGET := 0.25           # с между поиском цели
const SPIN_UP := 0.5             # с раскрутки стволов до первого выстрела
const SPIN_SPEED := 28.0         # рад/с у раскрученного блока стволов
const PITCH_LIMIT := Vector2(-1.05, 0.45)
const TRACER_LIFE := 0.07
const GATLING_TOLERANCE := 0.07  # рад: пулемёт бьёт очередью, когда ствол смотрит на цель
const PITCH_TOLERANCE := 0.12    # рад: и по высоте — ствол довернулся к цели
## Куда целятся пулемёт и лазер: в середину тела врага, а не в землю у ног (иначе трассеры
## и луч уходили в землю, а враг всё равно падал).
const BODY_Y := 0.55
## Улучшение в бою (I → II → III, turrets.gd): каждая ступень — чаще стреляет и дальше бьёт,
## на III пулемёт и лазер пробивают ещё одного врага, мортира и жаровня бьют шире.
const MAX_TIER := 3
const TIER_RATE := 1.25          # во сколько раз чаще стреляет с каждой ступенью
const TIER_RANGE := 1.08
const TIER_COST := [0.0, 1.0, 1.6]  # цена ступеней II и III — доля цены турели
const TIER_COLORS := [Color(0.78, 0.8, 0.84), Color(0.98, 0.74, 0.22)]

var kind := "gatling"
## Куда смотрит турель (поворот вокруг Y, задать до добавления в сцену): середина сектора огня.
var facing := 0.0
## Ступень улучшения (1..MAX_TIER) и сколько монет вложено (покупка и улучшения) — от этого
## цена продажи.
var tier := 1
var spent := 0
var _model: Node3D
## С мастерством этой турели (mastery.gd): поворот, сколько валит за выстрел, радиус и сила
## огня или взрыва, кассета, поджог земли.
var _turn := TURN_SPEED
var _pierce := 1
var _radius_mult := 1.0
var _kill_mult := 1.0
var _cluster := false
var _ignite := false
var _shots := 0
var _beam: Node3D
var _spark: GPUParticles3D
var _beam_light: OmniLight3D
var horde: Node3D
var _map: Node3D

var _head: Node3D
var _muzzle: Node3D
var _range := 30.0
var _min_range := 0.0
var _reload := 1.0
var _cool := 0.0
var _retarget := 0.0
var _target := -1
## Постоянный номер цели (horde.uid_of): индекс _target после чужой смерти может указывать уже
## на другого врага в другом конце карты — тогда цель сразу ищется заново.
var _target_uid := 0
var _aim := Vector3.ZERO
## Точка прицела на теле врага (_aim — у его ног: туда бьют облака холода и огонь).
var _body := Vector3.ZERO
var _has_aim := false
var _audio: AudioStreamPlayer3D
var _flame: GPUParticles3D
var _gun: Node3D
var _barrels: Node3D
var _spin := 0.0                 # 0 — стволы стоят, 1 — раскручены
var _flash: MeshInstance3D
var _flash_time := 0.0
var _casings: GPUParticles3D
var _recoil := 0.0
var _gun_rest := Vector3.ZERO
static var _shell_mesh: Mesh
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _next_tracer := 0


func _ready() -> void:
	var t: Dictionary = TYPES[kind]
	refresh_stats()
	var model: Node3D = TurretModels.scene(kind).instantiate()
	# Крупнее человека — чтобы со стены было хорошо видно, где что стоит
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	_model = model
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_head = model.find_child("Head")
	_muzzle = model.find_child("Muzzle")
	_gun = model.find_child("Gun")
	_barrels = model.find_child("Barrels")
	# Голова сразу смотрит вдоль каналов — к пещерам (на север)
	_head.rotation.y = facing
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 18.0
	_audio.volume_db = -4.0
	add_child(_audio)
	match kind:
		"gatling":
			var loop: AudioStreamWAV = GATLING_SOUND.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_end = int(GATLING_SOUND.get_length() * GATLING_SOUND.mix_rate)
			_audio.stream = loop
			_audio.volume_db = -6.0
			_build_gatling_effects()
		"freeze":
			# Шипение струи — звук огнемёта выше и тише
			var loop: AudioStreamWAV = FLAME_SOUND.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_end = int(FLAME_SOUND.get_length() * FLAME_SOUND.mix_rate)
			_audio.stream = loop
			_audio.volume_db = -16.0
			_audio.pitch_scale = 1.6
			_flame = _flame_emitter(true)
		"flame":
			var loop: AudioStreamWAV = FLAME_SOUND.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_end = int(FLAME_SOUND.get_length() * FLAME_SOUND.mix_rate)
			_audio.stream = loop
			_audio.volume_db = -10.0
			_flame = _flame_emitter(false)
		"laser":
			var loop: AudioStreamWAV = LASER_SOUND.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_end = int(LASER_SOUND.get_length() * LASER_SOUND.mix_rate)
			_audio.stream = loop
			_audio.volume_db = -12.0
			_build_laser_effects()
		"mortar":
			# Глухой хлопок выстрела — низкий и тихий звук взрыва
			_audio.stream = MORTAR_SOUND
			_audio.volume_db = -9.0
			_audio.pitch_scale = 0.62
			_build_mortar_effects()


## Параметры: из типа турели, «Оптики» общего древа, мастерства самой турели и ступени улучшения.
## Заново — после улучшения и если прокачку докупили посреди боя (main.gd).
func refresh_stats() -> void:
	var t: Dictionary = TYPES[kind]
	var tiers := tier - 1
	_range = t["range"] * Upgrades.turret_range(kind) * pow(TIER_RANGE, tiers)
	_min_range = t["min_range"]
	_reload = t["reload"] * Mastery.mult(kind, "reload") / Mastery.mult(kind, "rate") / pow(TIER_RATE, tiers) / Upgrades.turret_rate()
	_turn = TURN_SPEED * Mastery.mult(kind, "turn")
	# Пуля и луч прошивают толпу: в реке врагов задевают не одного
	_pierce = BASE_PIERCE + int(Mastery.add(kind, "pierce"))
	_radius_mult = Mastery.mult(kind, "radius")
	_kill_mult = Mastery.mult(kind, "kills")
	_cluster = Mastery.flag(kind, "cluster")
	_ignite = Mastery.flag(kind, "fire")
	if kind == "laser":
		_pierce += LASER_PIERCE - 1
	# Узлы своей турели из общего древа (upgrades.gd)
	match kind:
		"gatling":
			_pierce += Upgrades.level("gat_pierce")
			_reload /= 1.0 + 0.1 * Upgrades.level("gat_rate")
		"flame":
			_radius_mult *= 1.0 + 0.12 * Upgrades.level("flame_radius")
		"laser":
			_range *= 1.0 + 0.08 * Upgrades.level("laser_reach")
			_pierce += Upgrades.level("laser_pierce")
		"mortar":
			_radius_mult *= 1.0 + 0.12 * Upgrades.level("mortar_radius")
			_reload /= 1.0 + 0.12 * Upgrades.level("mortar_rate")
	if tier == MAX_TIER:
		if kind in ["gatling", "laser"]:
			_pierce += 1
		else:
			_radius_mult *= 1.2


## Следующая ступень: чаще стреляет, дальше бьёт; на III — пробой или шире удар. Модель чуть
## крупнее, на основании — кольцо: серебряное на II, золотое на III.
func upgrade() -> void:
	if tier >= MAX_TIER:
		return
	tier += 1
	refresh_stats()
	_model.scale = Vector3.ONE * MODEL_SCALE * (1.0 + 0.07 * (tier - 1))
	# Кольцо на земле вокруг основания (каждая ступень — ещё одно, снаружи), чуть светится
	var r := _base_radius() + 0.12 + 0.32 * (tier - 2)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r
	torus.outer_radius = r + 0.22
	torus.rings = 28
	torus.ring_segments = 5
	ring.mesh = torus
	var mat := _flat(TIER_COLORS[tier - 2])
	mat.emission_enabled = true
	mat.emission = TIER_COLORS[tier - 2]
	mat.emission_energy_multiplier = 0.35
	ring.material_override = mat
	ring.position.y = 0.06
	ring.scale = Vector3(1, 0.35, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


## Радиус основания модели по земле (по её габаритам), м.
func _base_radius() -> float:
	var base: Node3D = _model.find_child("Base")
	var r := 1.0
	for mi: MeshInstance3D in (base if base else _model).find_children("*", "MeshInstance3D", true, false) \
			+ ([base] if base is MeshInstance3D else []):
		var box: AABB = mi.global_transform * mi.get_aabb()
		r = maxf(r, maxf(maxf(absf(box.position.x - global_position.x), absf(box.end.x - global_position.x)),
			maxf(absf(box.position.z - global_position.z), absf(box.end.z - global_position.z))))
	return r


func _process(delta: float) -> void:
	if not horde:
		return
	_cool = maxf(_cool - delta, 0.0)
	_retarget -= delta
	# Цель убили (или под её индексом теперь другой враг) — новую ищем сразу, а не через 0.25 с
	if _target >= 0 and not horde.same(_target, _target_uid):
		_target = -1
		_retarget = 0.0
	if _retarget <= 0.0:
		_retarget = RETARGET
		# Прежняя цель ещё в радиусе и видна — держим её, иначе голова мечется между жуками
		var keep: bool = _target >= 0 and _target < horde.count() and \
			horde.position_of(_target).distance_to(global_position) < _range and _in_arc(horde.position_of(_target)) \
			and (kind == "mortar" or _visible(horde.position_of(_target)))
		if not keep:
			_target = _find_target()
			_target_uid = horde.uid_of(_target)
	_has_aim = _target >= 0 and horde.same(_target, _target_uid)
	if _has_aim:
		_aim = horde.position_of(_target)
		_body = _aim + Vector3(0, BODY_Y, 0)
	var aimed := false
	if _has_aim:
		var d := _aim - _head.global_position
		# Голова не крутится на 360: только в пределах своего сектора
		var want := facing + clampf(angle_difference(facing, atan2(-d.x, -d.z)), -ARC, ARC)
		_head.rotation.y = rotate_toward(_head.rotation.y, want, _turn * delta)
		var tolerance := GATLING_TOLERANCE if kind == "gatling" else AIM_TOLERANCE
		aimed = absf(angle_difference(_head.rotation.y, want)) < tolerance
		if _gun and kind == "mortar":
			# Труба мортиры всегда задрана — навесной огонь; целится только поворотом головы
			_gun.rotation.x = rotate_toward(_gun.rotation.x, MORTAR_PITCH, _turn * delta)
		elif _gun:
			# Ствол — по высоте на цель (от цапф)
			var g := _body - _gun.global_position
			var pitch := clampf(atan2(g.y, Vector2(g.x, g.z).length()), PITCH_LIMIT.x, PITCH_LIMIT.y)
			_gun.rotation.x = rotate_toward(_gun.rotation.x, pitch, _turn * delta)
			aimed = aimed and absf(_gun.rotation.x - pitch) < PITCH_TOLERANCE
	if kind == "freeze" or kind == "flame":
		_update_flame(aimed and _has_aim)
	if kind == "gatling":
		# Стволы крутятся, пока есть цель; стреляет — когда навёлся
		_update_gatling(_has_aim, aimed, delta)
		if _spin < 1.0:
			aimed = false
	if kind == "laser":
		# Лазер заряжается, пока есть цель; луч горит, когда заряжен и навёлся
		_update_laser(_has_aim, aimed, delta)
		if _spin < 1.0:
			aimed = false
	if kind == "mortar":
		_update_mortar(delta)
	if aimed and _cool == 0.0:
		_cool = _reload
		_fire()


## Цель: ближайший к воротам из тех, кого видно (сквозь скалы и стенки каналов не стреляют).
## Мортира стреляет навесом поверх скал — ей видимость не нужна: из ближних к воротам она
## выбирает того, вокруг кого гуще толпа.
func _find_target() -> int:
	if kind == "mortar":
		var best := -1
		var best_n := -1
		for i in horde.pick_targets(global_position, _range, _min_range, 24):
			var p: Vector3 = horde.position_of(i)
			if not _in_arc(p):
				continue
			var n: int = horde.count_near(p, MORTAR_RADIUS)
			if n > best_n:
				best_n = n
				best = i
		return best
	for i in horde.pick_targets(global_position, _range, _min_range, 12):
		var p: Vector3 = horde.position_of(i)
		if _in_arc(p) and _visible(p):
			return i
	return -1


## В секторе ли огня точка p.
func _in_arc(p: Vector3) -> bool:
	var d := p - global_position
	return absf(angle_difference(facing, atan2(-d.x, -d.z))) <= ARC


## Видно ли точку p из дула: луч до неё не задевает землю и скалы (слой мира), деревья и хижины
## (map_builder.gd: line_blocked).
func _visible(p: Vector3) -> bool:
	var to := p + Vector3(0, 0.4, 0)
	var query := PhysicsRayQueryParameters3D.create(_muzzle.global_position, to, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	if not _map:
		_map = get_tree().get_first_node_in_group("map")
	return not (_map and _map.line_blocked(_muzzle.global_position, to))


## Луч или пуля за целью летит дальше, но не сквозь скалу: обрезать по первому препятствию.
func _clip(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.4, 0), to + Vector3(0, 0.4, 0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return to if hit.is_empty() else Vector3(hit.position.x, to.y, hit.position.z)


func _fire() -> void:
	match kind:
		"laser":
			var from := _muzzle.global_position
			# Луч бьёт и за целью — по толпе позади неё
			var reach := LASER_REACH + 3.0 * Upgrades.level("laser_reach")
			var to := _clip(_body, _body + Vector3(_body.x - from.x, 0.0, _body.z - from.z).normalized() * reach)
			horde.kill_line(from, to, 0.55, _pierce, "laser", LASER_DAMAGE)
			_shots += 1
			if _ignite and _shots % 10 == 0:
				_burn_ground(_aim, 0.9)
		"gatling":
			var from := _muzzle.global_position
			# Пуля с небольшим разбросом; падает первый жук на линии огня
			# В тело цели; разброс маленький — очередь ложится в того, в кого смотрит ствол
			var to := _body + Vector3(randf_range(-0.12, 0.12), randf_range(-0.1, 0.1), randf_range(-0.12, 0.12))
			if _pierce > 1:
				# Пробивная пуля летит дальше цели — через толпу за ней, но не сквозь скалу
				to = _clip(to, to + (to - from).normalized() * 6.0)
			horde.kill_line(from, to, 0.6, _pierce, "gatling")
			_shots += 1
			if _ignite and _shots % 8 == 0:
				_burn_ground(_aim, 1.0)
			_show_tracer(from, to)
			_flash.visible = true
			_flash.rotation.z = randf() * TAU
			_flash_time = 0.04
		"freeze":
			# Ледяное облако у цели: все вокруг идут медленнее, слабых — в осколки
			var radius := FREEZE_RADIUS * _radius_mult
			var slow := FREEZE_SLOW * (0.6 if Mastery.flag(kind, "deep") else 1.0) * pow(0.85, Upgrades.level("freeze_power"))
			horde.chill(_aim, radius, slow, FREEZE_TIME + 0.6 * Upgrades.level("freeze_time"))
			var kills := FREEZE_KILLS + int(Mastery.add(kind, "kills"))
			horde.kill_area(_aim, radius * 0.6, kills, "freeze", 2 if Mastery.flag(kind, "shatter") else 1)
			_shots += 1
		"flame":
			# Огонь по месту: всех вокруг цели, и раз в несколько тиков земля загорается
			horde.kill_area(_aim, FLAME_RADIUS * _radius_mult, FLAME_KILLS, "flame")
			_shots += 1
			if _shots % maxi(FLAME_PATCH_EVERY - Upgrades.level("flame_burn"), 2) == 0:
				_burn_ground(_aim, 0.6)
		"mortar":
			# Мина летит навесом туда, где цель будет к прилёту
			var from := _muzzle.global_position
			var to: Vector3 = _aim + horde.velocity_of(_target) * MORTAR_FLIGHT
			if not _map:
				_map = get_tree().get_first_node_in_group("map")
			if _map:
				to.y = _map.height(Vector2(to.x, to.z))
			var dist := from.distance_to(to)
			var v: Vector3 = horde.velocity_of(_target)
			var flow := v.normalized() if v.length() > 0.2 else Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
			_shoot(_mortar_shell(), from, to, dist / MORTAR_FLIGHT, 4.0 + dist * 0.35, _mortar_hit.bind(flow), true)
			_shots += 1
			_recoil = MORTAR_RECOIL
			_flash.visible = true
			_flash.scale = Vector3.ONE * 1.4
			_flash_time = 0.12
			_audio.pitch_scale = randf_range(0.56, 0.68)
			_audio.play()


## Ядро мортиры упало: взрыв по толпе (пробивает доспехи, как все взрывы) и два малых заряда
## вдоль потока врагов flow (единичный вектор по земле).
func _mortar_hit(at: Vector3, flow: Vector3) -> void:
	if not is_inside_tree():
		return
	var boom := ExplosionScript.new()
	boom.horde = horde
	boom.radius = MORTAR_RADIUS * _radius_mult
	boom.max_kills = int(round(MORTAR_KILLS * _kill_mult))
	boom.source = "mortar"
	boom.ignite = _ignite
	boom.shake = 0.35
	boom.position = at
	get_tree().current_scene.add_child(boom)
	# Ядро раскалывается: два малых заряда вдоль потока — по цепочке врагов в канале
	for side in [-1.0, 1.0]:
		var p: Vector3 = at + flow * MORTAR_SPLIT * side
		if _map:
			p.y = _map.height(Vector2(p.x, p.z))
		var small := ExplosionScript.new()
		small.horde = horde
		small.radius = MORTAR_SPLIT_RADIUS * _radius_mult
		small.max_kills = int(round(MORTAR_SPLIT_KILLS * _kill_mult))
		small.source = "mortar"
		small.silent = true
		small.shake = 0.0
		small.position = p
		get_tree().current_scene.add_child(small)


## Мортира: труба после выстрела отскакивает назад и возвращается; вспышка у жерла гаснет.
func _update_mortar(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 0.5)
	_gun.position = _gun_rest + _gun.basis.z * _recoil
	_flash_time -= delta
	if _flash_time <= 0.0:
		_flash.visible = false
	else:
		_flash.scale = Vector3.ONE * (0.6 + _flash_time * 8.0)


## Ядро: чёрный гранёный шар (за ним тянется дымный след — turret_projectile.gd). Одно на все.
static func _mortar_shell() -> Mesh:
	if _shell_mesh:
		return _shell_mesh
	var mesh := SphereMesh.new()
	mesh.radius = 0.26
	mesh.height = 0.52
	mesh.radial_segments = 8
	mesh.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.11)
	m.roughness = 0.5
	mesh.material = m
	_shell_mesh = mesh
	return mesh


## Вспышка выстрела у жерла мортиры: оранжевый шар, гаснет за десятую долю секунды.
func _build_mortar_effects() -> void:
	_gun_rest = _gun.position
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	sphere.radial_segments = 8
	sphere.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.3)
	sphere.material = m
	_flash = MeshInstance3D.new()
	_flash.mesh = sphere
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash)


## Лазер: заряд, пока есть цель; луч от излучателя к цели (горит, пока заряжен и навёлся),
## искры и красный свет на конце, гудение.
func _update_laser(on: bool, aimed: bool, delta: float) -> void:
	_spin = move_toward(_spin, 1.0 if on else 0.0, delta / (SPIN_UP * TURN_SPEED / _turn if on else 0.6))
	var firing := on and aimed and _spin >= 1.0
	_beam.visible = firing
	_spark.emitting = firing
	_beam_light.visible = firing
	if firing:
		var from := _muzzle.global_position
		var dir := _body - from
		var t := Time.get_ticks_msec() / 1000.0
		var w := 1.0 + 0.18 * sin(t * 47.0) + 0.1 * sin(t * 31.0)
		_beam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).scaled_local(Vector3(w, w, dir.length())),
			from + dir / 2.0)
		_spark.global_position = _body
		_beam_light.global_position = _body + Vector3(0, 0.4, 0)
		if not _audio.playing:
			_audio.play()
	elif _audio.playing:
		_audio.stop()


func _build_laser_effects() -> void:
	# Луч: светлая сердцевина и красное свечение вокруг (два цилиндра вдоль оси Z узла)
	_beam = Node3D.new()
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)
	for layer in [[0.07, Color(1.0, 0.9, 0.82)], [0.24, Color(1.0, 0.12, 0.06, 0.5)]]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = layer[0]
		cyl.bottom_radius = layer[0]
		cyl.height = 1.0
		cyl.radial_segments = 8
		cyl.rings = 1
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = layer[1]
		cyl.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.rotation.x = PI / 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.add_child(mi)
	# Искры там, где луч упирается в цель
	_spark = FxBudget.cosmetic(GPUParticles3D.new())
	_spark.top_level = true
	_spark.emitting = false
	_spark.amount = 40
	_spark.lifetime = 0.35
	_spark.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -9.0, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.92, 0.8, 1.0))
	grad.set_color(1, Color(1.0, 0.15, 0.05, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	_spark.process_material = pm
	var dot := BoxMesh.new()
	dot.size = Vector3(0.06, 0.06, 0.06)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = dm
	_spark.draw_pass_1 = dot
	add_child(_spark)
	_beam_light = OmniLight3D.new()
	_beam_light.top_level = true
	_beam_light.light_color = Color(1.0, 0.25, 0.15)
	_beam_light.light_energy = 3.0
	_beam_light.omni_range = 5.0
	_beam_light.visible = false
	add_child(_beam_light)


## Поджечь землю в точке at (зажигательная лента, масляный котёл).
func _burn_ground(at: Vector3, size: float) -> void:
	var patch := FirePatch.new()
	patch.horde = horde
	patch.source = kind
	patch.scale_size = size
	patch.position = at
	get_tree().current_scene.add_child(patch)


## Пулемёт: стволы раскручиваются, пока есть цель, и замедляются без неё; звук очереди,
## гильзы и вспышка — только пока стреляет.
func _update_gatling(on: bool, aimed: bool, delta: float) -> void:
	_spin = move_toward(_spin, 1.0 if on else 0.0, delta / (SPIN_UP * TURN_SPEED / _turn if on else 1.2))
	_barrels.rotation.z += SPIN_SPEED * _spin * delta
	var firing := on and aimed and _spin >= 1.0
	_casings.emitting = firing
	if firing and not _audio.playing:
		_audio.play()
	elif not firing and _audio.playing:
		_audio.stop()
	_flash_time -= delta
	if _flash_time <= 0.0:
		_flash.visible = false
	for i in _tracers.size():
		_tracer_life[i] -= delta
		_tracers[i].visible = _tracer_life[i] > 0.0


func _show_tracer(from: Vector3, to: Vector3) -> void:
	var i := _next_tracer
	_next_tracer = (_next_tracer + 1) % _tracers.size()
	var basis := Basis.looking_at(to - from, Vector3.UP).scaled_local(Vector3(1, 1, from.distance_to(to)))
	_tracers[i].global_transform = Transform3D(basis, (from + to) / 2.0)
	_tracer_life[i] = TRACER_LIFE
	_tracers[i].visible = true


func _build_gatling_effects() -> void:
	# Трассеры — тонкие светящиеся бруски в мировых координатах
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.09, 0.09, 1.0)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.85, 0.4)
	tracer_mesh.material = tm
	for i in 6:
		var t := MeshInstance3D.new()
		t.mesh = tracer_mesh
		t.top_level = true
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)
		_tracers.append(t)
		_tracer_life.append(0.0)
	# Вспышка у дула: звезда из лучей и конус вперёд
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := TAU * k / 6.0
		var tip := Vector3(cos(a), sin(a), 0.0) * (0.35 if k % 2 == 0 else 0.2)
		var side := Vector3(cos(a + PI / 2), sin(a + PI / 2), 0.0) * 0.06
		st.set_color(Color(1.0, 0.95, 0.6))
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1.0, 0.45, 0.05, 0.3))
		st.add_vertex(tip + side)
		st.add_vertex(tip - side)
		st.set_color(Color(1.0, 0.95, 0.6))
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1.0, 0.4, 0.05, 0.2))
		st.add_vertex(Vector3(cos(a) * 0.12, sin(a) * 0.12, -0.6))
		st.add_vertex(Vector3(cos(a + TAU / 6) * 0.12, sin(a + TAU / 6) * 0.12, -0.6))
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash = MeshInstance3D.new()
	_flash.mesh = st.commit()
	_flash.material_override = fm
	_flash.visible = false
	_flash.scale = Vector3.ONE * 1.8
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash)
	# Гильзы: латунные цилиндрики летят вправо-вверх от короба и падают
	_casings = FxBudget.cosmetic(GPUParticles3D.new())
	_casings.amount = 24
	_casings.lifetime = 0.8
	_casings.emitting = false
	_casings.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0.8, 0.2)
	pm.spread = 18.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	_casings.process_material = pm
	var casing := CylinderMesh.new()
	casing.top_radius = 0.025
	casing.bottom_radius = 0.025
	casing.height = 0.09
	casing.radial_segments = 6
	casing.material = _flat(Color(0.85, 0.65, 0.25))
	_casings.draw_pass_1 = casing
	_casings.position = Vector3(0.3, 0.05, 0.0)
	_casings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gun.add_child(_casings)


func _shoot(mesh: Mesh, from: Vector3, to: Vector3, speed: float, arc: float, on_arrive: Callable, smoke := false) -> void:
	var p := ProjectileScript.new()
	p.smoke = smoke
	p.from = from
	p.to = to
	p.speed = speed
	p.arc = arc
	p.mesh = mesh
	p.on_arrive = on_arrive
	get_tree().current_scene.add_child(p)


func _update_flame(on: bool) -> void:
	if on != _flame.emitting:
		_flame.emitting = on
		if on:
			_audio.play()
		else:
			_audio.stop()
	if on:
		var from := _muzzle.global_position
		_flame.global_position = from
		if from.distance_to(_aim) > 0.3:
			_flame.look_at(_aim + Vector3(0, 0.3, 0), Vector3.UP)
		var pm: ParticleProcessMaterial = _flame.process_material
		var speed := from.distance_to(_aim) / 0.45
		pm.initial_velocity_min = speed * 0.9
		pm.initial_velocity_max = speed * 1.05


## Струя: огонь (frost = false) или ледяная — бело-голубой пар.
func _flame_emitter(frost := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = FxBudget.amount(90)
	p.lifetime = 0.45
	p.emitting = false
	p.local_coords = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 6.0
	pm.gravity = Vector3(0, 2.0, 0)
	var curve := Curve.new()
	curve.max_value = 8.0
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(1.0, 4.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	if frost:
		grad.colors = PackedColorArray([Color(0.95, 1.0, 1.0, 0.95), Color(0.65, 0.88, 1.0, 0.85),
			Color(0.5, 0.75, 1.0, 0.55), Color(0.85, 0.95, 1.0, 0.0)])
	else:
		grad.colors = PackedColorArray([Color(1.0, 0.72, 0.22, 1.0), Color(1.0, 0.42, 0.06, 0.95),
			Color(0.85, 0.18, 0.03, 0.7), Color(0.3, 0.08, 0.03, 0.0)])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m
