extends SceneTree
## Снимки оружия в игре: в покое, в момент выстрела, после выстрела (трупики), перезарядка.
## Запуск: Godot --path . -s res://tools/weapon_test.gd -- out_dir=/путь

var _out := "user://weapon_test"
var _prewarm := 1700


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("prewarm="):
			_prewarm = int(arg.trim_prefix("prewarm="))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	var horde: Node3D = scene.horde
	var player: CharacterBody3D = scene.player
	# Случайные клики и клавиши в окне теста не должны двигать игрока и стрелять
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	# Прогон: жуки доходят почти до ворот (кадры не держим подолгу)
	for k in _prewarm:
		if horde.count() < 5000:
			for j in 10:
				horde._spawn()
		horde._step(1.0 / 30.0)
		if k % 20 == 0:
			await process_frame
	# Смотрим на широкий канал перед воротами
	var cam: Camera3D = player.camera
	var target := Vector3(-12, 0.3, 82)
	var dir := (target - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	scene._hint_time = 0.0
	# Цель — самый густой поток жуков перед камерой (ближе 30 м)
	var best := Vector3(-12, 0.3, 82)
	var best_n := 0
	for gx in range(-30, 31, 4):
		for gz in range(60, 96, 4):
			var n := 0
			for i in horde.count():
				if horde._pos[i].distance_to(Vector2(gx, gz)) < 4.0:
					n += 1
			if n > best_n:
				best_n = n
				best = Vector3(gx, 0.3, gz)
	print("цель ", best, " жуков рядом: ", best_n, " игрок: ", player.global_position, " убито до выстрела: ", horde.kills)
	dir = (best - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y) + 0.12
	await _frames(20)
	await _shot("w1_idle")
	player.head.rotation.x -= 0.12
	await _frames(1)
	var aimed: Vector3 = scene.gun._aim()["point"]
	scene.gun.fire()
	await _shot("w2_fire")
	# Снаряд в полёте и взрыв (тест идёт медленно — снимаем по таймеру с запасом)
	await _seconds(0.25)
	await _shot("w3_flight")
	var kills0: int = horde.kills
	for k in 60:
		await process_frame
		if horde.kills > kills0:
			break
	await _frames(1)
	for node in scene.get_children():
		if node.get_script() == preload("res://effects/explosion.gd"):
			print("метка: ", aimed, " взрыв: ", node.global_position, " промах: %.3f м" % aimed.distance_to(node.global_position))
	await _shot("w4_explosion")
	await _seconds(0.35)
	await _shot("w5_fireball")
	await _seconds(1.0)
	print("убито: ", horde.kills)
	await _shot("w6_smoke")
	# Метка зоны взрыва вблизи: прицел на ближний поток (15–30 м от стены)
	var near_best := Vector3(0, 0.3, 85)
	var near_n := 0
	for gx in range(-20, 21, 2):
		for gz in range(78, 94, 2):
			var n := 0
			for i in horde.count():
				if horde._pos[i].distance_to(Vector2(gx, gz)) < 4.0:
					n += 1
			if n > near_n:
				near_n = n
				near_best = Vector3(gx, 0.3, gz)
	dir = (near_best - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	await _frames(6)
	await _shot("w8_marker")
	var hit: Vector3 = horde.last_hit
	print("попадание: ", hit)
	scene.view_from(hit + Vector3(-6, 6, 8), hit)
	await _frames(4)
	await _shot("w7_crater")
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
