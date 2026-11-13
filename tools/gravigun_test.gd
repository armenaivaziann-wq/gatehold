extends SceneTree
## Гравипушка: в руках (вид от первого лица), полёт заряда и чёрная дыра в толпе.
## Печатает, сколько врагов затянуло. Запуск:
## Godot --path . -s res://tools/gravigun_test.gd -- out_dir=/путь [level=2]

var _out := "user://gravigun_test"
var _level := 1


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("level="):
			_level = int(arg.trim_prefix("level=")) - 1
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var main_script: GDScript = load("res://core/main.gd")
	main_script.current_level = _level
	main_script.start_in_game = true
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
	await _frames(10)
	scene._hint_time = 0.0
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	var horde: Node3D = scene.horde
	scene.select_weapon(2)
	var gun: Node3D = scene.gun
	scene.waves.start()
	horde.send_wave(1200, 120.0)
	for k in 1500:
		horde._process(1.0 / 30.0)
		if k % 60 == 0:
			await process_frame
	await _frames(30)
	print("оружие: ", gun.display_name, ", заряды ", gun.ammo_text(), ", на карте ", horde.count())
	await _shot("b1_hands")
	# Самое густое место ближе 45 м от стены: туда стреляем
	var best := Vector3.ZERO
	var best_n := -1
	for i in range(0, horde.count(), 7):
		var p: Vector3 = horde.position_of(i)
		if p.distance_to(player.global_position) > 45.0:
			continue
		var n: int = horde.count_near(p, 6.0)
		if n > best_n:
			best_n = n
			best = p
	print("цель ", best, ", рядом ", best_n)
	var hole: Node3D = load("res://effects/black_hole.gd").new()
	hole.horde = horde
	hole.target = best
	hole.has_target = true
	hole.velocity = (best - gun._muzzle.global_position).normalized() * hole.FLIGHT_SPEED
	scene.add_child(hole)
	hole.global_position = gun._muzzle.global_position
	var kills0: int = horde.kills
	for k in 12:
		await physics_frame
	await _shot("b2_flight")
	for k in 40:
		await process_frame
	await _shot("b3_wall")
	var c := hole.global_position
	scene.view_from(c + Vector3(9, 6, 9), c + Vector3(0, -0.5, 0))
	await _frames(20)
	await _shot("b4_close")
	await create_timer(1.5).timeout
	await _shot("b5_close_later")
	await create_timer(3.0).timeout
	print("затянуло: ", horde.kills - kills0, ", чёрная дыра ещё есть: ", is_instance_valid(hole))
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
