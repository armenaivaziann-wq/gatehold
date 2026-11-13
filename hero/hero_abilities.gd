extends Node3D
## Умения героя — клавиши Q, E, R и удары с неба Z, X, C, у каждого своя перезарядка. Бьют в
## точку под прицелом:
##   Q — ракетный залп: восемь малых ракет веером по самым густым местам толпы вокруг точки;
##   E — напалм: огненная дорожка вдоль взгляда, горит несколько секунд;
##   R — боевой дрон (drone.gd): летит к точке и дальше воюет сам, независимо от героя;
##   Z — авиаудар: штурмовик сбрасывает цепочку напалмовых бомб (air_strike.gd);
##   X — ракетный дождь с неба по кругу (air_strike.gd);
##   C — орбитальный лазер: столб света из космоса ведёт по земле и выжигает (orbital_laser.gd).
## Иконки умений — ui/icons (по листу пользователя).
## С уровнем героя (player.gd) перезарядка короче: cd_mult. Умения открываются в общем древе
## (строка «Герой», узел ABILITIES[i].id в upgrades.gd) — закрытое не срабатывает.

const ShellScript := preload("res://weapons/shell.gd")
const ExplosionScript := preload("res://effects/explosion.gd")
const FirePatch := preload("res://effects/fire_patch.gd")
const DroneScript := preload("res://hero/drone.gd")
const AirStrikeScript := preload("res://effects/air_strike.gd")
const OrbitalScript := preload("res://effects/orbital_laser.gd")
const FxBudget := preload("res://core/fx_budget.gd")
const WHOOSH := preload("res://audio/sounds/gravigun_fire.wav")
const Upgrades := preload("res://core/upgrades.gd")

## id — узел древа (upgrades.gd), который открывает умение.
## id — узел древа (upgrades.gd), который открывает умение; tex — иконка.
const ABILITIES := [
	{"key": KEY_Q, "letter": "Q", "name": "Ракетный залп", "icon": "salvo", "id": "ab_salvo", "cd": 13.0,
		"tex": "res://ui/icons/ability_rockets.png"},
	{"key": KEY_E, "letter": "E", "name": "Напалм", "icon": "napalm", "id": "ab_napalm", "cd": 16.0,
		"tex": "res://ui/icons/ability_napalm.png"},
	{"key": KEY_R, "letter": "R", "name": "Боевой дрон", "icon": "drone", "id": "ab_drone", "cd": 30.0,
		"tex": "res://ui/icons/ability_drone.png"},
	# Удары с неба — в точку под прицелом; открываются в древе, строка «Удары с неба»
	{"key": KEY_Z, "letter": "Z", "name": "Авиаудар: напалм", "icon": "airstrike", "id": "strike_napalm", "cd": 45.0,
		"tex": ""},
	{"key": KEY_X, "letter": "X", "name": "Ракетный дождь", "icon": "rocketrain", "id": "strike_rockets", "cd": 55.0,
		"tex": ""},
	{"key": KEY_C, "letter": "C", "name": "Орбитальный лазер", "icon": "orbital", "id": "strike_laser", "cd": 80.0,
		"tex": ""},
]
const AIM_DISTANCE := 170.0
const SALVO := 8
const SALVO_RADIUS := 13.0
const NAPALM_PATCHES := 8
const NAPALM_STEP := 2.6

var horde: Node3D
var player: CharacterBody3D
## С уровнем героя перезарядка короче.
var cd_mult := 1.0

var _left: Array[float] = []
var _queue: Array = []           # [через сколько с, Callable]
var _whoosh: AudioStreamPlayer


func _ready() -> void:
	_left.resize(ABILITIES.size())
	_left.fill(0.0)
	_whoosh = AudioStreamPlayer.new()
	_whoosh.stream = WHOOSH
	_whoosh.volume_db = -8.0
	add_child(_whoosh)


## Готовность умения i: 0 — только что применено, 1 — готово.
func progress(i: int) -> float:
	var cd: float = ABILITIES[i]["cd"] * cd_mult
	return 1.0 - clampf(_left[i] / cd, 0.0, 1.0)


func is_open(i: int) -> bool:
	return Upgrades.level(ABILITIES[i]["id"]) > 0


func seconds_left(i: int) -> float:
	return _left[i]


func reset() -> void:
	for i in _left.size():
		_left[i] = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not player or not player.active or player.down_left > 0.0:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		for i in ABILITIES.size():
			if event.physical_keycode == ABILITIES[i]["key"]:
				use(i)
				get_viewport().set_input_as_handled()
				return


## Применить умение i, если готово и прицел смотрит на землю. Возвращает успех.
func use(i: int) -> bool:
	if _left[i] > 0.0 or not is_open(i):
		return false
	var aim: Variant = _aim()
	if aim == null:
		return false
	var at: Vector3 = aim
	match ABILITIES[i]["icon"]:
		"salvo":
			_salvo(at)
		"napalm":
			_napalm(at)
		"drone":
			_drone(at)
		"airstrike", "rocketrain":
			_strike(ABILITIES[i]["icon"], at)
		"orbital":
			_orbital(at)
	_left[i] = ABILITIES[i]["cd"] * cd_mult
	return true


