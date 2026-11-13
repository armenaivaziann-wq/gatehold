extends SceneTree
## Проверка маршрутов роя и площадок турелей: сколько точек маршрута, где площадки.
func _initialize() -> void:
	load("res://core/main.gd").start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var route: Array[Vector2] = scene.horde.route_points()
	print("точек маршрута: ", route.size(), ", первая ", route[0] if route.size() else "нет", ", последняя ", route[-1] if route.size() else "нет")
	print("площадок: ", scene.turrets.slot_count())
	for i in scene.turrets.slot_count():
		var p: Vector3 = scene.turrets._slots[i]["pos"]
		print("  ", i, " ", p, " до маршрута %.1f м" % scene.turrets._distance_to(route, Vector2(p.x, p.z)))
	quit()
