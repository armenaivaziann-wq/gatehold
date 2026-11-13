extends "res://weapons/weapon.gd"
## Гравипушка от первого лица (дочерний узел камеры).
## ЛКМ — выстрел зарядом-сингулярностью: он летит в точку под прицелом и раскрывается
## чёрной дырой (black_hole.gd), которая затягивает врагов в радиусе и забирает их.
## Зарядов CHARGES (с мастерством больше); пустые восстанавливаются сами по одному за RECHARGE
## секунд, в начале
## волны — все. В излучателе, пока есть заряд, крутится маленькая фиолетовая воронка.
## Модель — по листу пользователя (gravigun_model.gd); хват как у электропушки, ствол смотрит в
## прицел. Покупается за трофеи на вкладке «Оружие» (upgrades.gd: WEAPONS).

const GravigunModel := preload("res://weapons/gravigun_model.gd")
const FIRE_SOUND := preload("res://audio/sounds/gravigun_fire.wav")
const BlackHoleScript := preload("res://effects/black_hole.gd")
const SwirlShader := preload("res://effects/shaders/black_hole_swirl.gdshader")
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")

# Положение в кадре (оси камеры): справа внизу, излучатель смотрит к прицелу
const REST_POS := Vector3(0.2, -0.27, -0.52)
const REST_ROT := Vector3(0.1, 0.22, -0.05)
const VIEW_SCALE := 0.5
const RIGHT_HAND := GravigunModel.RIGHT_HAND
const LEFT_HAND := GravigunModel.LEFT_HAND

const CHARGES := 2
const RECHARGE := 12.0         # с на один заряд
const FIRE_DELAY := 0.9        # с между выстрелами
const MARKER_DISTANCE := 110.0

## С мастерством (mastery.gd) и «Оружейником»: заряды, восстановление, радиус и сила дыры;
## «Близнецы» — две дыры за выстрел.
var max_charges: int
var recharge: float
var radius: float
var twins: bool
## Ветка гравипушки: дольше живёт дыра, «Сверхновая» — золотой взрыв при коллапсе.
var life_bonus := 0.0
var nova := false
var _glow_mat: StandardMaterial3D
var _base_glow := Color.WHITE
const TWINS_GLOW := Color(0.3, 0.9, 1.0)
const NOVA_GLOW := Color(1.0, 0.75, 0.2)
## Сколько зарядов готово.
var charges: int
var _recharge := 0.0
var _delay := 0.0
var _kick := 0.0
var _muzzle: Node3D
## Стрелять без мыши (для автоматических снимков и проверок).
var force_fire := false
var _swirl: MeshInstance3D
var _light: OmniLight3D
var _audio: AudioStreamPlayer


## Параметры из мастерства и общего древа; заново — если прокачку докупили посреди боя (main.gd).
func refresh_stats() -> void:
	max_charges = CHARGES + int(Mastery.add("gravigun", "charges"))
	recharge = RECHARGE * Mastery.mult("gravigun", "recharge")
	radius = BlackHoleScript.RADIUS * Mastery.mult("gravigun", "radius") * Upgrades.weapon_radius()
	twins = Mastery.flag("gravigun", "twin")
	radius *= 1.0 + 0.2 * Upgrades.w("gv_radius")
	max_charges += Upgrades.w("gv_charges")
	life_bonus = 1.5 * Upgrades.w("gv_life")
	recharge *= pow(0.8, Upgrades.w("gv_recharge"))
	if Upgrades.w("gv_twins") > 0:
		twins = true
	nova = Upgrades.w("gv_nova") > 0
	charges = mini(charges, max_charges)
	if _glow_mat:
		_glow_mat.emission = TWINS_GLOW if Upgrades.w("gv_twins") > 0 else (NOVA_GLOW if nova else _base_glow)


func _init() -> void:
	refresh_stats()
	charges = max_charges


