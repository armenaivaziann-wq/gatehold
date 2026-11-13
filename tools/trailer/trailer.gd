extends SceneTree
## Трейлер игры: режиссёрский сценарий поверх настоящей игры. Камеры по траекториям, орды,
## стрельба из оружия и турелей, локации, Вождь гоблинов, надписи и логотип; склейки — на
## тактах музыки (tools/trailer/make_trailer_music.py, 120 уд/мин, такт — 2 с).
## Пишется кадр за кадром режимом Movie Maker, звук — вместе с игрой. Прогресс не пишется.
## Запуск (окно нужно — это рендер):
##   Godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie <папка>/frame.png \
##     -s res://tools/trailer/trailer.gd -- music=<trailer_music.wav> [until=СЕКУНДЫ]
## Потом: swift tools/trailer/assemble.swift <папка> <папка>/frame.wav <трейлер.mp4>

const FPS := 30
const LENGTH := 56.0
const GATE_Z := 100.0
const GOLD := Color(0.98, 0.74, 0.22)
const ExplosionScript := preload("res://effects/explosion.gd")

var scene: Node3D
var cam: Camera3D
var _frame := 0
var _until_s := LENGTH
var _main_script: GDScript
var _overlay: CanvasLayer
var _black: ColorRect
var _flash: ColorRect
var _bars: Array[ColorRect] = []
var _caption: Label
var _logo: Control
var _logo_parts: Array[Control] = []
## Надписи: [с, по, текст, размер, цвет]
var _texts := [
	[0.6, 3.7, "ОНИ ПРИШЛИ ИЗ ПЕЩЕР", 76, Color(1, 0.95, 0.85)],
	[12.0, 13.9, "ТЫСЯЧИ.", 150, GOLD],
	[30.0, 31.9, "УДЕРЖИ ВОРОТА.", 130, GOLD],
	[35.0, 37.8, "10 ЗЕМЕЛЬ. 10 ВОЖДЕЙ.", 96, Color(1, 0.95, 0.85)],
	[38.6, 40.9, "ВОЖДЬ ИДЁТ.", 140, Color(1.0, 0.35, 0.25)],
]
var _shake := 0.0
var _font: Font


func _initialize() -> void:
	_run()


