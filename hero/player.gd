extends CharacterBody3D
## Герой от первого лица с реактивным ранцем. На земле или на стене — ходит (WASD, Shift — бег).
## Пробел — взлёт: в воздухе ранец держит высоту сам, WASD — лететь куда смотришь, Пробел —
## выше, Shift — ниже; опустился на землю или стену — снова пешком. Выше CEILING над землёй не
## поднимается, за край карты не вылетает. H — сразу обратно на стену.
## Здоровье: копья орков (spears.gd) ранят, если летать низко над толпой; само восстанавливается,
## если пару секунд не задевали. Сбили — через DOWN_TIME снова на стене с полным здоровьем.
## Уровень в бою: опыт за каждого убитого врага (кем угодно), с уровнем — больше здоровья.
## ЛКМ захватывает мышь (Esc — пауза, её ведёт main.gd).

signal leveled_up(level: int)
signal downed
signal hit_taken
## Пикирование с молотом закончилось ударом о землю: height — с какой высоты падал.
signal dive_landed(height: float)

const MapBuilder := preload("res://locations/map_builder.gd")
const Upgrades := preload("res://core/upgrades.gd")
const JET_SOUND := preload("res://audio/sounds/flame_loop.wav")

const WALK_SPEED := 5.5
const SPRINT_SPEED := 9.0
const FLY_SPEED := 15.0
const CLIMB := 9.0
const ACCEL := 12.0
const FLY_ACCEL := 3.0           # в воздухе разгон и торможение мягче — чувствуется инерция
const TAKEOFF := 6.0
const GRAVITY := 15.0
const CEILING := 40.0            # м над землёй
const BOUNDS := MapBuilder.HALF - 6.0
const MOUSE_SENS := 0.0025      # умножается на чувствительность из настроек
const Settings := preload("res://core/settings.gd")
const EYE_HEIGHT := 1.65
const FOV := 72.0
const FOV_FAST := 82.0
const HP_BASE := 100.0
const HP_PER_LEVEL := 10.0
const REGEN := 6.0               # здоровья в секунду
const REGEN_DELAY := 2.5         # с без попаданий — потом восстанавливается
const DOWN_TIME := 3.0
const MAX_LEVEL := 20
## Ранец: сколько секунд полёта на полном баке без прокачки («Время полёта» добавляет), за сколько
## бак наполняется, пока герой стоит на вышке или на земле, и как медленно он опускается, когда
## топливо кончилось (набрать высоту уже нельзя — пора садиться).
const FLIGHT_BASE := 6.0
const FUEL_REFILL := 3.0
const FALL_GLIDE := 5.0
const TAKEOFF_FUEL := 0.1         # меньше — ранец не заводится, просто прыжок
# Клавиши (по физическому положению — работают при любой раскладке)
const KEYS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"jump": KEY_SPACE, "sprint": KEY_SHIFT, "respawn": KEY_H,
}

var spawn_point := Vector3.ZERO
var spawn_yaw := 0.0
var active := true
var head: Node3D
var camera: Camera3D
## В воздухе на ранце.
var flying := false
var hp := HP_BASE
var hp_max := HP_BASE
var down_left := 0.0
var level := 1
var xp := 0
var _shake := 0.0
var _since_hit := 99.0
var _roll := 0.0
var _jets: Array[GPUParticles3D] = []
var _jet_audio: AudioStreamPlayer
var _thrust := 0.0
## Топливо ранца (0..1) и сколько секунд полёта даёт полный бак.
var fuel := 1.0
var flight_time := FLIGHT_BASE
## Скорость полёта (с «Скоростью полёта» из древа).
var fly_speed := FLY_SPEED
var _xp_frac := 0.0
## Пикирует вниз с молотом (hammer.gd: зажать удар в воздухе).
var diving := false
var _dive_from := 0.0
const DIVE_SPEED := 40.0
const DIVE_FORWARD := 7.0


## Начать пикирование: ранец гаснет, герой камнем летит вниз и чуть вперёд, куда смотрит.
func start_dive() -> void:
	diving = true
	flying = false
	_dive_from = global_position.y
	velocity = Vector3(velocity.x * 0.3, -12.0, velocity.z * 0.3)


## Высота ног над землёй под героем (на вышке — над землёй под ней).
func height_above_ground() -> float:
	return global_position.y - _ground_height()


func _ready() -> void:
	add_to_group("player")
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, ev)
	# Игрок упирается и в мир, и в ограждения стены (слой 2)
	collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 3000.0
	head.add_child(camera)
	floor_snap_length = 0.4
	_build_jets()
	respawn()


## Поставить героя на стену и развернуть по направлению.
func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	diving = false
	rotation.y = spawn_yaw
	head.rotation.x = -0.12
	flying = false


