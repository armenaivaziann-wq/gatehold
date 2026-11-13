extends SceneTree
## Гоблины крупно: локация 1, волна идёт по тропам; снимки толпы вблизи, трупов после взрыва,
## лагеря-«пещеры» и вида со стены.
## Запуск: Godot --path . -s res://tools/goblin_test.gd -- out_dir=/путь

var _out := "user://goblin_test"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var main_script: GDScript = load("res://core/main.gd")
	main_script.current_level = 0
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
	player.set_physics_process(false)
	var horde: Node3D = scene.horde
	print("монстр: ", horde.monster, ", счётчик: ", scene.hud.enemies)
	scene.waves.start()
	for k in 1500:
		horde._process(1.0 / 30.0)
		if k % 60 == 0:
			await process_frame
		if horde.reached > 5:
			break
	print("на карте ", horde.count(), ", дошло ", horde.reached)
	await _frames(6)
	await _shot("g1_wall")
	# Ближайший к середине карты гоблин — смотрим на толпу вблизи
	var best := -1
	var best_d := 1e9
	for i in horde.count():
		var p: Vector3 = horde.position_of(i)
		var d := p.distance_to(Vector3(0, 0, 40))
		if d < best_d:
			best_d = d
			best = i
	var at: Vector3 = horde.position_of(best)
	var vel: Vector3 = horde.velocity_of(best)
	var fwd := vel.normalized() if vel.length() > 0.1 else Vector3(0, 0, 1)
	scene.view_from(at + fwd * 4.5 + Vector3(1.5, 1.6, 0), at + Vector3(0, 0.6, 0))
	await _frames(3)
	await _shot("g2_close")
	horde.kill_area(at + fwd * 2.0, 3.0, 12)
	for k in 20:
		horde._process(1.0 / 30.0)
	await _frames(3)
	await _shot("g3_corpses")
	var cave: Array = scene._map.caves()[0]
	var c0: Vector2 = cave[0]
	var c1: Vector2 = cave[1]
	var d2 := (c1 - c0).normalized()
	var eye := c0 + d2 * 16.0
	scene.view_from(Vector3(eye.x + 4, 6, eye.y), Vector3(c0.x, 2, c0.y))
	await _frames(3)
	await _shot("g4_camp")
	scene.view_from(Vector3(0, 120, 140), Vector3(0, 0, -5))
	await _frames(3)
	await _shot("g5_top")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
