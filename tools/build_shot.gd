extends SceneTree
## Снимки свободной стройки: призрак турели (можно — зелёный, с кругом дальности), нельзя —
## красный с причиной, ловушки на дне канала, бой с поставленным сверху.
## Запуск: Godot --path . -s res://tools/build_shot.gd -- out_dir=/путь

var _out := "user://build_shot"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	load("res://core/progress.gd").read_only = true
	load("res://core/mastery.gd").force_all = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(20)
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene._hint_time = 0.0
	var turrets: Node3D = scene.turrets
	print("карточки: ", turrets.items)
	scene.set_building(true)
	var spots: Array[Vector3] = turrets.suggestions("gatling", 4)
	print("места: ", spots)
	# 1. Призрак пулемёта на хорошем месте
	turrets.choice = turrets.items.find("gatling")
	_aim(player, spots[0])
	await _frames(4)
	print("1: ", turrets._ghost_why)
	await _shot("b1_ghost_ok")
	# Сверху: сектор огня призрака должен смотреть на канал впереди
	var f: float = turrets.facing_at(spots[0], false)
	print("сектор: поворот %.2f рад, направление %s" % [f, Vector3(0, 0, -1).rotated(Vector3.UP, f)])
	scene.view_from(spots[0] + Vector3(0, 55, 0.5), spots[0])
	await _frames(3)
	await _shot("b1_top")
	scene._set_overview(false)
	await _frames(2)
	# Поставить: пулемёты, мортиру и ловушки
	turrets.place("gatling", spots[0])
	turrets.place("gatling", spots[1])
	turrets.place("laser", spots[2])
	for kind in ["spikes", "spikes", "tar"]:
		var t: Array[Vector3] = turrets.suggestions(kind, 1)
		if not t.is_empty():
			turrets.place(kind, t[0])
	print("стоит: турелей %d, ловушек %d" % [turrets.turret_count(), turrets._traps.size()])
	# 2. Вторая лазер без монет — нельзя
	turrets.choice = turrets.items.find("laser")
	# Лазер из запаса уже стоит, на вторую монет нет
	var bad := spots[3]
	for c: Vector3 in turrets.suggestions("gatling", 6):
		if c.x < 0.0:
			bad = c
			break
	_aim(player, bad)
	await _frames(4)
	print("2: ", turrets._ghost_why, " | hover ", turrets._hover, " trap ", turrets._hover_trap, " ghost ",
		turrets._ghost.visible if turrets._ghost else null, " at ", turrets._ghost_pos, " item ", turrets.items[turrets.choice],
		" left ", turrets.stock_left("laser"), " coins ", scene.waves.coins, " check ", turrets.check("laser", spots[3]))
	await _shot("b2_ghost_bad")
	# 3. Шипы на дно канала — призрак ловушки
	turrets.choice = turrets.items.find("spikes")
	var trap_spot: Array[Vector3] = turrets.suggestions("spikes", 1)
	if not trap_spot.is_empty():
		_aim(player, trap_spot[0])
	await _frames(4)
	print("3: ", turrets._ghost_why)
	await _shot("b3_trap_ghost")
	# 4. Улучшение: прицел на поставленный пулемёт
	scene.waves.coins = 1000
	_aim(player, spots[0] + Vector3(0, 0.9, 0))
	await _frames(4)
	await _shot("b4_hover_turret")
	scene.set_building(false)
	# Ловушки крупно, до волны
	for trap: Dictionary in turrets._traps:
		if trap["kind"] == "spikes":
			var c: Vector3 = trap["pos"]
			scene.view_from(c + Vector3(4.5, 4.0, 5.5), c)
			await _seconds(0.4)
			await _shot("b6_spikes_close")
			break
	for trap: Dictionary in turrets._traps:
		if trap["kind"] == "tar":
			var c: Vector3 = trap["pos"]
			scene.view_from(c + Vector3(5.0, 4.5, 6.0), c)
			await _seconds(0.4)
			await _shot("b7_tar_close")
			break
	# 5. Бой: ловушки и турели в деле
	scene.waves.start()
	var horde: Node3D = scene.horde
	for k in 900:
		horde._process(1.0 / 30.0)
		if k % 20 == 0:
			await process_frame
	await _seconds(4.0)
	var p: Vector3 = turrets._traps[0]["pos"] if not turrets._traps.is_empty() else spots[0]
	scene.view_from(p + Vector3(9, 9, 12), p)
	await _seconds(0.6)
	await _shot("b5_traps_battle")
	print("убито шипами: ", horde.kills_by.get("spikes", 0), ", всего ", horde.kills)
	quit()


func _aim(player: Node3D, at: Vector3) -> void:
	var cam: Camera3D = player.camera
	var dir := (at - cam.global_position).normalized()
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = asin(dir.y)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