## Новый бой: полное здоровье, первый уровень.
func reset_hero() -> void:
	level = 1
	xp = 0
	hp_max = HP_BASE + Upgrades.hero_hp_bonus()
	hp = hp_max
	flight_time = FLIGHT_BASE + Upgrades.flight_bonus()
	fly_speed = FLY_SPEED * Upgrades.fly_speed_mult()
	fuel = 1.0
	down_left = 0.0
	visible = true
	respawn()


## Тряхнуть камеру (взрыв рядом): amount от 0 до 1, гаснет за полсекунды.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Попадание (копьё): урон, тряска; здоровье кончилось — сбит.
func take_hit(damage: float) -> void:
	if down_left > 0.0:
		return
	hp = maxf(hp - damage * Upgrades.spear_mult(), 0.0)
	_since_hit = 0.0
	shake(0.35)
	hit_taken.emit()
	if hp <= 0.0:
		down_left = DOWN_TIME
		downed.emit()


## Опыт за убитых: сколько нужно до следующего уровня — растёт с уровнем.
func add_xp(amount: int) -> void:
	if level >= MAX_LEVEL:
		return
	# «Боевой опыт» — дробные остатки копятся, чтобы не терялись на одиночных убийствах
	_xp_frac += amount * Upgrades.hero_xp_mult()
	xp += int(_xp_frac)
	_xp_frac -= int(_xp_frac)
	while level < MAX_LEVEL and xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		hp_max = HP_BASE + HP_PER_LEVEL * (level - 1) + Upgrades.hero_hp_bonus()
		hp = hp_max
		leveled_up.emit(level)


func xp_needed() -> int:
	return 100 * level


func _process(delta: float) -> void:
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	var s := _shake * _shake * 0.06
	camera.position = Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
	# В полёте вбок — лёгкий крен, на скорости шире обзор
	var side := velocity.dot(global_basis.x) / fly_speed if flying else 0.0
	_roll = lerpf(_roll, -side * 0.06, minf(delta * 4.0, 1.0))
	camera.rotation.z = randf_range(-s, s) * 0.5 + _roll
	var speed := Vector2(velocity.x, velocity.z).length()
	var want_fov := lerpf(FOV, FOV_FAST, clampf(speed / fly_speed, 0.0, 1.0)) if flying else FOV
	camera.fov = lerpf(camera.fov, want_fov, minf(delta * 3.0, 1.0))
	# Здоровье само восстанавливается; сбитый — через DOWN_TIME снова на стене
	_since_hit += delta
	if down_left > 0.0:
		down_left -= delta
		if down_left <= 0.0:
			hp = hp_max
			respawn()
	elif _since_hit > REGEN_DELAY - Upgrades.regen_delay_cut():
		hp = minf(hp + REGEN * Upgrades.regen_mult() * delta, hp_max)
	# Пламя сопел и гул ранца — сильнее, когда набираем высоту или летим
	var want_thrust := 0.0
	if flying and fuel <= 0.0:
		# Бак пуст — ранец чихает
		want_thrust = 0.12 if fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25 else 0.04
	elif flying:
		want_thrust = 0.45 + 0.35 * clampf(speed / fly_speed, 0.0, 1.0) + (0.4 if velocity.y > 1.0 else 0.0)
	_thrust = lerpf(_thrust, want_thrust, minf(delta * 6.0, 1.0))
	for j in _jets:
		j.emitting = _thrust > 0.05
		j.amount_ratio = clampf(_thrust, 0.1, 1.0)
	_jet_audio.volume_db = linear_to_db(maxf(_thrust * 0.5, 0.0001))
	_jet_audio.pitch_scale = 0.55 + _thrust * 0.35


func set_active(on: bool) -> void:
	active = on
	if on:
		camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * Settings.sensitivity
		rotation.y -= event.relative.x * sens
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sens, -1.5, 1.5)


func _physics_process(delta: float) -> void:
	if not active or down_left > 0.0:
		return
	if Input.is_action_just_pressed("respawn") or global_position.y < -6.0:
		respawn()
		return
	if diving:
		_dive(delta)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if flying:
		_fly(input, delta)
	else:
		_walk(input, delta)
	move_and_slide()
	_keep_inside()
	# Опустились на землю или стену без тяги вверх (или без топлива) — снова пешком
	if flying and is_on_floor() and velocity.y <= 0.1 and (fuel <= 0.0 or not Input.is_action_pressed("jump")):
		flying = false
	# Топливо: в воздухе тратится, на ногах — наполняется
	if flying:
		fuel = maxf(fuel - delta / flight_time, 0.0)
	elif is_on_floor():
		fuel = minf(fuel + delta / (FUEL_REFILL * Upgrades.refuel_mult()), 1.0)


