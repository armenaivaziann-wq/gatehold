extends Node3D
## Игра от первого лица: герой с реактивным ранцем (player.gd) защищает ворота от орды — с
## ракетницей и умениями Q E R (hero_abilities.gd), летает над толпой, где его достают копья
## (spears.gd), растёт в уровне за убитых.
## Начинается с главного меню: за ним камера медленно облетает каньоны, где идёт бой
## (жуки текут к воротам, по ним рвутся снаряды). «Играть» — бой с первой волны, Esc — пауза.
## Оружие: 1 — мушкетон, 2 — огнемёт, 3 — гравипушка, 4 — миниган (или колесо мыши; что открыто).
## B — строить турели (turrets.gd).
## Enter — следующая волна. Tab — вид
## сверху (мышь с зажатой кнопкой — вращать, колесо — приблизить, WASD — двигать) и обратно.
## F3 — счётчик FPS. Локация — current_level (levels.gd); после победы открывается следующая.
## Параметры запуска (после --): level=N — сразу эта локация, unlock_all — всё древо прокачки.

const Lang := preload("res://core/lang.gd")

const Mobs := preload("res://mobs/mobs.gd")
const MapBuilder := preload("res://locations/map_builder.gd")
const PlayerScript := preload("res://hero/player.gd")
const AbilitiesScript := preload("res://hero/hero_abilities.gd")
const SpearsScript := preload("res://mobs/spears.gd")
const HordeScript := preload("res://mobs/horde.gd")
const BlunderbussScript := preload("res://weapons/blunderbuss.gd")
const FlamethrowerScript := preload("res://weapons/flamethrower.gd")
const GravigunScript := preload("res://weapons/gravigun.gd")
const MinigunScript := preload("res://weapons/minigun.gd")
const LightningScript := preload("res://weapons/lightning_gun.gd")
const SawScript := preload("res://weapons/saw_gun.gd")
const HammerScript := preload("res://weapons/hammer.gd")
const FxBudget := preload("res://core/fx_budget.gd")
const MusicScript := preload("res://audio/music/music.gd")
const TutorialScript := preload("res://ui/tutorial.gd")
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")
const WavesScript := preload("res://core/waves.gd")
const HudScript := preload("res://ui/hud.gd")
const MenuScript := preload("res://ui/menu.gd")
const GameOverScript := preload("res://ui/game_over.gd")
const LootPopupsScript := preload("res://effects/loot_popups.gd")
## Кто сколько убил — подписи для итогов боя (кроме оружия и турелей из mastery.gd).
const SOURCE_NAMES := {"musket": "Ракетница", "flame": "Турель-огнемёт", "flamer": "Огнемёт", "salvo": "Ракетный залп",
	"napalm": "Напалм", "drone": "Дрон", "airstrike": "Авиаудар", "rocketrain": "Ракетный дождь",
	"orbital": "Орбитальный лазер", "spikes": "Шипы"}
const TurretsScript := preload("res://turrets/turrets.gd")
const BaseScript := preload("res://locations/base_builder.gd")
const SwarmAudioScript := preload("res://mobs/swarm_audio.gd")
const ExplosionScript := preload("res://effects/explosion.gd")
const Settings := preload("res://core/settings.gd")
const Levels := preload("res://locations/levels.gd")
const Progress := preload("res://core/progress.gd")
const HINT_TIME := 8.0
# Фон меню: облёт вокруг центра карты, взрывы по орде
const MENU_ORBIT_CENTER := Vector3(-10, 0, 20)
const MENU_ORBIT_RADIUS := 62.0
const MENU_ORBIT_HEIGHT := 26.0
const MENU_ORBIT_SPEED := 0.035
const MENU_BOOM_EVERY := 2.2

## Перезагрузить сцену сразу в бой, без главного меню (Enter после конца игры, тесты).
static var start_in_game := false
## Какую локацию загрузить (-1 — последнюю открытую).
## Трофей — за каждых столько убитых (upgrades.gd: валюта общего древа).
const TROPHY_KILLS := 30          # было 12: трофеев выходило так много, что всё открывалось за пару боёв
## Трофеи и кристаллы, уже записанные за этот бой (растут после каждой волны).
var trophies_battle := 0
var crystals_battle := 0
static var current_level := -1

## Индекс загруженной локации.
var level_index := 0
var _sun: DirectionalLight3D

