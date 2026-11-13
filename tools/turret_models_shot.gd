extends SceneTree
## Снимок трёх турелей рядом на сером фоне (как лист эскизов): пулемёт, лазер, заморозка.
## Запуск: Godot --path . -s res://tools/turret_models_shot.gd -- out_dir=/путь

const TurretModels := preload("res://turrets/turret_models.gd")

var _out := "user://turret_models"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1500, 700))
	var scene := Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.41, 0.46)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	var kinds := ["gatling", "laser", "freeze"]
	for k in kinds.size():
		var t: Node3D = TurretModels.scene(kinds[k]).instantiate()
		t.position = Vector3((k - 1) * 2.4, 0, 0)
		# Голова — вполоборота влево, как на листе
		t.get_node("Head").rotation.y = 2.3
		t.get_node("Head/Gun").rotation.x = 0.05
		scene.add_child(t)
	var cam := Camera3D.new()
	cam.fov = 32.0
	scene.add_child(cam)
	cam.make_current()
	await _frames(4)
	cam.global_position = Vector3(0.6, 2.6, 7.6)
	cam.look_at(Vector3(0, 0.85, 0), Vector3.UP)
	await _frames(4)
	await _shot("turrets_warmup")
	cam.global_position = Vector3(0.5, 2.4, 8.4)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	await _frames(4)
	await _shot("turrets_sheet")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
