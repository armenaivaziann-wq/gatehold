extends SceneTree
## Бот-прохождение: сам запускает волны, целится в скопление жуков ближе всего к воротам,
## стреляет из мушкетона, а когда жуки подошли близко и мушкетон перезаряжается — жжёт
## огнемётом. Печатает статистику по каждой волне и делает снимки.
## Целится мгновенно и без промаха — если даже он проигрывает, игра слишком сложная.
## fresh=1 — как у нового игрока: без прокачки, оружие и турели — только награды за локации до этой;
## level=N — локация.
## diff=X — своя сложность локации (для подбора баланса); miss=R — промах до R м (как живой игрок), shoot=0 — игрок не стреляет вовсе (одни турели).
## Запуск: Godot --path . -s res://tools/playtest_bot.gd -- out_dir=/путь speed=3 [level=1] [fresh=1] [miss=4] [shoot=0]
## С --headless — без снимков и намного быстрее.

const MapBuilder := preload("res://locations/map_builder.gd")

var _out := "user://playtest"
var _speed := 3.0
var _level := 0
var _fresh := false
## tree=N — как игрок, что дошёл до этой локации: N трофеев потрачено на общее древо (жадно, по
## списку TREE_PLAN), за пройденные локации — по 2 звезды и по 2 кристалла.
var _tree := 0
var _traps := true                 # traps=0 — не ставить ловушки (замерить их вклад)
const TREE_PLAN := ["stockpile", "armorer", "ab_salvo", "stock_gatling", "hands", "flight", "hero_armor", "ab_napalm", "ab_drone",
	"ab_speed", "bulk", "supply", "stock_gatling", "stock_laser", "stock_freeze", "optics", "stock_laser",
	"stock_gatling", "rapid", "trophy_gain", "stockpile", "armorer", "hands", "stock_freeze", "stock_laser",
	"stock_flame", "stock_barricade", "gat_pierce", "gat_rate", "laser_reach", "laser_pierce", "flame_radius",
	"freeze_power", "barricade_hp", "salvo_more", "napalm_long", "drone_time", "stock_gatling", "stock_flame",
	"gate", "repair", "strike_napalm", "strike_power", "strike_rockets", "stock_mortar", "mortar_radius", "mortar_rate"]
var _miss := 0.0
var _shoot := true
var _diff := 0.0
var _target_score := 0
var _auto := true
var _quality := -1
## Замеры: что спрятать (частицы, лампы, тени) и сколько секунд играть до выхода (0 — до конца).
var _hide := []
## Каких турелей не ставить (замерить вклад новой турели): skip=mortar
var _skip := []
var _secs := 0.0
var _kills_prev := {}


