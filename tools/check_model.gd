extends SceneTree
## Проверка импорта модели: узлы, меши, материалы. Запуск: -s res://tools/check_model.gd -- path=res://...
func _initialize() -> void:
	var path := "res://weapons/models/blunderbuss.glb"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("path="):
			path = arg.trim_prefix("path=")
	var scene: Node = load(path).instantiate()
	for n in scene.find_children("*", "", true, false):
		if n is MeshInstance3D:
			print("mesh ", n.name, " surfaces=", n.mesh.get_surface_count(), " aabb=", n.get_aabb())
		elif n is Node3D:
			print("node ", n.name, " at ", (n as Node3D).position)
	scene.free()
	quit()