var camera: Camera3D
var player: CharacterBody3D
var abilities: Node3D
var spears: Node3D
var _kills_seen := 0
var horde: Node3D
## Оружие в руках сейчас и всё оружие по порядку клавиш.
var gun: Node3D
var weapons: Array[Node3D] = []
var waves: Node
var hud: CanvasLayer
var menu: CanvasLayer
## Экран поражения (ui/game_over.gd).
var game_over: CanvasLayer
## Всплывающие монеты над убитыми и рубежи убийств (effects/loot_popups.gd).
var loot_popups: Node3D
## Убито каждым оружием, турелью и умением за весь бой (kills_by орды очищается на рубежах).
var battle_kills_by := {}
var turrets: Node3D
var in_menu := false
var music: Node
## Звуки орды (рокот, крики, рог). В главном меню на паузе — там играет только музыка.
var swarm_audio: Node
var tutorial: CanvasLayer
var _last_state := -1
var overview := false
var target := Vector3(0, 0, 0)
var yaw := 0.0
var pitch := -0.95
var distance := 240.0

var _map: Node3D
var _env: Environment
var _hint: Label
var _crosshair: Control
var _stats: Label
var _hint_time := HINT_TIME
var _hud_layer: CanvasLayer
var _menu_time := 0.0
var _dusk_sky: Sky
var _menu_boom := 1.0