func _process(delta: float) -> void:
	for i in _left.size():
		_left[i] = maxf(_left[i] - delta, 0.0)
	var k := 0
	while k < _queue.size():
		_queue[k][0] -= delta
		if _queue[k][0] <= 0.0:
			var job: Callable = _queue[k][1]
			_queue.remove_at(k)
			job.call()
			continue
		k += 1


# --- прицел -----------------------------------------------------------------------------------

func _aim() -> Variant:
	var cam: Camera3D = player.camera
	var dir := -cam.global_basis.z
	var from := cam.global_position + dir * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, cam.global_position + dir * AIM_DISTANCE, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.position


## Откуда летят ракеты и молния: из ствола ракетницы, если она в руках, иначе чуть правее и
## ниже глаз.
func _launch_point() -> Vector3:
	var gun: Node3D = get_tree().current_scene.get("gun")
	if gun and gun.visible and "_muzzle" in gun and gun._muzzle:
		return gun._muzzle.global_position
	var cam: Camera3D = player.camera
	return cam.global_position + cam.global_basis * Vector3(0.3, -0.25, -1.2)


# --- Q: ракетный залп -------------------------------------------------------------------------

func _salvo(at: Vector3) -> void:
	# «Залп: больше ракет» и «Залп: шире» из древа
	var count := SALVO + 2 * Upgrades.level("salvo_more")
	var radius := SALVO_RADIUS * (1.0 + 0.15 * Upgrades.level("salvo_wide"))
	var targets: Array[Vector3] = []
	var picks: PackedInt32Array = horde.pick_targets(at, radius, 0.0, 80)
	if picks.size() >= count:
		var step := picks.size() / count
		for k in count:
			targets.append(horde.position_of(picks[k * step]))
	else:
		for k in count:
			var r := Vector2.from_angle(TAU * k / count) * radius * randf_range(0.3, 0.8)
			targets.append(at + Vector3(r.x, 0.0, r.y))
	for k in count:
		var to: Vector3 = targets[k]
		_queue.append([k * 0.07, func() -> void: _rocket(to, 3.0, 25, "salvo")])
	_whoosh.pitch_scale = 1.4
	_whoosh.play()


func _rocket(to: Vector3, radius: float, kills: int, source: String) -> void:
	var shell := ShellScript.new()
	shell.horde = horde
	shell.rocket = true
	shell.source = source
	shell.blast_radius = radius
	shell.max_kills = kills
	shell.exclude = [player.get_rid()]
	var from := _launch_point() + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.2), 0.0)
	shell.velocity = (to - from).normalized() * 58.0
	shell.target = to
	shell.has_target = true
	get_tree().current_scene.add_child(shell)
	shell.global_position = from


# --- E: напалм --------------------------------------------------------------------------------

func _napalm(at: Vector3) -> void:
	var fwd: Vector3 = -player.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var start := at - fwd * NAPALM_STEP * 2.0
	var map := get_tree().get_first_node_in_group("map")
	# «Напалм: длиннее» — на треть больше луж за уровень
	var patches := int(NAPALM_PATCHES * (1.0 + Upgrades.level("napalm_long") / 3.0))
	var burn := 5.0 + 1.5 * Upgrades.level("napalm_time")
	for k in patches:
		var p := start + fwd * NAPALM_STEP * k
		if map:
			p.y = map.height(Vector2(p.x, p.z))
		var delay := k * 0.06
		_queue.append([delay, func() -> void:
			var fire := FirePatch.new()
			fire.horde = horde
			fire.source = "napalm"
			fire.scale_size = 1.5
			fire.burn_time = burn
			fire.position = p
			get_tree().current_scene.add_child(fire)])
	var boom := ExplosionScript.new()
	boom.horde = horde
	boom.radius = 4.0
	boom.max_kills = 40
	boom.source = "napalm"
	boom.position = at
	get_tree().current_scene.add_child(boom)


# --- Z, X, C: удары с неба ------------------------------------------------------------------------

## Направление удара — куда смотрит герой (по земле).
func _strike_dir() -> Vector3:
	var fwd: Vector3 = -player.camera.global_basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func _strike(kind: String, at: Vector3) -> void:
	var s := AirStrikeScript.new()
	s.kind = "napalm" if kind == "airstrike" else "rockets"
	s.horde = horde
	s.dir = _strike_dir()
	s.power = 1.0 + 0.25 * Upgrades.level("strike_power")
	s.position = at
	get_tree().current_scene.add_child(s)


func _orbital(at: Vector3) -> void:
	var l := OrbitalScript.new()
	l.horde = horde
	l.dir = _strike_dir()
	l.position = at
	get_tree().current_scene.add_child(l)


# --- R: боевой дрон ---------------------------------------------------------------------------

## Дрон вылетает от героя и сам идёт к точке прицела; дальше — сам по себе (drone.gd).
func _drone(at: Vector3) -> void:
	var drone := DroneScript.new()
	drone.horde = horde
	drone.start_goal = at
	# «Дрон: дольше» и «Дрон: темп» из древа
	drone.life_time = DroneScript.TIME + 5.0 * Upgrades.level("drone_time")
	drone.rate = DroneScript.RATE / (1.0 + 0.2 * Upgrades.level("drone_guns"))
	get_tree().current_scene.add_child(drone)
	drone.global_position = _launch_point() + Vector3(0, 1.0, 0)
	_whoosh.pitch_scale = 1.4
	_whoosh.play()