## Пикирование: разгон вниз до DIVE_SPEED, немного вперёд по взгляду; коснулся земли или
## настила — удар (dive_landed), дальше снова пешком.
func _dive(delta: float) -> void:
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() * DIVE_FORWARD
	velocity.x = move_toward(velocity.x, fwd.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, fwd.z, 30.0 * delta)
	velocity.y = move_toward(velocity.y, -DIVE_SPEED, 90.0 * delta)
	move_and_slide()
	_keep_inside()
	if is_on_floor() or height_above_ground() < 0.25:
		diving = false
		var fell := maxf(_dive_from - global_position.y, 0.0)
		velocity = Vector3.ZERO
		shake(clampf(0.4 + fell / 25.0, 0.4, 1.0))
		dive_landed.emit(fell)


func _walk(input: Vector2, delta: float) -> void:
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var accel := ACCEL if is_on_floor() else ACCEL * 0.3
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	if Input.is_action_just_pressed("jump") and (is_on_floor() or fuel >= TAKEOFF_FUEL):
		# Ранец: прыжок сразу переходит в полёт (если в баке есть топливо — иначе просто прыжок)
		velocity.y = TAKEOFF
		flying = fuel >= TAKEOFF_FUEL
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta


## Полёт: по горизонтали — куда смотрит камера (без наклона вверх-вниз), высота — Пробел и
## Shift; отпустил — зависает.
func _fly(input: Vector2, delta: float) -> void:
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var up := 0.0
	if Input.is_action_pressed("jump"):
		up += 1.0
	if Input.is_action_pressed("sprint"):
		up -= 1.0
	var want := Vector3(dir.x * fly_speed, up * CLIMB, dir.z * fly_speed)
	if fuel <= 0.0:
		# Без топлива — медленно планирует вниз, вверх уже никак
		want = Vector3(dir.x * fly_speed * 0.6, -FALL_GLIDE, dir.z * fly_speed * 0.6)
	velocity = velocity.lerp(want, minf(delta * FLY_ACCEL, 1.0))
	# Потолок — над землёй под героем
	var ground: float = _ground_height()
	if global_position.y > ground + CEILING + Upgrades.ceiling_bonus() and velocity.y > 0.0:
		velocity.y = 0.0


func _keep_inside() -> void:
	var p := global_position
	# В замкнутой долине — не дальше скал (map.bounds), иначе — края карты
	var map := get_tree().get_first_node_in_group("map")
	var b: Rect2 = map.bounds() if map else Rect2(-BOUNDS, -BOUNDS, BOUNDS * 2.0, BOUNDS * 2.0)
	p.x = clampf(p.x, b.position.x, b.end.x)
	p.z = clampf(p.z, b.position.y, b.end.y)
	if p != global_position:
		global_position = p


func _ground_height() -> float:
	var map := get_tree().get_first_node_in_group("map")
	if map:
		return map.height(Vector2(global_position.x, global_position.z))
	return 0.0


# --- ранец ------------------------------------------------------------------------------------

## Два сопла ранца за спиной: пламя бьёт вниз и назад — краем видно, если смотреть под ноги.
func _build_jets() -> void:
	for sx in [-0.22, 0.22]:
		var p := GPUParticles3D.new()
		p.amount = 40
		p.lifetime = 0.35
		p.local_coords = false
		p.position = Vector3(sx, 1.0, 0.35)
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, -1, 0.35)
		pm.spread = 8.0
		pm.initial_velocity_min = 7.0
		pm.initial_velocity_max = 10.0
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.5
		pm.scale_max = 1.0
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		grad.colors = PackedColorArray([Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.5, 0.1, 0.8), Color(0.4, 0.35, 0.3, 0.0)])
		var ramp := GradientTexture1D.new()
		ramp.gradient = grad
		pm.color_ramp = ramp
		var curve := CurveTexture.new()
		var c := Curve.new()
		c.add_point(Vector2(0, 0.4))
		c.add_point(Vector2(0.3, 1.0))
		c.add_point(Vector2(1, 1.6))
		curve.curve = c
		pm.scale_curve = curve
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		quad.material = mat
		p.draw_pass_1 = quad
		p.emitting = false
		add_child(p)
		_jets.append(p)
	var loop: AudioStreamWAV = JET_SOUND.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(JET_SOUND.get_length() * JET_SOUND.mix_rate)
	_jet_audio = AudioStreamPlayer.new()
	_jet_audio.stream = loop
	_jet_audio.volume_db = -60.0
	add_child(_jet_audio)
	_jet_audio.play()
