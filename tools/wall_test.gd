extends SceneTree
## Стена ворот: вид с бортика вниз на орду у ворот, обычный вид вперёд, вид на стену снаружи.
## Проверяет, что со стены нельзя упасть: игрока толкают назад, вперёд и вбок с прыжками.
## Запуск: Godot --path . -s res://tools/wall_test.gd -- out_dir=/путь [level=7]

var _out := "user://wall_test"
var _level := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("level="):
			_level = int(arg.trim_prefix("level=")) - 1
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
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
	# Упасть со стены: жмём в каждую сторону по две секунды с прыжками
	var y0 := player.global_position.y
	for dir in [["move_back", "назад"], ["move_forward", "вперёд"], ["move_left", "влево"], ["move_right", "вправо"]]:
		player.respawn()
		Input.action_press(dir[0])
		var lowest := y0
		for k in 120:
			if k % 20 == 0:
				Input.action_press("jump")
			elif k % 20 == 2:
				Input.action_release("jump")
			await physics_frame
			lowest = minf(lowest, player.global_position.y)
		Input.action_release(dir[0])
		print("%s: игрок в %s, ниже старта на %.2f м" % [dir[1], player.global_position, y0 - lowest])
	player.respawn()
	player.set_physics_process(false)
	var horde: Node3D = scene.horde
	scene.waves.start()
	for k in 1800:
		horde._process(1.0 / 30.0)
		if k % 60 == 0:
			await process_frame
		if horde.reached > 20:
			break
	print("дошло до ворот: ", horde.reached, ", на карте ", horde.count())
	await _frames(4)
	await _shot("w1_forward")
	# К самому бортику и взгляд вниз
	player.global_position.z = 99.0
	player.head.rotation.x = -0.95
	await _frames(4)
	await _shot("w2_down")
	scene.view_from(Vector3(14, 9, 84), Vector3(0, 3, 99))
	await _frames(4)
	await _shot("w3_outside")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
