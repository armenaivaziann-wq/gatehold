extends "res://weapons/weapon.gd"
## Боевой молот от первого лица (дочерний узел камеры). Модель — hammer_model.gd (по листу
## пользователя), держится двумя руками за рукоять, как настоящий: правая у навершия, левая выше.
## ЛКМ — серия из трёх ударов (следующее нажатие в течение COMBO_WINDOW продолжает серию):
##  1. «Размах» — боковой удар справа налево, валит тех, кто перед героем;
##  2. «Вихрь» — обратный размах слева направо с разворотом: бьёт всех вокруг героя;
##  3. «Сокрушение» — молот над головой и сверху в землю: ударная волна (shockwave.gd).
## В воздухе (выше DIVE_MIN_HEIGHT над землёй) зажать ЛКМ — пике: герой камнем летит вниз и
## бьёт в землю, чем выше падал — тем шире и сильнее волна. Коротко нажать в воздухе — обычный
## удар (по воздуху). Бьёт только у земли: с вышки или в полёте размах никого не достанет.
## Покупается за трофеи на вкладке «Оружие» (upgrades.gd: WEAPONS).

const HammerModel := preload("res://weapons/hammer_model.gd")
const ShockwaveScript := preload("res://effects/shockwave.gd")
const SWING_SOUND := preload("res://audio/sounds/hammer_swing.wav")
const Upgrades := preload("res://core/upgrades.gd")
const ZapScript := preload("res://effects/zap_chain.gd")
const StrikeScript := preload("res://effects/sky_strike.gd")
const FirePatch := preload("res://effects/fire_patch.gd")
const THUNDER_GLOW := Color(0.35, 0.75, 1.0)
const FIRE_GLOW := Color(1.0, 0.42, 0.08)

const VIEW_SCALE := 0.6
const HAND_SIZE := 1.45          # кисти в осях уменьшенной модели — крупнее, под толстую рукоять
# Куда уходят локти (оси камеры): вниз и назад к плечам героя
const RIGHT_ELBOW := Vector3(0.7, -0.8, 1.0)
const LEFT_ELBOW := Vector3(-0.5, -0.9, 1.0)
const GRIP_MID := (HammerModel.GRIP_LOW + HammerModel.GRIP_HIGH) * 0.5
const COMBO_WINDOW := 0.7        # с после удара: следующее нажатие продолжает серию
const MELEE_HEIGHT := 2.6        # м над землёй: выше — молот машет по воздуху
const DIVE_MIN_HEIGHT := 3.0     # м: выше этого в воздухе можно зажать удар — пике
const DIVE_HOLD := 0.22          # с держать ЛКМ, чтобы начать пике
const TRAIL_LIFE := 0.16
const NAMES := ["Размах", "Вихрь", "Сокрушение"]

# Позы: [где кисти (оси камеры), куда смотрит рукоять от кистей к бойку, куда смотрит боёк]
const REST := [Vector3(0.27, -0.42, -0.52), Vector3(0.3, 0.92, 0.22), Vector3(0, 0, -1)]
const WIND_R := [Vector3(0.32, -0.33, -0.48), Vector3(0.9, 0.35, 0.25), Vector3(0, 0, -1)]
const MID_L := [Vector3(0.05, -0.35, -0.56), Vector3(0.0, 0.12, -1.0), Vector3(-1, 0, 0)]
const FOLLOW_L := [Vector3(-0.3, -0.35, -0.48), Vector3(-0.9, 0.1, -0.3), Vector3(-0.2, 0, 1)]
const WIND_L := [Vector3(-0.3, -0.33, -0.48), Vector3(-0.9, 0.35, 0.25), Vector3(0, 0, -1)]
const MID_R := [Vector3(0.05, -0.33, -0.56), Vector3(0.0, 0.15, -1.0), Vector3(1, 0, 0)]
const FOLLOW_R := [Vector3(0.32, -0.35, -0.48), Vector3(0.9, 0.15, -0.2), Vector3(0.1, 0, 1)]
const RAISE := [Vector3(0.15, -0.17, -0.4), Vector3(0.1, 0.8, 0.55), Vector3(0, 0.55, -0.8)]
const SLAM := [Vector3(0.05, -0.31, -0.58), Vector3(0.0, -0.55, -0.85), Vector3(0, -1, 0)]
const SLAM_LOW := [Vector3(0.05, -0.38, -0.55), Vector3(0.0, -0.7, -0.7), Vector3(0, -1, 0)]