func _run() -> void:
	var music_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("music="):
			music_path = a.substr(6)
		elif a.begins_with("until="):
			_until_s = float(a.substr(6))
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var progress: GDScript = load("res://core/progress.gd")
	progress.read_only = true
	progress.load_progress()
	progress.tutorial_done = true
	# Всё оружие и турели, всё древо — для зрелища
	load("res://core/mastery.gd").force_all = true
	for n: Dictionary in load("res://core/upgrades.gd").NODES:
		progress.upgrades[n["id"]] = n["max"]
	_main_script = load("res://core/main.gd")
	_main_script.start_in_game = true
	_build_overlay()
	# Музыка — на своей шине чуть громче, звуки игры (Master) — чуть тише
	AudioServer.add_bus()
	var score := AudioServer.bus_count - 1
	AudioServer.set_bus_name(score, "Score")
	AudioServer.set_bus_volume_db(score, 3.0)
	AudioServer.set_bus_volume_db(0, -3.0)
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	var music := AudioStreamPlayer.new()
	music.stream = AudioStreamWAV.load_from_file(music_path)
	music.bus = "Score"
	root.add_child(music)
	music.play()

	# --- 0–4 с: чёрный экран, «ОНИ ПРИШЛИ ИЗ ПЕЩЕР»; за ним грузится лес и выходит орда -------
	_black.color.a = 1.0
	await _load_level(0)
	var h: Node3D = scene.horde
	h.mix = PackedFloat32Array([0.62, 0.28, 0.1])
	h.armor_share = 0.35
	h.send_wave(14000, 120.0)
	_sim(4.0)
	await _until(4.0, func(_k: float, _t: float) -> void: pass)

	# --- 4–8 с: облёт над пещерой — орда льётся в каньон ------------------------------------
	_black.color.a = 0.0
	var s0: Vector2 = h._spawns[0]
	var dir := (_ahead(s0, 30.0) - s0).normalized()
	var y0 := _ground(s0)
	await _until(8.0, func(k: float, _t: float) -> void:
		var e := _smooth(k)
		var p := s0 - dir * (8.0 - 24.0 * e)
		var at := s0 + dir * (6.0 + 26.0 * e)
		_look(Vector3(p.x, y0 + 30.0 - 12.0 * e, p.y), Vector3(at.x, _ground(at), at.y)))

	# --- 8–12 с: у земли в каньоне — орда бежит прямо на камеру -----------------------------
	_sim(2.0)
	var lead := _densest(60, 400)
	await _until(12.0, func(k: float, _t: float) -> void:
		var p: Vector2 = h._pos[lead] if lead < h.count() else s0
		var c := _ahead(p, 11.0 - 3.0 * k)
		_shake = maxf(_shake, 0.05)
		_look(Vector3(c.x, _ground(c) + 1.3, c.y), Vector3(p.x, _ground(p) + 1.1, p.y)))

	# --- 12–14 с: «ТЫСЯЧИ.» — весь лес сверху, потоки орды ----------------------------------
	_flash_now(0.8)
	_sim(4.0)
	await _until(14.0, func(k: float, _t: float) -> void:
		_look(Vector3(-20.0 + 30.0 * k, 95.0 - 8.0 * k, GATE_Z + 30.0 - 20.0 * k), Vector3(0.0, 0.0, -25.0)))

	# --- 14–18 с: мушкетон от первого лица, первый взрыв — в замедлении -----------------------
	_sim(75.0)
	await _first_person(0)
	var musket: Node3D = scene.weapons[0]
	musket.reload_time = 0.42
	musket.clip = 99
	var aim_i := [_densest(10, 70)]
	await _until(18.0, func(_k: float, t: float) -> void:
		if aim_i[0] < 0 or aim_i[0] >= h.count() or int(t * FPS) % 15 == 0:
			aim_i[0] = _densest(10, 70)
		_aim_player(h.position_of(aim_i[0]) if aim_i[0] >= 0 else Vector3(0, 0, 40))
		if t > 0.15 and musket._reload == 0.0:
			musket.fire()
		Engine.time_scale = 0.3 if t > 0.55 and t < 1.6 else 1.0)
	Engine.time_scale = 1.0

	# --- 18–22 с: пулемёт III крупно; дальше все турели на площадках ------------------------
	_cinematic()
	_build_turrets()
	var g: Node3D = _busiest_turret("gatling", 26.0)
	await _until(22.0, func(k: float, _t: float) -> void:
		var head: Node3D = g._head
		var fwd := -head.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized().rotated(Vector3.UP, 0.5 - 0.6 * k)
		var base: Vector3 = g.global_position
		_look(base - fwd * 3.6 + Vector3(0, 2.4, 0) + fwd.cross(Vector3.UP) * 1.2, base + fwd * 14.0 + Vector3(0, 0.6, 0)))
	_flash_now(0.35)

	# --- 22–24 с: лазер режет толпу — сбоку ----------------------------------------------------
	var l: Node3D = _busiest_turret("laser", 28.0)
	await _until(24.0, func(k: float, _t: float) -> void:
		var fwd := -(l._head as Node3D).global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		var base: Vector3 = l.global_position
		var mid := base + fwd * 9.0
		_look(mid + side * (9.0 - 2.0 * k) + Vector3(0, 3.0, 0) - fwd * 2.0, mid + Vector3(0, 0.6, 0)))

	# --- 24–26 с: мортиры накрывают толпу — общий план сверху, взрывы в такт ------------------
	var crowd := _densest(15, 120)
	var cp: Vector3 = h.position_of(crowd) if crowd >= 0 else Vector3(0, 0, 40)
	await _until(26.0, func(k: float, t: float) -> void:
		if int(t * FPS) % 9 == 0:
			var i := _densest(10, 140)
			if i >= 0:
				_boom(h.position_of(i) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
		_look(cp + Vector3(-22.0 + 6.0 * k, 20.0, 18.0), cp))

	# --- 26–28 с: гравипушка — чёрная дыра засасывает толпу ----------------------------------
	await _first_person(2)
	var grav: Node3D = scene.weapons[2]
	var hole_at := _densest(20, 80)
	await _until(28.0, func(_k: float, t: float) -> void:
		if hole_at >= 0 and hole_at < h.count():
			_aim_player(h.position_of(hole_at))
		if t > 0.1 and t < 0.15 and grav.charges > 0:
			grav.fire())

	# --- 28–30 с: миниган — веер трассеров -------------------------------------------------------
	await _first_person(3)
	var mini: Node3D = scene.weapons[3]
	mini._spin = 1.0
	mini.clip = 999
	var a_i := _densest(10, 60)
	var b_i := _densest(30, 110)
	var pa: Vector3 = h.position_of(a_i) if a_i >= 0 else Vector3(-10, 0, 50)
	var pb: Vector3 = h.position_of(b_i) if b_i >= 0 else Vector3(10, 0, 30)
	await _until(30.0, func(k: float, _t: float) -> void:
		mini.force_fire = true
		_aim_player(pa.lerp(pb, 0.5 - 0.5 * cos(k * PI * 2.0))))
	mini.force_fire = false

	# --- 30–32 с: «УДЕРЖИ ВОРОТА.» — из-за ворот: все турели палят ----------------------------
	_cinematic()
	_flash_now(0.7)
	_sim(3.0, true)
	await _until(32.0, func(k: float, t: float) -> void:
		if int(t * FPS) % 12 == 0:
			var i := _densest(5, 80)
			if i >= 0:
				_boom(h.position_of(i))
		_look(Vector3(8.0 - 4.0 * k, 16.0 + 4.0 * k, GATE_Z + 16.0 - 4.0 * k), Vector3(0.0, 0.0, GATE_Z - 45.0)))

	# --- 32–38 с: монтаж локаций, по секунде ----------------------------------------------------
	var montage := [[1, true], [5, false], [6, true], [7, false], [8, true], [9, false]]
	for m in montage.size():
		var level_i: int = montage[m][0]
		var high: bool = montage[m][1]
		_flash_now(1.0)
		await _load_level(level_i)
		h = scene.horde
		h.mix = PackedFloat32Array([0.6, 0.3, 0.1])
		h.armor_share = 0.4
		h.send_wave(5000, 220.0)
		_sim(16.0)
		var c_i := _densest(25, 220)
		var c0: Vector2 = h._pos[c_i] if c_i >= 0 else Vector2(0, 0)
		var fdir := (_ahead(c0, 12.0) - c0).normalized()
		var side := Vector2(-fdir.y, fdir.x)
		var end_s := 33.0 + m
		await _until(end_s, func(k: float, t: float) -> void:
			if int(t * FPS) % 8 == 4:
				var bi := _densest(20, 260)
				if bi >= 0:
					_boom(scene.horde.position_of(bi))
			var at := c0 + fdir * (2.0 + 4.0 * k)
			var at3 := Vector3(at.x, _ground(at), at.y)
			if high:
				var p := c0 - fdir * 14.0 + side * (10.0 - 6.0 * k)
				_look(Vector3(p.x, at3.y + 22.0 - 4.0 * k, p.y), at3)
			else:
				var p := _ahead(c0, 14.0 - 4.0 * k) + side * 2.0
				_look(Vector3(p.x, _ground(p) + 1.6, p.y), at3 + Vector3(0, 1.0, 0)))

	# --- 38–44 с: Вождь гоблинов — идёт на камеру, у ворот бьёт дубиной -------------------------
	_flash_now(1.0)
	await _load_level(0)
	h = scene.horde
	h.mix = PackedFloat32Array([0.7, 0.2, 0.1])
	h.armor_share = 0.6
	h.send_wave(9000, 160.0)
	_sim(50.0)
	h.spawn_boss(1000, 3.4)
	var start := _path_point(90)
	h._pos[h.boss_index()] = start
	h._write_buffer()
	scene.swarm_audio._horn.play()
	await _until(41.0, func(k: float, _t: float) -> void:
		var bi: int = h.boss_index()
		if bi < 0:
			return
		var p: Vector2 = h._pos[bi]
		var c := _ahead(p, 9.0 - 1.5 * k)
		_shake = maxf(_shake, 0.12 * absf(sin(k * 12.0)))
		_look(Vector3(c.x, _ground(c) + 0.7, c.y), Vector3(p.x, _ground(p) + 3.3, p.y)))
	var bi2: int = h.boss_index()
	if bi2 >= 0:
		h._pos[bi2] = Vector2(0.0, GATE_Z - 12.0)
	await _until(44.0, func(k: float, _t: float) -> void:
		var bi: int = h.boss_index()
		var p: Vector2 = h._pos[bi] if bi >= 0 else Vector2(0, GATE_Z - 8.0)
		var view: Node3D = h._boss_view
		if view and view._swing > 0.7 and view._swing < 0.76:
			_shake = 0.5
		_look(Vector3(p.x + 3.5 - 1.0 * k, _ground(p) + 1.4, p.y + 6.5), Vector3(p.x, _ground(p) + 2.6, p.y)))

	# --- 44–48 с: кульминация — всё стреляет, взрывы, камера взмывает; в конце замедление -------
	var boss_i: int = h.boss_index()
	if boss_i >= 0:
		h.kill_area(h.position_of(boss_i), 2.0, 1, "", 5000)
	_build_turrets()
	_sim(6.0)
	_sim(1.0, true)
	var musket2: Node3D = scene.weapons[0]
	musket2.reload_time = 0.3
	musket2.clip = 99
	_flash_now(0.6)
	await _until(48.0, func(k: float, t: float) -> void:
		var i := _densest(5, 90)
		if i >= 0:
			_aim_player(h.position_of(i))
			# Оружие убрано (камера трейлера) — перезарядка не идёт сама: стреляем по счёту кадров
			if int(t * FPS) % 9 == 0:
				musket2._reload = 0.0
				musket2.fire()
			if int(t * FPS) % 7 == 0:
				_boom(h.position_of(_densest(10, 140)) if _densest(10, 140) >= 0 else h.position_of(i))
		_shake = maxf(_shake, 0.15)
		Engine.time_scale = 0.35 if k > 0.78 else 1.0
		var e := _smooth(k)
		_look(Vector3(-6.0 + 10.0 * e, 9.0 + 26.0 * e, GATE_Z + 6.0 - 10.0 * e), Vector3(0.0, 0.0, GATE_Z - 40.0 - 20.0 * e)))
	Engine.time_scale = 1.0

	# --- 48–56 с: обрыв в чёрное; удар — логотип, «Скоро в Steam» -----------------------------
	_black.color.a = 1.0
	for b in _bars:
		b.visible = false
	_build_logo()
	await _until(LENGTH, func(_k: float, t: float) -> void:
		var lt := t - 0.5
		_logo.visible = lt > 0.0
		if lt > 0.0 and lt < 0.06:
			_flash_now(1.0)
		_logo.scale = Vector2.ONE * lerpf(1.18, 1.0, _smooth(clampf(lt / 0.5, 0.0, 1.0))) * (1.0 - 0.01 * lt)
		_logo_parts[0].modulate.a = clampf(lt / 0.2, 0.0, 1.0)
		_logo_parts[1].modulate.a = clampf((lt - 1.6) / 0.5, 0.0, 1.0)
		_logo_parts[2].modulate.a = clampf((lt - 3.0) / 0.5, 0.0, 1.0)
		_logo.modulate.a = clampf((LENGTH - 48.0 - 0.6 - t) / 1.2 + 0.2, 0.0, 1.0))
	quit()


# --- съёмка --------------------------------------------------------------------------------------

## Кадры до момента t_end (с начала трейлера): каждый кадр — fn(доля шота 0..1, с от начала шота).
func _until(t_end: float, fn: Callable) -> void:
	if _frame >= int(_until_s * FPS):
		quit()
		return
	var end := int(round(minf(t_end, _until_s) * FPS))
	var n := maxi(end - _frame, 1)
	for k in n:
		fn.call(float(k) / n, float(k) / FPS)
		_hide_hud()
		_update_overlay()
		await process_frame
		_frame += 1
	if _frame >= int(_until_s * FPS):
		quit()


## Загрузить локацию (кадр закрыт вспышкой или чернотой).
func _load_level(index: int) -> void:
	if scene:
		root.remove_child(scene)
		scene.queue_free()
	Engine.time_scale = 1.0
	_main_script.current_level = index
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene.waves.coins = 1000000
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 900.0
	scene.add_child(cam)
	_cinematic()
	# Два кадра на физику и отложенную настройку сцены — под вспышкой
	for k in 2:
		_hide_hud()
		_update_overlay()
		await process_frame
		_frame += 1
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, -80.0)


