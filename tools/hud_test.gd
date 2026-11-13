extends SceneTree
## Снимки интерфейса: перед первой волной, в бою (после выстрела, ворота побиты), поражение.
## Запуск: Godot --path . -s res://tools/hud_test.gd -- out_dir=/путь

var _out := "user://hud_test"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(20)
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene._hint_time = 0.0
	await _frames(5)
	await _shot("h1_ready")
	# Волна 1: жуки идут, часть доходит до ворот
	scene.waves.start()
	var horde: Node3D = scene.horde
	for k in 1400:
		horde._process(1.0 / 30.0)
		if k % 20 == 0:
			await process_frame
	var cam: Camera3D = player.camera
	var dir := (Vector3(8, 0.3, 75) - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	scene.gun.fire()
	await _seconds(1.0)
	print("ворота: ", scene.waves.gate_hp, " монеты: ", scene.waves.coins, " заряды: ", scene.gun.clip, "/", scene.gun.reserve)
	await _shot("h2_battle")
	scene.waves.gate_hp = 30
	scene.waves.gate_hit.emit(10)
	await _frames(3)
	await _shot("h3_gate_hit")
	scene.waves.gate_hp = 0
	await _frames(5)
	await _shot("h4_lost")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
