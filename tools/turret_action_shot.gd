extends SceneTree
## Снимки турелей в бою: пулемёт, лазер и заморозка на вышках у канала, крупно, пока стреляют.
## Печатает, сколько убила каждая. Запуск: Godot --path . -s res://tools/turret_action_shot.gd -- out_dir=/путь

var _out := "user://turret_action"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	load("res://core/progress.gd").read_only = true
	load("res://core/mastery.gd").force_all = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(20)
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene._hint_time = 0.0
	var turrets: Node3D = scene.turrets
	var horde: Node3D = scene.horde
	var placed := {}
	for kind in ["gatling", "laser", "freeze", "gatling", "freeze"]:
		var spots: Array[Vector3] = turrets.suggestions(kind, 1)
		if not spots.is_empty() and turrets.place(kind, spots[0]):
			if not placed.has(kind):
				placed[kind] = spots[0]
	print("поставлено: ", placed.keys())
	scene.waves.start()
	for k in 900:
		horde._process(1.0 / 30.0)
		if k % 25 == 0:
			await process_frame
	await _seconds(3.0)
	for kind: String in placed:
		var p: Vector3 = placed[kind]
		scene.view_from(p + Vector3(6.5, 6.0, 7.5), p + Vector3(0, 3.5, -6.0))
		await _seconds(0.5)
		await _shot("a_" + kind)
	print("убили: ", horde.kills_by)
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
