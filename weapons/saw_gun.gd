extends "res://weapons/weapon.gd"
## Дискомёт от первого лица (дочерний узел камеры). ЛКМ — запускает вращающийся энергодиск:
## он летит по прямой в прицел и прорезает толпу насквозь (до PIERCE врагов), пока не упрётся в
## землю или скалу или не улетит на RANGE. Пока заряжен — диск на стволе крутится и светится.
## Дисков в обойме CLIP; кончились — перезарядка (сама или по T), запас пополняется сам.
## Модель — saw_model.gd (по листу пользователя), хват как у электропушки. Покупается за трофеи
## на вкладке «Оружие» (upgrades.gd: WEAPONS).

const SawModel := preload("res://weapons/saw_model.gd")
const SHOT_SOUND := preload("res://audio/sounds/saw_throw.wav")
const WHIRR_SOUND := preload("res://audio/sounds/saw_whirr.wav")
const Upgrades := preload("res://core/upgrades.gd")

const REST_POS := Vector3(0.2, -0.27, -0.52)
const REST_ROT := Vector3(0.1, 0.22, -0.05)
const VIEW_SCALE := 0.5
const CLIP := 8
const RESERVE := 30
const FIRE_DELAY := 0.28
const RELOAD := 1.6
const RESUPPLY := 1.2           # с на один диск в запас
const SPEED := 48.0
const RANGE := 75.0
const PIERCE := 14
const WIDTH := 1.1               # полуширина реза, м
const MARKER_DISTANCE := 75.0

var clip := CLIP
var reserve := RESERVE
## Ветка дискомёта («Улучшения оружия»): прорез, обойма, рикошет, разгон, «Рой», «Бумеранг».
var pierce := PIERCE
var clip_size := CLIP
var speed := SPEED
var fire_delay := FIRE_DELAY
var bounce := false
var swarm := false
var boomerang := false
var disc_color := SawModel.BLUE
const SWARM_COLOR := Color(1.0, 0.45, 0.08)
const BOOMERANG_COLOR := Color(0.25, 1.0, 0.35)
## Стрелять без мыши (для автоматических снимков и проверок).
var force_fire := false

var _delay := 0.0
var _reload := 0.0
var _supply := 0.0
var _kick := 0.0
var _muzzle: Node3D
var _disc: Node3D
var _audio: AudioStreamPlayer


func refresh_stats() -> void:
	pierce = PIERCE + 6 * Upgrades.w("sd_pierce")
	clip_size = CLIP + 3 * Upgrades.w("sd_clip")
	speed = SPEED * (1.0 + 0.25 * Upgrades.w("sd_speed"))
	fire_delay = FIRE_DELAY / (1.0 + 0.15 * Upgrades.w("sd_speed"))
	bounce = Upgrades.w("sd_bounce") > 0
	swarm = Upgrades.w("sd_swarm") > 0
	boomerang = Upgrades.w("sd_boomerang") > 0
	disc_color = SWARM_COLOR if swarm else (BOOMERANG_COLOR if boomerang else SawModel.BLUE)
	clip = mini(clip, clip_size)
	if _disc:
		(_disc as MeshInstance3D).mesh = SawModel.disc_mesh(0.24, 0.15, true, disc_color)


func _init() -> void:
	refresh_stats()
	clip = clip_size


func _ready() -> void:
	super()
	display_name = "Дискомёт"
	ammo_kind = "shells"
	_setup_model(SawModel.scene(), VIEW_SCALE, SawModel.RIGHT_HAND, SawModel.LEFT_HAND)
	_muzzle = _model.find_child("Muzzle")
	_disc = _model.find_child("Disc")
	refresh_stats()
	_make_marker(WIDTH * 2.0)
	_audio = AudioStreamPlayer.new()
	_audio.stream = SHOT_SOUND
	_audio.volume_db = -4.0
	add_child(_audio)
	_update_pose(0.0)


