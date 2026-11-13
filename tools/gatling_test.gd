extends SceneTree
## Пулемёт крупно во время стрельбы: ставим на площадку у канала, ждём, пока раскрутится,
## снимаем сбоку и со стены. Печатает, сколько жуков он убил.
## Запуск: Godot --path . -s res://tools/gatling_test.gd -- out_dir=/путь

var _out := "user://gatling_test"


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
	scene.waves.coins = 1000
	turrets.buy(5, "gatling")
	var gun: Node3D = turrets._slots[5]["turret"]
	scene.waves.start()
	var horde: Node3D = scene.horde
	# Ждём, пока жуки подойдут и пулемёт раскрутится
	for k in 1800:
		horde._process(1.0 / 30.0)
		if k % 30 == 0:
			await process_frame
		if k > 300 and horde.pick_target(gun.global_position, 26.0) >= 0:
			break
	var kills0: int = horde.kills
	print("жуков на карте ", horde.count(), ", дошло ", horde.reached, ", пулемёт в ", gun.global_position, ", ближняя цель ", horde.pick_target(gun.global_position, 30.0))
	for k in 5:
		await create_timer(0.3).timeout
		print("цель ", gun._target, " есть ", gun._has_aim, " голова ", gun._head.rotation.y, " раскрутка ", gun._spin, " ствол ", gun._gun.rotation.x if gun._gun else "нет", " обрабатывается ", gun.is_processing())
	for k in 240:
		await process_frame
		if gun._spin >= 1.0 and gun._flash.visible:
			break
	var p: Vector3 = gun.global_position
	var fwd: Vector3 = -gun._head.global_basis.z
	var right: Vector3 = gun._head.global_basis.x
	scene.view_from(p + right * 3.2 - fwd * 1.0 + Vector3(0, 2.4, 0), p + fwd * 3.0 + Vector3(0, 1.6, 0))
	for k in 30:
		await process_frame
		if gun._flash.visible:
			break
	await _shot("g1_side")
	scene.view_from(p - fwd * 4.0 + right * 1.2 + Vector3(0, 3.2, 0), p + fwd * 12.0)
	for k in 30:
		await process_frame
		if gun._flash.visible:
			break
	await _shot("g2_behind")
	await create_timer(2.0).timeout
	print("пулемёт убил за ~2.5 с: ", horde.kills - kills0, ", раскрутка ", gun._spin)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