func _hide_hud() -> void:
	if not scene:
		return
	scene.hud.visible = false
	scene._hud_layer.visible = false
	scene.turrets.set_ui_visible(false)
	scene._hint_time = 0.0


## Камера трейлера (не игрока): оружие убрано.
func _cinematic() -> void:
	scene._set_overview(true)
	cam.make_current()


## От первого лица с оружием index (уже в руках, без доставания).
func _first_person(index: int) -> void:
	scene._set_overview(false)
	scene.select_weapon(index)
	var w: Node3D = scene.weapons[index]
	w._equip = 1.0


func _aim_player(at: Vector3) -> void:
	var player: CharacterBody3D = scene.player
	var c: Camera3D = player.camera
	var d := (at + Vector3(0, 0.3, 0) - c.global_position).normalized()
	player.rotation.y = atan2(-d.x, -d.z)
	player.head.rotation.x = asin(clampf(d.y, -1.0, 1.0))


func _look(from: Vector3, at: Vector3) -> void:
	_shake *= 0.9
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35
	cam.global_position = from + jitter
	if from.distance_to(at) > 0.1:
		cam.look_at(at + jitter * 0.5, Vector3.UP)
	cam.make_current()


## Прогнать орду (и турели, если with_turrets) на seconds вперёд без кадров — между склейками.
func _sim(seconds: float, with_turrets := false) -> void:
	var h: Node3D = scene.horde
	var steps := int(seconds * 30.0)
	for k in steps:
		h._tick(1.0 / 30.0)
		if with_turrets:
			for t in scene.turrets.get_children():
				if t.has_method("refresh_stats"):
					t._process(1.0 / 30.0)
	h._write_buffer()