func _ready() -> void:
	FxBudget.reset()
	Settings.load_settings()
	Progress.load_progress()
	# Узлы, убранные из древа, — вернуть потраченные трофеи
	if Upgrades.migrate():
		Progress.save()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			current_level = int(arg.trim_prefix("level=")) - 1
		elif arg == "unlock_all":
			# Для проверки: всё оружие открыто и общее древо куплено (только в памяти)
			Mastery.force_all = true
			for n: Dictionary in Upgrades.NODES:
				Progress.upgrades[n["id"]] = n["max"]
			# Проверочный режим ничего не сохраняет — иначе «всё куплено» попало бы в настоящий прогресс
			Progress.read_only = true
	level_index = current_level if current_level >= 0 else Progress.last_unlocked()
	level_index = clampi(level_index, 0, Levels.count() - 1)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.ssao_radius = 2.0
	_env.ssao_intensity = 2.5
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = 300.0
	_env.fog_depth_end = 1200.0
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	# Тени, затенение и разрешение 3D — по настройке качества графики
	Settings.env = _env
	Settings.sun = _sun
	Settings.apply()
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 3000.0
	add_child(camera)
	_build_map()
	# Двор за воротами — только там, где крепость (в долине с туннелем его нет)
	if not _map.is_tunnel():
		var base := BaseScript.new()
		base.setup(_map)
		add_child(base)
	horde = HordeScript.new()
	horde.setup(_map)
	add_child(horde)
	player = PlayerScript.new()
	player.spawn_point = _map.player_spawn()
	add_child(player)
	# Умения героя: Q E R
	abilities = AbilitiesScript.new()
	abilities.horde = horde
	abilities.player = player
	add_child(abilities)
	# Главное оружие — ракетница; остальное — награды за локации и покупки за трофеи (mastery.gd)
	_arm(BlunderbussScript)
	refresh_arsenal()
	gun = weapons[0]
	waves = WavesScript.new()
	waves.horde = horde
	waves.weapons = weapons
	waves.difficulty = Levels.get_level(level_index)["difficulty"]
	waves.pattern = Levels.get_level(level_index).get("pattern", "steady")
	waves.tough = Levels.get_level(level_index).get("tough", 1.0)
	waves.coin_mult = Levels.get_level(level_index).get("coins", 1.0)
	waves.horde_mult = Levels.get_level(level_index).get("horde", 1.0)
	waves.boss_name = Levels.get_level(level_index).get("boss", "Босс")
	waves.mini_name = Levels.get_level(level_index).get("mini", "Вожак")
	horde.speed_scale = Levels.get_level(level_index).get("speed", 1.0)
	var boss_model: String = Levels.get_level(level_index).get("boss_model", "")
	var mini_model: String = Levels.get_level(level_index).get("mini_model", "")
	horde.boss_scene = load(boss_model) if boss_model != "" else null
	horde.mini_scene = load(mini_model) if mini_model != "" else null
	waves.won.connect(_on_won)
	waves.finished.connect(_commit_xp)
	# После итогов (_commit_xp считает рекорд и что по карману) — экран поражения
	waves.finished.connect(func() -> void:
		if waves.state == waves.State.LOST:
			_show_game_over())
	# Рубеж орды: опыт и трофеи — сразу в сохранение, и сообщение о бонусе
	waves.milestone.connect(func(n: int) -> void:
		_commit_xp()
		hud.toast("Пройдено %d%% орды · +%d трофеев · подвоз боеприпасов, ворота подлатали" % [
			n * 100 / waves.STEPS, int(step_reward(n) * Upgrades.trophy_mult())], Color(1.0, 0.85, 0.4)))
	# Enter после конца игры: победа — следующая локация, поражение — эта же заново
	waves.restart_requested.connect(func(won: bool) -> void:
		current_level = mini(level_index + 1, Levels.count() - 1) if won else level_index
		start_in_game = true
		get_tree().reload_current_scene())
	add_child(waves)
	music = MusicScript.new()
	add_child(music)
	# Обучение писалось под стрелка на стене — для героя с ранцем его пока нет
	loot_popups = LootPopupsScript.new()
	loot_popups.horde = horde
	loot_popups.waves = waves
	add_child(loot_popups)
	swarm_audio = SwarmAudioScript.new()
	swarm_audio.horde = horde
	swarm_audio.waves = waves
	add_child(swarm_audio)
	# Босс пришёл — полоса здоровья, сообщение и тревожный рог
	# Враги надели доспехи — предупредить
	waves.armor_appeared.connect(func(heavy: bool) -> void:
		hud.toast("Тяжёлые доспехи — держат 3 попадания" if heavy else "Враги в доспехах — держат 2 попадания",
			Color(0.7, 0.8, 1.0)))
	waves.boss_arrived.connect(func(boss_name: String, _mini: bool) -> void:
		hud.boss_arrived(boss_name)
		swarm_audio._horn.play())
	turrets = TurretsScript.new()
	turrets.horde = horde
	turrets.waves = waves
	turrets.camera = player.camera
	turrets.setup(_map)
	add_child(turrets)
	spears = SpearsScript.new()
	spears.horde = horde
	spears.waves = waves
	spears.player = player
	add_child(spears)
	hud = HudScript.new()
	hud.waves = waves
	hud.gun = gun
	hud.level_name = Levels.get_level(level_index)["name"]
	hud.tunnel = _map.is_tunnel()
	hud.enemies = Mobs.plural(horde.monster)
	hud.next_name = Levels.get_level(level_index + 1)["name"] if level_index + 1 < Levels.count() else ""
	hud.weapons = weapons
	hud.player = player
	hud.abilities = abilities
	add_child(hud)
	player.leveled_up.connect(_on_level_up)
	player.hit_taken.connect(hud.hurt)
	player.downed.connect(func() -> void:
		hud.toast("Тебя сбили! Через %d с — снова на стене" % int(player.DOWN_TIME), Color(1.0, 0.45, 0.35)))
	if tutorial:
		add_child(tutorial)
	select_weapon(0)
	_build_hud()
	menu = MenuScript.new()
	menu.play_pressed.connect(start_game)
	menu.level_chosen.connect(_choose_level)
	menu.resume_pressed.connect(resume)
	menu.menu_pressed.connect(func() -> void:
		get_tree().paused = false
		start_in_game = false
		get_tree().reload_current_scene())
	menu.quit_pressed.connect(func() -> void: get_tree().quit())
	add_child(menu)
	game_over = GameOverScript.new()
	game_over.retry_pressed.connect(func() -> void: waves.start())
	game_over.upgrades_pressed.connect(open_upgrades)
	game_over.menu_pressed.connect(func() -> void:
		get_tree().paused = false
		start_in_game = false
		get_tree().reload_current_scene())
	add_child(game_over)
	if start_in_game:
		start_in_game = false
		start_game()
	else:
		_enter_menu()


## Главное меню: игрок и интерфейс боя спрятаны, за меню — облёт камеры над боем.
func _enter_menu() -> void:
	in_menu = true
	overview = false
	player.set_active(false)
	for w in weapons:
		w.set_active(false)
	hud.visible = false
	_hud_layer.visible = false
	turrets.set_ui_visible(false)
	waves.set_process(false)
	swarm_audio.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_light(true)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	horde.send_wave(1000000, 30.0)
	_prewarm_menu_horde()
	_update_menu_camera(0.0)
	menu.open("main")


