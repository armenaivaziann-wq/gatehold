extends SceneTree
## Скриншоты локации: общий план сверху, вид от ворот (с высоты игрока) и канал вблизи.
## Запуск: Godot --path . -s res://tools/shots.gd -- out_dir=/путь level=1..10

var _out := "user://shots"
var _palette := "level"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("level="):
			_palette = "level" + arg.trim_prefix("level=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var t0 := Time.get_ticks_msec()
	load("res://core/main.gd").start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	print("built in ", Time.get_ticks_msec() - t0, " ms")
	await _frames(30)
	scene.view_from(Vector3(0, 195, 140), Vector3.ZERO)
	await _frames(4)
	await _shot("%s_1_overview" % _palette)
	scene.view_from(Vector3(0, 230, 120), Vector3(0, 0, -5))
	await _frames(4)
	await _shot("%s_2_top" % _palette)
	scene.view_from(Vector3(0, 11.5, 102), Vector3(0, 2, 40))
	await _frames(4)
	await _shot("%s_3_gate_view" % _palette)
	scene.view_from(Vector3(-40, 14, -60), Vector3(-75, 1, -30))
	await _frames(4)
	await _shot("%s_4_channel" % _palette)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
