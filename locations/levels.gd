extends RefCounted
## Десять локаций. Каждая — своя раскладка каналов (число пещер, ширина, извивы, перемычки),
## свой биом (цвета рельефа, свет, небо, туман), свои детали вокруг и особенность (вода в
## каналах, светящиеся трещины, светящиеся кристаллы). Сложность растёт от локации к локации:
## волны больше. Следующая локация открывается, когда пройдена предыдущая (progress.gd).
##
## Раскладка: «paths» — каналы вручную, или параметры генератора make_paths():
## caves — сколько пещер, width — полуширина дна, amp — размах извивов, waves — сколько
## извивов на пути, bridges — перемычек между соседними каналами, seed — зерно случайности.
## monster — кто идёт ("bug" по умолчанию или "goblin"), speed — множитель их скорости,
## difficulty — во сколько раз орда больше и злее первой; pattern — характер наступления
## (waves.gd: PATTERNS — натиски, фланги, засада, извержения…),
## boss — имя босса последней волны (на 5-й волне — его вожак поменьше).
## horizon — что стоит кольцом за краем карты (map_builder.gd): mesas, spires, dunes, hills, peaks,
## moon, volcano, crystals, hive.
## Детали: mesh — rock, shrub, spike, cactus, pine, dead_tree, mushroom, reed, pillar, mound,
## oak, hut, stakes;
## where — top (плато подальше от края), edge (плато у края), floor (дно у стенок), any.

