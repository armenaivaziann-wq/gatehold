extends SceneTree
## Замер производительности: большая волна на локации, все площадки с пулемётами, вид со стены.
## Печатает FPS, время кадра, сколько из него уходит на орду (шаг и буфер), треугольники и
## вызовы отрисовки. Вертикальная синхронизация выключена — FPS не упирается в монитор.
## Запуск: Godot --path . -s res://tools/perf_test.gd -- [level=1] [units=3000] [seconds=6]

var _level := 0
var _units := 3000
var _seconds := 6.0


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			_level = int(arg.trim_prefix("level=")) - 1
		elif arg.begins_with("units="):
			_units = int(arg.trim_prefix("units="))
		elif arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main_script: GDScript = load("res://core/main.gd")
	main_script.current_level = _level
	main_script.start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(10)
	scene._hint_time = 0.0
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	var horde: Node3D = scene.horde
	# Орду набираем без отрисовки: волна (чтобы турели стреляли) плюс сколько надо сверху
	# Поток на минуту с лишним: к замеру орда тянется от пещер до самых ворот
	# Ворота бессмертны: без обороны орда иначе прорывается и замер идёт по пустой карте
	scene.waves.gate_max = 1000000000
	scene.waves.gate_hp = 1000000000
	load("res://core/mastery.gd").force_all = true
	scene.waves.start()
	horde.send_wave(_units * 3, _units / 25.0)
	# Темп выхода держим свой (ход боя его не переписывает) — на карте тысячи сразу
	scene.waves.set_process(false)
	# Турели всех видов у каналов (в долине нет площадок на стене — ставим по подсказкам)
	scene.waves.coins = 100000
	for kind: String in ["gatling", "gatling", "freeze", "flame", "laser", "gatling", "laser", "flame"]:
		var spots: Array[Vector3] = scene.turrets.suggestions(kind, 1)
		if not spots.is_empty():
			scene.turrets.place(kind, spots[0])
	for sim in 1800:
		horde._process(1.0 / 30.0)
		if sim % 120 == 0:
			await process_frame
	scene.waves.coins = 100000
	var turrets: Node3D = scene.turrets
	for i in turrets.slot_count():
		turrets.buy(i, "gatling")
	print("локация «%s»: на карте %d, турелей %d" % [scene._map.level["name"], horde.count(), turrets.turret_count()])
	await _frames(30)
	# Время орды меряем вручную: движок её не обновляет, обновляем сами с таймером
	horde.set_process(false)
	var guns: Array[Node3D] = []
	for i in turrets.slot_count():
		var t: Node3D = turrets._slots[i]["turret"]
		if t:
			t.set_process(false)
			guns.append(t)
	var frames := 0
	var t_horde := 0
	var t_guns := 0
	var t_gpu := 0.0
	var t_cpu := 0.0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var prims := 0
	var calls := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var worst := 0
	while Time.get_ticks_usec() - t0 < int(_seconds * 1e6):
		var h0 := Time.get_ticks_usec()
		horde._process(1.0 / 60.0)
		t_horde += Time.get_ticks_usec() - h0
		var g0 := Time.get_ticks_usec()
		for g in guns:
			g._process(1.0 / 60.0)
		t_guns += Time.get_ticks_usec() - g0
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		t_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		t_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		prims += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	print("кадров %d за %.1f с: FPS %.1f, кадр %.2f мс (худший %.1f мс)" % [frames, total / 1000.0, frames / (total / 1000.0), total / frames, worst / 1000.0])
	print("турели %.2f мс/кадр, убито %d" % [t_guns / 1000.0 / frames, horde.kills])
	if not guns.is_empty():
		var g: Node3D = guns[0]
		print("пулемёт: цель %d, навёлся %s, раскрутка %.2f, в %s" % [g._target, g._has_aim, g._spin, g.global_position])
	print("орда %.2f мс/кадр, отрисовка: процессор %.2f мс, видеокарта %.2f мс, на карте %d" % [t_horde / 1000.0 / frames,
		t_cpu / frames, t_gpu / frames, horde.count()])
	print("треугольников %d, вызовов отрисовки %d" % [prims / frames, calls / frames])
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