func _ready() -> void:
	super()
	display_name = "Гравипушка"
	ammo_kind = "charge"
	_setup_model(GravigunModel.scene(), VIEW_SCALE, RIGHT_HAND, LEFT_HAND)
	_muzzle = _model.find_child("Muzzle")
	var glow: MeshInstance3D = _model.find_child("Glow")
	_glow_mat = glow.mesh.surface_get_material(0).duplicate()
	glow.material_override = _glow_mat
	_base_glow = _glow_mat.emission
	refresh_stats()
	_make_marker(radius)
	# Воронка в излучателе: те же спиральные полосы, только крошечные, ось — вдоль ствола
	_swirl = MeshInstance3D.new()
	_swirl.mesh = BlackHoleScript.swirl_mesh(28)
	var sm := ShaderMaterial.new()
	sm.shader = SwirlShader
	sm.set_shader_parameter("radius", 0.11)
	sm.set_shader_parameter("core", 0.02)
	sm.set_shader_parameter("height", 0.0)
	sm.set_shader_parameter("width", 0.003)
	sm.set_shader_parameter("length_scale", 0.12)
	sm.set_shader_parameter("rate", 1.6)
	sm.set_shader_parameter("energy", 3.0)
	_swirl.material_override = sm
	_swirl.rotation.x = PI / 2
	_swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_swirl)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.65, 0.35, 1.0)
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_muzzle.add_child(_light)
	_audio = AudioStreamPlayer.new()
	_audio.stream = FIRE_SOUND
	_audio.volume_db = -3.0
	add_child(_audio)
	_update_pose(0.0)


func _process(delta: float) -> void:
	var can_shoot := _can_shoot()
	_delay = maxf(_delay - delta, 0.0)
	if charges < max_charges:
		_recharge += delta
		if _recharge >= recharge:
			_recharge = 0.0
			charges += 1
	_kick = move_toward(_kick, 0.0, delta * 3.0)
	if _delay == 0.0 and charges > 0 and (force_fire or can_shoot and Input.is_action_just_pressed("fire")):
		fire()
	_light.light_energy = move_toward(_light.light_energy, 0.4 if charges > 0 else 0.0, delta * 20.0)
	(_swirl.material_override as ShaderMaterial).set_shader_parameter("energy", 3.0 if charges > 0 else 0.4)
	_update_pose(delta)
	_update_marker(radius, MARKER_DISTANCE, charges == 0 or _delay > 0.0)


## Выстрел: заряд из излучателя в точку под прицелом.
func fire() -> void:
	charges -= 1
	_delay = FIRE_DELAY
	_kick = 1.0
	_audio.pitch_scale = randf_range(0.95, 1.05)
	_audio.play()
	_light.light_energy = 8.0
	var aim := _aim()
	var target: Vector3 = aim["point"]
	var from := _muzzle.global_position
	var targets := [target]
	if twins:
		targets.append(target + (target - from).cross(Vector3.UP).normalized() * radius * 0.9)
	for to: Vector3 in targets:
		var hole := BlackHoleScript.new()
		hole.horde = horde
		hole.radius = radius
		hole.core = BlackHoleScript.CORE * Mastery.mult("gravigun", "core")
		hole.pull_speed = BlackHoleScript.PULL_SPEED * Mastery.mult("gravigun", "pull")
		hole.life = BlackHoleScript.LIFE + Mastery.add("gravigun", "life") + life_bonus
		hole.collapse_blast = Mastery.flag("gravigun", "collapse") or nova
		if nova:
			hole.blast_scale = 1.1
			hole.blast_kills = 320
			hole.blast_tint = Color(1.0, 0.75, 0.2)
		if _player():
			hole.exclude = [_player().get_rid()]
		hole.velocity = (to - from).normalized() * BlackHoleScript.FLIGHT_SPEED
		hole.target = to
		hole.has_target = aim["hit"]
		get_tree().current_scene.add_child(hole)
		hole.global_position = from


## В начале волны — все заряды.
func restock() -> void:
	charges = max_charges
	_recharge = 0.0


## Готовность: пока заряды есть — пауза между выстрелами, нет — восстановление заряда.
func reload_progress() -> float:
	if charges == 0:
		return _recharge / recharge
	return 1.0 - _delay / FIRE_DELAY


func ammo_text() -> String:
	return "%d / %d" % [charges, max_charges]


func ammo_note() -> String:
	if charges < max_charges:
		return "заряд через %d с" % ceili(recharge - _recharge)
	return ""


func ammo_empty() -> bool:
	return charges == 0


func _update_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var k := ease(_kick, 0.4)
	var breath := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.002, 0.0)
	position = REST_POS + breath + Vector3(0.0, -0.4 * lower, 0.09 * k)
	rotation = REST_ROT + Vector3(0.2 * k - 0.6 * lower, 0.0, 0.0)
	_point_at_crosshair(REST_POS, REST_ROT, delta)
