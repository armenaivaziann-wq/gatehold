extends SceneTree
## Снимки огнемёта в игре: в руках, струя по потоку жуков, горящие пятна, крупный план.
## Запуск: Godot --path . -s res://tools/flame_test.gd -- out_dir=/путь

var _out := "user://flame_test"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	# Огнемёт и гравипушка — награды за локации; для проверки открываем всё (в памяти)
	var upgrades: GDScript = load("res://core/upgrades.gd")
	var progress: GDScript = load("res://core/progress.gd")
	progress.load_progress()
	for n: Dictionary in upgrades.NODES:
		progress.upgrades[n["id"]] = n["max"]
	load("res://core/mastery.gd").force_all = true
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
	var horde: Node3D = scene.horde
	for k in 1500:
		if horde.count() < 4000:
			for j in 10:
				horde._spawn()
		horde._step(1.0 / 30.0)
		if k % 20 == 0:
			await process_frame
	scene.select_weapon(1)
	# Цель — густой поток жуков в 10–18 м от стены
	var cam: Camera3D = player.camera
	var best := Vector3(0, 0.3, 88)
	var best_n := 0
	for gx in range(-16, 17, 2):
		for gz in range(78, 95, 2):
			var n := 0
			for i in horde.count():
				if horde._pos[i].distance_to(Vector2(gx, gz)) < 3.0:
					n += 1
			if n > best_n:
				best_n = n
				best = Vector3(gx, 0.3, gz)
	print("цель ", best, " жуков рядом: ", best_n)
	var dir := (best - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	await _seconds(0.6)
	await _shot("f1_idle")
	var flame: Node3D = scene.gun
	var kills0: int = horde.kills
	flame.force_fire = true
	await _seconds(0.35)
	await _shot("f2_stream")
	await _seconds(0.6)
	# Струя сбоку: отдельная камера, игрок продолжает жечь
	var side := Camera3D.new()
	side.fov = 55.0
	scene.add_child(side)
	var mid: Vector3 = (player.camera.global_position + best) / 2.0
	side.look_at_from_position(mid + Vector3(-14, 5, -4), mid, Vector3.UP)
	side.make_current()
	await _frames(3)
	await _shot("f3b_side")
	player.camera.make_current()
	side.queue_free()
	await _seconds(0.6)
	await _shot("f3_burning")
	flame.force_fire = false
	print("сожжено: ", horde.kills - kills0, " топливо: ", flame.fuel, " пятен: ", flame._patches.size())
	for p in flame._patches:
		print("  пятно ", p.global_position)
	print("  прицел ", flame._aim())
	await _seconds(0.6)
	await _shot("f4_patches")
	scene.view_from(best + Vector3(-7, 6, 8), best)
	await _frames(4)
	await _shot("f5_closeup")
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
