extends "res://tools/trailer/trailer.gd"
## Короткий динамичный трейлер (30 с) под нынешнюю игру: герой с ранцем, всё оружие с финалами
## веток, молот с пике, локации с новыми врагами, логотип. Камеры, надписи, вспышки и логотип —
## из trailer.gd; склейки — на ударах музыки (make_trailer2_music.py, 120 уд/мин).
## Запуск (нужно окно — это рендер):
##   Godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie <папка>/frame.png \
##     -s res://tools/trailer/trailer2.gd -- music=<music2.wav> [until=СЕКУНДЫ]
## Потом: swift tools/trailer/assemble.swift <папка> <папка>/frame.wav <трейлер.mp4>

const LENGTH2 := 30.0
const BONE := Color(1, 0.95, 0.85)
## Финалы веток для зрелища (обычные улучшения — все на максимум).
const FINALS := ["rk_nuke", "mg_fire", "fl_tornado", "lt_ball", "gv_nova", "sd_swarm", "hm_thunder"]


func _run() -> void:
	# Дерево сцены готово только со следующего кадра — до музыки, чтобы склейки не съехали
	await process_frame
	_until_s = LENGTH2
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
	load("res://core/mastery.gd").force_all = true
	progress.upgrades = {}
	for n: Dictionary in load("res://core/upgrades.gd").NODES:
		if not n.get("final", false) or n["id"] in FINALS:
			progress.upgrades[n["id"]] = n["max"]
	_main_script = load("res://core/main.gd")
	_main_script.start_in_game = true
	# Без надписей — только картинка и музыка; в конце логотип
	_texts = []
	_build_overlay()
	AudioServer.add_bus()
	var score := AudioServer.bus_count - 1
	AudioServer.set_bus_name(score, "Score")
	AudioServer.set_bus_volume_db(score, 3.0)
	AudioServer.set_bus_volume_db(0, -4.0)
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	var music := AudioStreamPlayer.new()
	music.stream = AudioStreamWAV.load_from_file(music_path)
	music.bus = "Score"
	root.add_child(music)
	music.play()

	# --- 0–5 с: из черноты — облёт над пещерой, орда льётся по долине к туннелю -------------
	_black.color.a = 1.0
	await _load_level(0)
	var h: Node3D = scene.horde
	h.send_wave(14000, 140.0)
	_sim(8.0)
	var s0: Vector2 = h._spawns[0]
	var dir := (_ahead(s0, 30.0) - s0).normalized()
	var y0 := _ground(s0)
	await _until(5.0, func(k: float, _t: float) -> void:
		_black.color.a = maxf(0.0, 1.0 - k * 5.0)
		var e := _smooth(k)
		var p := s0 - dir * (6.0 - 30.0 * e)
		var at := s0 + dir * (10.0 + 30.0 * e)
		_look(Vector3(p.x, y0 + 26.0 - 10.0 * e, p.y), Vector3(at.x, _ground(at), at.y)))

	# --- 5–6 с: у самой земли — толпа бежит на камеру, «ТЫСЯЧИ.» ----------------------------
	_sim(2.0)
	var lead := _densest(60, 400)
	await _until(6.0, func(k: float, _t: float) -> void:
		var p: Vector2 = h._pos[lead] if lead >= 0 and lead < h.count() else s0
		var c := _ahead(p, 16.0 - 4.0 * k)
		_shake = maxf(_shake, 0.06)
		_look(Vector3(c.x, _ground(c) + 2.6, c.y), Vector3(p.x, _ground(p) + 0.6, p.y)))

	# --- 6–9 с: ракетница от первого лица, ядерная ракета; первый взрыв — в замедлении -------
	_flash_now(0.9)
	_sim(70.0)
	var rockets := _weapon("Ракетница")
	rockets.reload_time = 0.3
	rockets.clip = 99
	rockets._shots = 2
	var aim := [_densest(10, 70)]
	await _until(9.0, func(_k: float, t: float) -> void:
		if aim[0] < 0 or aim[0] >= h.count() or int(t * FPS) % 12 == 0:
			aim[0] = _densest(10, 70)
		if aim[0] >= 0:
			_aim_player(h.position_of(aim[0]))
		if t > 0.1 and rockets._reload == 0.0:
			rockets.fire()
		Engine.time_scale = 0.35 if t > 0.45 and t < 1.2 else 1.0)
	Engine.time_scale = 1.0

	# --- 9–10.5 с: миниган — «Огненный шквал», веер красных трассеров ----------------------
	var mini := _weapon("Миниган")
	mini._spin = 1.0
	mini.clip = 999
	var a_i := _densest(10, 60)
	var b_i := _densest(30, 110)
	var pa: Vector3 = h.position_of(a_i) if a_i >= 0 else Vector3(-10, 0, 50)
	var pb: Vector3 = h.position_of(b_i) if b_i >= 0 else Vector3(10, 0, 30)
	mini.force_fire = true
	await _until(10.5, func(k: float, _t: float) -> void:
		_aim_player(pa.lerp(pb, 0.5 - 0.5 * cos(k * PI * 2.0))))
	mini.force_fire = false

	# --- 10.5–12 с: огнемёт и огненный торнадо ------------------------------------------------
	var flamer := _weapon("Огнемёт")
	var f_i := _densest(5, 45)
	var fp: Vector3 = h.position_of(f_i) if f_i >= 0 else Vector3(0, 0, 70)
	flamer.force_fire = true
	await _until(12.0, func(_k: float, t: float) -> void:
		_aim_player(fp)
		if t > 0.05 and t < 0.09:
			flamer._spawn_tornado(fp))
	flamer.force_fire = false

	# --- 12–13.5 с: электропушка и шаровая молния ---------------------------------------------
	var tesla := _weapon("Электропушка")
	var l_i := _densest(10, 60)
	var lp: Vector3 = h.position_of(l_i) if l_i >= 0 else Vector3(0, 0, 60)
	tesla.force_fire = true
	await _until(13.5, func(_k: float, t: float) -> void:
		_aim_player(lp)
		if t > 0.05 and t < 0.09:
			tesla._spawn_ball(lp))
	tesla.force_fire = false

	# --- 13.5–15 с: гравипушка — чёрная дыра засасывает толпу --------------------------------
	var grav := _weapon("Гравипушка")
	var g_i := _densest(20, 80)
	var gp: Vector3 = h.position_of(g_i) if g_i >= 0 else Vector3(0, 0, 50)
	await _until(15.0, func(_k: float, t: float) -> void:
		_aim_player(gp)
		grav.force_fire = t > 0.03 and t < 0.1)
	grav.force_fire = false

	# --- 15–18 с: молот грома — пике с высоты в толпу ----------------------------------------
	var hammer := _weapon("Молот")
	var player: CharacterBody3D = scene.player
	# Толпа подальше от чёрной дыры (она ещё жива) — чтобы удар и молнии было видно
	var mp := Vector3(0, 0, 60)
	var best_n := -1
	for i in range(0, h.count(), maxi(1, h.count() / 300)):
		var q: Vector3 = h.position_of(i)
		if q.distance_to(gp) < 28.0:
			continue
		var n: int = h.count_near(q, 5.0)
		if n > best_n:
			best_n = n
			mp = q
	var back: Vector3 = scene.player.global_position - mp
	back.y = 0.0
	back = back.normalized()
	player.global_position = mp + back * 5.0 + Vector3(0, 20.0, 0)
	player.velocity = Vector3.ZERO
	player.flying = true
	player.set_physics_process(true)
	var landed := [false]
	player.dive_landed.connect(func(_hgt: float) -> void:
		landed[0] = true
		_flash_now(0.7)
		_shake = 0.6, CONNECT_ONE_SHOT)
	await _until(18.0, func(_k: float, t: float) -> void:
		if not landed[0]:
			_aim_player(mp)
		else:
			player.head.rotation.x = lerpf(player.head.rotation.x, -0.3, 0.15)
		if t > 0.35 and not landed[0] and not player.diving:
			hammer.force_dive = true
		if landed[0] and t > 1.6 and hammer._attack.is_empty():
			hammer.force_fire = true)
	hammer.force_fire = false
	player.set_physics_process(false)

	# --- 18–22 с: локации — по секунде, новые враги ----------------------------------------------
	var montage := [[1, true], [3, false], [5, true], [7, false]]
	for m in montage.size():
		var level_i: int = montage[m][0]
		var high: bool = montage[m][1]
		_flash_now(1.0)
		await _load_level(level_i)
		h = scene.horde
		h.send_wave(5000, 220.0)
		_sim(18.0)
		var c_i := _densest(25, 220)
		var c0: Vector2 = h._pos[c_i] if c_i >= 0 else Vector2(0, 0)
		var fdir := (_ahead(c0, 12.0) - c0).normalized()
		var side := Vector2(-fdir.y, fdir.x)
		await _until(19.0 + m, func(k: float, t: float) -> void:
			if int(t * FPS) % 9 == 4:
				var bi := _densest(20, 260)
				if bi >= 0:
					_boom(scene.horde.position_of(bi))
			var at := c0 + fdir * (2.0 + 4.0 * k)
			var at3 := Vector3(at.x, _ground(at), at.y)
			if high:
				var p := c0 - fdir * 12.0 + side * (9.0 - 6.0 * k)
				_look(Vector3(p.x, at3.y + 16.0 - 4.0 * k, p.y), at3)
			else:
				var p := _ahead(c0, 18.0 - 4.0 * k) + side * 3.0
				_look(Vector3(p.x, _ground(p) + 3.2, p.y), at3 + Vector3(0, 0.5, 0)))

	# --- 22–24 с: «ДЕРЖИ ОБОРОНУ.» — над туннелем, ракеты и взрывы; камера взмывает ----------
	_flash_now(1.0)
	await _load_level(0)
	h = scene.horde
	h.send_wave(12000, 200.0)
	_sim(60.0)
	await _until(24.0, func(k: float, t: float) -> void:
		if int(t * FPS) % 6 == 0:
			var i := _densest(5, 90)
			if i >= 0:
				_boom(h.position_of(i) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
		_shake = maxf(_shake, 0.12)
		var e := _smooth(k)
		# Над долиной у туннеля (не в скалах): камера взмывает и отъезжает, орда — внизу
		_look(Vector3(-8.0 + 14.0 * e, 16.0 + 18.0 * e, GATE_Z - 14.0 - 10.0 * e), Vector3(0.0, 0.0, GATE_Z - 50.0 - 10.0 * e)))

	# --- 24–30 с: обрыв в чёрное; удар — логотип -------------------------------------------------
	_black.color.a = 1.0
	for b in _bars:
		b.visible = false
	_build_logo()
	_logo_parts[1].visible = false
	(_logo_parts[2] as Label).text = "COMING SOON TO STEAM"
	await _until(LENGTH2, func(_k: float, t: float) -> void:
		var lt := t - 0.4
		_logo.visible = lt > 0.0
		if lt > 0.0 and lt < 0.06:
			_flash_now(1.0)
		_logo.scale = Vector2.ONE * lerpf(1.18, 1.0, _smooth(clampf(lt / 0.5, 0.0, 1.0))) * (1.0 - 0.01 * lt)
		_logo_parts[0].modulate.a = clampf(lt / 0.2, 0.0, 1.0)
		_logo_parts[2].modulate.a = clampf((lt - 1.4) / 0.5, 0.0, 1.0)
		_logo.modulate.a = clampf((LENGTH2 - 24.0 - 0.4 - t) / 1.0 + 0.2, 0.0, 1.0))
	quit()


## Загрузка локации: сразу в бой (а не в главное меню), клавиатура игре не нужна — нажатия
## (если окно рендера в фокусе) не откроют паузу или прокачку посреди съёмки.
func _load_level(index: int) -> void:
	_main_script.start_in_game = true
	await super(index)
	scene.set_process_unhandled_input(false)
	scene.menu.close()
	scene.get_tree().paused = false


## Оружие по имени — от первого лица, сразу в руках; возвращает его.
func _weapon(name: String) -> Node3D:
	var idx := 0
	for i in scene.weapons.size():
		if scene.weapons[i].display_name == name:
			idx = i
	_first_person(idx)
	return scene.weapons[idx]