func _process(delta: float) -> void:
	var can_shoot := _can_shoot()
	_delay = maxf(_delay - delta, 0.0)
	_supply += delta
	if _supply >= RESUPPLY:
		_supply = 0.0
		reserve = mini(reserve + 1, RESERVE)
	if _reload > 0.0:
		_reload = maxf(_reload - delta, 0.0)
		if _reload == 0.0:
			var take := mini(clip_size - clip, reserve)
			clip += take
			reserve -= take
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("reload"):
		start_reload()
	var want := force_fire or can_shoot and Input.is_action_pressed("fire")
	if want and _delay == 0.0 and _reload == 0.0:
		if clip > 0:
			_fire()
		else:
			start_reload()
	# Диск в пасти крутится, пока заряжен; на перезарядке гаснет
	_disc.rotation.z += delta * (14.0 if clip > 0 and _reload == 0.0 else 2.0)
	_disc.visible = clip > 0 or _reload > 0.0
	_kick = move_toward(_kick, 0.0, delta * 5.0)
	_update_marker(WIDTH * 2.0, MARKER_DISTANCE, _reload > 0.0)
	_update_pose(delta)


func start_reload() -> void:
	if _reload > 0.0 or clip >= clip_size or reserve <= 0:
		return
	_reload = RELOAD


func _fire() -> void:
	clip -= 1
	_delay = fire_delay
	_kick = 1.0
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.play()
	var aim := _aim()
	var from := _muzzle.global_position
	var to: Vector3 = aim["point"]
	var dir := (to - from).normalized()
	var disc := SawDisc.new()
	disc.horde = horde
	disc.velocity = dir * speed
	disc.max_range = RANGE
	disc.pierce = pierce
	disc.width = WIDTH
	disc.bounces = 1 if bounce else 0
	disc.split = swarm
	disc.boomerang = boomerang
	disc.color = disc_color
	disc.owner_gun = self
	disc.exclude = [_player().get_rid()] if _player() else []
	get_tree().current_scene.add_child(disc)
	# Появляется чуть впереди пасти — не закрывает экран в момент выстрела
	disc.global_position = from + dir * 1.2


func reload_progress() -> float:
	return 1.0 - _reload / RELOAD if _reload > 0.0 else (1.0 - _delay / fire_delay)


func ammo_text() -> String:
	return "%d / %d" % [clip, reserve]


func ammo_note() -> String:
	if _reload > 0.0:
		return "перезарядка…"
	return "T — перезарядить" if clip < clip_size and reserve > 0 else ""


func ammo_empty() -> bool:
	return clip == 0 and reserve == 0


func restock() -> void:
	clip = clip_size
	reserve = RESERVE
	_reload = 0.0


func _update_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var k := ease(_kick, 0.4)
	var r := sin(clampf(1.0 - _reload / RELOAD, 0.0, 1.0) * PI) if _reload > 0.0 else 0.0
	var breath := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.002, 0.0)
	position = REST_POS + breath + Vector3(0.0, -0.06 * r - 0.4 * lower, 0.06 * k)
	rotation = REST_ROT + Vector3(0.1 * k - 0.3 * r - 0.6 * lower, 0.0, 0.3 * r)
	_point_at_crosshair(REST_POS, REST_ROT, delta)


