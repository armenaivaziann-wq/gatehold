extends SceneTree
## Проверка звуков орды: рог в начале волны, источники роя на скоплениях жуков (позиция,
## громкость), удары в ворота, хруст при смерти. Печатает, что и когда звучало.
## Запуск: Godot --path . -s res://tools/audio_test.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	load("res://core/main.gd").start_in_game = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(20)
	var audio: Node3D = null
	for c in scene.get_children():
		if c.get_script() == preload("res://mobs/swarm_audio.gd"):
			audio = c
	scene.waves.start()
	await _frames(2)
	print("рог играет: ", audio._horn.playing)
	var horde: Node3D = scene.horde
	var hits := [0]
	scene.waves.gate_hit.connect(func(_d: int) -> void: hits[0] += 1)
	for k in 1500:
		horde._process(1.0 / 30.0)
		scene.waves._process(0.0)
		if k % 30 == 0:
			await process_frame
	await create_timer(1.0).timeout
	for i in audio._voices.size():
		var v: AudioStreamPlayer3D = audio._voices[i]
		print("рой %d: %s, громкость %.1f дБ, играет %s" % [i, v.global_position, v.volume_db, v.playing])
	print("далёкий гул: %.1f дБ" % audio._distant.volume_db)
	print("ударов в ворота за прогон: ", hits[0], ", ворота ", scene.waves.gate_hp)
	# Прицел — на ближайшего к воротам жука, выстрел
	var target: Vector3 = horde.position_of(horde.pick_target(Vector3(0, 0, 100), 60.0))
	var cam: Camera3D = scene.player.camera
	var dir := (target - cam.global_position).normalized()
	scene.player.rotation.y = atan2(-dir.x, -dir.z)
	scene.player.head.rotation.x = asin(dir.y)
	await _frames(2)
	var kills0: int = horde.kills
	print("цель ", target, ", прицел ", scene.gun._aim(), ", оружие активно ", scene.gun.is_processing(), ", жуков рядом с прицелом ", horde.count_near(scene.gun._aim()["point"], 3.5))
	scene.gun.fire()
	for k in 120:
		await process_frame
		if audio._squish.playing:
			break
	print("убито выстрелом: ", horde.kills - kills0)
	print("хруст после выстрела: играет ", audio._squish.playing, ", место ", audio._squish.global_position)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