func _initialize() -> void:
	_run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out = arg.trim_prefix("out_dir=")
		elif arg.begins_with("speed="):
			_speed = float(arg.trim_prefix("speed="))
		elif arg.begins_with("level="):
			_level = int(arg.trim_prefix("level=")) - 1
		elif arg == "fresh=1":
			_fresh = true
		elif arg == "traps=0":
			_traps = false
		elif arg.begins_with("tree="):
			_fresh = true
			_tree = int(arg.trim_prefix("tree="))
		elif arg.begins_with("miss="):
			_miss = float(arg.trim_prefix("miss="))
		elif arg == "shoot=0":
			_shoot = false
		elif arg.begins_with("hide="):
			_hide = arg.trim_prefix("hide=").split(",")
		elif arg.begins_with("secs="):
			_secs = float(arg.trim_prefix("secs="))
		elif arg.begins_with("skip="):
			_skip = arg.trim_prefix("skip=").split(",")
		elif arg == "auto=0":
			_auto = false
		elif arg.begins_with("quality="):
			_quality = int(arg.trim_prefix("quality="))
		elif arg.begins_with("diff="):
			_diff = float(arg.trim_prefix("diff="))
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	load("res://core/main.gd").start_in_game = true
	load("res://core/main.gd").current_level = _level
	# Огнемёт и гравипушка — награды за локации; для проверки открываем всё (в памяти)
	var upgrades: GDScript = load("res://core/upgrades.gd")
	var progress: GDScript = load("res://core/progress.gd")
	progress.load_progress()
	progress.tutorial_done = true
	if _fresh:
		# Новый игрок: никакой прокачки; награды — только за пройденные до этой локации
		progress.upgrades = {}
		progress.mastery = {}
		progress.stars = {}
		progress.best = {}
		for i in _level:
			progress.best[i] = 1
		if _tree > 0:
			for i in _level:
				progress.stars[i] = 2
			progress.trophies = _tree
			progress.crystals = 2 * _level
			progress.read_only = true
			# Жадно по списку, по кругу, пока хоть что-то покупается
			var bought := true
			while bought:
				bought = false
				for id: String in TREE_PLAN:
					if upgrades.buy(id):
						bought = true
			# Остаток — на самое дешёвое из доступного, пока хватает
			var more := true
			while more:
				more = false
				var cheapest := ""
				var cost := 1 << 30
				for n: Dictionary in upgrades.NODES:
					var id: String = n["id"]
					if id.begins_with("w_") or n.has("item") and not String(n["item"]) in ["", "gatling", "laser", "freeze", "flame", "mortar"]:
						continue
					if upgrades.can_buy(id) and upgrades.cost_at(id) < cost:
						cost = upgrades.cost_at(id)
						cheapest = id
				if cheapest != "" and upgrades.buy(cheapest):
					more = true
			print("древо на %d трофеев: %d узлов, осталось %d" % [_tree, progress.upgrades.size(), progress.trophies])
	else:
		for n: Dictionary in upgrades.NODES:
			progress.upgrades[n["id"]] = n["max"]
		load("res://core/mastery.gd").force_all = true
	# Снимки и проверки не пишут прогресс игрока на диск
	load("res://core/progress.gd").read_only = true
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(20)
	# Графика для замеров: качество и авто-качество (в память, settings.cfg не трогаем)
	var settings: GDScript = load("res://core/settings.gd")
	settings.auto_quality = _auto
	if _quality >= 0:
		settings.quality = _quality
	settings.apply()
	if "shadow" in _hide:
		scene._sun.shadow_enabled = false
	if "particles" in _hide or "lights" in _hide:
		node_added.connect(func(n: Node) -> void:
			if n is GPUParticles3D and "particles" in _hide:
				(n as GPUParticles3D).visible = false
			elif n is Light3D and not n is DirectionalLight3D and "lights" in _hide:
				(n as Light3D).visible = false)
	for k: String in _skip:
		scene.turrets.kinds.erase(k)
		scene.turrets.items.erase(k)
	var player: CharacterBody3D = scene.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	scene._hint_time = 0.0
	var waves: Node = scene.waves
	var horde: Node3D = scene.horde
	if _diff > 0.0:
		waves.difficulty = _diff
	var gate_before_boss := [0]
	var bosses_escaped := [0]
	waves.boss_arrived.connect(func(boss_name: String, _mini: bool) -> void:
		gate_before_boss[0] = waves.gate_hp
		print("  БОСС: %s, прочность %d" % [boss_name, horde.boss_max]))
	var blunder: Node3D = scene.weapons[0]
	var flame: Node3D = scene.weapons[1] if scene.weapons.size() > 1 else null
	Engine.time_scale = _speed
	var cam: Camera3D = player.camera
	var fps_samples: Array[float] = []
	var wave_start_ms := 0
	var last_step := 0
	var shots := 0
	var shots_dry := 0
	var flame_time := 0.0
	var aim_timer := 0.0
	var target := Vector3(0, 0, 80)
	var last_wave := 0
	var snap_done := {}
	var frame := 0
	var proc_ms := 0.0
	var phys_ms := 0.0
	var prof_n := 0
	while true:
		await process_frame
		frame += 1
		proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		prof_n += 1
		fps_samples.append(Engine.get_frames_per_second())
		if frame % 600 == 0:
			print("  … пройдено %d%%, на карте %d, в лагерях %d, ворота %d, убито %d, FPS %d, авто −%d, логика %.1f мс, физика %.1f мс, вызовов отрисовки %d, объектов %d" % [waves.percent(), horde.count(),
				horde.pending, waves.gate_hp, horde.kills, Engine.get_frames_per_second(), load("res://core/settings.gd").auto_step(),
				proc_ms / maxf(prof_n, 1.0), phys_ms / maxf(prof_n, 1.0),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
			proc_ms = 0.0
			phys_ms = 0.0
			prof_n = 0
		if waves.state == waves.State.WON or waves.state == waves.State.LOST:
			break
		if _secs > 0.0 and wave_start_ms > 0 and Time.get_ticks_msec() - wave_start_ms > _secs * 1000.0:
			var sum := 0.0
			for f in fps_samples:
				sum += f
			print("ЗАМЕР %s: FPS ср %.0f за %.0f с, кадров %d, на карте %d" % [",".join(_hide), sum / maxf(fps_samples.size(), 1.0),
				_secs, fps_samples.size(), horde.count()])
			quit()
			return
		if waves.state == waves.State.READY:
			_buy_turrets(scene)
			await _seconds(1.0)
			waves.start()
			wave_start_ms = Time.get_ticks_msec()
			continue
		# Рубеж орды: отчёт за отрезок и покупки
		if waves.step > last_step:
			last_step = waves.step
			_wave_report(waves, horde, wave_start_ms, shots, shots_dry, flame_time, fps_samples)
			_buy_turrets(scene)
			wave_start_ms = Time.get_ticks_msec()
			shots = 0
			shots_dry = 0
			flame_time = 0.0
			fps_samples.clear()
		if not horde.kills_by.is_empty():
			_kills_prev = horde.kills_by.duplicate()
		# Как живой игрок: в бою докупает турели и улучшения, как только хватает монет
		if frame % 90 == 0:
			_buy_turrets(scene, false)
		# Цель: точка с наибольшим числом жуков среди самых близких к воротам
		aim_timer -= 1.0 / 60.0
		if aim_timer <= 0.0 and horde.count() > 0:
			aim_timer = 0.15
			target = _pick_target(horde)
			# Босс или вожак в досягаемости — как живой игрок, бьём по нему, но сперва — по тем,
			# кто уже у самых ворот
			var bi: int = horde.boss_index()
			if bi >= 0 and target.z < MapBuilder.GATE_Z - 30.0:
				var bp: Vector3 = horde.position_of(bi)
				if bp.distance_to(cam.global_position) < 75.0:
					target = bp + horde.velocity_of(bi) * 0.5
					_target_score = 99
			if _miss > 0.0:
				var r := Vector2.from_angle(randf() * TAU) * randf() * _miss
				target += Vector3(r.x, 0.0, r.y)
		var dir := (target - cam.global_position).normalized()
		player.rotation.y = atan2(-dir.x, -dir.z)
		player.head.rotation.x = asin(clampf(dir.y, -1.0, 1.0))
		# Умения героя — как живой игрок: по готовности, в густую толпу
		var ab: Node3D = scene.get("abilities")
		if ab and _shoot and _target_score >= 12 and frame % 20 == 0:
			for i in ab.ABILITIES.size():
				if ab.progress(i) >= 1.0 and ab.use(i):
					break
		var dist := cam.global_position.distance_to(target)
		if flame and _shoot:
			var close: bool = dist < flame.RANGE
			# Огнемёт — когда жуки близко и мушкетону нечем стрелять (или он перезаряжается)
			var blunder_busy: bool = blunder.clip == 0 or blunder._reload > 0.0
			var want_flame: bool = close and blunder_busy and not flame.ammo_empty() and flame.fuel > 5.0
			if want_flame and scene.gun != flame:
				scene.select_weapon(1)
			elif not want_flame and scene.gun != blunder and not close:
				scene.select_weapon(0)
			elif not want_flame and scene.gun == flame and (flame.ammo_empty() or flame.fuel <= 5.0):
				scene.select_weapon(0)
			flame.force_fire = scene.gun == flame and flame._equip >= 1.0
			if flame.force_fire:
				flame_time += 1.0 / 60.0 * _speed
		# Как живой игрок: бьёт по скоплению или по тем, кто уже у ворот, одиночек издали не ждёт
		var worth := _target_score >= 8 or target.z > MapBuilder.GATE_Z - 25.0
		if _shoot and worth and scene.gun == blunder and blunder._equip >= 1.0 and blunder._reload == 0.0:
			if blunder.clip > 0:
				blunder.fire()
				shots += 1
			elif blunder.reserve == 0:
				shots_dry += 1
			else:
				blunder.start_reload()
		# Снимки: начало орды, середина, конец
		for at in [10, 50, 85]:
			var key := "p%d" % at
			if not snap_done.has(key) and waves.percent() >= at:
				snap_done[key] = true
				await _shot("play_%d" % at)
	_wave_report(waves, horde, wave_start_ms, shots, shots_dry, flame_time, fps_samples)
	if waves.BOSSES:
		print("  боссов убито %d, дошли до ворот %d" % [horde.bosses_killed + horde.minis_killed, horde.boss_escaped])
	Engine.time_scale = 1.0
	await _shot("play_end")
	print("ИТОГ: ", "победа" if waves.state == waves.State.WON else "поражение, пройдено %d%% орды" % waves.percent(),
		", ворота %d/%d, убито %d из %d, монет %d" % [waves.gate_hp, waves.gate_max, horde.kills, waves.total, waves.coins])
	scene._commit_trophies(waves.state == waves.State.WON)
	print("ТРОФЕИ за бой: ", scene.trophies_battle)
	quit()


## Как живой игрок: всё из запаса — в дело. Турели — на подсказанные места у каналов (ближе к
## воротам), по очереди пулемёт, лазер, мортира, жаровня; когда места на плато нет — на башни и
## стену. Ловушки — на путь орды. Монеты — на самое дешёвое: ступень или турель сверх запаса.
func _buy_turrets(scene: Node3D, report := true) -> void:
	var turrets: Node3D = scene.turrets
	var plan: Array = ["gatling", "laser", "mortar", "flame", "freeze"].filter(func(k: String) -> bool: return k in turrets.kinds)
	var placed := true
	while placed:
		placed = false
		for kind: String in plan:
			if turrets.stock_left(kind) <= 0:
				continue
			var spots: Array[Vector3] = turrets.suggestions(kind, 1)
			if not spots.is_empty():
				placed = turrets.place(kind, spots[0]) or placed
			elif turrets.free_slot() >= 0:
				placed = turrets.buy(turrets.free_slot(), kind) or placed
	for kind: String in ["spikes", "tar", "barricade"]:
		if not kind in turrets.items or not _traps:
			continue
		while turrets.stock_left(kind) > 0:
			var spots: Array[Vector3] = turrets.suggestions(kind, 1)
			if spots.is_empty() or not turrets.place(kind, spots[0]):
				break
	# Монеты: самое дешёвое из «улучшить турель» и «докупить турель сверх запаса», пока хватает
	var no_room: Array[String] = []
	for guard in 300:
		var best := 1 << 30
		var best_slot := -1
		var best_kind := ""
		for i in turrets.slot_count():
			var c: int = turrets.upgrade_cost(i)
			if c >= 0 and c < best:
				best = c
				best_slot = i
		for kind: String in plan:
			if kind in no_room:
				continue
			var c: int = turrets.extra_cost(kind)
			if c <= best:
				best = c
				best_kind = kind
				best_slot = -1
		if best_slot < 0 and best_kind == "" or scene.waves.coins < best:
			break
		if best_kind == "":
			turrets.upgrade(best_slot)
			continue
		var spots: Array[Vector3] = turrets.suggestions(best_kind, 1)
		if not spots.is_empty():
			turrets.place(best_kind, spots[0])
		elif turrets.free_slot() >= 0:
			turrets.buy(turrets.free_slot(), best_kind)
		else:
			no_room.append(best_kind)
	var tiers := [0, 0, 0]
	var by_kind := {}
	for i in turrets.slot_count():
		var t: Node3D = turrets._slots[i]["turret"]
		if t:
			tiers[t.tier - 1] += 1
			by_kind[t.kind] = by_kind.get(t.kind, 0) + 1
	if report:
		print("  турелей: ", turrets.turret_count(), " (I/II/III: %d/%d/%d)" % tiers, " ", by_kind, ", ловушек ",
			turrets._traps.size(), ", монет осталось ", scene.waves.coins)


func _wave_report(waves: Node, horde: Node3D, start_ms: int, shots: int, dry: int, flame_time: float, fps: Array[float]) -> Dictionary:
	var sum := 0.0
	var low := 999.0
	for f in fps:
		sum += f
		low = minf(low, f)
	var avg := sum / maxf(fps.size(), 1.0)
	var secs := (Time.get_ticks_msec() - start_ms) / 1000.0 * _speed
	var out: float = waves.spawned()
	var mix: PackedFloat32Array = waves.wave_mix(out)
	var line := "РУБЕЖ %d (%d%% орды): вышло %d%%, сейчас бегунов %d%%, громил %d%% по %d, в доспехах %d%%, в тяжёлых %d%%; отрезок %.0f с игры, ворота %d/%d, выстрелов %d, огнемёт %.1f с, монет %d, FPS ср %.0f мин %.0f" % [
		waves.step, waves.percent(), int(out * 100), int(mix[1] * 100), int(mix[2] * 100), waves.brute_hp(out),
		int(waves.armor_share(out) * 100), int(waves.heavy_share(out) * 100), secs, waves.gate_hp, waves.gate_max,
		shots, flame_time, waves.coins, avg, low]
	print(line)
	# Кто сколько убил за волну (main.gd обнуляет счёт в конце волны — берём последний снимок)
	var parts: Array[String] = []
	for src: String in _kills_prev:
		parts.append("%s %d" % [src, _kills_prev[src]])
	_kills_prev = {}
	print("  убили: ", ", ".join(parts))
	return {"line": line}


## Жуки ближе всего к воротам: из 40 самых продвинувшихся берём того, у кого больше соседей.
func _pick_target(horde: Node3D) -> Vector3:
	var best := Vector2(0, 80)
	var best_z := -1e9
	var front: Array[Vector2] = []
	var n: int = horde.count()
	var step := maxi(1, n / 1500)
	for i in range(0, n, step):
		var p: Vector2 = horde._pos[i]
		if p.y > best_z - 15.0:
			front.append(p)
			if p.y > best_z:
				best_z = p.y
	var best_score := -1
	for p in front:
		if p.y < best_z - 15.0:
			continue
		var score: int = horde.count_near(Vector3(p.x, 0, p.y), 3.5)
		if score > best_score:
			best_score = score
			best = p
	_target_score = best_score
	return Vector3(best.x, horde._floor_at(best), best.y)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(t: float) -> void:
	await create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		return
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