## Летящий энергодиск: крутится, режет толпу по пути, гаснет у земли или скалы.
## bounces — сколько раз отскочит от земли/скалы; split — через SPLIT_AFTER с делится на 4 малых
## веером; boomerang — долетев (или ударившись), возвращается к герою и режет толпу второй раз.
class SawDisc extends Node3D:
	const SPLIT_AFTER := 0.35
	static var _whirr: AudioStreamWAV
	const SKIM := 0.5                # м над землёй, когда диск скользит по ней
	static var _meshes := {}
	var horde: Node3D
	var velocity := Vector3.ZERO
	var max_range := 75.0
	var pierce := 10
	var width := 0.9
	var exclude: Array = []
	var bounces := 0
	var split := false
	var boomerang := false
	var color := SawModel.BLUE
	var size := 1.0
	var owner_gun: Node3D
	## Скользит над землёй (после отскока от неё) — держится высоты SKIM.
	var skim := false
	var _map: Node3D
	var _flown := 0.0
	var _age := 0.0
	var _left := 0
	var _returning := false
	var _mesh: MeshInstance3D
	var _light: OmniLight3D
	var _dying := 0.0

	func _ready() -> void:
		_left = pierce
		_map = get_tree().get_first_node_in_group("map")
		_mesh = MeshInstance3D.new()
		var key := "%s_%s" % [color.to_html(), size]
		if not _meshes.has(key):
			_meshes[key] = SawModel.disc_mesh(0.3 * size, 0.19 * size, true, color)
		_mesh.mesh = _meshes[key]
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
		if size >= 1.0:
			# Жужжание летящего диска — слышно, когда он проносится рядом
			if not _whirr:
				_whirr = WHIRR_SOUND.duplicate()
				_whirr.loop_mode = AudioStreamWAV.LOOP_FORWARD
				_whirr.loop_end = int(WHIRR_SOUND.get_length() * WHIRR_SOUND.mix_rate)
			var hum := AudioStreamPlayer3D.new()
			hum.stream = _whirr
			hum.unit_size = 5.0
			hum.volume_db = -6.0
			hum.pitch_scale = randf_range(0.9, 1.1)
			hum.autoplay = true
			add_child(hum)
			_light = OmniLight3D.new()
			_light.light_color = color.lightened(0.2)
			_light.light_energy = 2.0
			_light.omni_range = 4.0
			add_child(_light)
		_face()
		# Диск летит плашмя, как вылетел из пасти
		_mesh.rotation.x = PI / 2.0

	func _face() -> void:
		if velocity.length_squared() > 0.01:
			look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.FORWARD)

	func _process(delta: float) -> void:
		_mesh.rotate_object_local(Vector3.FORWARD, delta * 22.0)
		if _dying > 0.0:
			_dying -= delta
			scale = Vector3.ONE * maxf(_dying / 0.2, 0.01)
			if _dying <= 0.0:
				queue_free()
			return
		_age += delta
		if split and _age >= SPLIT_AFTER:
			_split(Vector3.ZERO)
			return
		if _returning and is_instance_valid(owner_gun):
			# Бумеранг: доворачивает к герою
			var home := owner_gun.global_position
			velocity = (home - global_position).normalized() * velocity.length()
			if global_position.distance_to(home) < 2.0:
				queue_free()
				return
		var from := global_position
		var to := from + velocity * delta
		if skim and _map and not _returning:
			to.y = _map.height(Vector2(to.x, to.z)) + SKIM
		# Упёрся в землю или скалу — отскок, разворот бумеранга или гаснет там
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = exclude
		var hit := {} if _returning or skim else get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			to = hit.position
		if horde and _left > 0:
			_left -= horde.kill_line(from, to, width, _left, "saw")
		global_position = to
		_flown += from.distance_to(to)
		if not hit.is_empty() and split:
			# «Рой» ударился о землю — делится прямо тут и веером скользит по толпе
			_split(hit.normal)
			return
		if not hit.is_empty() and bounces > 0:
			bounces -= 1
			var n: Vector3 = hit.normal
			if n.y > 0.6:
				# Земля: диск не гаснет, а дальше скользит над ней сквозь толпу
				var flat := Vector3(velocity.x, 0.0, velocity.z)
				velocity = flat.normalized() * velocity.length() if flat.length_squared() > 0.01 else velocity.bounce(n)
				skim = true
			else:
				velocity = velocity.bounce(n)
			# Чуть приподнять над землёй, чтобы не застрять в ней
			global_position = to + n * 0.3
			_face()
			return
		var done := not hit.is_empty() or _flown >= max_range or _left <= 0
		if done and boomerang and not _returning:
			_returning = true
			_left = pierce
			_flown = 0.0
			return
		if done or _flown >= max_range * 2.0:
			_dying = 0.2

	## «Рой»: диск делится на 4 малых, они расходятся веером и режут дальше.
	## ground — нормаль земли, если делится от удара о неё (тогда малые скользят по земле).
	func _split(ground: Vector3) -> void:
		var parent := get_parent()
		var v := velocity
		if ground != Vector3.ZERO:
			var flat := Vector3(v.x, 0.0, v.z)
			v = flat.normalized() * v.length() if flat.length_squared() > 0.01 else v
		for a in [-0.42, -0.14, 0.14, 0.42]:
			var d := SawDisc.new()
			d.horde = horde
			d.skim = ground != Vector3.ZERO or skim
			d.velocity = v.rotated(Vector3.UP, a)
			d.max_range = maxf(max_range - _flown, 10.0)
			d.pierce = maxi(_left / 2, 4)
			d.width = width * 0.75
			d.exclude = exclude
			d.bounces = bounces
			d.color = color
			d.size = 0.8
			parent.add_child(d)
			d.global_position = global_position + ground * 0.4
		queue_free()
