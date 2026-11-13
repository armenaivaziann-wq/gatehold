extends SceneTree
## Снимок экрана итогов боя: новичок на первой локации, ворота падают на 2-й волне. Прогресс
## игрока не трогает (read_only). Запуск: Godot --path . -s res://tools/summary_shot.gd -- out_dir=/путь

var _out := "user://summary_shot"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var progress: GDScript = load("res://core/progress.gd")
	progress.load_progress()
	progress.read_only = true
	progress.upgrades = {}
	progress.trophies = 45
	progress.best_progress = {0: 18}
	load("res://core/main.gd").start_in_game = true
	load("res://core/main.gd").current_level = 0
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(20)
	scene.player.set_process_unhandled_input(false)
	scene.player.set_physics_process(false)
	scene._hint_time = 0.0
	var waves: Node = scene.waves
	var horde: Node3D = scene.horde
	# Пара пулемётов на вышках — как у новичка
	for k in 2:
		var spots: Array[Vector3] = scene.turrets.suggestions("gatling", 1)
		if not spots.is_empty():
			scene.turrets.place("gatling", spots[0])
	waves.start()
	for k in 1200:
		horde._process(1.0 / 30.0)
		if k % 40 == 0:
			await process_frame
	for k in 600:
		horde._process(1.0 / 30.0)
		if k % 40 == 0:
			await process_frame
	await _shot("summary_battle")
	# Ворота пали
	waves.gate_hp = 0
	await _frames(10)
	await _shot("summary_lost")
	print("состояние ", waves.state, ", трофеев ", progress.trophies)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
