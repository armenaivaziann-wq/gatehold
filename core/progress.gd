extends RefCounted
## Прохождение: какие локации открыты и пройдены, звёзды за них и купленные улучшения
## (upgrades.gd). Первая открыта всегда; пройдёшь локацию — открывается следующая.
## Хранится в user://progress.cfg.

const Levels := preload("res://locations/levels.gd")
const PATH := "user://progress.cfg"
## Прежнее имя проекта: сохранения лежали в его папке (app_userdata/<имя>) — переносим их.
const OLD_NAME := "3D orcs"

## Сколько локаций открыто (с начала списка).
static var unlocked := 1
## Пройденные локации и сколько прочности ворот при этом осталось (лучший результат).
static var best := {}
## Лучшие звёзды за локацию (1–3): ≥90% прочности ворот — три, ≥50% — две, иначе одна.
static var stars := {}
## Рекорд: до какой волны дошёл на каждой локации (и в проигранных боях).
static var best_progress := {}
## Купленные улучшения общего древа: id узла → уровень.
static var upgrades := {}
## Трофеи (за убитых в любом бою, и при проигрыше) и кристаллы (за убитых боссов) — валюта
## общего древа (upgrades.gd).
static var trophies := 0
static var crystals := 0
## Сколько трофеев даёт каждая звезда, когда старое древо (на звёздах) переводится на трофеи.
const TROPHIES_PER_STAR := 40
## Мастерство (mastery.gd): опыт оружия и турелей и купленные узлы их деревьев.
static var xp := {}
static var mastery := {}
## Обучение на первой локации пройдено или скрыто.
static var tutorial_done := false

static var _loaded := false
## Ничего не записывать на диск (тесты и снимки — чтобы не трогать прогресс игрока).
static var read_only := false


## Игра переименована: если в новой папке ещё нет прогресса и настроек, скопировать их из
## папки прежнего имени.
static func migrate_old_save() -> void:
	var old_dir := OS.get_user_data_dir().get_base_dir().path_join(OLD_NAME)
	for file: String in ["progress.cfg", "settings.cfg"]:
		var to := "user://" + file
		var from := old_dir.path_join(file)
		if not FileAccess.file_exists(to) and FileAccess.file_exists(from):
			DirAccess.copy_absolute(from, ProjectSettings.globalize_path(to))


static func load_progress() -> void:
	if _loaded:
		return
	_loaded = true
	migrate_old_save()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		unlocked = clampi(cfg.get_value("progress", "unlocked", 1), 1, Levels.count())
		best = cfg.get_value("progress", "best", {})
		stars = cfg.get_value("progress", "stars", {})
		best_progress = cfg.get_value("progress", "best_progress", {})
		upgrades = cfg.get_value("progress", "upgrades", {})
		xp = cfg.get_value("progress", "xp", {})
		mastery = cfg.get_value("progress", "mastery", {})
		tutorial_done = cfg.get_value("progress", "tutorial_done", false)
		trophies = cfg.get_value("progress", "trophies", -1)
		crystals = cfg.get_value("progress", "crystals", 0)
		if trophies < 0:
			# Сохранение до трофеев: древо было на звёздах — покупки сбрасываются, звёзды
			# возвращаются трофеями
			upgrades = {}
			trophies = 0
			for i in stars:
				trophies += int(stars[i]) * TROPHIES_PER_STAR
		# Старые сохранения: звёзды по остатку ворот из прежнего максимума (500)
		for i in best:
			if not stars.has(i):
				stars[i] = stars_for(int(best[i]), 500)


static func save() -> void:
	if read_only:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "best_progress", best_progress)
	cfg.set_value("progress", "upgrades", upgrades)
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "mastery", mastery)
	cfg.set_value("progress", "tutorial_done", tutorial_done)
	cfg.set_value("progress", "trophies", trophies)
	cfg.set_value("progress", "crystals", crystals)
	cfg.save(PATH)


static func is_unlocked(index: int) -> bool:
	return index < unlocked


static func is_completed(index: int) -> bool:
	return best.has(index)


## Звёзды за остаток прочности ворот hp из max_hp.
static func stars_for(hp: int, max_hp: int) -> int:
	var k := float(hp) / maxf(max_hp, 1.0)
	return 3 if k >= 0.9 else (2 if k >= 0.5 else 1)


## Локация пройдена с остатком прочности ворот gate_hp из gate_max: открыть следующую,
## запомнить рекорд. Возвращает, сколько звёзд добавилось (0 — рекорд не побит).
static func complete(index: int, gate_hp: int, gate_max: int) -> int:
	best[index] = maxi(int(best.get(index, 0)), gate_hp)
	var got := stars_for(gate_hp, gate_max)
	var added := maxi(got - int(stars.get(index, 0)), 0)
	stars[index] = maxi(int(stars.get(index, 0)), got)
	unlocked = clampi(maxi(unlocked, index + 2), 1, Levels.count())
	save()
	return added


## Последняя открытая локация — с неё начинается игра и её показывает фон меню.
static func last_unlocked() -> int:
	return unlocked - 1
