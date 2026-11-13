extends RefCounted
## Мастерство оружия и турелей. Каждое оружие и каждая турель копят опыт от своих убийств
## (одно убийство — одно очко опыта); с опытом растёт уровень мастерства (до MAX_LEVEL),
## каждый уровень — очко в собственное древо этого оружия. В древе есть развилки-специализации
## (group): из пары можно взять только одну; сброс древа возвращает очки.
## Новое оружие и турели открываются наградой за локации (reward — номер локации с нуля,
## после прохождения которой выдаётся; −1 — есть с самого начала).
## Что даёт узел — fx: множители (mult: 1 + сумма уровень × значение), прибавки (add) и флаги
## (flag: куплен ли хоть один узел с этим ключом). Код оружия спрашивает mult/add/flag.
## Опыт и купленные узлы хранятся в progress.gd (xp, mastery).

const Progress := preload("res://core/progress.gd")

const MAX_LEVEL := 10
## Опыт до уровня n: XP_BASE × n^XP_POW (накопленный).
const XP_BASE := 600.0
const XP_POW := 1.7

const ORDER := ["musket", "flamer", "gravigun", "minigun", "saw", "lightning", "hammer", "gatling", "freeze", "flame", "laser",
	"mortar"]
const ITEMS := {
	"musket": {"name": "Мушкетон", "kind": "weapon", "reward": -1, "color": Color(1.0, 0.6, 0.25),
		"model": "res://weapons/models/blunderbuss.glb", "desc": "Разрывные ядра — взрыв по толпе."},
	# Ручной огнемёт больше не выдаётся (reward 99 — никогда): огнемёт теперь турель («flame»)
	"flamer": {"name": "Огнемёт", "kind": "weapon", "reward": 99, "color": Color(1.0, 0.42, 0.18),
		"model": "weapon:flamer", "desc": "Струя огня: держи ЛКМ, жги толпу вблизи. Клавиша 2."},
	# Гравипушка тоже покупается за трофеи (upgrades.gd: WEAPONS), за локацию не выдаётся
	"gravigun": {"name": "Гравипушка", "kind": "weapon", "reward": 99, "color": Color(0.72, 0.42, 1.0),
		"model": "res://weapons/models/gravigun.glb", "desc": "Заряд раскрывается чёрной дырой и затягивает врагов. Клавиша 3."},
	# Миниган и электропушка не выдаются за локации — покупаются за трофеи (upgrades.gd: WEAPONS)
	"minigun": {"name": "Миниган", "kind": "weapon", "reward": 99, "color": Color(1.0, 0.62, 0.2),
		"model": "res://weapons/models/minigun.glb",
		"desc": "Ручной пулемёт: держи ЛКМ — раскручивается и засыпает врагов градом свинца. Клавиша 4."},
	"saw": {"name": "Дискомёт", "kind": "weapon", "reward": 99, "color": Color(0.3, 0.6, 1.0),
		"model": "weapon:saw", "desc": "ЛКМ: вращающийся энергодиск прорезает толпу насквозь."},
	"lightning": {"name": "Электропушка", "kind": "weapon", "reward": 99, "color": Color(0.35, 0.65, 1.0),
		"model": "weapon:lightning", "desc": "Держи ЛКМ: молния бьёт в толпу и перескакивает на соседей."},
	"hammer": {"name": "Молот", "kind": "weapon", "reward": 99, "color": Color(0.75, 0.72, 0.78),
		"model": "weapon:hammer", "desc": "Серия из трёх ударов; в воздухе зажми ЛКМ — пике в землю."},
	# Все турели открыты с начала игры (просьба пользователя); за локации их больше не выдают
	"gatling": {"name": "Пулемёт", "kind": "turret", "reward": -1, "color": Color(0.98, 0.78, 0.25),
		"model": "turret:gatling", "desc": "Турель: очередь по ближним врагам."},
	"laser": {"name": "Лазер", "kind": "turret", "reward": -1, "color": Color(1.0, 0.3, 0.22),
		"model": "turret:laser", "desc": "Турель: красный луч прожигает врагов насквозь. Ставится в стройке (B)."},
	"freeze": {"name": "Заморозка", "kind": "turret", "reward": -1, "color": Color(0.55, 0.78, 1.0),
		"model": "turret:freeze", "desc": "Турель: ледяная струя — толпа у цели идёт втрое медленнее. Ставится в стройке (B)."},
	"flame": {"name": "Огнемёт", "kind": "turret", "reward": -1, "color": Color(1.0, 0.45, 0.16),
		"model": "turret:flame", "desc": "Турель: струя огня жжёт толпу вблизи и поджигает землю под ней. Ставится в стройке (B)."},
	"mortar": {"name": "Мортира", "kind": "turret", "reward": -1, "color": Color(0.62, 0.72, 0.3),
		"model": "turret:mortar", "desc": "Турель: мины навесом через скалы — взрыв в самой густой толпе. Ставится в стройке (B)."},
}

