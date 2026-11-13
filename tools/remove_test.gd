extends SceneTree
## Проверка: мортиру убирают, пока её ядро в полёте, — ошибок нет, ядро долетает и исчезает;
## ловушку убирают посреди волны — смола перестаёт тормозить. Печатает ошибки, если есть.
## Запуск: Godot --headless --path . -s res://tools/remove_test.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	load("res://core/main.gd").start_in_game = true
	load("res://core/progress.gd").read_only = true
	load("res://core/mastery.gd").force_all = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 20:
		await process_frame
	scene.player.set_process_unhandled_input(false)
	scene.player.set_physics_process(false)
	var turrets: Node3D = scene.turrets
	var horde: Node3D = scene.horde
	var spot: Vector3 = turrets.suggestions("laser", 1)[0]
	print("лазер: ", turrets.place("laser", spot))
	var tar: Array[Vector3] = turrets.suggestions("tar", 1)
	print("смола: ", turrets.place("tar", tar[0]))
	var slow_cells := 0
	for v in horde._slow:
		if v < 1.0:
			slow_cells += 1
	print("клеток в смоле: ", slow_cells)
	scene.waves.start()
	Engine.time_scale = 4.0
	# Ждём первого ядра в полёте
	var flying := false
	for k in 3000:
		await process_frame
		for c in scene.get_children():
			if c.get_script() == load("res://turrets/turret_projectile.gd"):
				flying = true
		if flying:
			break
	print("ядро в полёте: ", flying)
	var idx := -1
	for i in turrets.slot_count():
		if turrets._slots[i]["turret"] and turrets._slots[i]["turret"].kind == "laser":
			idx = i
	turrets.remove(idx)
	print("лазер убрана, в запасе: ", turrets.stock_left("laser"))
	for k in 200:
		await process_frame
	var left := 0
	for c in scene.get_children():
		if c.get_script() == load("res://turrets/turret_projectile.gd"):
			left += 1
	print("ядер осталось: ", left)
	turrets.remove_trap(0)
	slow_cells = 0
	for v in horde._slow:
		if v < 1.0:
			slow_cells += 1
	print("после уборки смолы клеток: ", slow_cells, ", ловушек в запасе: ", turrets.stock_left("tar"))
	Engine.time_scale = 1.0
	quit()
