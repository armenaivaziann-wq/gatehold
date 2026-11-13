extends "res://weapons/weapon.gd"
## Мушкетон от первого лица (дочерний узел камеры).
## ЛКМ — выстрел разрывным ядром: оно летит по прямой в точку под прицелом (shell.gd) и
## взрывается ровно в ней (explosion.gd). После выстрела — отдача, вспышка и дым
## из раструба, затем короткая пауза на взвод. В стволе clip_size зарядов; когда кончились —
## перезарядка из запаса (сама или по R), она дольше.
## Модель — models/weapons/blunderbuss.glb (исходник art_src/weapons/build_blunderbuss.py),
## руки в перчатках держат её: правая — шейку приклада, левая — снизу цевьё.
## rockets = true — то же оружие в виде ракетницы героя: своя модель (launcher_model.gd),
## вместо ядер — ракеты с густым дымным следом (shell.gd rocket), из ствола торчит боеголовка.

const FxBudget := preload("res://core/fx_budget.gd")

const MODEL := preload("res://weapons/models/blunderbuss.glb")
const SHOT_SOUND := preload("res://audio/sounds/blunderbuss_shot.wav")
const ShellScript := preload("res://weapons/shell.gd")
const ExplosionScript := preload("res://effects/explosion.gd")
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")

# Положение в кадре (оси камеры): справа внизу, раструб смотрит к прицелу, виден левый бок с замком
const REST_POS := Vector3(0.25, -0.23, -0.5)
const REST_ROT := Vector3(0.08, 0.36, -0.15)
# В кадре ружьё чуть меньше настоящего — не загораживает поле боя
const VIEW_SCALE := 0.85
# Руки в осях модели: точка на оси, ось хвата, радиус ложа там, куда уходит локоть
const RIGHT_HAND := [Vector3(0.0, -0.02, 0.175), Vector3(0.0, -0.25, 1.0), 0.032, Vector3(0.7, -0.6, 0.35)]
const LEFT_HAND := [Vector3(0.0, -0.045, -0.24), Vector3(0.1, 0.03, -1.0), 0.04, Vector3(-0.7, -0.6, 0.4)]

const RELOAD_TIME := 1.15      # взвод между выстрелами
const FULL_RELOAD_TIME := 2.3  # перезарядка из запаса
const CLIP_SIZE := 6
const START_RESERVE := 36
const RESUPPLY_TIME := 1.5     # с на одно ядро из обоза: запас в руках пополняется сам
## Базука героя на старте слабая — растёт в «Прокачке» («Мощь ракет», «Боезапас»,
## «Быстрая перезарядка»): 3 ракеты в стволе, 12 в запасе, подвоз раз в 3 с, взрыв поменьше.
const ROCKET_CLIP := 3
const ROCKET_RESERVE := 12
const ROCKET_RESUPPLY := 3.0
const ROCKET_BLAST := 0.85
const SHELL_SPEED := 72.0
# Метка зоны взрыва видна, если точка прицела не дальше этого
const MARKER_DISTANCE := 110.0
const LauncherModel := preload("res://weapons/launcher_model.gd")
## Базука на правом плече: ствол вдоль взгляда справа от лица, раструб — за плечом, нос
## чуть смотрит к прицелу.
const LAUNCHER_SCALE := 0.62
const LAUNCHER_POS := Vector3(0.25, -0.14, -0.2)
const LAUNCHER_ROT := Vector3(0.02, 0.06, 0.0)

var _muzzle: Node3D
var _kick := 0.0
var _reload := 0.0
## С мастерством (mastery.gd) и «Оружейником»: зарядов в стволе и в запасе, взвод, взрыв.
var clip_size: int
var reserve_size: int
var reload_time: float
var blast: float
var blast_kills: int
## Картечь — три ядра веером; зажигательные — взрыв поджигает землю.
var cluster: bool
var incendiary: bool
var _reload_total := RELOAD_TIME
var _supply := 0.0
var _refill := false            # идёт перезарядка из запаса
## Зарядов в стволе и в запасе.
var clip: int
var reserve: int
var _flash: MeshInstance3D
var _light: OmniLight3D
var _smoke: GPUParticles3D
var _flash_frames := 0
var _audio: AudioStreamPlayer
## Ракетница вместо мушкетона (задать до добавления в сцену).
var rockets := false
## Стрелять без мыши (для автоматических снимков и проверок).
var force_fire := false
## Уровень героя в бою (main.gd): радиус взрыва растёт.
var level_mult := 1.0
var _warhead: Node3D
## Ветка ракетницы («Улучшения оружия»): кассета, наведение, ядерная боеголовка, «Град».
var bombs := 0
var homing := false
var nuke := false
var barrage := false
var _shots := 0
const NUKE_EVERY := 4
const NUKE_COLOR := Color(0.35, 1.0, 0.25)


