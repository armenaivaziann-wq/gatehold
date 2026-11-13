extends SceneTree
## Проверка орды: заполняет карту жуками, меряет время шага и FPS, снимает кадры.
## Запуск: Godot --path . -s res://tools/horde_test.gd -- out_dir=/путь count=8000

var _out := "user://horde_test"
var _count := 8000


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("count="):
			_count = int(arg.trim_prefix("count="))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	print("игрок до прогона: ", scene.player.global_position)
	var horde: Node3D = scene.horde
	# Прогон симуляции без отрисовки, чтобы жуки растеклись по каналам
	for k in 2400:
		if horde.count() < _count:
			for j in 12:
				horde._spawn()
		horde._step(1.0 / 30.0)
		# Не держим кадр секундами — окно должно оставаться отзывчивым
		if k % 20 == 0:
			await process_frame
	print("жуков на карте: ", horde.count(), ", дошло: ", horde.reached)
	var t0 := Time.get_ticks_usec()
	for k in 20:
		horde._step(1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	for k in 20:
		horde._write_buffer()
	var t2 := Time.get_ticks_usec()
	print("шаг симуляции: %.2f мс, буфер: %.2f мс" % [(t1 - t0) / 20000.0, (t2 - t1) / 20000.0])
	await _seconds(2.0)
	print("FPS от первого лица: ", Engine.get_frames_per_second(), ", игрок: ", scene.player.global_position)
	await _shot("horde_1_fp")
	scene.player.head.rotation.x = -0.5
	await _frames(3)
	await _shot("horde_2_fp_down")
	scene.view_from(Vector3(0, 195, 140), Vector3.ZERO)
	await _seconds(1.5)
	print("FPS сверху: ", Engine.get_frames_per_second())
	await _shot("horde_3_top")
	scene.view_from(Vector3(-56, 7, -6), Vector3(-72, 0, -26))
	await _frames(4)
	await _shot("horde_4_close")
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
