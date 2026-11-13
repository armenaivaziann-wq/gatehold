extends SceneTree
## Снимок вкладки «Турели и ловушки» общего древа: как у игрока после нескольких боёв (в памяти,
## ничего не сохраняется). Запуск: Godot --path . -s res://tools/tree_shot.gd -- out_dir=/путь

var _out := "user://tree_shot"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = false
	var progress: GDScript = load("res://core/progress.gd")
	progress.read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _seconds(2.0)
	progress.stars = {0: 3, 1: 2, 2: 2}
	progress.best = {0: 500, 1: 320, 2: 260}
	progress.unlocked = 4
	progress.trophies = 640
	progress.crystals = 5
	progress.upgrades = {"stock_gatling": 2, "stock_spikes": 1, "bulk": 1, "stock_laser": 1}
	scene.menu.show_page("upgrades")
	await _frames(3)
	scene.menu._tree._select_tab(3)
	await _frames(3)
	scene.menu._tree._set_hover("s:stock_tar")
	await _frames(2)
	await _shot("tree_turrets")
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
