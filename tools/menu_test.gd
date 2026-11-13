extends SceneTree
## Снимки меню: главное (с живым фоном), настройки, управление, бой после «Играть», пауза.
## Запуск: Godot --path . -s res://tools/menu_test.gd -- out_dir=/путь

var _out := "user://menu_test"


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = false
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# lang=en — снимки на английском (язык — только в памяти)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("lang="):
			var settings: GDScript = load("res://core/settings.gd")
			settings.language = arg.trim_prefix("lang=")
			settings.apply()
	await _seconds(4.0)
	print("в меню: ", scene.in_menu, ", жуков на фоне: ", scene.horde.count())
	await _shot("m1_main")
	scene.menu.show_page("settings")
	await _frames(3)
	await _shot("m2_settings")
	scene.menu.show_page("controls")
	await _frames(3)
	await _shot("m3_controls")
	# Выбор локаций: для снимка в памяти (без сохранения) три пройдены, четвёртая открыта
	var progress: GDScript = load("res://core/progress.gd")
	var saved_unlocked: int = progress.unlocked
	var saved_best: Dictionary = progress.best
	progress.unlocked = 4
	progress.best = {0: 500, 1: 320, 2: 140}
	progress.stars = {0: 3, 1: 2, 2: 1}
	scene.menu.show_page("levels")
	await _frames(3)
	await _shot("m6_levels")
	# Древо: в памяти семь звёзд, куплено несколько узлов (ничего не сохраняется)
	var saved_stars: Dictionary = progress.stars
	var saved_upgrades: Dictionary = progress.upgrades
	progress.stars = {0: 3, 1: 2, 2: 2}
	progress.upgrades = {"mentor": 1, "armorer": 1, "bulk": 1, "gate": 1}
	scene.menu.show_page("upgrades")
	await _frames(3)
	scene.menu._tree._set_hover("armorer")
	await _frames(2)
	await _shot("m7_upgrades")
	# Мастерство мушкетона: опыт на 4-й уровень, взята «Картечь» — «Тяжёлое ядро» перечёркнуто
	var saved_xp: Dictionary = progress.xp
	var saved_mastery: Dictionary = progress.mastery
	progress.xp = {"musket": 9000, "gatling": 2500}
	progress.mastery = {"musket": {"powder": 2, "drum": 1, "cock": 1, "cluster": 1}, "gatling": {"belt": 2}}
	scene.menu._tree._select_tab(0)
	await _frames(3)
	scene.menu._tree._set_hover("bulk")
	await _frames(2)
	await _shot("m8_mastery")
	scene.menu._tree._select_tab(3)
	await _frames(3)
	await _shot("m9_locked")
	scene.menu._tree._select_tab(4)
	await _frames(3)
	await _shot("m10_fortress")
	progress.xp = saved_xp
	progress.mastery = saved_mastery
	scene.menu._tree._tab = 0
	progress.stars = saved_stars
	progress.upgrades = saved_upgrades
	progress.unlocked = saved_unlocked
	progress.best = saved_best
	scene.menu.show_page("main")
	scene.start_game()
	await _frames(10)
	print("после «Играть»: в меню ", scene.in_menu, ", жуков ", scene.horde.count(), ", бой ", scene.waves.state)
	await _shot("m4_game")
	scene.pause()
	await _frames(3)
	print("пауза: ", paused)
	await _shot("m5_pause")
	scene.resume()
	await _frames(2)
	print("продолжили: пауза ", paused)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t, true).timeout


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