## Все площадки — турели на высшей ступени: пулемёты, лазеры, мортиры, жаровни.
func _build_turrets() -> void:
	var turrets: Node3D = scene.turrets
	var kinds := ["gatling", "laser", "mortar", "gatling", "laser", "brazier", "gatling", "mortar"]
	for i in turrets.slot_count():
		if not turrets._slots[i]["turret"]:
			turrets.buy(i, kinds[i % kinds.size()])
		while turrets.upgrade(i):
			pass


## Турель вида kind, у которой больше всего врагов в радиусе r.
func _busiest_turret(kind: String, r: float) -> Node3D:
	var best: Node3D = null
	var best_n := -1
	for t in scene.turrets.get_children():
		if t.has_method("refresh_stats") and t.kind == kind:
			var n: int = scene.horde.count_near(t.global_position, r)
			if n > best_n:
				best_n = n
				best = t
	return best


## Взрыв (как ядро мортиры) в точке p.
func _boom(p: Vector3) -> void:
	var e := ExplosionScript.new()
	e.horde = scene.horde
	e.source = "mortar"
	e.position = p
	scene.add_child(e)
	_shake = maxf(_shake, 0.25)


# --- где орда ---------------------------------------------------------------------------------

## Враг в самой густой толпе среди тех, кому до ворот от min_steps до max_steps клеток пути.
func _densest(min_steps: int, max_steps: int) -> int:
	var h: Node3D = scene.horde
	var n: int = h.count()
	var step := maxi(1, n / 300)
	var best := -1
	var best_n := -1
	for i in range(0, n, step):
		var d: int = h._dist[_cell(h._pos[i])]
		if d < min_steps or d > max_steps:
			continue
		var c: int = h.count_near(h.position_of(i), 5.0)
		if c > best_n:
			best_n = c
			best = i
	return best