const LEVELS := [
	{
		"name": "Гоблинский лес", "desc": "Лесная долина в кольце скал. Орда гоблинов идёт из лагерей на севере к туннелю на юге.",
		"difficulty": 1.2, "pattern": "steady", "boss": "Вождь гоблинов", "mini": "Вожак гоблинов",
		"boss_model": "res://mobs/bosses/goblin_chief.glb", "mini_model": "res://mobs/bosses/goblin_rider.glb", "monster": "goblin", "speed": 0.9,
		# Замкнутая долина: по краю — скалы (valley, bounds — где можно летать), вместо крепости —
		# вход в туннель в южном хребте (gate: tunnel), рядом — смотровая вышка героя
		"style": "converge", "horizon": "hills", "valley": true, "gate": "tunnel",
		"bounds": Rect2(-80.0, -36.0, 160.0, 140.0), "saturation": 0.72,
		"caves": 3, "width": 5.0, "amp": 9.0, "waves": 1.0, "bridges": 0, "seed": 606, "cracks": 6,
		"starts": [Vector2(-104, -106), Vector2(0, -108), Vector2(104, -106)],
		"palette": {
			"top": Color("61834d"), "rim": Color("84a265"), "crack": Color("4d6c3c"), "wall": Color("5e4c3a"),
			"floor": Color("7b654c"), "rock": Color("737368"), "stone": Color("949084"), "wood": Color("4c3929"),
			"cave": Color("120d09"),
		},
		# Предвечерний тёплый свет: солнце ниже, длинные тени, лёгкая дымка вглубь долины
		"light": {"sky": Color(0.72, 0.78, 0.82), "ambient": Color(0.78, 0.8, 0.74), "ambient_energy": 0.44,
			"sun": Color(1.0, 0.86, 0.68), "sun_energy": 1.05, "sun_rot": Vector3(-27, -38, 0),
			"fog_begin": 90.0, "fog_end": 620.0},
		"props": [
			{"mesh": "oak", "count": 85, "where": "top", "min": 1.6, "max": 2.8, "color": Color("ffffff")},
			{"mesh": "pine", "count": 35, "where": "top", "min": 2.2, "max": 3.6, "color": Color("3f6e34")},
			{"mesh": "hut", "count": 5, "where": "top", "min": 1.6, "max": 2.1, "color": Color("ffffff")},
			{"mesh": "shrub", "count": 130, "where": "top", "min": 0.7, "max": 1.3, "color": Color("4f8a34")},
		],
	},
	{
		"name": "Песчаные каньоны", "desc": "Три пещеры, лабиринт с перемычками. Здесь всё начинается.",
		"difficulty": 2.1, "pattern": "surges", "boss": "Песчаный великан", "monster": "scarab", "boss_model": "res://mobs/bosses/sand_giant.glb", "mini": "Молодой рогач",
		"paths": [
			{"w": 5.0, "pts": [Vector2(-88, -106), Vector2(-70, -82), Vector2(-92, -52), Vector2(-66, -28),
				Vector2(-80, 0), Vector2(-52, 22), Vector2(-40, 52), Vector2(-16, 78), Vector2(0, 96)]},
			{"w": 5.0, "pts": [Vector2(4, -106), Vector2(22, -80), Vector2(-6, -58), Vector2(18, -34),
				Vector2(-4, -8), Vector2(24, 14), Vector2(10, 44), Vector2(16, 70), Vector2(0, 96)]},
			{"w": 5.0, "pts": [Vector2(90, -106), Vector2(68, -84), Vector2(92, -58), Vector2(60, -36),
				Vector2(84, -6), Vector2(50, 18), Vector2(60, 50), Vector2(30, 76), Vector2(0, 96)]},
			{"w": 3.5, "pts": [Vector2(18, -34), Vector2(-20, -24), Vector2(-46, -38), Vector2(-66, -28)]},
			{"w": 3.5, "pts": [Vector2(60, -36), Vector2(42, -54), Vector2(22, -80)]},
			{"w": 3.5, "pts": [Vector2(-52, 22), Vector2(-22, 34), Vector2(10, 44)]},
			{"w": 3.5, "pts": [Vector2(24, 14), Vector2(50, 18)]},
		],
		"caves": 3,
		"horizon": "mesas",
		"palette": {
			"top": Color("e8a853"), "rim": Color("f6cf8f"), "crack": Color("b8742f"), "wall": Color("a35c28"),
			"floor": Color("b97a3e"), "rock": Color("8c5a33"), "stone": Color("b9a184"), "wood": Color("6b4326"),
			"cave": Color("2a1a10"),
		},
		"light": {"sky": Color("f2d6a8"), "ambient": Color("ffe2b8"), "ambient_energy": 0.55,
			"sun": Color(1.0, 0.96, 0.9), "sun_energy": 1.0, "sun_rot": Vector3(-52, -35, 0),
			"fog_begin": 300.0, "fog_end": 1200.0},
		"props": [
			{"mesh": "rock", "count": 170, "where": "top_floor", "min": 0.6, "max": 2.4, "color": Color("8c5a33")},
			{"mesh": "rock", "count": 600, "where": "any", "min": 0.12, "max": 0.35, "color": Color("c98f55")},
			{"mesh": "shrub", "count": 140, "where": "top", "min": 0.8, "max": 1.6, "color": Color("7d6a3a")},
		],
	},
	{
		"name": "Солончак", "desc": "Белая соль до горизонта. Две пещеры, длинный серпантин — жуки бегут быстрее.",
		"difficulty": 2.7, "pattern": "rush", "tough": 2.45, "coins": 0.26, "boss": "Соляной великан", "monster": "crab", "boss_model": "res://mobs/bosses/salt_giant.glb", "mini": "Соляной скарабей",
		"style": "switchback", "rows": 3, "span": 50.0, "z0": -40.0, "z1": 60.0, "speed": 1.75, "horizon": "dunes",
		"caves": 2, "width": 6.0, "amp": 30.0, "waves": 1.6, "bridges": 0, "seed": 101,
		"starts": [Vector2(-106, -66), Vector2(-40, -106)],
		"palette": {
			"top": Color("d8cdbd"), "rim": Color("efe8de"), "crack": Color("b3a28f"), "wall": Color("a8927e"),
			"floor": Color("c4b19b"), "rock": Color("a8988a"), "stone": Color("cfc3b4"), "wood": Color("6b5040"),
			"cave": Color("3a3028"),
		},
		"light": {"sky": Color("bcd2e2"), "ambient": Color("dfe6ee"), "ambient_energy": 0.5,
			"sun": Color(1.0, 0.97, 0.92), "sun_energy": 0.95, "sun_rot": Vector3(-42, -25, 0),
			"fog_begin": 250.0, "fog_end": 1000.0},
		"props": [
			{"mesh": "spike", "count": 120, "where": "top", "min": 0.6, "max": 1.6, "color": Color("f6f2ec")},
			{"mesh": "rock", "count": 400, "where": "any", "min": 0.1, "max": 0.3, "color": Color("d8ccbc")},
			{"mesh": "rock", "count": 60, "where": "top", "min": 0.6, "max": 1.4, "color": Color("bfb0a0")},
		],
	},
	{
		"name": "Красная гряда", "desc": "Узкие зигзаги в красном камне. Каменные столбы-останцы.",
		"difficulty": 2.7, "pattern": "armored", "horde": 1.04, "tough": 1.7, "coins": 0.5, "speed": 1.7, "boss": "Красный титан", "monster": "ant", "boss_model": "res://mobs/bosses/red_titan.glb", "mini": "Каменный жук",
		"caves": 3, "width": 4.0, "amp": 22.0, "waves": 4.0, "bridges": 3, "seed": 202, "horizon": "spires",
		"palette": {
			"top": Color("c8643c"), "rim": Color("e3926a"), "crack": Color("8a3a20"), "wall": Color("8c3a22"),
			"floor": Color("a24d2c"), "rock": Color("7a3420"), "stone": Color("c08a6a"), "wood": Color("5a3220"),
			"cave": Color("2a120a"),
		},
		"light": {"sky": Color("f2c49a"), "ambient": Color("ffcfa8"), "ambient_energy": 0.55,
			"sun": Color(1.0, 0.82, 0.62), "sun_energy": 1.1, "sun_rot": Vector3(-28, -60, 0),
			"fog_begin": 260.0, "fog_end": 1000.0},
		"props": [
			{"mesh": "pillar", "count": 45, "where": "top", "min": 1.6, "max": 3.2, "color": Color("b0532e")},
			{"mesh": "rock", "count": 160, "where": "top_floor", "min": 0.6, "max": 2.0, "color": Color("7a3420")},
			{"mesh": "rock", "count": 400, "where": "any", "min": 0.12, "max": 0.3, "color": Color("c06a44")},
		],
	},
	{
		"name": "Сухая степь", "desc": "Выгоревшая трава и мёртвые деревья. Рой идёт с флангов — с запада и востока.",
		"difficulty": 3.0, "pattern": "flank", "boss": "Король-энт", "monster": "locust", "boss_model": "res://mobs/bosses/treant_king.glb", "mini": "Степной вожак",
		"caves": 4, "width": 4.5, "amp": 18.0, "waves": 2.0, "bridges": 1, "seed": 303, "horizon": "hills",
		"starts": [Vector2(-106, -70), Vector2(-106, 10), Vector2(106, -30), Vector2(106, 45)],
		"palette": {
			"top": Color("b4a24e"), "rim": Color("d8c87a"), "crack": Color("857432"), "wall": Color("8a6a3a"),
			"floor": Color("9c7c4a"), "rock": Color("7a7268"), "stone": Color("b8ad98"), "wood": Color("5c4030"),
			"cave": Color("201810"),
		},
		"light": {"sky": Color("dfe6e6"), "ambient": Color("eef0e2"), "ambient_energy": 0.55,
			"sun": Color(1.0, 0.95, 0.85), "sun_energy": 1.05, "sun_rot": Vector3(-50, 20, 0),
			"fog_begin": 260.0, "fog_end": 1100.0},
		"props": [
			{"mesh": "shrub", "count": 420, "where": "top", "min": 0.7, "max": 1.4, "color": Color("9a9a3e")},
			{"mesh": "dead_tree", "count": 40, "where": "top", "min": 1.6, "max": 2.6, "color": Color("6a5440")},
			{"mesh": "rock", "count": 90, "where": "top_floor", "min": 0.6, "max": 1.8, "color": Color("7a7268")},
		],
	},
	{
		"name": "Ледяная пустошь", "desc": "Снег, ледяные шипы и ели. Каналы впадают в кольцо вокруг ледяного плато.",
		"difficulty": 3.4, "pattern": "tide", "tough": 2.0, "coins": 0.28, "speed": 1.7, "boss": "Ледяной великан", "monster": "ice_spider", "boss_model": "res://mobs/bosses/ice_giant.glb", "mini": "Ледяной жук",
		"style": "ring", "ring": 44.0, "caves": 3, "width": 5.0, "amp": 22.0, "waves": 2.0, "bridges": 0, "seed": 404,
		"horizon": "peaks",
		"palette": {
			"top": Color("e4edf7"), "rim": Color("fbfdff"), "crack": Color("93b1d6"), "wall": Color("7f9cc4"),
			"floor": Color("b7cae2"), "rock": Color("6f86a6"), "stone": Color("a9b2bf"), "wood": Color("5c4433"),
			"cave": Color("1b2433"),
		},
		"light": {"sky": Color("cfe0f2"), "ambient": Color("dde9f7"), "ambient_energy": 0.6,
			"sun": Color(0.95, 0.97, 1.0), "sun_energy": 0.95, "sun_rot": Vector3(-40, -50, 0),
			"fog_begin": 200.0, "fog_end": 900.0},
		"props": [
			{"mesh": "pine", "count": 70, "where": "top", "min": 1.6, "max": 2.8, "color": Color("3f6a5a")},
			{"mesh": "spike", "count": 90, "where": "top", "min": 0.8, "max": 1.8, "color": Color("9fd0f0"), "glow": 0.3},
			{"mesh": "rock", "count": 300, "where": "any", "min": 0.12, "max": 0.35, "color": Color("9fb2cc")},
		],
	},
	{
		"name": "Ночная пустыня", "desc": "Ночь, луна и кактусы. Шесть пещер и шесть дорожек с перемычками — рой льётся отовсюду.",
		"difficulty": 3.0, "pattern": "ambush", "horde": 1.1, "tough": 0.75, "coins": 1.12, "boss": "Ночное чудище", "monster": "scorpion", "boss_model": "res://mobs/bosses/night_beast.glb", "mini": "Ночной вожак",
		"style": "lanes", "caves": 6, "width": 3.6, "amp": 6.0, "waves": 2.0, "bridges": 9, "seed": 505,
		"horizon": "moon",
		"palette": {
			"top": Color("c9945a"), "rim": Color("e0b680"), "crack": Color("8a5a30"), "wall": Color("8a4e26"),
			"floor": Color("9a6436"), "rock": Color("6e4a30"), "stone": Color("a8967e"), "wood": Color("5a3a20"),
			"cave": Color("100a06"),
		},
		"light": {"sky": Color("1a2038"), "ambient": Color("6c7cb0"), "ambient_energy": 0.75,
			"sun": Color(0.62, 0.72, 1.0), "sun_energy": 0.7, "sun_rot": Vector3(-45, 140, 0),
			"fog_begin": 150.0, "fog_end": 700.0},
		"props": [
			{"mesh": "cactus", "count": 80, "where": "top", "min": 1.2, "max": 2.2, "color": Color("4f7a46")},
			{"mesh": "rock", "count": 140, "where": "top_floor", "min": 0.6, "max": 2.0, "color": Color("6e4a30")},
			{"mesh": "rock", "count": 400, "where": "any", "min": 0.12, "max": 0.3, "color": Color("a87a4e")},
		],
	},
	{
		"name": "Вулкан", "desc": "Чёрный базальт, светящиеся трещины лавы, вулкан на горизонте. Широкий ствол распадается на пять рукавов.",
		"difficulty": 4.1, "pattern": "eruption", "tough": 1.85, "coins": 0.3, "speed": 1.65, "boss": "Огненный демон", "monster": "imp", "boss_model": "res://mobs/bosses/fire_demon.glb", "mini": "Огненный жук",
		"style": "delta", "arms": 5, "caves": 3, "width": 4.5, "amp": 22.0, "waves": 1.0, "bridges": 2, "seed": 707,
		"horizon": "volcano",
		"crack_glow": 2.5, "cracks": 160,
		"palette": {
			"top": Color("3c3534"), "rim": Color("5c504c"), "crack": Color("ff6a1e"), "wall": Color("2a2424"),
			"floor": Color("4a2c22"), "rock": Color("222020"), "stone": Color("5a5250"), "wood": Color("3a2a20"),
			"cave": Color("ff4a10"),
		},
		"light": {"sky": Color("5c3a32"), "ambient": Color("c88a70"), "ambient_energy": 0.6,
			"sun": Color(1.0, 0.6, 0.4), "sun_energy": 0.9, "sun_rot": Vector3(-30, -110, 0),
			"fog_begin": 150.0, "fog_end": 700.0},
		"props": [
			{"mesh": "spike", "count": 110, "where": "top", "min": 0.8, "max": 2.2, "color": Color("1a1618")},
			{"mesh": "rock", "count": 160, "where": "top_floor", "min": 0.6, "max": 2.0, "color": Color("2a2626")},
			{"mesh": "rock", "count": 300, "where": "any", "min": 0.12, "max": 0.3, "color": Color("4a3a36")},
		],
	},
	{
		"name": "Кристальное плато", "desc": "Сумерки и гигантские кристаллы. Шесть пещер со всех сторон сходятся на площади.",
		"difficulty": 4.5, "pattern": "siege", "tough": 2.3, "coins": 0.28, "speed": 1.7, "boss": "Кристальный великан", "monster": "crystal_mite", "boss_model": "res://mobs/bosses/crystal_giant.glb", "mini": "Кристальный вожак",
		"style": "clearing", "center": Vector2(0, -22), "clearing": 18.0, "forks": [-52.0, 0.0, 52.0],
		"caves": 6, "width": 4.5, "amp": 16.0, "waves": 1.5, "bridges": 0, "seed": 808, "horizon": "crystals",
		"starts": [Vector2(-106, -96), Vector2(-40, -108), Vector2(40, -108), Vector2(106, -96),
			Vector2(-108, -10), Vector2(108, -10)],
		"crack_glow": 1.6,
		"palette": {
			"top": Color("6c5c8c"), "rim": Color("a28cd2"), "crack": Color("c070ff"), "wall": Color("4a3a6c"),
			"floor": Color("5a4a7c"), "rock": Color("3e3458"), "stone": Color("8a80a0"), "wood": Color("3a2a40"),
			"cave": Color("120a1c"),
		},
		"light": {"sky": Color("2c2244"), "ambient": Color("9a8cd0"), "ambient_energy": 0.7,
			"sun": Color(0.8, 0.75, 1.0), "sun_energy": 0.75, "sun_rot": Vector3(-35, 60, 0),
			"fog_begin": 160.0, "fog_end": 750.0},
		"props": [
			{"mesh": "spike", "count": 90, "where": "top", "min": 1.0, "max": 2.6, "color": Color("5ee0ff"), "glow": 1.4},
			{"mesh": "spike", "count": 60, "where": "top", "min": 0.8, "max": 2.0, "color": Color("ff6ae0"), "glow": 1.4},
			{"mesh": "rock", "count": 300, "where": "any", "min": 0.12, "max": 0.35, "color": Color("4a4068")},
		],
	},
	{
		"name": "Гнездо роя", "desc": "Сердце роя: ульи из песка и смолы. Пять пещер со всех сторон. Последний бой.",
		"difficulty": 5.0, "pattern": "hive", "tough": 1.12, "speed": 1.4, "boss": "Владыка орды", "monster": "wasp", "boss_model": "res://mobs/bosses/horde_warlord.glb", "mini": "Страж королевы",
		"caves": 5, "width": 5.0, "amp": 20.0, "waves": 2.5, "bridges": 8, "seed": 909, "horizon": "hive",
		"starts": [Vector2(-106, -20), Vector2(-62, -106), Vector2(0, -106), Vector2(62, -106), Vector2(106, -20)],
		"palette": {
			"top": Color("8c6a48"), "rim": Color("ad8a5c"), "crack": Color("5a3a28"), "wall": Color("6a4a32"),
			"floor": Color("5a3a26"), "rock": Color("4a3020"), "stone": Color("a08c74"), "wood": Color("4a3020"),
			"cave": Color("1a0c06"),
		},
		"light": {"sky": Color("cfa072"), "ambient": Color("e6c39a"), "ambient_energy": 0.55,
			"sun": Color(1.0, 0.85, 0.65), "sun_energy": 0.95, "sun_rot": Vector3(-38, -80, 0),
			"fog_begin": 110.0, "fog_end": 520.0},
		"props": [
			{"mesh": "mound", "count": 45, "where": "top", "min": 1.8, "max": 3.6, "color": Color("9a7650")},
			{"mesh": "spike", "count": 90, "where": "top", "min": 0.6, "max": 1.4, "color": Color("c08a2a"), "glow": 0.25},
			{"mesh": "rock", "count": 300, "where": "any", "min": 0.12, "max": 0.35, "color": Color("6a4a32")},
		],
	},
]