## Чтобы фон сразу был живым: жуки уже растеклись по каналам (считаем по кусочкам).
func _prewarm_menu_horde() -> void:
	for k in 30:
		for j in 25:
			horde._process(1.0 / 30.0)
		await get_tree().process_frame


## Бой с первой волны: орда и счёт с нуля, игрок на стене с мушкетоном.
func start_game() -> void:
	in_menu = false
	menu.close()
	swarm_audio.process_mode = Node.PROCESS_MODE_INHERIT
	_apply_light(false)
	horde.clear()
	waves.reset()
	waves.set_process(true)
	# Сначала параметры (боезапас из «Прокачки»), потом пополнить — иначе первый бой со старыми
	player.reset_hero()
	_on_level_up(1, false)
	for w in weapons:
		w.restock()
	hud.visible = true
	_hud_layer.visible = true
	turrets.set_ui_visible(true)
	_hint_time = HINT_TIME
	abilities.reset()
	_kills_seen = horde.kills
	battle_kills_by.clear()
	if loot_popups:
		loot_popups.hud = hud
		loot_popups.reset()
	select_weapon(0)
	_set_overview(false)


func pause() -> void:
	get_tree().paused = true
	if game_over and game_over.active:
		game_over.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	_hud_layer.visible = false
	turrets.set_ui_visible(false)
	menu.open("pause")


## U в бою — сразу «Прокачка» (через паузу: Esc или «Назад» возвращают в меню паузы).
func open_upgrades() -> void:
	pause()
	menu.show_page("upgrades")


func resume() -> void:
	_apply_upgrades()
	menu.close()
	get_tree().paused = false
	Settings.save()
	if game_over and game_over.active:
		# Бой проигран — возвращаемся к экрану поражения, а не в HUD
		game_over.visible = true
		game_over.refresh_loot(Progress.trophies, _offers())
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	hud.visible = true
	_hud_layer.visible = true
	turrets.set_ui_visible(true)


## Прокачку могли докупить посреди боя — оружие, турели и ворота сразу получают новые параметры.
func _apply_upgrades() -> void:
	for w in weapons:
		w.refresh_stats()
	for t in turrets.get_children():
		if t.has_method("refresh_stats"):
			t.refresh_stats()
	turrets.refresh_traps()
	var grow: int = Upgrades.gate_hp() - waves.gate_max
	if grow > 0:
		waves.gate_max += grow
		waves.gate_hp += grow


func _build_map() -> void:
	if _map:
		_map.queue_free()
	var t0 := Time.get_ticks_msec()
	_map = MapBuilder.new()
	_map.level = Levels.get_level(level_index)
	_map.add_to_group("map")
	add_child(_map)
	print("локация «%s» построена за %d мс" % [_map.level["name"], Time.get_ticks_msec() - t0])
	_apply_light(false)


## Свет, небо и туман локации. dusk — для главного меню: то же место на закате (низкое тёплое
## солнце, тёплая дымка) — фон меню спокойнее и атмосфернее, в бою — обычный свет локации.
func _apply_light(dusk: bool) -> void:
	var light: Dictionary = _map.light()
	var sky: Color = light["sky"]
	var ambient: Color = light["ambient"]
	var sun_col: Color = light["sun"]
	var sun_rot: Vector3 = light["sun_rot"]
	if dusk:
		sky = sky.lerp(Color(0.96, 0.7, 0.5), 0.5)
		ambient = ambient.lerp(Color(0.85, 0.66, 0.55), 0.35)
		sun_col = Color(1.0, 0.68, 0.42)
		sun_rot.x = -13.0
	_env.background_color = sky
	# Закатное небо в меню: тёплый горизонт, сумеречный верх; в бою — ровный цвет локации
	if dusk:
		if not _dusk_sky:
			var mat := ProceduralSkyMaterial.new()
			mat.sky_top_color = Color(0.32, 0.36, 0.52)
			mat.sky_horizon_color = Color(1.0, 0.66, 0.42)
			mat.sky_curve = 0.12
			mat.ground_horizon_color = Color(0.9, 0.6, 0.42)
			mat.ground_bottom_color = Color(0.3, 0.22, 0.18)
			mat.sun_angle_max = 18.0
			_dusk_sky = Sky.new()
			_dusk_sky.sky_material = mat
		_env.sky = _dusk_sky
		_env.background_mode = Environment.BG_SKY
		sky = Color(0.98, 0.68, 0.46)
	else:
		_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_color = ambient
	_env.ambient_light_energy = light["ambient_energy"] * (0.85 if dusk else 1.0)
	_env.fog_light_color = sky
	_env.fog_depth_begin = light["fog_begin"] * (0.5 if dusk else 1.0)
	_env.fog_depth_end = light["fog_end"] * (0.7 if dusk else 1.0)
	# Насыщенность картинки — своя у локации (лес приглушённый)
	var sat: float = _map.level.get("saturation", 1.0)
	_env.adjustment_enabled = sat != 1.0 or dusk
	_env.adjustment_saturation = sat * (1.1 if dusk else 1.0)
	_env.adjustment_contrast = 1.08 if dusk else (1.05 if sat != 1.0 else 1.0)
	_sun.light_color = sun_col
	_sun.light_energy = light["sun_energy"] * (1.1 if dusk else 1.0)
	_sun.rotation_degrees = sun_rot