# Удары: ключевые кадры [время, поза] (первый кадр — поза, с которой начали), момент удара,
# окно следа замаха [с, по]
const ATTACKS := [
	{"keys": [[0.13, WIND_R], [0.24, MID_L], [0.33, FOLLOW_L], [0.62, REST]], "hit": 0.22, "trail": [0.12, 0.34]},
	{"keys": [[0.11, WIND_L], [0.21, MID_R], [0.31, FOLLOW_R], [0.6, REST]], "hit": 0.2, "trail": [0.1, 0.32]},
	{"keys": [[0.26, RAISE], [0.38, SLAM], [0.52, SLAM_LOW], [0.9, REST]], "hit": 0.37, "trail": [0.27, 0.4]},
]
const LAND := {"keys": [[0.07, SLAM], [0.25, SLAM_LOW], [0.65, REST]], "hit": -1.0, "trail": [0.0, 0.08]}

## Бить без мыши (для автоматических снимков и проверок): серия ударов подряд.
var force_fire := false
## Начать пике без мыши (для проверок).
var force_dive := false
## Сколько врагов свалил последний удар (для проверок).
var last_kills := 0
## Ветка молота («Улучшения оружия»): сила и скорость ударов, «Землетрясение», «Метеор»,
## финалы «Молот грома» и «Огненный молот».
var kill_mult := 1.0
var radius_mult := 1.0
var speed := 1.0
var quake := false
var meteor := false
var thunder := false
var fire := false
var dive_min := DIVE_MIN_HEIGHT
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _aura: GPUParticles3D

var _attack: Dictionary = {}
var _combo := -1                 # номер последнего удара серии (0..2)
var _t := 0.0
var _hit_done := false
var _since := 99.0               # с после конца последнего удара
var _queued := false
var _holding := false
var _hold := 0.0
var _from_pos := Vector3.ZERO
var _from_rot := Quaternion.IDENTITY
var _pos := Vector3.ZERO
var _rot := Quaternion.IDENTITY
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array = []       # [внутренняя точка, внешняя, возраст] в осях камеры
var _audio: AudioStreamPlayer
var _hands: Array[Node3D] = []


func refresh_stats() -> void:
	kill_mult = 1.0 + 0.3 * Upgrades.w("hm_power")
	radius_mult = 1.0 + 0.1 * Upgrades.w("hm_power")
	speed = 1.0 + 0.15 * Upgrades.w("hm_speed")
	quake = Upgrades.w("hm_quake") > 0
	meteor = Upgrades.w("hm_dive") > 0
	thunder = Upgrades.w("hm_thunder") > 0
	fire = Upgrades.w("hm_fire") > 0
	dive_min = 2.0 if meteor else DIVE_MIN_HEIGHT
	if _glow:
		_apply_glow()


