extends SceneTree
## Снимки турелей: режим строительства (площадки, карточки), турели на площадках в бою,
## каждая турель крупно во время стрельбы. Печатает, сколько жуков убили турели.
## Запуск: Godot --path . -s res://tools/turret_test.gd -- out_dir=/путь

var _out := "user://turret_test"


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
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene._hint_time = 0.0
	var turrets: Node3D = scene.turrets
	print("площадок: ", turrets.slot_count())
	for i in turrets.slot_count():
		print("  площадка ", i, " ", turrets._slots[i]["pos"])
	# Режим строительства: смотрим на дальнюю площадку плато
	scene.set_building(true)
	var cam: Camera3D = player.camera
	var look: Vector3 = turrets._slots[6]["pos"]
	var dir := (look - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	scene.waves.coins = 300
	await _frames(5)
	await _shot("t1_build")
	# Поставить всё: на площадки по очереди пулемёт, жаровня, лазер
	scene.waves.coins = 100000
	var kinds := ["gatling", "freeze", "laser"]
	for i in turrets.slot_count():
		turrets.buy(i, kinds[i % 3])
	scene.set_building(false)
	print("турелей: ", turrets.turret_count())
	# Волна идёт сама
	scene.waves.start()
	var horde: Node3D = scene.horde
	for k in 1500:
		horde._process(1.0 / 30.0)
		if k % 20 == 0:
			await process_frame
	var kills0: int = horde.kills
	await _seconds(6.0)
	print("за 6 с турели убили: ", horde.kills - kills0, " (на карте ", horde.count(), ")")
	dir = (Vector3(0, 0, 60) - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)
	await _frames(3)
	await _shot("t2_battle")
	# Каждая турель крупно
	for i in [4, 5, 6]:
		var p: Vector3 = turrets._slots[i]["pos"]
		scene.view_from(p + Vector3(5, 3.5, 6), p + Vector3(0, 1.0, -4))
		await _seconds(0.5)
		await _shot("t3_turret_%d" % i)
	scene.view_from(Vector3(0, 70, 135), Vector3(0, 0, 55))
	await _frames(4)
	await _shot("t4_top")
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
