extends SceneTree
## Снимки базуки как на листе эскиза: сбоку, сзади-сбоку в перспективе, спереди, сверху и ракета
## отдельно — на сером фоне. Вид от первого лица — tools/hero_shot.gd.
## Запуск: Godot --path . -s res://tools/bazooka_shot.gd -- out_dir=/путь

const LauncherModel := preload("res://weapons/launcher_model.gd")
const ShellScript := preload("res://weapons/shell.gd")

var _out := "user://bazooka_shot"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1400, 800))
	var scene := Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.43, 0.44, 0.49)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	scene.add_child(cam)
	cam.make_current()
	var gun: Node3D = LauncherModel.scene().instantiate()
	scene.add_child(gun)
	var rocket := MeshInstance3D.new()
	rocket.mesh = ShellScript.new()._rocket()
	rocket.visible = false
	scene.add_child(rocket)
	await _frames(5)
	var views := {
		"z1_side": [Vector3(2.6, 0.0, -0.1), Vector3(0, -0.04, -0.1)],
		"z2_side_left": [Vector3(-2.6, 0.0, -0.1), Vector3(0, -0.04, -0.1)],
		"z3_perspective": [Vector3(1.6, 0.9, -1.7), Vector3(0, -0.03, -0.12)],
		"z4_back": [Vector3(-1.3, 0.55, 1.9), Vector3(0, -0.03, -0.12)],
		"z5_top": [Vector3(0.01, 2.6, -0.1), Vector3(0, 0, -0.1)],
	}
	for shot: String in views:
		cam.global_position = views[shot][0]
		cam.look_at(views[shot][1], Vector3.UP if shot != "z5_top" else Vector3.FORWARD)
		await _frames(3)
		await _shot(shot)
	gun.visible = false
	rocket.visible = true
	cam.global_position = Vector3(1.6, 0.3, -0.05)
	cam.look_at(Vector3(0, 0, -0.08), Vector3.UP)
	await _frames(3)
	await _shot("z6_rocket")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