## Боёк под финал: голубое свечение и искры или раскалённый с языками огня.
func _apply_glow() -> void:
	if _aura:
		_aura.queue_free()
		_aura = null
	if not thunder and not fire:
		_glow.material_override = null
		return
	var col := THUNDER_GLOW if thunder else FIRE_GLOW
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.albedo_color = col.lightened(0.3)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = col
	_glow_mat.emission_energy_multiplier = 2.5
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.material_override = _glow_mat
	_aura = GPUParticles3D.new()
	_aura.amount = 24 if thunder else 30
	_aura.lifetime = 0.25 if thunder else 0.55
	_aura.local_coords = true
	_aura.position = Vector3(0, HammerModel.HEAD_Y, 0)
	_aura.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.1, 0.12, 0.34)
	if thunder:
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 180.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.6
		pm.gravity = Vector3.ZERO
	else:
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 20.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.5
		pm.gravity = Vector3(0, 1.2, 0)
	var grad := Gradient.new()
	if thunder:
		grad.set_color(0, Color(0.9, 0.97, 1.0, 1.0))
		grad.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	else:
		grad.set_color(0, Color(1.0, 0.55, 0.12, 1.0))
		grad.set_color(1, Color(0.7, 0.1, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_aura.process_material = pm
	var mesh: Mesh
	if thunder:
		var b := BoxMesh.new()
		b.size = Vector3(0.012, 0.012, 0.05)
		mesh = b
	else:
		var sp := SphereMesh.new()
		sp.radius = 0.02
		sp.height = 0.04
		sp.radial_segments = 6
		sp.rings = 3
		mesh = sp
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.surface_set_material(0, mm)
	_aura.draw_pass_1 = mesh
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(_aura)


func _ready() -> void:
	super()
	display_name = "Молот"
	ammo_kind = "melee"
	_setup_model(HammerModel.scene(), VIEW_SCALE, HammerModel.RIGHT_HAND, HammerModel.LEFT_HAND)
	# Кисти — точка вращения: модель сдвинута так, что середина хвата в начале координат
	_model.position = Vector3(0, -GRIP_MID * VIEW_SCALE, 0)
	for c in _model.get_children():
		if c.has_meta("right"):
			_hands.append(c)
	_glow = _model.find_child("Glow")
	refresh_stats()
	_pos = REST[0]
	_rot = _quat(REST)
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_trail.material_override = m
	_camera.add_child.call_deferred(_trail)
	_audio = AudioStreamPlayer.new()
	_audio.stream = SWING_SOUND
	_audio.volume_db = -3.0
	add_child(_audio)
	_apply_pose(0.0)


func set_active(on: bool) -> void:
	super(on)
	_holding = false
	_queued = false
	if _trail:
		_trail_pts.clear()
		_trail_mesh.clear_surfaces()


func _process(delta: float) -> void:
	var can := _can_shoot()
	var p := _player()
	var hero := p as CharacterBody3D
	var high: bool = hero != null and not hero.is_on_floor() and hero.call("height_above_ground") > dive_min
	var diving := hero != null and bool(hero.get("diving"))
	var pressed := (can and Input.is_action_just_pressed("fire")) or (force_fire and _attack.is_empty())
	_since += delta
	if force_dive and high and not diving and _attack.is_empty():
		force_dive = false
		_start_dive(hero)
		diving = true
	if diving:
		# Пике: молот занесён над головой, пока не коснёмся земли
		_attack = {}
		_blend_to(RAISE, delta * 14.0)
	else:
		if pressed:
			if high and _attack.is_empty():
				_holding = true
				_hold = 0.0
			else:
				_queued = true
		if _holding:
			if Input.is_action_pressed("fire") and high:
				_hold += delta
				if _hold >= DIVE_HOLD:
					_holding = false
					_start_dive(hero)
			else:
				_holding = false
				_queued = true
		if _queued and _can_chain():
			_queued = false
			_next_attack()
		if not _attack.is_empty():
			_play(delta)
		else:
			_blend_to(REST, delta * 8.0)
	_update_trail(delta)
	_apply_pose(delta)


## Можно начинать следующий удар: молот не занят или уже возвращается после удара.
func _can_chain() -> bool:
	if _attack.is_empty():
		return true
	var keys: Array = _attack["keys"]
	return _hit_done and _t >= float(keys[keys.size() - 2][0])


func _next_attack() -> void:
	var chained := not _attack.is_empty() or _since < COMBO_WINDOW
	_combo = (_combo + 1) % 3 if chained else 0
	_begin(ATTACKS[_combo])
	_audio.pitch_scale = randf_range(0.9, 1.1) * (0.85 if _combo == 2 else 1.0)
	_audio.play()


func _begin(attack: Dictionary) -> void:
	_attack = attack
	_t = 0.0
	_hit_done = false
	_from_pos = _pos
	_from_rot = _rot


func _play(delta: float) -> void:
	_t += delta * speed
	var keys: Array = _attack["keys"]
	var hit: float = _attack["hit"]
	if not _hit_done and hit >= 0.0 and _t >= hit:
		_hit_done = true
		_strike(_combo)
	elif hit < 0.0:
		_hit_done = true
	# Поза между соседними ключевыми кадрами (первый — откуда начали)
	var prev_t := 0.0
	var prev_pos := _from_pos
	var prev_rot := _from_rot
	for k: Array in keys:
		var kt: float = k[0]
		if _t <= kt:
			var f := smoothstep(0.0, 1.0, (_t - prev_t) / maxf(kt - prev_t, 0.001))
			_pos = prev_pos.lerp(k[1][0], f)
			_rot = prev_rot.slerp(_quat(k[1]), f)
			break
		prev_t = kt
		prev_pos = k[1][0]
		prev_rot = _quat(k[1])
	var last: float = keys[keys.size() - 1][0]
	if _t >= last:
		_pos = prev_pos
		_rot = prev_rot
		_attack = {}
		_since = 0.0


## Удар серии: кого задело. Высоко над землёй (вышка, полёт) — мимо.
func _strike(step: int) -> void:
	last_kills = 0
	var hero := _player() as CharacterBody3D
	if not horde or not hero or hero.call("height_above_ground") > MELEE_HEIGHT:
		return
	var feet := hero.global_position
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var left := Vector3.UP.cross(fwd)
	var dmg := 2 if fire else 1
	match step:
		0:
			var at := feet + fwd * 2.2 + left * 0.4
			last_kills = horde.kill_area(at, 2.6 * radius_mult, int(8 * kill_mult), "hammer", 2 * dmg)
			get_tree().call_group("player", "shake", 0.15)
			_final_fx(at, 0)
		1:
			last_kills = _wave(feet, 3.6 * radius_mult, int(12 * kill_mult), 2 * dmg, 0.15)
			_final_fx(feet, 1)
		2:
			var r := 4.5 * radius_mult * (1.3 if quake else 1.0)
			var at := feet + fwd * 2.6
			last_kills = _wave(at, r, int(25 * kill_mult * (1.4 if quake else 1.0)), 3 * dmg, 0.5, 2.0 if quake else 1.0)
			_final_fx(at, 2, r)


## Финал ветки после удара: цепная молния (и молния с неба) или огонь на земле.
## kind: 0 — размах, 1 — вихрь, 2 — сокрушение, 3 — пике.
func _final_fx(at: Vector3, kind: int, r := 4.0) -> void:
	if not thunder and not fire:
		return
	var map := get_tree().get_first_node_in_group("map")
	if map:
		at.y = map.height(Vector2(at.x, at.z))
	var scene := get_tree().current_scene
	if thunder:
		var zap := ZapScript.new()
		zap.horde = horde
		zap.count = [3, 5, 8, 12][kind]
		zap.radius = 7.0 + kind
		zap.position = at + Vector3(0, 0.5, 0)
		scene.add_child(zap)
		last_kills += zap.killed
		if kind >= 2:
			# Удар молнии с неба в точку удара, у пике — ещё две рядом
			var strikes: Array[Vector3] = [at]
			if kind == 3:
				var a := randf() * TAU
				for k in 2:
					var q := at + Vector3(cos(a + PI * k), 0, sin(a + PI * k)) * r * 0.5
					if map:
						q.y = map.height(Vector2(q.x, q.z))
					strikes.append(q)
			for q in strikes:
				var strike := StrikeScript.new()
				strike.horde = horde
				strike.radius = 4.0
				strike.kills = 20
				strike.position = q
				scene.add_child(strike)
		return
	# Огонь: пятна горящей земли там, где ударил молот
	var spots: Array = []
	match kind:
		0:
			spots = [[at, 0.7]]
		1:
			var a0 := randf() * TAU
			for k in 3:
				var a := a0 + TAU * k / 3.0
				spots.append([at + Vector3(cos(a), 0, sin(a)) * 2.5, 0.6])
		2:
			spots = [[at, 1.4]]
		3:
			spots = [[at, 1.3]]
			for k in 6:
				var a := TAU * k / 6.0
				spots.append([at + Vector3(cos(a), 0, sin(a)) * r * 0.55, 0.9])
	for sp: Array in spots:
		var p: Vector3 = sp[0]
		if map:
			p.y = map.height(Vector2(p.x, p.z))
		var patch := FirePatch.new()
		patch.horde = horde
		patch.source = "hammer"
		patch.scale_size = sp[1]
		patch.position = p
		scene.add_child(patch)


## Ударная волна в точке на земле.
func _wave(at: Vector3, radius: float, kills: int, damage: int, power: float, stun := 1.0) -> int:
	var map := get_tree().get_first_node_in_group("map")
	if map:
		at.y = map.height(Vector2(at.x, at.z))
	var w := ShockwaveScript.new()
	w.horde = horde
	w.radius = radius
	w.kills = kills
	w.damage = damage
	w.power = power
	w.stun_time = stun
	w.position = at
	get_tree().current_scene.add_child(w)
	return w.killed


func _start_dive(hero: CharacterBody3D) -> void:
	if not hero.is_connected("dive_landed", _on_dive_landed):
		hero.connect("dive_landed", _on_dive_landed)
	hero.call("start_dive")
	_audio.pitch_scale = 0.7
	_audio.play()


## Пике закончилось: чем выше падал, тем шире и сильнее волна.
func _on_dive_landed(height: float) -> void:
	var hero := _player() as CharacterBody3D
	if not hero:
		return
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	var at := hero.global_position + fwd.normalized() * 1.2
	var k := clampf(height / 30.0, 0.0, 1.0)
	var r := lerpf(4.5, 11.0, k) * radius_mult * (1.25 if meteor else 1.0)
	var kills := int(lerpf(25.0, 150.0, k) * kill_mult * (1.5 if meteor else 1.0))
	last_kills = _wave(at, r, kills, 4 * (2 if fire else 1), lerpf(0.55, 1.0, k), 2.0 if quake else 1.0)
	_final_fx(at, 3, r)
	_combo = -1
	_begin(LAND)


func _blend_to(pose: Array, f: float) -> void:
	f = minf(f, 1.0)
	_pos = _pos.lerp(pose[0], f)
	_rot = _rot.slerp(_quat(pose), f)


## Поворот из позы: ось модели +Y — по рукояти, +Z — куда смотрит боёк.
static func _quat(pose: Array) -> Quaternion:
	var y: Vector3 = (pose[1] as Vector3).normalized()
	var face: Vector3 = pose[2]
	var z := (face - y * face.dot(y)).normalized()
	return Basis(y.cross(z), y, z).get_rotation_quaternion()


func _apply_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var breath := Vector3(sin(t * 1.3) * 0.003, sin(t * 2.1) * 0.003, 0.0) if _attack.is_empty() else Vector3.ZERO
	transform = Transform3D(Basis(_rot), _pos + breath + Vector3(0.0, -0.45 * lower, 0.0))
	_place_hands()


## Руки на рукояти; локти — к телу героя, как бы ни был повёрнут молот.
func _place_hands() -> void:
	var to_model := (transform.basis * _model.transform.basis).inverse()
	for hand in _hands:
		var right: bool = hand.get_meta("right")
		var g: Array = HammerModel.RIGHT_HAND if right else HammerModel.LEFT_HAND
		var elbow: Vector3 = (to_model * (RIGHT_ELBOW if right else LEFT_ELBOW)).normalized()
		Hands.place(hand, g[0], g[1], g[2], elbow, HAND_SIZE)


## След замаха: лента, которую оставляет боёк, — в осях камеры, гаснет за TRAIL_LIFE.
func _update_trail(delta: float) -> void:
	for pt: Array in _trail_pts:
		pt[2] += delta
	while not _trail_pts.is_empty() and _trail_pts[0][2] > TRAIL_LIFE:
		_trail_pts.pop_front()
	if not _attack.is_empty():
		var win: Array = _attack["trail"]
		if _t >= float(win[0]) and _t <= float(win[1]):
			var tf := transform * _model.transform
			_trail_pts.append([tf * Vector3(0, HammerModel.HEAD_Y - 0.14, 0), tf * Vector3(0, HammerModel.HEAD_Y + 0.14, 0), 0.0])
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _trail_pts.size() - 1:
		var a: Array = _trail_pts[i]
		var b: Array = _trail_pts[i + 1]
		var ca := Color(1.0, 0.95, 0.85, 0.3 * (1.0 - float(a[2]) / TRAIL_LIFE))
		var cb := Color(1.0, 0.95, 0.85, 0.3 * (1.0 - float(b[2]) / TRAIL_LIFE))
		for v: Array in [[a[0], ca], [a[1], ca], [b[1], cb], [a[0], ca], [b[1], cb], [b[0], cb]]:
			_trail_mesh.surface_set_color(v[1])
			_trail_mesh.surface_add_vertex(v[0])
	_trail_mesh.surface_end()


func ammo_text() -> String:
	return "%d / 3" % (((_combo + 1) % 3 if _since < COMBO_WINDOW or not _attack.is_empty() else 0) + 1)


func ammo_note() -> String:
	var hero := _player() as CharacterBody3D
	if hero and bool(hero.get("diving")):
		return "пике!"
	if hero and not hero.is_on_floor() and hero.call("height_above_ground") > dive_min:
		return "зажми ЛКМ — пике"
	var next := (_combo + 1) % 3 if _since < COMBO_WINDOW or not _attack.is_empty() else 0
	return NAMES[next]


func reload_progress() -> float:
	if _attack.is_empty():
		return 1.0
	var keys: Array = _attack["keys"]
	return clampf(_t / float(keys[keys.size() - 1][0]), 0.0, 1.0)