## Во сколько раз тропы короче исходной раскладки (стянуты к воротам) и точка, к которой стянуты.
const PATH_SCALE := 0.62
const GATE_ANCHOR := 100.0


static func count() -> int:
	return LEVELS.size()


static func get_level(index: int) -> Dictionary:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


## Каналы локации: из «paths» или сгенерированные. Первые caves каналов начинаются у пещер;
## последний — широкий участок перед воротами. Тип раскладки (style):
##   converge — каналы от пещер на севере петляют и сходятся к воротам;
##   switchback — от пещер в один длинный серпантин (rows проходов шириной ±span от z0 до z1);
##   ring — каналы впадают в кольцо вокруг центрального плато, из кольца — к воротам;
##   clearing — тропы сходятся на поляне (center, радиус clearing), с неё тремя (forks) — к воротам;
##   lanes — много почти прямых параллельных дорожек с перемычками, у ворот — воронка;
##   delta — пещеры сходятся в широкий ствол, ствол распадается на arms рукавов до ворот;
## starts — где пещеры (по умолчанию на севере в ряд; можно по бокам карты).
static func make_paths(level: Dictionary) -> Array:
	var out: Array = []
	if level.has("paths"):
		out = level["paths"].duplicate()
		out.append({"w": 8.0, "pts": [Vector2(0, 86), Vector2(0, 95)]})
		return _compress(out)
	var rng := RandomNumberGenerator.new()
	rng.seed = level["seed"]
	var n: int = level["caves"]
	var w: float = level["width"]
	var amp: float = level["amp"]
	var waves: float = level["waves"]
	var starts: Array = level.get("starts", [])
	if starts.is_empty():
		for i in n:
			starts.append(Vector2(lerpf(-86.0, 86.0, (i + 0.5) / n) + rng.randf_range(-6.0, 6.0), -106.0))
	var mains: Array = []
	match level.get("style", "converge"):
		"switchback":
			var rows: int = level.get("rows", 4)
			var span: float = level.get("span", 84.0)
			var z0: float = level.get("z0", -78.0)
			var z1: float = level.get("z1", 66.0)
			var serp: Array = []
			for r in rows:
				var z := lerpf(z0, z1, float(r) / (rows - 1))
				var xs := [-span, span] if r % 2 == 0 else [span, -span]
				for k in 4:
					var x := lerpf(xs[0], xs[1], k / 3.0)
					serp.append(Vector2(x, z + sin(k * 1.7 + r) * amp * 0.25))
			serp.append(Vector2(0, 82))
			serp.append(Vector2(0, 94))
			for i in n:
				var pts := _meander(starts[i], serp[0] + Vector2(0, -2), amp * 0.3, 1.0, rng)
				out.append({"w": w, "pts": pts})
				mains.append(pts)
			out.append({"w": w, "pts": serp})
		"ring":
			var center := Vector2(0, -15)
			var radius: float = level.get("ring", 46.0)
			var ring: Array = []
			for k in 17:
				var a := TAU * k / 16.0
				ring.append(center + Vector2(cos(a), sin(a)) * radius)
			for i in n:
				var target: Vector2 = center + (starts[i] - center).normalized() * radius
				var pts := _meander(starts[i], target, amp * 0.6, waves * 0.5, rng)
				out.append({"w": w, "pts": pts})
				mains.append(pts)
			out.append({"w": w, "pts": ring})
			var exit := _meander(center + Vector2(0, radius), Vector2(0, 80), amp, waves * 0.5, rng)
			exit.append(Vector2(0, 94))
			out.append({"w": w, "pts": exit})
		"clearing":
			var center: Vector2 = level.get("center", Vector2(0, -14))
			var radius: float = level.get("clearing", 15.0)
			for i in n:
				var pts := _meander(starts[i], center, amp, waves, rng)
				out.append({"w": w, "pts": pts})
				mains.append(pts)
			out.append({"w": radius, "pts": [center - Vector2(3, 0), center + Vector2(3, 0)]})
			for x: float in level.get("forks", [-40.0, 0.0, 40.0]):
				var pts := _meander(center + Vector2(x * 0.25, radius * 0.7), Vector2(x, 44), amp * 0.4, 1.0, rng)
				pts.append(Vector2(x * 0.35, 72))
				pts.append(Vector2(0, 86))
				pts.append(Vector2(0, 94))
				out.append({"w": w, "pts": pts})
		"lanes":
			# Много почти прямых параллельных дорожек с севера на юг; у ворот сходятся в воронку
			for i in n:
				var a: Vector2 = starts[i]
				var pts := _meander(a, Vector2(a.x * 0.8, 40), amp, waves, rng)
				pts.append(Vector2(a.x * 0.35, 68))
				pts.append(Vector2(0, 84))
				pts.append(Vector2(0, 94))
				out.append({"w": w, "pts": pts})
				mains.append(pts)
		"delta":
			# Пещеры сходятся в широкий ствол на севере, ствол веером распадается на рукава,
			# рукава снова сходятся у ворот — как дельта реки
			var trunk_a := Vector2(0, -78)
			var trunk_b := Vector2(0, -38)
			for i in n:
				var pts := _meander(starts[i], trunk_a, amp * 0.5, 1.0, rng)
				out.append({"w": w, "pts": pts})
			out.append({"w": w * 1.8, "pts": [trunk_a, trunk_b]})
			var arms: int = level.get("arms", 5)
			for k in arms:
				var x := lerpf(-70.0, 70.0, float(k) / (arms - 1))
				var pts := _meander(trunk_b, Vector2(x, 40), amp * 0.4, 1.0, rng)
				pts.append(Vector2(x * 0.35, 70))
				pts.append(Vector2(0, 86))
				pts.append(Vector2(0, 94))
				out.append({"w": w * 0.85, "pts": pts})
				mains.append(pts)
		_:
			for i in n:
				var pts := _meander(starts[i], Vector2(0, 80), amp, waves, rng)
				pts.append(Vector2(0, 94))
				out.append({"w": w, "pts": pts})
				mains.append(pts)
	# Перемычки между соседними каналами — орда растекается по лабиринту
	for b in level["bridges"]:
		if mains.size() < 2:
			break
		var i := rng.randi_range(0, mains.size() - 2)
		var la: Array = mains[i]
		var lb: Array = mains[i + 1]
		var k := rng.randi_range(2, mini(la.size(), lb.size()) - 3)
		var a: Vector2 = la[k]
		var c: Vector2 = lb[clampi(k + rng.randi_range(-1, 1), 1, lb.size() - 2)]
		var mid := (a + c) / 2.0 + Vector2(0, rng.randf_range(-12.0, 12.0))
		out.append({"w": w * 0.7, "pts": [a, mid, c]})
	out.append({"w": 8.0, "pts": [Vector2(0, 86), Vector2(0, 95)]})
	return _compress(out)