## Параметры из мастерства и общего древа; заново — если прокачку докупили посреди боя (main.gd).
func refresh_stats() -> void:
	clip_size = (ROCKET_CLIP + Upgrades.clip_bonus() if rockets else CLIP_SIZE) + int(Mastery.add("musket", "clip"))
	reserve_size = int(((ROCKET_RESERVE if rockets else START_RESERVE) + Mastery.add("musket", "reserve")) * Upgrades.ammo_mult())
	reload_time = RELOAD_TIME * Mastery.mult("musket", "reload") * Upgrades.reload_mult()
	blast = ExplosionScript.RADIUS * Mastery.mult("musket", "radius") * Upgrades.weapon_radius() * level_mult \
		* (ROCKET_BLAST if rockets else 1.0)
	# Ракета задевает вдвое меньше врагов, чем ядро мушкетона: героя и так выручают умения
	blast_kills = int(ExplosionScript.MAX_KILLS * Mastery.mult("musket", "kills") * (0.5 if rockets else 1.0))
	# «Тройной выстрел» и «Зажигательные ракеты» из древа (или мастерство мушкетона)
	cluster = Mastery.flag("musket", "cluster") or (rockets and Upgrades.level("shrapnel") > 0)
	incendiary = Mastery.flag("musket", "fire") or (rockets and Upgrades.level("incendiary") > 0)
	if rockets:
		clip_size += Upgrades.w("rk_drum")
		blast *= 1.0 + 0.15 * Upgrades.w("rk_shock")
		blast_kills = int(blast_kills * (1.0 + 0.3 * Upgrades.w("rk_shock")))
		bombs = 3 if Upgrades.w("rk_cluster") > 0 else 0
		homing = Upgrades.w("rk_homing") > 0
		nuke = Upgrades.w("rk_nuke") > 0
		barrage = Upgrades.w("rk_barrage") > 0
		if barrage:
			cluster = true
			reload_time *= 0.5
		if is_inside_tree():
			_paint_warhead()


## Боеголовка в стволе: ядерная — жёлтая с чёрным, «Град» — синяя, иначе красная.
func _paint_warhead() -> void:
	if not _warhead:
		return
	if nuke:
		_warhead.mesh = LauncherModel.warhead_mesh(Color(1.0, 0.82, 0.1), Color(0.08, 0.08, 0.08), Color(0.1, 0.1, 0.1))
	elif barrage:
		_warhead.mesh = LauncherModel.warhead_mesh(Color(0.2, 0.45, 1.0), Color(0.12, 0.25, 0.7), Color(0.75, 0.85, 1.0))
	else:
		_warhead.mesh = LauncherModel.warhead_mesh()


func _init() -> void:
	refresh_stats()
	clip = clip_size
	reserve = reserve_size


func _ready() -> void:
	super()
	display_name = "Ракетница" if rockets else "Мушкетон"
	ammo_kind = "shells"
	# Ракетница длиннее мушкетона — в кадре мельче и правее, чтобы не закрывала поле боя
	if rockets:
		_setup_model(LauncherModel.scene(), VIEW_SCALE * LAUNCHER_SCALE, LauncherModel.RIGHT_HAND, LauncherModel.LEFT_HAND)
	else:
		_setup_model(MODEL, VIEW_SCALE, RIGHT_HAND, LEFT_HAND)
	_muzzle = _model.find_child("Muzzle")
	_warhead = _model.find_child("Warhead")
	if rockets:
		_paint_warhead()
	_make_marker(blast)
	_build_effects()
	_audio = AudioStreamPlayer.new()
	_audio.stream = SHOT_SOUND
	_audio.volume_db = -4.0
	add_child(_audio)
	_update_pose(0.0)


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var can_shoot := _can_shoot()
	_reload = maxf(_reload - delta, 0.0)
	_supply += delta
	if _supply >= (ROCKET_RESUPPLY * Upgrades.resupply_mult() if rockets else RESUPPLY_TIME):
		_supply = 0.0
		reserve = mini(reserve + 1, reserve_size)
	if _refill and _reload == 0.0:
		_refill = false
		var take := mini(clip_size - clip, reserve)
		clip += take
		reserve -= take
	if captured and Input.is_action_just_pressed("reload"):
		start_reload()
	_kick = move_toward(_kick, 0.0, delta * 4.0)
	if _reload == 0.0 and clip > 0 and (force_fire or can_shoot and Input.is_action_just_pressed("fire")):
		fire()
	_update_effects(delta)
	_update_pose(delta)
	if _warhead:
		_warhead.visible = _reload <= 0.0 and clip > 0
	_update_marker(blast, MARKER_DISTANCE, _reload > 0.0)