## Выбор локации в меню: эта уже загружена — сразу в бой, другая — перезагрузить сцену с ней.
func _choose_level(index: int) -> void:
	if index == level_index:
		start_game()
		return
	current_level = index
	start_in_game = true
	get_tree().reload_current_scene()


## Прицел в центре экрана и подсказка по управлению (гаснет через несколько секунд).
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud_layer = layer
	add_child(layer)
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	layer.add_child(_crosshair)
	_hint = Label.new()
	_hint.text = "Клик — захватить мышь · ЛКМ — ракета · Q E R — умения · Пробел — взлететь, Shift — ниже · WASD — лететь\nEnter — выпустить орду · B — стройка · H — назад (стена или вышка) · Tab — вид сверху · Esc — пауза"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 110
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)
	_stats = Label.new()
	_stats.position = Vector2(24, 110)
	_stats.visible = false
	_stats.add_theme_font_size_override("font_size", 18)
	_stats.add_theme_constant_override("outline_size", 5)
	_stats.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_stats)


## Прицел: точка и кольцо. Пока ружьё перезаряжается, кольцо заполняется по кругу;
## если метка на земле накрывает жуков — прицел красный.
func _draw_crosshair() -> void:
	var c := _crosshair
	var charge: float = gun.reload_progress()
	var hot: bool = gun.targets > 0
	var main := Color(1.0, 0.35, 0.2) if hot else Color(1, 1, 1)
	var shadow := Color(0, 0, 0, 0.5)
	var r := 15.0
	c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, shadow, 4.0, true)
	if charge >= 1.0:
		c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, main, 2.0, true)
	else:
		c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		c.draw_arc(Vector2.ZERO, r, -PI / 2, -PI / 2 + TAU * charge, 48, Color(1.0, 0.75, 0.3), 2.5, true)
	c.draw_circle(Vector2.ZERO, 3.0, shadow)
	c.draw_circle(Vector2.ZERO, 1.8, main)
	# Короткие засечки снаружи кольца
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2)
		c.draw_line(d * (r + 4.0), d * (r + 9.0), shadow, 4.0)
		c.draw_line(d * (r + 4.0), d * (r + 9.0), main, 2.0)


## Музыка по обстановке: меню — тема меню; бой — тема боя (между волнами тише); победа и
## поражение — заставка.
func _update_music() -> void:
	if not music:
		return
	if in_menu:
		music.want(MusicScript.MENU, 1.0)
		return
	var state: int = waves.state
	if state != _last_state:
		if state == waves.State.WON:
			music.sting(true)
		elif state == waves.State.LOST:
			music.sting(false)
		_last_state = state
	match state:
		# Бой — чуть тише полной громкости: музыка фоном, выстрелы и взрывы слышны поверх
		waves.State.FIGHT:
			music.want(MusicScript.FIGHT, 0.75)
		waves.State.READY:
			music.want(MusicScript.BUILD, 0.8)
		_:
			music.want(null, 0.0)