## Все тропы стягиваются к воротам в PATH_SCALE раз: раскладка та же, но пещеры ближе — орда
## доходит быстрее, бой плотнее (ширина каналов не меняется).
static func _compress(paths: Array) -> Array:
	var gate := Vector2(0, GATE_ANCHOR)
	var out: Array = []
	for path: Dictionary in paths:
		var pts: Array = []
		for p: Vector2 in path["pts"]:
			pts.append(gate + (p - gate) * PATH_SCALE)
		out.append({"w": path["w"], "pts": pts})
	return out


## Извилистый путь от a к b: поперечные изгибы (размах amp, waves изгибов), к концу затухают,
## чтобы путь точно пришёл в b.
static func _meander(a: Vector2, b: Vector2, amp: float, waves: float, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	var dir := (b - a).normalized()
	var side := dir.orthogonal()
	var phase := rng.randf() * TAU
	var steps := maxi(int(a.distance_to(b) / 18.0), 3)
	for k in steps + 1:
		var t := float(k) / steps
		var fade := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.65, 1.0, t))
		var p := a.lerp(b, t) + side * sin(t * waves * TAU + phase) * amp * fade
		p += side * rng.randf_range(-3.0, 3.0) * fade
		pts.append(Vector2(clampf(p.x, -104.0, 104.0), clampf(p.y, -108.0, 96.0)))
	return pts