# Раскладка: каждое древо — строка экрана «Прокачка». col — колонка слева направо, lane — дорожка
# (0 — основная линия, −1 — ответвление вверх, +1 — вниз); пары-специализации стоят друг над другом.

const TREES := {
	"musket": [
		{"id": "powder", "name": "Порох", "max": 3, "needs": [], "col": 1, "lane": 0, "icon": "blast",
			"fx": {"radius": 0.12}, "desc": "Радиус взрыва +12% за уровень."},
		{"id": "drum", "name": "Барабан", "max": 2, "needs": ["powder"], "col": 2, "lane": 0, "icon": "drum",
			"fx": {"clip": 2.0}, "desc": "+2 ядра в стволе за уровень."},
		{"id": "cock", "name": "Быстрый взвод", "max": 2, "needs": ["drum"], "col": 3, "lane": 0, "icon": "clock",
			"fx": {"reload": -0.15}, "desc": "Взвод между выстрелами быстрее на 15% за уровень."},
		{"id": "pouch", "name": "Подсумок", "max": 2, "needs": ["drum"], "col": 2, "lane": 1, "icon": "boxes",
			"fx": {"reserve": 8.0}, "desc": "+8 ядер в запасе за уровень."},
		{"id": "cluster", "name": "Картечь", "max": 1, "needs": ["cock"], "col": 4, "lane": -1, "icon": "cluster",
			"group": "m1", "fx": {"cluster": 1.0}, "desc": "Специализация: выстрел — три ядра веером."},
		{"id": "heavy", "name": "Тяжёлое ядро", "max": 1, "needs": ["cock"], "col": 4, "lane": 1, "icon": "bigball",
			"group": "m1", "fx": {"radius": 0.35, "reload": 0.2}, "desc": "Специализация: радиус взрыва +35%, но взвод на 20% дольше."},
		{"id": "incendiary", "name": "Зажигательные", "max": 1, "needs": ["cluster", "heavy"], "col": 5, "lane": 0,
			"icon": "fire", "fx": {"fire": 1.0}, "desc": "Взрыв поджигает землю: там ещё несколько секунд горит огонь."},
		{"id": "shrapnel", "name": "Осколки", "max": 1, "needs": ["incendiary"], "col": 6, "lane": -1, "icon": "star",
			"group": "m2", "fx": {"kills": 0.5, "radius": 0.15}, "desc": "Специализация: взрыв задевает больше врагов, радиус +15%."},
		{"id": "rapid", "name": "Скорострел", "max": 1, "needs": ["incendiary"], "col": 6, "lane": 1, "icon": "clock",
			"group": "m2", "fx": {"reload": -0.3}, "desc": "Специализация: взвод быстрее ещё на 30%."},
	],
	"flamer": [
		{"id": "nozzle", "name": "Широкое сопло", "max": 2, "needs": [], "col": 1, "lane": 0, "icon": "ring",
			"fx": {"radius": 0.2}, "desc": "Область огня там, куда бьёт струя, +20% за уровень."},
		{"id": "tank", "name": "Бак", "max": 2, "needs": ["nozzle"], "col": 2, "lane": 0, "icon": "tank",
			"fx": {"tank": 0.3}, "desc": "Бак больше на 30% за уровень."},
		{"id": "reach", "name": "Дальнобой", "max": 2, "needs": ["tank"], "col": 3, "lane": 0, "icon": "range",
			"fx": {"range": 0.15}, "desc": "Струя бьёт дальше на 15% за уровень."},
		{"id": "refuel", "name": "Быстрая заправка", "max": 2, "needs": ["tank"], "col": 2, "lane": 1, "icon": "clock",
			"fx": {"regen": 0.4}, "desc": "Топливо восстанавливается быстрее на 40% за уровень."},
		{"id": "napalm", "name": "Напалм", "max": 1, "needs": ["reach"], "col": 4, "lane": -1, "icon": "fire",
			"group": "f1", "fx": {"napalm": 1.0}, "desc": "Специализация: лужи огня горят вдвое дольше и шире."},
		{"id": "blue", "name": "Синее пламя", "max": 1, "needs": ["reach"], "col": 4, "lane": 1, "icon": "star",
			"group": "f1", "fx": {"kills": 0.5}, "desc": "Специализация: струя сжигает на 50% больше врагов."},
		{"id": "thrift", "name": "Экономный расход", "max": 2, "needs": ["napalm", "blue"], "col": 5, "lane": 0,
			"icon": "tank", "fx": {"burn": -0.2}, "desc": "Расход топлива меньше на 20% за уровень."},
		{"id": "wall", "name": "Огненный вал", "max": 1, "needs": ["thrift"], "col": 6, "lane": -1, "icon": "wall",
			"group": "f2", "fx": {"wall": 1.0}, "desc": "Специализация: струя оставляет вдвое больше луж огня."},
		{"id": "inferno", "name": "Пекло", "max": 1, "needs": ["thrift"], "col": 6, "lane": 1, "icon": "blast",
			"group": "f2", "fx": {"radius": 0.3, "kills": 0.3}, "desc": "Специализация: область огня +30%, сжигает на 30% больше."},
	],
	"gravigun": [
		{"id": "gravity", "name": "Сила притяжения", "max": 2, "needs": [], "col": 1, "lane": 0, "icon": "core",
			"fx": {"radius": 0.12}, "desc": "Радиус затягивания +12% за уровень."},
		{"id": "capacitor", "name": "Конденсатор", "max": 2, "needs": ["gravity"], "col": 2, "lane": 0, "icon": "clock",
			"fx": {"recharge": -0.2}, "desc": "Заряд восстанавливается быстрее на 20% за уровень."},
		{"id": "capacity", "name": "Ёмкость", "max": 1, "needs": ["capacitor"], "col": 3, "lane": 0, "icon": "cells",
			"fx": {"charges": 1.0}, "desc": "+1 заряд."},
		{"id": "hunger", "name": "Жадное ядро", "max": 2, "needs": ["capacitor"], "col": 2, "lane": 1, "icon": "core",
			"fx": {"core": 0.3, "pull": 0.2}, "desc": "Ядро больше на 30%, тянет сильнее на 20% за уровень."},
		{"id": "collapse", "name": "Коллапс", "max": 1, "needs": ["capacity"], "col": 4, "lane": -1,
			"icon": "blast", "group": "g1", "fx": {"collapse": 1.0}, "desc": "Специализация: схлопываясь, дыра взрывается."},
		{"id": "stable", "name": "Стабилизатор", "max": 1, "needs": ["capacity"], "col": 4, "lane": 1,
			"icon": "clock", "group": "g1", "fx": {"life": 2.0}, "desc": "Специализация: дыра держится на 2 секунды дольше."},
		{"id": "circuit", "name": "Второй контур", "max": 1, "needs": ["collapse", "stable"], "col": 5, "lane": 0,
			"icon": "cells", "fx": {"charges": 1.0}, "desc": "+1 заряд."},
		{"id": "supermass", "name": "Сверхмасса", "max": 1, "needs": ["circuit"], "col": 6, "lane": -1, "icon": "core",
			"group": "g2", "fx": {"pull": 0.6, "core": 0.3}, "desc": "Специализация: тянет на 60% сильнее, ядро больше."},
		{"id": "twins", "name": "Близнецы", "max": 1, "needs": ["circuit"], "col": 6, "lane": 1, "icon": "cluster",
			"group": "g2", "fx": {"twin": 1.0}, "desc": "Специализация: каждый выстрел — две чёрные дыры рядом."},
	],
	"minigun": [
		{"id": "belt", "name": "Длинная лента", "max": 3, "needs": [], "col": 1, "lane": 0, "icon": "rate",
			"fx": {"rate": 0.12}, "desc": "Темп стрельбы +12% за уровень."},
		{"id": "drum", "name": "Большой барабан", "max": 2, "needs": ["belt"], "col": 2, "lane": 0, "icon": "drum",
			"fx": {"clip": 100.0}, "desc": "+100 патронов в ленте за уровень."},
		{"id": "pouch", "name": "Подсумок", "max": 2, "needs": ["drum"], "col": 2, "lane": 1, "icon": "boxes",
			"fx": {"reserve": 300.0}, "desc": "+300 патронов в запасе за уровень."},
		{"id": "motor", "name": "Мотор", "max": 2, "needs": ["drum"], "col": 3, "lane": 0, "icon": "spin",
			"fx": {"spin": -0.3}, "desc": "Стволы раскручиваются быстрее на 30% за уровень."},
		{"id": "ap", "name": "Бронебой", "max": 1, "needs": ["motor"], "col": 4, "lane": -1, "icon": "pierce",
			"group": "n1", "fx": {"pierce": 1.0}, "desc": "Специализация: пуля прошивает двоих."},
		{"id": "hail", "name": "Свинцовый град", "max": 1, "needs": ["motor"], "col": 4, "lane": 1, "icon": "rate",
			"group": "n1", "fx": {"rate": 0.3}, "desc": "Специализация: темп стрельбы +30%."},
		{"id": "cooling", "name": "Охлаждение", "max": 2, "needs": ["ap", "hail"], "col": 5, "lane": 0, "icon": "clock",
			"fx": {"reload": -0.2}, "desc": "Перезарядка быстрее на 20% за уровень."},
		{"id": "incendiary", "name": "Зажигательные", "max": 1, "needs": ["cooling"], "col": 6, "lane": -1,
			"icon": "fire", "group": "n2", "fx": {"fire": 1.0}, "desc": "Специализация: каждая 6-я пуля поджигает землю."},
		{"id": "explosive", "name": "Разрывные", "max": 1, "needs": ["cooling"], "col": 6, "lane": 1, "icon": "blast",
			"group": "n2", "fx": {"blast": 1.0}, "desc": "Специализация: каждая пуля рвётся и задевает соседей."},
	],
	"gatling": [
		{"id": "belt", "name": "Длинная лента", "max": 3, "needs": [], "col": 1, "lane": 0, "icon": "rate",
			"fx": {"rate": 0.15}, "desc": "Скорострельность +15% за уровень."},
		{"id": "scope", "name": "Прицел", "max": 2, "needs": ["belt"], "col": 2, "lane": 0, "icon": "range",
			"fx": {"range": 0.12}, "desc": "Дальность +12% за уровень."},
		{"id": "servo", "name": "Сервоприводы", "max": 1, "needs": ["scope"], "col": 3, "lane": 0, "icon": "spin",
			"fx": {"turn": 1.0}, "desc": "Поворачивается и раскручивает стволы вдвое быстрее."},
		{"id": "serial", "name": "Серийный выпуск", "max": 2, "needs": ["scope"], "col": 2, "lane": 1, "icon": "coin",
			"fx": {"cost": -0.15}, "desc": "Пулемёт дешевле на 15% за уровень."},
		{"id": "twin", "name": "Спаренные стволы", "max": 1, "needs": ["servo"], "col": 4, "lane": -1,
			"icon": "rate", "group": "t1", "fx": {"pierce": 1.0}, "desc": "Специализация: каждый выстрел валит двоих."},
		{"id": "ap", "name": "Бронебой", "max": 1, "needs": ["servo"], "col": 4, "lane": 1, "icon": "pierce",
			"group": "t1", "fx": {"pierce": 2.0, "rate": -0.2}, "desc": "Специализация: пуля прошивает троих, но стреляет реже на 20%."},
		{"id": "cooling", "name": "Охлаждение", "max": 2, "needs": ["twin", "ap"], "col": 5, "lane": 0, "icon": "rate",
			"fx": {"rate": 0.1}, "desc": "Скорострельность ещё +10% за уровень."},
		{"id": "incendiary", "name": "Зажигательная лента", "max": 1, "needs": ["cooling"], "col": 6, "lane": -1,
			"icon": "fire", "group": "t2", "fx": {"fire": 1.0}, "desc": "Специализация: каждая 8-я пуля поджигает землю."},
		{"id": "overdrive", "name": "Форсаж", "max": 1, "needs": ["cooling"], "col": 6, "lane": 1, "icon": "spin",
			"group": "t2", "fx": {"rate": 0.3}, "desc": "Специализация: скорострельность +30%."},
	],
	# У турели-огнемёта своего мастерства нет — качается в общем древе (upgrades.gd)
	"flame": [],
	# Мортира, как огнемёт, качается в общем древе (upgrades.gd)
	"mortar": [],
	"lightning": [],
	"saw": [],
	"hammer": [],
	"freeze": [
		{"id": "frost", "name": "Мороз", "max": 3, "needs": [], "col": 1, "lane": 0, "icon": "ring",
			"fx": {"radius": 0.12}, "desc": "Облако холода шире на 12% за уровень."},
		{"id": "nozzle", "name": "Длинное сопло", "max": 2, "needs": ["frost"], "col": 2, "lane": 0, "icon": "range",
			"fx": {"range": 0.12}, "desc": "Дальность +12% за уровень."},
		{"id": "pump", "name": "Насос", "max": 2, "needs": ["nozzle"], "col": 3, "lane": 0, "icon": "rate",
			"fx": {"rate": 0.15}, "desc": "Бьёт чаще на 15% за уровень."},
		{"id": "assembly", "name": "Серийная сборка", "max": 2, "needs": ["nozzle"], "col": 2, "lane": 1, "icon": "coin",
			"fx": {"cost": -0.15}, "desc": "Заморозка дешевле на 15% за уровень."},
		{"id": "deep", "name": "Глубокая заморозка", "max": 1, "needs": ["pump"], "col": 4, "lane": -1, "icon": "clock",
			"group": "f1", "fx": {"deep": 1.0}, "desc": "Специализация: замёрзшие почти стоят на месте."},
		{"id": "shards", "name": "Ледяные осколки", "max": 1, "needs": ["pump"], "col": 4, "lane": 1, "icon": "star",
			"group": "f1", "fx": {"kills": 2.0}, "desc": "Специализация: разбивает ещё двоих за выстрел."},
		{"id": "coolant", "name": "Хладагент", "max": 2, "needs": ["deep", "shards"], "col": 5, "lane": 0, "icon": "spin",
			"fx": {"turn": 0.5, "rate": 0.1}, "desc": "Поворачивается быстрее и бьёт чаще на 10% за уровень."},
		{"id": "blizzard", "name": "Буран", "max": 1, "needs": ["coolant"], "col": 6, "lane": -1, "icon": "ring",
			"group": "f2", "fx": {"radius": 0.35}, "desc": "Специализация: облако холода ещё +35%."},
		{"id": "shatter", "name": "Хрупкость", "max": 1, "needs": ["coolant"], "col": 6, "lane": 1, "icon": "blast",
			"group": "f2", "fx": {"shatter": 1.0}, "desc": "Специализация: осколки пробивают доспехи (двойной урон)."},
	],
	"laser": [
		{"id": "focus", "name": "Фокусировка", "max": 3, "needs": [], "col": 1, "lane": 0, "icon": "rate",
			"fx": {"rate": 0.15}, "desc": "Луч жжёт чаще на 15% за уровень."},
		{"id": "lens", "name": "Линза", "max": 2, "needs": ["focus"], "col": 2, "lane": 0, "icon": "range",
			"fx": {"range": 0.1}, "desc": "Дальность +10% за уровень."},
		{"id": "capacitor", "name": "Конденсатор", "max": 2, "needs": ["lens"], "col": 3, "lane": 0, "icon": "spin",
			"fx": {"turn": 0.5}, "desc": "Заряжается и поворачивается быстрее на 50% за уровень."},
		{"id": "assembly", "name": "Серийная сборка", "max": 2, "needs": ["lens"], "col": 2, "lane": 1, "icon": "coin",
			"fx": {"cost": -0.15}, "desc": "Лазер дешевле на 15% за уровень."},
		{"id": "wide", "name": "Широкий луч", "max": 1, "needs": ["capacitor"], "col": 4, "lane": -1,
			"icon": "pierce", "group": "l1", "fx": {"pierce": 2.0}, "desc": "Специализация: прожигает ещё двоих на линии."},
		{"id": "overheat", "name": "Перегрев", "max": 1, "needs": ["capacitor"], "col": 4, "lane": 1,
			"icon": "star", "group": "l1", "fx": {"rate": 0.35}, "desc": "Специализация: жжёт чаще на 35%."},
		{"id": "cooling", "name": "Охлаждение", "max": 2, "needs": ["wide", "overheat"], "col": 5, "lane": 0,
			"icon": "clock", "fx": {"rate": 0.1}, "desc": "Жжёт чаще ещё на 10% за уровень."},
		{"id": "scorch", "name": "Выжигание", "max": 1, "needs": ["cooling"], "col": 6, "lane": -1, "icon": "fire",
			"group": "l2", "fx": {"fire": 1.0}, "desc": "Специализация: луч поджигает землю под целью."},
		{"id": "overcharge", "name": "Сверхзаряд", "max": 1, "needs": ["cooling"], "col": 6, "lane": 1, "icon": "core",
			"group": "l2", "fx": {"pierce": 3.0}, "desc": "Специализация: прожигает ещё троих на линии."},
	],
}