## Трофеи за убитых в этом бою (каждые TROPHY_KILLS — трофей, «Трофейщик» прибавляет) и
## кристаллы за убитых вожаков и боссов — сразу в сохранение: при проигрыше они не пропадают.
## win_bonus — победа: ещё половина трофеев сверху.
## Награда за рубежи орды (каждые 20 %): 1-й — 20 трофеев, 2-й — 30, … последний (вся орда
## разбита) — 60. Даже короткий проигранный бой двигает вперёд, и видно, что зайти дальше — это больше.
func step_reward(n: int) -> int:
	return int((10 + 10 * n) * Upgrades.milestone_mult())


func wave_bonus() -> int:
	var total := 0
	for n in range(1, waves.step + 1):
		total += step_reward(n)
	return total


func _commit_trophies(win_bonus := false) -> void:
	if not horde:
		return
	var earned := int((horde.kills / float(TROPHY_KILLS) + wave_bonus()) * Upgrades.trophy_mult())
	var gems: int = horde.minis_killed * 1 + horde.bosses_killed * 2 \
		+ (horde.minis_killed + horde.bosses_killed) * Upgrades.boss_crystals()
	if win_bonus:
		earned += int(earned * 0.5)
	Progress.trophies += maxi(earned - trophies_battle, 0)
	Progress.crystals += maxi(gems - crystals_battle, 0)
	trophies_battle = maxi(earned, trophies_battle)
	crystals_battle = maxi(gems, crystals_battle)
	hud.trophies_battle = trophies_battle
	hud.crystals_battle = crystals_battle
	Progress.save()


## Итоги боя для экрана в конце: сколько орды пройдено, рекорд, сколько улучшений в древе уже
## по карману — чтобы сразу было ясно, что делать дальше (прокачаться и снова в бой).
func _battle_summary() -> void:
	var reached: int = waves.percent()
	var before: int = int(Progress.best_progress.get(level_index, 0))
	hud.summary_wave = reached
	hud.summary_record = reached > before
	hud.summary_best = maxi(reached, before)
	if reached > before:
		Progress.best_progress[level_index] = reached
		Progress.save()
	# Что по карману — от дешёвого к дорогому, первые три
	var offers: Array = []
	for n: Dictionary in Upgrades.NODES:
		if Upgrades.can_buy(n["id"]):
			offers.append([Upgrades.cost_at(n["id"]), n["name"]])
	offers.sort()
	hud.summary_buy = offers.size()
	var names: Array[String] = []
	for k in mini(offers.size(), 3):
		names.append("%s (%d)" % [Lang.t(offers[k][1]), offers[k][0]])
	hud.summary_offer = " · ".join(names) + (Lang.t(" и ещё %d") % (offers.size() - 3) if offers.size() > 3 else "")


## Что уже по карману в древе: [сколько, «первые три (цена)»].
func _offers() -> Array:
	var offers: Array = []
	for n: Dictionary in Upgrades.NODES:
		if Upgrades.is_shown(n["id"]) and Upgrades.can_buy(n["id"]):
			offers.append([Upgrades.cost_at(n["id"]), n["name"]])
	offers.sort()
	var names: Array[String] = []
	for k in mini(offers.size(), 3):
		names.append("%s (%d)" % [Lang.t(offers[k][1]), offers[k][0]])
	return [offers.size(), " · ".join(names) + (Lang.t(" и ещё %d") % (offers.size() - 3) if offers.size() > 3 else "")]


## Кто убил больше всех за бой: [[название, сколько], …] — первые три.
func _best_killers() -> Array:
	var rows: Array = []
	for src: String in battle_kills_by:
		var name: String = SOURCE_NAMES.get(src, Mastery.ITEMS[src]["name"] if Mastery.ITEMS.has(src) else src)
		rows.append([int(battle_kills_by[src]), name])
	rows.sort()
	rows.reverse()
	return rows.slice(0, 3)


