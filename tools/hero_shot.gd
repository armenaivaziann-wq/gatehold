extends SceneTree
## Снимки героя с реактивным ранцем: со стены на вышки с турелями, полёт над ордой с ракетами,
## умения (залп, тесла, лёд, напалм), низкий полёт под копьями. Печатает здоровье и убитых.
## Запуск: Godot --path . -s res://tools/hero_shot.gd -- out_dir=/путь

var _out := "user://hero_shot"


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
	var horde: Node3D = scene.horde
	# Турели на вышках у каналов
	for kind in ["gatling", "gatling", "laser", "laser", "gatling"]:
		var spots: Array[Vector3] = turrets.suggestions(kind, 1)
		if not spots.is_empty():
			turrets.place(kind, spots[0])
	print("турелей: ", turrets.turret_count())
	# 1. Со стены: вышки с турелями
	_aim(player, Vector3(0, 2, 70))
	await _frames(5)
	await _shot("h1_wall")
	if "only_wall=1" in OS.get_cmdline_user_args():
		quit()
		return
	# Волна идёт: орда растекается по каналам
	scene.waves.start()
	for k in 700:
		horde._process(1.0 / 30.0)
		if k % 25 == 0:
			await process_frame
	# 2. Полёт над ордой: встаём над самой густой толпой и бьём ракетами
	var crowd := _crowd(horde)
	print("толпа у ", crowd, ", рядом ", horde.count_near(crowd, 12.0))
	player.flying = true
	player.global_position = crowd + Vector3(9.0, 16.0, 18.0)
	_aim(player, crowd)
	await _frames(3)
	var gun: Node3D = scene.weapons[0]
	gun._equip = 1.0
	gun.fire()
	await _seconds(0.25)
	await _shot("h2_rocket")
	await _seconds(0.5)
	await _shot("h3_boom")
	# 3. Умения: тесла, потом залп
	scene.abilities.use(1)
	await _frames(2)
	await _shot("h4_tesla")
	await _seconds(0.5)
	_aim(player, _crowd(horde))
	scene.abilities.use(0)
	await _seconds(0.45)
	await _shot("h5_salvo")
	# 4. Лёд и напалм
	await _seconds(0.8)
	var c2 := _crowd(horde)
	_aim(player, c2)
	scene.abilities.use(2)
	await _seconds(0.8)
	await _shot("h6_frost")
	scene.abilities.use(3)
	await _seconds(0.7)
	await _shot("h7_napalm")
	# 5. Низко над толпой — копья
	var c3 := _crowd(horde)
	player.global_position = c3 + Vector3(0.0, 5.0, 4.0)
	_aim(player, c3 + Vector3(0, 0, -20))
	var hp0: float = player.hp
	await _seconds(3.0)
	await _shot("h8_low")
	print("здоровье: %d → %d, уровень %d, убито %d" % [hp0, player.hp, player.level, horde.kills])
	print("по источникам: ", horde.kills_by)
	quit()


## Самое густое место орды ближе к воротам.
func _crowd(horde: Node3D) -> Vector3:
	var best := Vector3(0, 0, 60)
	var best_n := -1
	for k in 40:
		var i := randi() % maxi(horde.count(), 1)
		if horde.count() == 0:
			break
		var p: Vector3 = horde.position_of(i)
		var n: int = horde.count_near(p, 10.0)
		if n > best_n:
			best_n = n
			best = p
	return best


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