## Для проверки: всё оружие открыто (параметр запуска unlock_all).
static var force_all := false


# --- открытие и опыт -------------------------------------------------------------------------

static func is_unlocked(item: String) -> bool:
	var reward: int = ITEMS[item]["reward"]
	# Купленное в «Оружии» за трофеи (upgrades.gd: WEAPONS) — тоже открыто
	return force_all or reward < 0 or Progress.is_completed(reward) or int(Progress.upgrades.get("wpn_" + item, 0)) > 0


## Что выдаётся за прохождение локации index ("" — ничего).
static func reward_for(index: int) -> String:
	for item: String in ORDER:
		if ITEMS[item]["reward"] == index:
			return item
	return ""


static func xp(item: String) -> int:
	Progress.load_progress()
	return int(Progress.xp.get(item, 0))


static func xp_for_level(n: int) -> int:
	return int(XP_BASE * pow(n, XP_POW))


static func level_of(item: String) -> int:
	var x := xp(item)
	var lv := 0
	while lv < MAX_LEVEL and x >= xp_for_level(lv + 1):
		lv += 1
	return lv


## Добавить опыт; возвращает, на сколько уровней выросло мастерство.
static func add_xp(item: String, amount: int) -> int:
	if amount <= 0 or not ITEMS.has(item):
		return 0
	var before := level_of(item)
	Progress.xp[item] = xp(item) + amount
	return level_of(item) - before