## Поражение: HUD и стройка прячутся, камера летит к месту прорыва, экран с итогами.
func _show_game_over() -> void:
	if turrets.building:
		set_building(false)
	hud.visible = false
	_hud_layer.visible = false
	turrets.set_ui_visible(false)
	var offers := _offers()
	var info := {
		"reached": hud.summary_wave, "best": hud.summary_best, "record": hud.summary_record,
		"step": waves.step, "steps": waves.STEPS, "kills": horde.kills, "time": waves._time,
		"trophies": trophies_battle, "total": Progress.trophies, "crystals": crystals_battle,
		"offer_count": offers[0], "offers": offers[1], "who": Mobs.who(horde.monster), "tunnel": _map.is_tunnel(),
		"killers": _best_killers(),
	}
	var gate := Vector3(0.0, 0.0, MapBuilder.GATE_Z)
	gate.y = _map.height(Vector2(gate.x, gate.z))
	_set_overview(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_over.show_loss(info, camera, gate)


## Локация пройдена: звёзды, а если впервые — награда (новое оружие или турель).
func _on_won() -> void:
	_commit_trophies(true)
	var first_time := not Progress.is_completed(level_index)
	hud.stars_added = Progress.complete(level_index, waves.gate_hp, waves.gate_max)
	hud.stars_got = Progress.stars_for(waves.gate_hp, waves.gate_max)
	var item := Mastery.reward_for(level_index)
	if first_time and item != "":
		var info: Dictionary = Mastery.ITEMS[item]
		hud.show_reward(info["name"], info["desc"], info["model"], info["kind"] == "turret")


## Опыт мастерства: убийства каждого оружия и турели за прошедшее время — в сохранение;
## выросший уровень мастерства — сообщением в бою. Заодно трофеи и кристаллы за бой.
func _commit_xp() -> void:
	_commit_trophies()
	if waves.state == waves.State.LOST or waves.state == waves.State.WON:
		_battle_summary()
	if not horde or horde.kills_by.is_empty():
		return
	for item: String in horde.kills_by:
		battle_kills_by[item] = int(battle_kills_by.get(item, 0)) + int(horde.kills_by[item])
	for item: String in horde.kills_by:
		if not Mastery.ITEMS.has(item):
			continue
		var grew := Mastery.add_xp(item, int(round(horde.kills_by[item] * Upgrades.xp_mult())))
		if grew > 0 and hud:
			hud.toast("%s: мастерство %d — очко в «Прокачку» (U)" % [Mastery.ITEMS[item]["name"],
				Mastery.level_of(item)], Mastery.ITEMS[item]["color"])
	horde.kills_by.clear()
	Progress.save()


func _exit_tree() -> void:
	_commit_xp()


## Новый уровень героя: шире взрыв ракет, короче перезарядка умений.
func _on_level_up(lvl: int, announce := true) -> void:
	abilities.cd_mult = maxf(1.0 - 0.035 * (lvl - 1), 0.5) * Upgrades.ability_cd_mult()
	for w in weapons:
		if "level_mult" in w:
			w.level_mult = 1.0 + 0.02 * (lvl - 1)
			w.refresh_stats()
	if announce:
		hud.level_up(lvl)


## Взять оружие по номеру (с 0): остальное убирается.
## Оружие, что уже открыто (награда или покупка во вкладке «Оружие»), но ещё не в руках, —
## добавить: купил в меню или посреди боя — сразу можно взять (клавиша или колесо).
func refresh_arsenal() -> void:
	var added := false
	for pair in [["flamer", FlamethrowerScript], ["gravigun", GravigunScript], ["minigun", MinigunScript],
			["saw", SawScript], ["lightning", LightningScript], ["hammer", HammerScript]]:
		if Mastery.is_unlocked(pair[0]) and not weapons.any(func(w: Node3D) -> bool: return w.get_script() == pair[1]):
			var w := _arm(pair[1])
			added = true
			if gun:
				w.set_active(false)
	if added and hud:
		hud.rebuild_stack()


func _arm(script: GDScript) -> Node3D:
	var w: Node3D = script.new()
	if script == BlunderbussScript:
		w.rockets = true
	w.horde = horde
	player.camera.add_child(w)
	weapons.append(w)
	return w


func select_weapon(index: int) -> void:
	gun = weapons[posmod(index, weapons.size())]
	for w in weapons:
		w.set_active(w == gun and not overview and not turrets.building)
	hud.gun = gun


## Режим строительства турелей: оружие убирается, площадки подсвечиваются.
func set_building(on: bool) -> void:
	turrets.set_building(on)
	hud.building = on
	select_weapon(weapons.find(gun))


func _set_overview(on: bool) -> void:
	overview = on
	player.set_active(not on)
	_crosshair.visible = not on
	for w in weapons:
		w.set_active(w == gun and not on)
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		camera.make_current()
		_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if in_menu:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			pause()
			return
		if game_over and game_over.active:
			# На экране поражения: Enter — снова в бой, U — прокачка, остальное не нужно
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				waves.start()
			elif event.physical_keycode == KEY_U:
				open_upgrades()
			return
		if event.keycode == KEY_TAB:
			if turrets.building:
				set_building(false)
			_set_overview(not overview)
			return
		if event.physical_keycode == KEY_U:
			open_upgrades()
			return
		if event.physical_keycode == KEY_B and not overview:
			set_building(not turrets.building)
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			waves.start()
			return
		if event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7] and event.keycode - KEY_1 < weapons.size() \
				and not overview and not turrets.building:
			select_weapon(event.keycode - KEY_1)
			return
		if event.keycode == KEY_F3:
			Settings.show_fps = not Settings.show_fps
			return
	if not overview:
		# Колесо мыши — следующее или предыдущее оружие (в строительстве колесо листает турели)
		if not turrets.building and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			select_weapon(weapons.find(gun) + step)
		return
	if event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_LEFT):
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.5, -0.08)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance * 0.9, 12.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance * 1.1, 600.0)
		_update_camera()


