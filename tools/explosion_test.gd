extends SceneTree
## Взрыв крупным планом: кадры через 0.05, 0.2, 0.45, 1.0 и 3 секунды.
## Запуск: Godot --path . -s res://tools/explosion_test.gd -- out_dir=/путь

const ExplosionScript := preload("res://effects/explosion.gd")

var _out := "user://explosion_test"


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
	scene._hint_time = 0.0
	var at := Vector3(0, 0.0, 84)
	scene.view_from(at + Vector3(-9, 6, 12), at + Vector3(0, 1.5, 0))
	await _frames(5)
	var boom := ExplosionScript.new()
	boom.position = at
	scene.add_child(boom)
	var t0 := Time.get_ticks_msec()
	for stamp in [0.05, 0.2, 0.45, 1.0, 3.0]:
		while (Time.get_ticks_msec() - t0) / 1000.0 < stamp:
			await process_frame
		await _shot("boom_%.2f" % stamp)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