# --- древо ------------------------------------------------------------------------------------

static func nodes(item: String) -> Array:
	return TREES[item]


static func get_node(item: String, id: String) -> Dictionary:
	for n: Dictionary in TREES[item]:
		if n["id"] == id:
			return n
	return {}


static func level(item: String, id: String) -> int:
	Progress.load_progress()
	return int(Progress.mastery.get(item, {}).get(id, 0))


## Очки: уровень мастерства плюс бонус «Ветерана» из общего древа; сколько потрачено и свободно.
static func points_total(item: String) -> int:
	return level_of(item) + _bonus_points()


static func points_spent(item: String) -> int:
	var spent := 0
	for n: Dictionary in TREES[item]:
		spent += level(item, n["id"])
	return spent


static func points_free(item: String) -> int:
	return points_total(item) - points_spent(item)


## Узел открыт, если куплен хотя бы один из needs (или их нет).
static func is_open(item: String, id: String) -> bool:
	var needs: Array = get_node(item, id)["needs"]
	if needs.is_empty():
		return true
	for parent: String in needs:
		if level(item, parent) > 0:
			return true
	return false


## Узел закрыт выбором: в его паре-специализации уже куплен другой.
static func is_excluded(item: String, id: String) -> bool:
	var n := get_node(item, id)
	if not n.has("group"):
		return false
	for other: Dictionary in TREES[item]:
		if other["id"] != id and other.get("group", "") == n["group"] and level(item, other["id"]) > 0:
			return true
	return false