## Выстрел: ядро из раструба в точку под прицелом, эффекты у раструба.
func fire() -> void:
	clip -= 1
	_reload = reload_time
	_reload_total = reload_time
	_kick = 1.0
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.play()
	var aim := _aim()
	var target: Vector3 = aim["point"]
	var from := _muzzle.global_position
	if homing and aim["hit"]:
		target = _densest_near(target)
	_shots += 1
	# Ядерная: каждая NUKE_EVERY-я ракета — огромный зелёный взрыв
	var is_nuke := nuke and _shots % NUKE_EVERY == 0
	var targets := [target]
	if cluster:
		# Картечь: ещё два ядра по бокам от точки прицела
		var side := (target - from).cross(Vector3.UP).normalized() * blast * 0.9
		targets.append_array([target + side, target - side])
	for to: Vector3 in targets:
		var shell := ShellScript.new()
		shell.horde = horde
		shell.blast_radius = blast * (2.5 if is_nuke else 1.0)
		shell.max_kills = blast_kills * (4 if is_nuke else 1)
		shell.ignite = incendiary
		shell.rocket = rockets
		shell.bombs = bombs
		if is_nuke:
			shell.tint = NUKE_COLOR
		if _player():
			shell.exclude = [_player().get_rid()]
		# Строго по прямой из раструба в точку прицела
		shell.velocity = (to - from).normalized() * SHELL_SPEED * (Upgrades.rocket_speed() if rockets else 1.0)
		shell.target = to
		shell.has_target = aim["hit"]
		get_tree().current_scene.add_child(shell)
		shell.global_position = from
	# «Двойной выстрел»: иногда вслед вылетает вторая ракета — даром
	if rockets and randf() < Upgrades.double_chance():
		var extra := ShellScript.new()
		extra.horde = horde
		extra.blast_radius = blast
		extra.max_kills = blast_kills
		extra.ignite = incendiary
		extra.rocket = true
		if _player():
			extra.exclude = [_player().get_rid()]
		var to2 := target + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		extra.velocity = (to2 - from).normalized() * SHELL_SPEED * Upgrades.rocket_speed()
		extra.target = to2
		extra.has_target = aim["hit"]
		get_tree().current_scene.add_child(extra)
		extra.global_position = from + Vector3(0, 0.15, 0)
	# Вспышка, свет и дым
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash_frames = 3
	_light.light_energy = 6.0
	_smoke.restart()
	# Ствол пуст — сразу перезаряжаемся из запаса
	if clip == 0 and reserve > 0:
		start_reload()


## «Наведение»: ракета доворачивает в самую густую толпу в паре шагов от прицела.
func _densest_near(p: Vector3) -> Vector3:
	if not horde:
		return p
	var map := get_tree().get_first_node_in_group("map")
	var best := p
	var best_n: int = horde.count_near(p, blast)
	for ring: float in [3.0, 6.0]:
		for k in 8:
			var a := TAU * k / 8.0
			var q := p + Vector3(cos(a), 0.0, sin(a)) * ring
			var n: int = horde.count_near(q, blast)
			# Сдвигаемся, только если там заметно гуще
			if n > best_n * 1.3 + 2:
				best_n = n
				best = q
	if best != p and map:
		best.y = map.height(Vector2(best.x, best.z))
	return best


## Перезарядка из запаса (если есть что заряжать и что брать).
func start_reload() -> void:
	if _refill or clip >= clip_size or reserve <= 0:
		return
	_refill = true
	_reload = maxf(_reload, FULL_RELOAD_TIME)
	_reload_total = _reload


## Пополнить запас и ствол (начало волны).
func restock() -> void:
	reserve = reserve_size
	clip = clip_size
	_refill = false


