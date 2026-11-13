extends RefCounted
## Настройки игрока: чувствительность мыши, громкость, полный экран, счётчик FPS, качество графики.
## Хранятся в user://settings.cfg, читаются один раз при запуске и сразу применяются.

const Lang := preload("res://core/lang.gd")

const PATH := "user://settings.cfg"

static var sensitivity := 1.0    # множитель к базовой чувствительности мыши
static var volume := 0.8         # общая громкость, 0..1
static var music_volume := 0.6   # громкость музыки (шина «Music»), 0..1
static var fullscreen := false
static var show_fps := false
## Качество графики: 0 — минимальное (для слабых ПК и встроенной графики), 1 — низкое,
## 2 — среднее, 3 — высокое. Ниже — 3D рисуется в меньшем разрешении (FSR растягивает,
## интерфейс остаётся чётким), меньше сглаживания и частиц, проще тени; на минимальном теней нет.
static var quality := 2
const QUALITY_NAMES := ["Минимальное", "Низкое", "Среднее", "Высокое"]
const QUALITY_MAX := 3
## Авто-качество: если кадров мало (слабая видеокарта, большой бой), 3D понемногу рисуется в
## меньшем разрешении, а на нижних ступенях — без затенения и сглаживания; когда снова легко —
## качество возвращается. Интерфейс остаётся чётким всегда.
static var auto_quality := true
## Язык интерфейса: "ru" или "en" (core/lang.gd). Пусто — ещё не выбран: по языку системы.
static var language := ""
## Окружение и солнце текущей сцены (их передаёт main.gd): качество меняет и их.
static var env: Environment
static var sun: DirectionalLight3D

static var _loaded := false


static func load_settings() -> void:
	load("res://core/progress.gd").migrate_old_save()
	if _loaded:
		return
	_loaded = true
	# Первый запуск — качество по видеокарте (потом игрок выбирает сам)
	quality = _default_quality()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		sensitivity = cfg.get_value("game", "sensitivity", sensitivity)
		volume = cfg.get_value("game", "volume", volume)
		music_volume = cfg.get_value("game", "music_volume", music_volume)
		fullscreen = cfg.get_value("game", "fullscreen", fullscreen)
		show_fps = cfg.get_value("game", "show_fps", show_fps)
		if cfg.has_section_key("game", "graphics"):
			quality = clampi(cfg.get_value("game", "graphics", quality), 0, QUALITY_MAX)
		elif cfg.has_section_key("game", "quality"):
			# Старая настройка (0 низкое…2 высокое) — до появления «Минимального»
			quality = clampi(int(cfg.get_value("game", "quality", 1)) + 1, 0, QUALITY_MAX)
		auto_quality = cfg.get_value("game", "auto_quality", auto_quality)
		language = cfg.get_value("game", "language", language)
	apply()


## Качество для первого запуска: запасной рендер (OpenGL) или программная отрисовка без видеокарты —
## минимальное; встроенная графика (кроме Apple) — низкое; иначе — среднее.
static func _default_quality() -> int:
	if load("res://core/fx_budget.gd").lite():
		return 0
	var kind := RenderingServer.get_video_adapter_type()
	if kind == RenderingDevice.DEVICE_TYPE_CPU:
		return 0
	if kind == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU and not RenderingServer.get_video_adapter_vendor().containsn("apple"):
		return 1
	return 2


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "sensitivity", sensitivity)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("game", "music_volume", music_volume)
	cfg.set_value("game", "fullscreen", fullscreen)
	cfg.set_value("game", "show_fps", show_fps)
	cfg.set_value("game", "graphics", quality)
	cfg.set_value("game", "auto_quality", auto_quality)
	cfg.set_value("game", "language", language)
	cfg.save(PATH)


static func apply() -> void:
	if language == "":
		language = Lang.system_language()
	Lang.set_language(language)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	# Шина музыки — своя громкость, дальше идёт в общую
	var music := AudioServer.get_bus_index("Music")
	if music < 0:
		AudioServer.add_bus()
		music = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music, "Music")
		AudioServer.set_bus_send(music, "Master")
	AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen != full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not auto_quality:
		_step = 0
	_apply_graphics()
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if quality < 3
		else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, quality < 3, 0.5, 2, 50.0, 300.0)
	if is_instance_valid(sun):
		sun.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_ORTHOGONAL,
			DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][quality]
		sun.directional_shadow_max_distance = [100.0, 140.0, 230.0, 320.0][quality]


# --- авто-качество ------------------------------------------------------------------------------

## Ступени понижения: доля от разрешения 3D выбранного качества. Со ступени NO_EXTRAS_STEP — ещё
## без затенения (SSAO) и сглаживания, и эффекты (дым, частицы) скромнее; с NO_SHADOW_STEP — без теней.
const STEPS := [1.0, 0.88, 0.76, 0.66, 0.58, 0.5]
const NO_EXTRAS_STEP := 3
const NO_SHADOW_STEP := 4         # с этой ступени — и без теней (как «Минимальное»)
const MIN_SCALE := 0.35
const FPS_LOW := 50.0            # ниже — понижаем
const FPS_HIGH := 58.0           # выше (долго) — пробуем вернуть
const LOW_TIME := 1.2            # с подряд с низким FPS до понижения
const HIGH_TIME := 6.0           # с подряд с хорошим FPS до повышения
const HOLD_AFTER_DROP := 15.0    # с после понижения не повышаем — чтобы не качалось

static var _step := 0
static var _avg_dt := 1.0 / 60.0
static var _low := 0.0
static var _high := 0.0
static var _hold := 0.0


## Разрешение, сглаживание, затенение и детальность эффектов — по качеству и ступени авто-качества.
static func _apply_graphics() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var bare := _step >= NO_EXTRAS_STEP
	if tree:
		var vp := tree.root
		var scale: float = [0.5, 0.6, 0.8, 1.0][quality] * STEPS[_step]
		# FSR есть только в Forward+; на запасном рендере (OpenGL, старые видеокарты) — простое растяжение
		var fsr := scale < 0.999 and RenderingServer.get_current_rendering_method() == "forward_plus"
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = maxf(scale, MIN_SCALE)
		vp.msaa_3d = Viewport.MSAA_DISABLED if bare else [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	if is_instance_valid(env):
		env.ssao_enabled = quality > 1 and not bare
	if is_instance_valid(sun):
		sun.shadow_enabled = quality > 0 and _step < NO_SHADOW_STEP
	load("res://core/fx_budget.gd").set_detail(quality, bare)


## Каждый кадр (main.gd): следит за частотой кадров и двигает ступень авто-качества.
static func adapt(delta: float) -> void:
	if not auto_quality or delta <= 0.0 or delta > 0.5:
		return
	_avg_dt = lerpf(_avg_dt, delta, 0.08)
	var fps := 1.0 / _avg_dt
	_hold = maxf(_hold - delta, 0.0)
	_low = _low + delta if fps < FPS_LOW else 0.0
	_high = _high + delta if fps > FPS_HIGH and _hold == 0.0 else 0.0
	if _low >= LOW_TIME and _step < STEPS.size() - 1:
		_step += 1
		_low = 0.0
		_hold = HOLD_AFTER_DROP
		_apply_graphics()
	elif _high >= HIGH_TIME and _step > 0:
		_step -= 1
		_high = 0.0
		_apply_graphics()


## Текущая ступень авто-качества (0 — без понижения), для счётчика FPS.
static func auto_step() -> int:
	return _step