static func can_buy(item: String, id: String) -> bool:
	var n := get_node(item, id)
	return is_unlocked(item) and is_open(item, id) and not is_excluded(item, id) \
		and level(item, id) < int(n["max"]) and points_free(item) >= 1


static func buy(item: String, id: String) -> bool:
	if not can_buy(item, id):
		return false
	var tree: Dictionary = Progress.mastery.get(item, {})
	tree[id] = level(item, id) + 1
	Progress.mastery[item] = tree
	Progress.save()
	return true


static func reset(item: String) -> void:
	Progress.load_progress()
	Progress.mastery.erase(item)
	Progress.save()


# --- что даёт древо ---------------------------------------------------------------------------

## Множитель: 1 + сумма (уровень × значение) по узлам с ключом key.
static func mult(item: String, key: String) -> float:
	return maxf(1.0 + add(item, key), 0.1)


static func add(item: String, key: String) -> float:
	var total := 0.0
	for n: Dictionary in TREES[item]:
		var fx: Dictionary = n["fx"]
		if fx.has(key):
			total += level(item, n["id"]) * float(fx[key])
	return total


static func flag(item: String, key: String) -> bool:
	return add(item, key) > 0.0


static func _bonus_points() -> int:
	return int(Progress.upgrades.get("veteran", 0))