## Готовность к выстрелу: 0 — только что выстрелил, 1 — заряжен.
func reload_progress() -> float:
	if clip == 0 and not _refill:
		return 0.0
	return 1.0 - _reload / _reload_total


func ammo_text() -> String:
	return "%d / %d" % [clip, reserve]


func ammo_note() -> String:
	if _refill:
		return "перезарядка…"
	if clip == 0 and reserve == 0:
		return "нет зарядов"
	if clip < clip_size and reserve > 0:
		return "T — перезарядить"
	return ""


func ammo_empty() -> bool:
	return clip == 0


func _update_pose(delta: float) -> void:
	var lower := _tick_equip(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var k := ease(_kick, 0.35)
	# Перезарядка: ружьё опускается и заваливается на бок, потом возвращается
	var r := 0.0
	if _reload > 0.0:
		r = sin(clampf(1.0 - _reload / _reload_total, 0.0, 1.0) * PI)
		# Перезарядка из запаса — ружьё опускается ниже и дольше
		if _refill:
			r *= 1.6
		r *= 1.0 - k
	var breath := Vector3(sin(t * 1.3) * 0.002, sin(t * 2.1) * 0.002, 0.0)
	if rockets:
		# На плече: отдача толкает назад и чуть вверх, перезарядка — базука опускается с плеча
		position = LAUNCHER_POS + breath + Vector3(0.0, -0.08 * r - 0.4 * lower, 0.06 * k)
		rotation = LAUNCHER_ROT + Vector3(0.12 * k - 0.3 * r - 0.6 * lower, 0.0, 0.15 * r)
		_point_at_crosshair(LAUNCHER_POS, LAUNCHER_ROT, delta)
		return
	position = REST_POS + breath + Vector3(0.0, -0.06 * r - 0.4 * lower, 0.11 * k)
	rotation = REST_ROT + Vector3(0.28 * k - 0.35 * r - 0.6 * lower, 0.0, 0.45 * r)


# --- эффекты выстрела -----------------------------------------------------------------------

func _build_effects() -> void:
	# Вспышка: звезда из трёх скрещенных плоскостей, светится и гаснет за доли секунды
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := TAU * k / 6.0
		var tip := Vector3(cos(a), sin(a), 0.0) * (0.3 if k % 2 == 0 else 0.18)
		var side := Vector3(cos(a + PI / 2), sin(a + PI / 2), 0.0) * 0.05
		st.set_color(Color(1.0, 0.95, 0.6))
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1.0, 0.45, 0.05, 0.2))
		st.add_vertex(tip + side)
		st.add_vertex(tip - side)
		# Конус вперёд
		st.set_color(Color(1.0, 0.95, 0.6))
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(1.0, 0.4, 0.05, 0.2))
		st.add_vertex(Vector3(cos(a) * 0.1, sin(a) * 0.1, -0.5))
		st.add_vertex(Vector3(cos(a + TAU / 6) * 0.1, sin(a + TAU / 6) * 0.1, -0.5))
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.vertex_color_use_as_albedo = true
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash = MeshInstance3D.new()
	_flash.mesh = st.commit()
	_flash.material_override = flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_muzzle.add_child(_flash)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.35)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_muzzle.add_child(_light)
	# Дым: клубы серого дыма из раструба, остаются в мире (не едут вместе с ружьём)
	_smoke = FxBudget.cosmetic(GPUParticles3D.new())
	_smoke.one_shot = true
	_smoke.emitting = false
	_smoke.amount = 34
	_smoke.lifetime = 1.6
	_smoke.explosiveness = 0.9
	_smoke.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 18.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 2.5
	pm.damping_max = 4.0
	pm.scale_min = 0.35
	pm.scale_max = 0.9
	var curve := Curve.new()
	curve.max_value = 8.0  # по умолчанию кривая обрезана сверху единицей
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 1.6))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.77, 0.7, 0.5))
	grad.set_color(1, Color(0.7, 0.67, 0.62, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex
	_smoke.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	puff.radial_segments = 8
	puff.rings = 4
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.roughness = 1.0
	puff.material = smoke_mat
	_smoke.draw_pass_1 = puff
	_muzzle.add_child(_smoke)


func _update_effects(delta: float) -> void:
	_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 60.0)
	# Вспышка держится три кадра — видна при любом FPS
	if _flash.visible:
		_flash_frames -= 1
		if _flash_frames <= 0:
			_flash.visible = false
