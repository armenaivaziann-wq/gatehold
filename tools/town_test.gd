extends SceneTree
## Снимки базы за воротами: со стены назад, сверху, двор.
## Запуск: Godot --path . -s res://tools/town_test.gd -- out_dir=/путь

var _out := "user://town_test"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	var t0 := Time.get_ticks_msec()
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	print("сцена с городом: %d мс" % (Time.get_ticks_msec() - t0))
	await _frames(20)
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene._hint_time = 0.0
	# Со стены назад, на город
	player.rotation.y = PI
	player.head.rotation.x = -0.12
	await _frames(5)
	await _shot("c1_wall_back")
	scene.view_from(Vector3(0, 60, 70), Vector3(0, 0, 125))
	await _frames(4)
	await _shot("c2_top")
	scene.view_from(Vector3(14, 6, 140), Vector3(-6, 1, 118))
	await _frames(4)
	await _shot("c3_yard")
	player.camera.make_current()
	scene._set_overview(false)
	player.rotation.y = PI
	await create_timer(3.0).timeout
	print("FPS со стены на город: ", Engine.get_frames_per_second())
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
