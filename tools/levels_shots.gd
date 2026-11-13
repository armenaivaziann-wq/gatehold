extends SceneTree
## Все локации подряд: для каждой — время постройки, пещеры (дойдут ли жуки до ворот),
## площадки турелей, снимки сверху и со стены с идущим роем.
## Запуск: Godot --path . -s res://tools/levels_shots.gd -- out_dir=/путь [only=3]

const Levels := preload("res://locations/levels.gd")

var _out := "user://levels_shots"
var _only := -1


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("only="):
			_only = int(arg.trim_prefix("only=")) - 1
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var main_script: GDScript = load("res://core/main.gd")
	for i in Levels.count():
		if _only >= 0 and i != _only:
			continue
		main_script.current_level = i
		main_script.start_in_game = true
		var t0 := Time.get_ticks_msec()
		# Снимки и проверки не пишут прогресс игрока на диск
		load("res://core/progress.gd").read_only = true
		var scene: Node3D = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		var horde: Node3D = scene.horde
		var reach := []
		for s in horde._spawns:
			var c: int = clampi(int((s.y - horde._origin) / horde.CELL), 0, horde._w - 1) * horde._w + clampi(int((s.x - horde._origin) / horde.CELL), 0, horde._w - 1)
			reach.append(horde._dist[c])
		print("%d «%s»: %d мс, пещер %d, шагов от пещер до ворот %s, площадок %d" % [i + 1, Levels.get_level(i)["name"],
			Time.get_ticks_msec() - t0, horde._spawns.size(), reach, scene.turrets.slot_count()])
		var player: CharacterBody3D = scene.player
		player.set_process_unhandled_input(false)
		player.set_physics_process(false)
		scene._hint_time = 0.0
		scene.waves.start()
		for k in 900:
			horde._process(1.0 / 30.0)
			if k % 60 == 0:
				await process_frame
		await _frames(6)
		await _shot("L%02d_wall" % (i + 1))
		scene.view_from(Vector3(0, 175, 150), Vector3(0, 0, -10))
		await _frames(4)
		await _shot("L%02d_top" % (i + 1))
		scene.queue_free()
		await _frames(3)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