func _cell(p: Vector2) -> int:
	var h: Node3D = scene.horde
	var w: int = h._w
	return clampi(int((p.y - h._origin) / h.CELL), 0, w - 1) * w + clampi(int((p.x - h._origin) / h.CELL), 0, w - 1)


## Точка на тропе в meters вперёд (к воротам) от p.
func _ahead(p: Vector2, meters: float) -> Vector2:
	var h: Node3D = scene.horde
	var q := p
	for k in int(meters * 2.0):
		var f: Vector2 = h._flow[_cell(q)]
		if f == Vector2.ZERO:
			break
		q += f * 0.5
	return q


## Точка тропы, от которой до ворот примерно steps клеток (ближайшая к середине карты по x).
func _path_point(steps: int) -> Vector2:
	var h: Node3D = scene.horde
	var w: int = h._w
	var best := Vector2(0, GATE_Z - 30.0)
	var best_x := 1e9
	for c in h._dist.size():
		if h._dist[c] == steps:
			var p := Vector2(h._origin + (c % w + 0.5) * h.CELL, h._origin + (c / w + 0.5) * h.CELL)
			if absf(p.x) < best_x:
				best_x = absf(p.x)
				best = p
	return best


func _ground(p: Vector2) -> float:
	return scene.horde._floor_at(p)