func _process(delta: float) -> void:
	_update_music()
	if in_menu:
		_update_menu_camera(delta)
		return
	# Опыт героя — за каждого убитого (кем угодно: ракетами, умениями, турелями)
	if horde.kills > _kills_seen:
		player.add_xp(horde.kills - _kills_seen)
		_kills_seen = horde.kills
	hud.trophies_live = int((horde.kills / float(TROPHY_KILLS) + wave_bonus()) * Upgrades.trophy_mult())
	if not overview:
		_crosshair.queue_redraw()
		# После победы или поражения прицел не мешает надписям и награде
		_crosshair.visible = not overview and waves.state != waves.State.WON and waves.state != waves.State.LOST
	_hint_time -= delta
	_hint.modulate.a = clampf(_hint_time, 0.0, 1.0)
	Settings.adapt(delta)
	_stats.visible = Settings.show_fps
	if _stats.visible:
		_stats.text = "FPS %d · жуков %d · убито %d" % [Engine.get_frames_per_second(), horde.count(), horde.kills]
		if Settings.auto_step() > 0:
			_stats.text += " · авто −%d" % Settings.auto_step()
	if not overview:
		return
	var move := Vector2.ZERO
	for key in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_physical_key_pressed(key[0]):
			move += key[1]
	if move != Vector2.ZERO:
		var v := move.normalized().rotated(-yaw) * distance * 0.6 * delta
		target += Vector3(v.x, 0, v.y)
		_update_camera()


## Фон меню: камера медленно облетает каньоны, время от времени по орде рвутся снаряды.
func _update_menu_camera(delta: float) -> void:
	_menu_time += delta
	if _map.is_tunnel():
		# Долина: камера у туннеля и вышки героя медленно ходит из стороны в сторону, смотрит на
		# север — орда идёт прямо на зрителя
		var k := sin(_menu_time * 0.06)
		var xz := Vector2(10.0 + k * 22.0, 84.0 - absf(k) * 6.0)
		camera.global_position = Vector3(xz.x, _map.height(xz) + 13.0, xz.y)
		camera.look_at(Vector3(-14.0 + k * 10.0, 2.0, 28.0), Vector3.UP)
	else:
		var a := 0.9 + _menu_time * MENU_ORBIT_SPEED
		var from := MENU_ORBIT_CENTER + Vector3(sin(a) * MENU_ORBIT_RADIUS, MENU_ORBIT_HEIGHT, cos(a) * MENU_ORBIT_RADIUS)
		camera.global_position = from
		camera.look_at(MENU_ORBIT_CENTER + Vector3(0, -6, 0), Vector3.UP)
	_menu_boom -= delta
	if _menu_boom <= 0.0 and horde.count() > 50:
		_menu_boom = MENU_BOOM_EVERY * randf_range(0.6, 1.4)
		var p: Vector2 = horde._pos[randi() % horde.count()]
		var boom := ExplosionScript.new()
		boom.horde = horde
		boom.silent = true
		boom.position = Vector3(p.x, horde._floor_at(p), p.y)
		add_child(boom)


## Поставить камеру вида сверху по углам и расстоянию вокруг точки target.
func _update_camera() -> void:
	var offset := Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, distance)
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)


## Камера вида сверху в точку и на цель (для скриншотов).
func view_from(from: Vector3, look: Vector3) -> void:
	_set_overview(true)
	camera.global_position = from
	camera.look_at(look, Vector3.UP)
