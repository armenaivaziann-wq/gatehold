extends SceneTree
## Скриншоты от первого лица: вид со стены вперёд, вниз на канал и прогулка по боевому ходу.
## Запуск: Godot --path . -s res://tools/fp_shots.gd -- out_dir=/путь

var _out := "user://fp_shots"


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
	await _frames(30)
	var player: CharacterBody3D = scene.player
	print("игрок стоит на высоте %.2f, на полу: %s" % [player.global_position.y, player.is_on_floor()])
	await _shot("fp_1_forward")
	player.head.rotation.x = -0.45
	player.rotation.y = 0.5
	await _frames(3)
	await _shot("fp_2_down_left")
	# Прогулка вправо по боевому ходу
	player.head.rotation.x = -0.1
	player.rotation.y = -1.2
	Input.action_press("move_forward")
	await _seconds(1.5)
	Input.action_release("move_forward")
	await _frames(10)
	print("после прогулки: ", player.global_position)
	await _shot("fp_3_walk")
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