func _smooth(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


# --- надписи, полосы, вспышки, логотип -----------------------------------------------------

func _build_overlay() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Arial"])
	sf.font_weight = 900
	_font = sf
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	root.add_child(_overlay)
	# Кинополосы 2.39:1, поверх — чернота (начало и логотип), поверх неё — вспышки
	for y in [0, 1080 - 138]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.position = Vector2(0, y)
		bar.size = Vector2(1920, 138)
		_overlay.add_child(bar)
		_bars.append(bar)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.position = Vector2.ZERO
	_black.size = Vector2(1920, 1080)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_black)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.96, 0.88, 0.0)
	_flash.position = Vector2.ZERO
	_flash.size = Vector2(1920, 1080)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_flash)
	_caption = Label.new()
	_caption.add_theme_font_override("font", _font)
	_caption.add_theme_constant_override("outline_size", 18)
	_caption.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.9))
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_caption.add_theme_constant_override("shadow_offset_y", 8)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.size = Vector2(1920, 400)
	_caption.position = Vector2(0, 340)
	_caption.pivot_offset = Vector2(960, 200)
	_overlay.add_child(_caption)


func _flash_now(strength: float) -> void:
	_flash.color.a = strength


func _update_overlay() -> void:
	var t := float(_frame) / FPS
	_flash.color.a = maxf(_flash.color.a - 0.12, 0.0)
	_caption.visible = false
	for e in _texts:
		if t >= e[0] and t <= e[1]:
			var into: float = t - e[0]
			var left: float = e[1] - t
			_caption.visible = true
			_caption.text = e[2]
			_caption.add_theme_font_size_override("font_size", e[3])
			_caption.add_theme_color_override("font_color", e[4])
			_caption.modulate.a = clampf(into / 0.18, 0.0, 1.0) * clampf(left / 0.3, 0.0, 1.0)
			_caption.scale = Vector2.ONE * (lerpf(1.25, 1.0, _smooth(clampf(into / 0.25, 0.0, 1.0))) + 0.02 * into)


func _build_logo() -> void:
	_logo = VBoxContainer.new()
	_logo.alignment = BoxContainer.ALIGNMENT_CENTER
	_logo.size = Vector2(1920, 1080)
	_logo.pivot_offset = Vector2(960, 540)
	_logo.add_theme_constant_override("separation", 10)
	_overlay.add_child(_logo)
	var top := VBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 6)
	_logo.add_child(top)
	var emblem := Control.new()
	emblem.custom_minimum_size = Vector2(230, 230)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	emblem.draw.connect(scene.menu._draw_emblem.bind(emblem))
	top.add_child(emblem)
	var title := Label.new()
	title.text = "GATEHOLD"
	title.add_theme_font_override("font", scene.menu._title_font)
	title.add_theme_font_size_override("font_size", 190)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_constant_override("outline_size", 30)
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.09, 0.03))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var sub := Label.new()
	sub.text = "Удержи ворота. Останови орду."
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 54)
	sub.add_theme_color_override("font_color", Color(1, 0.93, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 40
	_logo.add_child(gap)
	var steam := Label.new()
	steam.text = "СКОРО В STEAM"
	steam.add_theme_font_override("font", _font)
	steam.add_theme_font_size_override("font_size", 46)
	steam.add_theme_color_override("font_color", GOLD)
	steam.add_theme_constant_override("outline_size", 10)
	steam.add_theme_color_override("font_outline_color", Color(0.18, 0.09, 0.03))
	steam.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_child(steam)
	_logo_parts = [top, sub, steam]
	_logo.visible = false
