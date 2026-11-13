extends RefCounted
## Древо прокачки на трофеях. Трофеи дают за убитых в каждом бою, и при проигрыше тоже
## (progress.gd: trophies). Каждый узел качается на несколько уровней, следующий уровень дороже
## (цена × уровень). Звёзды за пройденные локации открывают дальние узлы (gate — сколько звёзд
## всего нужно). Узел открывается, когда куплен хотя бы один уровень предыдущего (needs).
## Четыре раздела: герой (ранец, броня, умения), ракетница, турели, добыча. В древе только то,
## что у игрока есть: узлы турели (item) появляются, когда сама турель открыта наградой за
## локацию; у нового оружия свои узлы добавятся, когда оно появится. Уровни узлов хранятся в
## progress.gd (upgrades).

const Progress := preload("res://core/progress.gd")
const Mastery := preload("res://core/mastery.gd")

## Разделы древа на экране «Прокачка» слева направо. Колонки раздела — по x узлов, что видны
## (у турелей колонка появляется, когда турель открыта).
const ROWS := {
	"hero": {"name": "Герой", "icon": "medal", "color": Color(0.95, 0.38, 0.3)},
	"skills": {"name": "Умения", "icon": "star", "color": Color(0.75, 0.5, 1.0)},
	"strikes": {"name": "Удары с неба", "icon": "blast", "color": Color(1.0, 0.45, 0.25)},
	"rockets": {"name": "Ракетница", "icon": "blast", "color": Color(1.0, 0.56, 0.22)},
	"turrets": {"name": "Турели", "icon": "gatling", "color": Color(0.5, 0.78, 1.0)},
	"spoils": {"name": "Оборона и добыча", "icon": "loot", "color": Color(0.98, 0.76, 0.24)},
}
const ROW_ORDER := ["hero", "skills", "strikes", "rockets", "turrets", "spoils"]
## row — раздел, x и y — колонка и ярус в нём (сверху вниз); cost — трофеев за первый уровень;
## needs — что купить раньше (всегда выше в той же колонке); gate — сколько ★ нужно всего;
## item — турель, без которой узла не видно; tex — иконка-картинка (умения).
const NODES := [
	# --- Герой: ранец и живучесть
	{"id": "flight", "row": "hero", "name": "Время полёта", "cost": 20, "max": 6, "needs": "", "x": 0, "y": 0,
		"icon": "wing", "desc": "+2 с полёта на ранце за уровень (без прокачки — 6 с). Бак наполняется, пока стоишь на вышке или на земле."},
	{"id": "fly_speed", "row": "hero", "name": "Скорость полёта", "cost": 25, "max": 5, "needs": "flight", "x": 0, "y": 1,
		"icon": "rate", "desc": "Ранец несёт быстрее: +8% скорости полёта за уровень."},
	{"id": "refuel", "row": "hero", "name": "Быстрая заправка", "cost": 30, "max": 3, "needs": "fly_speed", "x": 0, "y": 2,
		"icon": "clock", "desc": "Бак ранца наполняется на 20% быстрее за уровень."},
	{"id": "ceiling", "row": "hero", "name": "Высота полёта", "cost": 45, "max": 3, "needs": "refuel", "x": 0, "y": 3,
		"icon": "range", "gate": 1, "desc": "Потолок полёта выше на 8 м за уровень."},
	{"id": "hero_armor", "row": "hero", "name": "Броня героя", "cost": 25, "max": 5, "needs": "", "x": 1, "y": 0,
		"icon": "tank", "desc": "Здоровье героя +15 за уровень: дольше держит копья в полёте."},
	{"id": "regen", "row": "hero", "name": "Регенерация", "cost": 30, "max": 4, "needs": "hero_armor", "x": 1, "y": 1,
		"icon": "repair", "desc": "Здоровье восстанавливается на 25% быстрее и на 0,3 с раньше за уровень."},
	{"id": "spear_guard", "row": "hero", "name": "Защита от копий", "cost": 35, "max": 4, "needs": "regen", "x": 1, "y": 2,
		"icon": "gate", "desc": "Копья гоблинов ранят на 10% слабее за уровень."},
	{"id": "hero_xp", "row": "hero", "name": "Боевой опыт", "cost": 50, "max": 3, "needs": "spear_guard", "x": 1, "y": 3,
		"icon": "medal", "gate": 2, "desc": "Уровень героя в бою растёт на 20% быстрее за уровень."},
	# --- Умения: по колонке на каждое
	{"id": "ab_salvo", "row": "skills", "name": "Ракетный залп (Q)", "cost": 30, "max": 1, "needs": "", "x": 0, "y": 0,
		"icon": "cluster", "tex": "res://ui/icons/ability_rockets.png", "desc": "Умение Q: восемь малых ракет по самым густым местам толпы."},
	{"id": "salvo_more", "row": "skills", "name": "Залп: больше ракет", "cost": 40, "max": 3, "needs": "ab_salvo", "x": 0, "y": 1,
		"icon": "cluster", "desc": "+2 ракеты в залпе за уровень."},
	{"id": "salvo_wide", "row": "skills", "name": "Залп: шире", "cost": 40, "max": 3, "needs": "salvo_more", "x": 0, "y": 2,
		"icon": "blast", "desc": "Ракеты залпа ложатся шире: +15% за уровень."},
	{"id": "ab_speed", "row": "skills", "name": "Быстрые умения", "cost": 40, "max": 5, "needs": "salvo_wide", "x": 0, "y": 3,
		"icon": "clock", "desc": "Перезарядка всех умений короче на 6% за уровень."},
	{"id": "ab_napalm", "row": "skills", "name": "Напалм (E)", "cost": 90, "max": 1, "needs": "", "x": 1, "y": 0,
		"icon": "fire", "tex": "res://ui/icons/ability_napalm.png", "gate": 1, "desc": "Умение E: огненная дорожка вдоль взгляда, горит 5 с."},
	{"id": "napalm_long", "row": "skills", "name": "Напалм: длиннее", "cost": 45, "max": 3, "needs": "ab_napalm", "x": 1, "y": 1,
		"icon": "fire", "desc": "Огненная дорожка длиннее на треть за уровень."},
	{"id": "napalm_time", "row": "skills", "name": "Напалм: дольше", "cost": 45, "max": 3, "needs": "napalm_long", "x": 1, "y": 2,
		"icon": "clock", "desc": "Напалм горит на 1,5 с дольше за уровень."},
	{"id": "ab_drone", "row": "skills", "name": "Боевой дрон (R)", "cost": 160, "max": 1, "needs": "", "x": 2, "y": 0,
		"icon": "eye", "tex": "res://ui/icons/ability_drone.png", "gate": 2,
		"desc": "Умение R: дрон летит к прицелу и 15 с сам бьёт очередями по ближним к туннелю врагам."},
	{"id": "drone_time", "row": "skills", "name": "Дрон: дольше", "cost": 60, "max": 3, "needs": "ab_drone", "x": 2, "y": 1,
		"icon": "clock", "desc": "Дрон воюет на 5 с дольше за уровень."},
	{"id": "drone_guns", "row": "skills", "name": "Дрон: темп", "cost": 60, "max": 3, "needs": "drone_time", "x": 2, "y": 2,
		"icon": "gatling", "desc": "Дрон стреляет на 20% чаще за уровень."},
	# --- Удары с неба: дорогие и за звёзды — открываются по ходу игры
	{"id": "strike_napalm", "row": "strikes", "name": "Авиаудар (Z)", "cost": 220, "max": 1, "needs": "", "x": 0, "y": 0,
		"icon": "fire", "gate": 2, "desc": "Умение Z: штурмовик проносится над полем и сбрасывает цепочку напалмовых бомб вдоль взгляда. Перезарядка 45 с."},
	{"id": "strike_rockets", "row": "strikes", "name": "Ракетный дождь (X)", "cost": 320, "max": 1, "needs": "strike_napalm", "x": 0, "y": 1,
		"icon": "cluster", "gate": 4, "desc": "Умение X: 20 ракет падают с неба на круг под прицелом. Перезарядка 55 с."},
	{"id": "strike_laser", "row": "strikes", "name": "Орбитальный лазер (C)", "cost": 500, "max": 1, "needs": "strike_rockets", "x": 0, "y": 2,
		"icon": "core", "gate": 6, "desc": "Умение C: столб света из космоса бьёт в точку и ведёт по земле, выжигая всё на пути. Перезарядка 80 с."},
	{"id": "strike_power", "row": "strikes", "name": "Удары: мощнее", "cost": 120, "max": 3, "needs": "strike_napalm", "x": 1, "y": 1,
		"icon": "blast", "gate": 3, "desc": "Авиаудар и ракетный дождь: на 25% больше бомб и ракет за уровень."},
	# --- Ракетница
	{"id": "armorer", "row": "rockets", "name": "Мощь ракет", "cost": 20, "max": 5, "needs": "", "x": 0, "y": 0,
		"icon": "blast", "desc": "Взрыв ракеты шире на 12% за уровень."},
	{"id": "rocket_speed", "row": "rockets", "name": "Скорость ракеты", "cost": 25, "max": 3, "needs": "armorer", "x": 0, "y": 1,
		"icon": "rate", "desc": "Ракета летит на 15% быстрее за уровень — легче попасть по бегущим."},
	{"id": "shrapnel", "row": "rockets", "name": "Тройной выстрел", "cost": 120, "max": 1, "needs": "rocket_speed", "x": 0, "y": 2,
		"icon": "cluster", "gate": 1, "desc": "Каждый выстрел — три ракеты веером: по центру и по бокам."},
	{"id": "incendiary", "row": "rockets", "name": "Зажигательные ракеты", "cost": 150, "max": 1, "needs": "shrapnel", "x": 0, "y": 3,
		"icon": "fire", "gate": 2, "desc": "Взрыв ракеты поджигает землю — там горит ещё несколько секунд."},
	{"id": "stockpile", "row": "rockets", "name": "Боезапас", "cost": 15, "max": 5, "needs": "", "x": 1, "y": 0,
		"icon": "chest", "desc": "+1 ракета в стволе и +25% ракет в запасе за уровень."},
	{"id": "hands", "row": "rockets", "name": "Быстрая перезарядка", "cost": 25, "max": 5, "needs": "stockpile", "x": 1, "y": 1,
		"icon": "rate", "desc": "Между выстрелами и при перезарядке ждать на 10% меньше за уровень."},
	{"id": "resupply", "row": "rockets", "name": "Подвоз ракет", "cost": 30, "max": 3, "needs": "hands", "x": 1, "y": 2,
		"icon": "boxes", "desc": "Запас ракет пополняется на 15% быстрее за уровень."},
	{"id": "double", "row": "rockets", "name": "Двойной выстрел", "cost": 60, "max": 3, "needs": "resupply", "x": 1, "y": 3,
		"icon": "drum", "gate": 3, "desc": "Шанс 15% за уровень, что вслед вылетит вторая ракета — даром."},
	# --- Турели: по колонке на каждую, колонка видна, когда турель открыта
	{"id": "stock_gatling", "row": "turrets", "name": "Пулемёты", "cost": 30, "max": 6, "needs": "", "x": 0, "y": 0,
		"icon": "gatling", "item": "gatling", "desc": "+1 пулемёт в запас на бой за уровень (без прокачки — 2)."},
	{"id": "gat_pierce", "row": "turrets", "name": "Пулемёт: пробой", "cost": 45, "max": 2, "needs": "stock_gatling", "x": 0, "y": 1,
		"icon": "pierce", "item": "gatling", "desc": "Пуля прошивает ещё одного врага за уровень."},
	{"id": "gat_rate", "row": "turrets", "name": "Пулемёт: темп", "cost": 40, "max": 3, "needs": "gat_pierce", "x": 0, "y": 2,
		"icon": "rate", "item": "gatling", "desc": "Пулемёт стреляет на 10% чаще за уровень."},
	{"id": "stock_freeze", "row": "turrets", "name": "Заморозки", "cost": 50, "max": 3, "needs": "", "x": 1, "y": 0,
		"icon": "snow", "item": "freeze", "desc": "+1 заморозка в запас за уровень (без прокачки — 1)."},
	{"id": "freeze_power", "row": "turrets", "name": "Заморозка: сильнее", "cost": 45, "max": 3, "needs": "stock_freeze", "x": 1, "y": 1,
		"icon": "snow", "item": "freeze", "desc": "Замороженные идут ещё на 15% медленнее за уровень."},
	{"id": "freeze_time", "row": "turrets", "name": "Заморозка: дольше", "cost": 40, "max": 3, "needs": "freeze_power", "x": 1, "y": 2,
		"icon": "clock", "item": "freeze", "desc": "Холод держит на 0,6 с дольше за уровень."},
	{"id": "stock_flame", "row": "turrets", "name": "Огнемёты", "cost": 50, "max": 3, "needs": "", "x": 2, "y": 0,
		"icon": "fire", "item": "flame", "desc": "+1 огнемёт в запас за уровень (без прокачки — 1)."},
	{"id": "flame_radius", "row": "turrets", "name": "Огнемёт: шире", "cost": 45, "max": 3, "needs": "stock_flame", "x": 2, "y": 1,
		"icon": "blast", "item": "flame", "desc": "Огонь накрывает на 12% шире за уровень."},
	{"id": "flame_burn", "row": "turrets", "name": "Огнемёт: поджог", "cost": 45, "max": 3, "needs": "flame_radius", "x": 2, "y": 2,
		"icon": "fire", "item": "flame", "desc": "Земля под струёй загорается чаще за уровень."},
	{"id": "stock_mortar", "row": "turrets", "name": "Мортиры", "cost": 60, "max": 3, "needs": "", "x": 5, "y": 0,
		"icon": "blast", "item": "mortar", "desc": "+1 мортира в запас за уровень (без прокачки — 1)."},
	{"id": "mortar_radius", "row": "turrets", "name": "Мортира: шире", "cost": 50, "max": 3, "needs": "stock_mortar", "x": 5, "y": 1,
		"icon": "ring", "item": "mortar", "desc": "Взрыв мины накрывает на 12% шире за уровень."},
	{"id": "mortar_rate", "row": "turrets", "name": "Мортира: темп", "cost": 50, "max": 3, "needs": "mortar_radius", "x": 5, "y": 2,
		"icon": "rate", "item": "mortar", "desc": "Мортира стреляет на 12% чаще за уровень."},
	{"id": "stock_barricade", "row": "turrets", "name": "Баррикады", "cost": 40, "max": 3, "needs": "", "x": 4, "y": 0,
		"icon": "gate", "desc": "+1 баррикада в запас на бой за уровень (без прокачки — 2). Ставится в канал: толпа упирается и стоит, пока не сломает."},
	{"id": "barricade_hp", "row": "turrets", "name": "Баррикада: прочнее", "cost": 45, "max": 3, "needs": "stock_barricade", "x": 4, "y": 1,
		"icon": "repair", "desc": "Баррикада держит на 30% дольше за уровень."},
	{"id": "stock_laser", "row": "turrets", "name": "Лазеры", "cost": 70, "max": 3, "needs": "", "x": 3, "y": 0,
		"icon": "range", "item": "laser", "desc": "+1 лазер в запас за уровень (без прокачки — 1)."},
	{"id": "laser_reach", "row": "turrets", "name": "Лазер: дальше", "cost": 50, "max": 3, "needs": "stock_laser", "x": 3, "y": 1,
		"icon": "range", "item": "laser", "desc": "Луч бьёт дальше: +8% дальности и +3 м за целью за уровень."},
	{"id": "laser_pierce", "row": "turrets", "name": "Лазер: прожиг", "cost": 60, "max": 2, "needs": "laser_reach", "x": 3, "y": 2,
		"icon": "pierce", "item": "laser", "desc": "Луч прожигает ещё одного врага на линии за уровень."},
	# --- Оборона и добыча
	{"id": "tunnel_hp", "row": "spoils", "name": "Прочность обороны", "cost": 25, "max": 5, "needs": "", "x": 0, "y": 0,
		"icon": "gate", "desc": "Туннель (или ворота) выдерживает на 10% больше врагов за уровень."},
	{"id": "repair", "row": "spoils", "name": "Ремонт на рубежах", "cost": 30, "max": 3, "needs": "tunnel_hp", "x": 0, "y": 1,
		"icon": "repair", "desc": "На каждом рубеже орды (20%) чинится ещё +5% прочности за уровень."},
	{"id": "bulk", "row": "spoils", "name": "Мастерская", "cost": 25, "max": 5, "needs": "repair", "x": 0, "y": 2,
		"icon": "repair", "desc": "Ступени турелей (II и III) дешевле на 6% за уровень."},
	{"id": "optics", "row": "spoils", "name": "Оптика", "cost": 30, "max": 5, "needs": "bulk", "x": 0, "y": 3,
		"icon": "eye", "desc": "Дальность всех турелей +5% за уровень."},
	{"id": "rapid", "row": "spoils", "name": "Скорострельность", "cost": 40, "max": 5, "needs": "optics", "x": 0, "y": 4,
		"icon": "rate", "gate": 2, "desc": "Все турели стреляют чаще на 5% за уровень."},
	{"id": "trophy_gain", "row": "spoils", "name": "Трофейщик", "cost": 30, "max": 5, "needs": "", "x": 1, "y": 0,
		"icon": "loot", "desc": "Трофеев за бой +10% за уровень."},
	{"id": "supply", "row": "spoils", "name": "Снабжение", "cost": 25, "max": 5, "needs": "trophy_gain", "x": 1, "y": 1,
		"icon": "boxes", "desc": "+100 монет на старте боя за уровень — сразу на ступени турелей."},
	{"id": "bounty", "row": "spoils", "name": "Награда за головы", "cost": 30, "max": 3, "needs": "supply", "x": 1, "y": 2,
		"icon": "coin", "desc": "Монет за каждого убитого +10% за уровень."},
	{"id": "milestone_bonus", "row": "spoils", "name": "Бонус рубежей", "cost": 40, "max": 2, "needs": "bounty", "x": 1, "y": 3,
		"icon": "star", "desc": "Трофеи за рубежи орды (каждые 20%) +25% за уровень."},
	# --- Улучшения оружия (вкладка «Улучшения оружия»): ветка каждого оружия, в конце — развилка из
	# двух финальных форм (excl — взять можно только одну). Видны, когда оружие есть (item).
	# Ракетница
	{"id": "rk_cluster", "row": "w_rockets", "name": "Кассета", "cost": 60, "max": 1, "needs": "", "x": 0, "y": 0,
		"icon": "cluster", "item": "musket", "desc": "После взрыва ракеты разлетаются 3 малые бомбы."},
	{"id": "rk_drum", "row": "w_rockets", "name": "Барабан", "cost": 45, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "drum", "item": "musket", "desc": "+1 ракета в стволе за уровень."},
	{"id": "rk_shock", "row": "w_rockets", "name": "Ударная волна", "cost": 60, "max": 2, "needs": "rk_cluster", "x": 0, "y": 1,
		"icon": "blast", "item": "musket", "desc": "Взрыв шире на 15% и валит больше врагов за уровень."},
	{"id": "rk_homing", "row": "w_rockets", "name": "Наведение", "cost": 70, "max": 1, "needs": "rk_drum", "x": 1, "y": 1,
		"icon": "eye", "item": "musket", "desc": "Ракета сама доворачивает в гущу толпы рядом с прицелом."},
	{"id": "rk_nuke", "row": "w_rockets", "name": "★ Ядерная боеголовка", "cost": 250, "max": 1, "needs": "rk_shock", "x": 0, "y": 2,
		"icon": "star", "item": "musket", "gate": 2, "excl": "rk_barrage", "final": true,
		"desc": "Финальная форма: каждая 4-я ракета — ядерная: огромный зелёный взрыв. Боеголовка жёлто-чёрная."},
	{"id": "rk_barrage", "row": "w_rockets", "name": "★ Град", "cost": 250, "max": 1, "needs": "rk_homing", "x": 1, "y": 2,
		"icon": "cluster", "item": "musket", "gate": 2, "excl": "rk_nuke", "final": true,
		"desc": "Финальная форма: каждый выстрел — 3 ракеты веером, перезарядка вдвое быстрее. Боеголовка синяя."},
	# Миниган
	{"id": "mg_spin", "row": "w_minigun", "name": "Быстрая раскрутка", "cost": 50, "max": 2, "needs": "", "x": 0, "y": 0,
		"icon": "clock", "item": "minigun", "desc": "Стволы раскручиваются на 30% быстрее за уровень."},
	{"id": "mg_pierce", "row": "w_minigun", "name": "Бронебой", "cost": 55, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "pierce", "item": "minigun", "desc": "Пуля прошивает ещё одного врага за уровень."},
	{"id": "mg_belt", "row": "w_minigun", "name": "Длинная лента", "cost": 50, "max": 2, "needs": "mg_spin", "x": 0, "y": 1,
		"icon": "chest", "item": "minigun", "desc": "+50% патронов в ленте за уровень."},
	{"id": "mg_ricochet", "row": "w_minigun", "name": "Рикошет", "cost": 65, "max": 2, "needs": "mg_pierce", "x": 1, "y": 1,
		"icon": "rate", "item": "minigun", "desc": "Шанс 25% за уровень, что пуля отскочит и свалит ещё одного рядом."},
	{"id": "mg_fire", "row": "w_minigun", "name": "★ Огненный шквал", "cost": 250, "max": 1, "needs": "mg_belt", "x": 0, "y": 2,
		"icon": "fire", "item": "minigun", "gate": 2, "excl": "mg_storm", "final": true,
		"desc": "Финальная форма: раскалённые пули бьют вдвое сильнее и поджигают землю. Красные трассеры, стволы светятся."},
	{"id": "mg_storm", "row": "w_minigun", "name": "★ Свинцовая буря", "cost": 250, "max": 1, "needs": "mg_ricochet", "x": 1, "y": 2,
		"icon": "blast", "item": "minigun", "gate": 2, "excl": "mg_fire", "final": true,
		"desc": "Финальная форма: темп +60%, каждая пуля разрывная. Белые трассеры."},
	# Огнемёт
	{"id": "fl_range", "row": "w_flamer", "name": "Длинное сопло", "cost": 50, "max": 2, "needs": "", "x": 0, "y": 0,
		"icon": "range", "item": "flamer", "desc": "Струя бьёт дальше на 25% за уровень."},
	{"id": "fl_burn", "row": "w_flamer", "name": "Густая смесь", "cost": 50, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "fire", "item": "flamer", "desc": "Огонь на земле горит на 50% дольше и появляется чаще за уровень."},
	{"id": "fl_wide", "row": "w_flamer", "name": "Широкая струя", "cost": 60, "max": 2, "needs": "fl_range", "x": 0, "y": 1,
		"icon": "blast", "item": "flamer", "desc": "Огонь накрывает на 20% шире за уровень."},
	{"id": "fl_heat", "row": "w_flamer", "name": "Жар", "cost": 60, "max": 2, "needs": "fl_burn", "x": 1, "y": 1,
		"icon": "fire", "item": "flamer", "desc": "Струя сжигает на 2 врагов больше за тик за уровень."},
	{"id": "fl_inferno", "row": "w_flamer", "name": "★ Синее Инферно", "cost": 250, "max": 1, "needs": "fl_wide", "x": 0, "y": 2,
		"icon": "fire", "item": "flamer", "gate": 2, "excl": "fl_tornado", "final": true,
		"desc": "Финальная форма: пламя синее, урон вдвое, жжёт и доспехи, синие лужи на земле. Окна огнемёта горят синим."},
	{"id": "fl_tornado", "row": "w_flamer", "name": "★ Огненный торнадо", "cost": 250, "max": 1, "needs": "fl_heat", "x": 1, "y": 2,
		"icon": "spin", "item": "flamer", "gate": 2, "excl": "fl_inferno", "final": true,
		"desc": "Финальная форма: пока жжёшь, каждые 3 с в точке удара встаёт огненный смерч — ползёт вперёд, затягивает и сжигает толпу."},
	# Дискомёт
	{"id": "sd_pierce", "row": "w_saw", "name": "Острая кромка", "cost": 50, "max": 2, "needs": "", "x": 0, "y": 0,
		"icon": "pierce", "item": "saw", "desc": "Диск прорезает на 6 врагов больше за уровень."},
	{"id": "sd_clip", "row": "w_saw", "name": "Магазин дисков", "cost": 45, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "chest", "item": "saw", "desc": "+3 диска в обойме за уровень."},
	{"id": "sd_bounce", "row": "w_saw", "name": "Рикошет", "cost": 60, "max": 1, "needs": "sd_pierce", "x": 0, "y": 1,
		"icon": "rate", "item": "saw", "desc": "Диск не гаснет о землю — скользит дальше сквозь толпу; от скал отскакивает."},
	{"id": "sd_speed", "row": "w_saw", "name": "Разгон", "cost": 55, "max": 2, "needs": "sd_clip", "x": 1, "y": 1,
		"icon": "clock", "item": "saw", "desc": "Диск летит на 25% быстрее, стрельба чаще на 15% за уровень."},
	{"id": "sd_swarm", "row": "w_saw", "name": "★ Рой дисков", "cost": 250, "max": 1, "needs": "sd_bounce", "x": 0, "y": 2,
		"icon": "cluster", "item": "saw", "gate": 2, "excl": "sd_boomerang", "final": true,
		"desc": "Финальная форма: в полёте диск делится на 4 малых, они веером режут канал. Диски раскалённо-оранжевые."},
	{"id": "sd_boomerang", "row": "w_saw", "name": "★ Бумеранг", "cost": 250, "max": 1, "needs": "sd_speed", "x": 1, "y": 2,
		"icon": "spin", "item": "saw", "gate": 2, "excl": "sd_swarm", "final": true,
		"desc": "Финальная форма: диск долетает и возвращается, режа толпу второй раз. Диски зелёные."},
	# Электропушка
	{"id": "lt_chain", "row": "w_lightning", "name": "Длинная цепь", "cost": 55, "max": 2, "needs": "", "x": 0, "y": 0,
		"icon": "pierce", "item": "lightning", "desc": "Молния скачет на 2 врагов дальше за уровень."},
	{"id": "lt_cap", "row": "w_lightning", "name": "Конденсатор", "cost": 50, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "chest", "item": "lightning", "desc": "+40% заряда и быстрее восстановление за уровень."},
	{"id": "lt_stun", "row": "w_lightning", "name": "Шок", "cost": 65, "max": 1, "needs": "lt_chain", "x": 0, "y": 1,
		"icon": "snow", "item": "lightning", "desc": "Вокруг удара толпа застывает и почти стоит секунду."},
	{"id": "lt_rate", "row": "w_lightning", "name": "Частые разряды", "cost": 60, "max": 2, "needs": "lt_cap", "x": 1, "y": 1,
		"icon": "rate", "item": "lightning", "desc": "Разряды чаще на 20% за уровень."},
	{"id": "lt_ball", "row": "w_lightning", "name": "★ Шаровая молния", "cost": 250, "max": 1, "needs": "lt_stun", "x": 0, "y": 2,
		"icon": "core", "item": "lightning", "gate": 2, "excl": "lt_storm", "final": true,
		"desc": "Финальная форма: пока бьёшь, каждые 2,5 с вылетает шаровая молния — плывёт над толпой и сама бьёт всех вокруг. Свечение бело-фиолетовое."},
	{"id": "lt_storm", "row": "w_lightning", "name": "★ Гроза", "cost": 250, "max": 1, "needs": "lt_rate", "x": 1, "y": 2,
		"icon": "blast", "item": "lightning", "gate": 2, "excl": "lt_ball", "final": true,
		"desc": "Финальная форма: каждый 8-й разряд — удар молнии с неба в точку прицела, выжигает круг. Свечение золотое."},
	# Гравипушка
	{"id": "gv_radius", "row": "w_gravigun", "name": "Широкий горизонт", "cost": 60, "max": 2, "needs": "", "x": 0, "y": 0,
		"icon": "ring", "item": "gravigun", "desc": "Дыра затягивает с радиуса на 20% больше за уровень."},
	{"id": "gv_charges", "row": "w_gravigun", "name": "Ещё заряд", "cost": 70, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "chest", "item": "gravigun", "desc": "+1 заряд за уровень."},
	{"id": "gv_life", "row": "w_gravigun", "name": "Долгая жизнь", "cost": 60, "max": 2, "needs": "gv_radius", "x": 0, "y": 1,
		"icon": "clock", "item": "gravigun", "desc": "Дыра держится на 1,5 с дольше за уровень."},
	{"id": "gv_recharge", "row": "w_gravigun", "name": "Быстрый заряд", "cost": 60, "max": 2, "needs": "gv_charges", "x": 1, "y": 1,
		"icon": "rate", "item": "gravigun", "desc": "Заряды восстанавливаются на 20% быстрее за уровень."},
	{"id": "gv_twins", "row": "w_gravigun", "name": "★ Близнецы", "cost": 250, "max": 1, "needs": "gv_life", "x": 0, "y": 2,
		"icon": "core", "item": "gravigun", "gate": 2, "excl": "gv_nova", "final": true,
		"desc": "Финальная форма: выстрел рождает две дыры рядом. Свечение пушки голубое."},
	{"id": "gv_nova", "row": "w_gravigun", "name": "★ Сверхновая", "cost": 250, "max": 1, "needs": "gv_recharge", "x": 1, "y": 2,
		"icon": "star", "item": "gravigun", "gate": 2, "excl": "gv_twins", "final": true,
		"desc": "Финальная форма: схлопываясь, дыра взрывается огромным золотым взрывом. Свечение пушки золотое."},
	# Молот
	{"id": "hm_power", "row": "w_hammer", "name": "Тяжёлый боёк", "cost": 50, "max": 2, "needs": "", "x": 0, "y": 0,
		"icon": "blast", "item": "hammer", "desc": "Удары шире на 10% и валят на 30% больше врагов за уровень."},
	{"id": "hm_speed", "row": "w_hammer", "name": "Быстрые руки", "cost": 50, "max": 2, "needs": "", "x": 1, "y": 0,
		"icon": "rate", "item": "hammer", "desc": "Замах и удар быстрее на 15% за уровень."},
	{"id": "hm_quake", "row": "w_hammer", "name": "Землетрясение", "cost": 65, "max": 1, "needs": "hm_power", "x": 0, "y": 1,
		"icon": "ring", "item": "hammer", "desc": "«Сокрушение» бьёт волной шире на 30%, валит больше, уцелевшие стоят оглушённые вдвое дольше."},
	{"id": "hm_dive", "row": "w_hammer", "name": "Метеор", "cost": 65, "max": 1, "needs": "hm_speed", "x": 1, "y": 1,
		"icon": "wing", "item": "hammer", "desc": "Пике можно начать уже с 2 м, волна от него шире на 25% и валит в полтора раза больше."},
	{"id": "hm_thunder", "row": "w_hammer", "name": "★ Молот грома", "cost": 250, "max": 1, "needs": "hm_quake", "x": 0, "y": 2,
		"icon": "pierce", "item": "hammer", "gate": 2, "excl": "hm_fire", "final": true,
		"desc": "Финальная форма: каждый удар пускает цепную молнию по врагам вокруг, «Сокрушение» и пике зовут удар молнии с неба. Боёк искрит голубым."},
	{"id": "hm_fire", "row": "w_hammer", "name": "★ Огненный молот", "cost": 250, "max": 1, "needs": "hm_dive", "x": 1, "y": 2,
		"icon": "fire", "item": "hammer", "gate": 2, "excl": "hm_thunder", "final": true,
		"desc": "Финальная форма: удары бьют вдвое сильнее и поджигают землю, пике оставляет кольцо огня. Боёк раскалён и горит."},
]
## Разделы вкладки «Улучшения оружия» — по одному на оружие (виден, когда оружие есть).
const WEAPON_ROWS := {
	"w_rockets": {"name": "Боеголовки", "icon": "blast", "color": Color(1.0, 0.5, 0.3)},
	"w_minigun": {"name": "Миниган", "icon": "gatling", "color": Color(0.85, 0.75, 0.3)},
	"w_flamer": {"name": "Огнемёт", "icon": "fire", "color": Color(1.0, 0.55, 0.15)},
	"w_saw": {"name": "Дискомёт", "icon": "spin", "color": Color(0.35, 0.6, 1.0)},
	"w_lightning": {"name": "Электропушка", "icon": "pierce", "color": Color(0.4, 0.8, 1.0)},
	"w_gravigun": {"name": "Гравипушка", "icon": "core", "color": Color(0.7, 0.4, 1.0)},
	"w_hammer": {"name": "Молот", "icon": "blast", "color": Color(0.8, 0.78, 0.85)},
}
const WEAPON_ROW_ORDER := ["w_rockets", "w_minigun", "w_flamer", "w_saw", "w_lightning", "w_gravigun", "w_hammer"]
## Оружие героя, которое покупается за трофеи навсегда (вкладка «Оружие»); куплено —
## Progress.upgrades["wpn_<вид>"] = 1. Ракетница есть с самого начала. Постепенное развитие:
## after — индекс локации, после прохождения которой оружие можно купить (до этого — силуэт с
## замком и «Пройди «…»»); цена растёт с каждым следующим оружием.
const WEAPONS := {
	"minigun": {"name": "Миниган", "cost": 600, "after": 0, "icon": "res://ui/icons/weapon_minigun.png",
		"desc": "Шесть стволов: держи ЛКМ — раскручивается и косит толпу очередью. 150 патронов в ленте, запас пополняется сам.",
		"stats": "Темп: 16 выстр./с · Дальность: 90 м · Против толпы в канале"},
	"hammer": {"name": "Молот", "cost": 900, "after": 1, "icon": "res://ui/icons/weapon_hammer.png",
		"desc": "Ближний бой: ЛКМ — серия из трёх ударов (размах, вихрь вокруг себя, сокрушение с ударной волной). В воздухе зажми ЛКМ — пике в землю: чем выше, тем сильнее.",
		"stats": "Ближний бой · Ударная волна · Пике с высоты"},
	"flamer": {"name": "Огнемёт", "cost": 1200, "after": 2, "icon": "res://ui/icons/weapon_flamer.png",
		"desc": "Держи ЛКМ: струя огня жжёт толпу вблизи и поджигает землю — там горит ещё несколько секунд. Бак наполняется сам.",
		"stats": "Дальность струи: 30 м · Жжёт по площади · Поджигает землю"},
	"saw": {"name": "Дискомёт", "cost": 1600, "after": 3, "icon": "res://ui/icons/weapon_saw.png",
		"desc": "ЛКМ: вращающийся энергодиск летит в прицел и прорезает толпу насквозь — до 14 врагов. 8 дисков в обойме.",
		"stats": "Пробивает толпу · Дальность: 75 м · Перезарядка: T"},
	"lightning": {"name": "Электропушка", "cost": 2100, "after": 4, "icon": "res://ui/icons/weapon_lightning.png",
		"desc": "Держи ЛКМ: молния бьёт в толпу под прицелом и перескакивает на соседей — до 5 врагов за разряд. Заряд копится сам; перегрев — подожди.",
		"stats": "8 разрядов/с · Цепь до 5 врагов · Дальность: 55 м"},
	"gravigun": {"name": "Гравипушка", "cost": 2800, "after": 6, "icon": "res://ui/icons/weapon_gravigun.png",
		"desc": "ЛКМ: заряд раскрывается чёрной дырой — она затягивает врагов вокруг и забирает их. 2 заряда, копятся сами.",
		"stats": "Чёрная дыра · Затягивает толпу · Дальность: 110 м"},
}


static func owns_weapon(item: String) -> bool:
	return level("wpn_" + item) > 0


## Оружие уже можно купить: пройдена нужная локация (after).
static func weapon_open(item: String) -> bool:
	return Progress.is_completed(int(WEAPONS[item].get("after", -1))) or int(WEAPONS[item].get("after", -1)) < 0


static func buy_weapon(item: String) -> bool:
	if owns_weapon(item) or not weapon_open(item) or Progress.trophies < int(WEAPONS[item]["cost"]):
		return false
	Progress.trophies -= int(WEAPONS[item]["cost"])
	Progress.upgrades["wpn_" + item] = 1
	Progress.save()
	return true


## Узлы, которых больше нет (тесла, мастерство, ловушки, боссы): цена первого уровня — чтобы
## вернуть игроку потраченные трофеи (migrate).
const REMOVED := {"ab_tesla": 90, "ab_frost": 120, "mentor": 25, "veteran": 150, "boss_bounty": 100, "stock_spikes": 30,
	"spike_power": 40, "stock_tar": 45, "tar_power": 40}

const BASE_GATE_HP := 500
const BASE_LOOT := 0.5


static var _by_id := {}


## Узел по id (из словаря — древо спрашивает сотни раз за кадр).
static func get_node(id: String) -> Dictionary:
	if _by_id.is_empty():
		for n: Dictionary in NODES:
			_by_id[n["id"]] = n
	return _by_id.get(id, {})


## Ветка оружия: уровень узла (для оружия — короче, чем Upgrades.level).
static func w(id: String) -> int:
	return level(id)


static func level(id: String) -> int:
	Progress.load_progress()
	return int(Progress.upgrades.get(id, 0))


## Узел в древе виден: его турель открыта (или он ни к какой не привязан).
static func is_shown(id: String) -> bool:
	var item: String = get_node(id).get("item", "")
	return item == "" or Mastery.is_unlocked(item)


## Купленные уровни узлов, которых больше нет, — вернуть трофеями (один раз, при загрузке).
static func migrate() -> bool:
	var changed := false
	for id: String in REMOVED:
		var lv := int(Progress.upgrades.get(id, 0))
		if lv <= 0 and not Progress.upgrades.has(id):
			continue
		for k in lv:
			Progress.trophies += int(REMOVED[id]) * (k + 1)
		Progress.upgrades.erase(id)
		changed = true
	return changed


## Звёзд всего (сумма лучших по локациям), потрачено и свободно.
static func stars_total() -> int:
	Progress.load_progress()
	var total := 0
	for i in Progress.stars:
		total += int(Progress.stars[i])
	return total


## Цена следующего уровня узла в трофеях и кристаллах.
static func cost_at(id: String) -> int:
	return int(get_node(id)["cost"]) * (level(id) + 1)


static func crystal_at(id: String) -> int:
	return int(get_node(id).get("crystal", 0))


## Открыт ли узел: куплен предыдущий и хватает звёзд (gate).
static func is_open(id: String) -> bool:
	var n := get_node(id)
	if n.is_empty():
		return false
	# Развилка: взята другая финальная форма — эта закрыта
	if n.has("excl") and level(n["excl"]) > 0:
		return false
	var needs: String = n["needs"]
	return (needs == "" or level(needs) > 0) and stars_total() >= int(n.get("gate", 0))


static func can_buy(id: String) -> bool:
	var n := get_node(id)
	if n.is_empty():
		return false
	return is_shown(id) and is_open(id) and level(id) < int(n["max"]) and Progress.trophies >= cost_at(id) \
		and Progress.crystals >= crystal_at(id)


static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	Progress.trophies -= cost_at(id)
	Progress.crystals -= crystal_at(id)
	Progress.upgrades[id] = level(id) + 1
	Progress.save()
	return true


## Вернуть трофеи и кристаллы: за все узлы или только за узлы из ids.
static func reset(ids: Array = []) -> void:
	Progress.load_progress()
	for n: Dictionary in NODES:
		var id: String = n["id"]
		if not ids.is_empty() and not id in ids:
			continue
		for k in level(id):
			Progress.trophies += int(n["cost"]) * (k + 1)
			Progress.crystals += int(n.get("crystal", 0))
		Progress.upgrades.erase(id)
	Progress.save()


# --- что дают улучшения ----------------------------------------------------------------------

## Множитель опыта мастерства (узла «Наставник» больше нет).
static func xp_mult() -> float:
	return 1.0


## Множитель радиуса поражения ручного оружия («Оружейник»).
static func weapon_radius() -> float:
	return 1.0 + 0.12 * level("armorer")


## Цена ступени турели: базовая, скидка «Мастерской» и скидка из мастерства этой турели.
static func turret_cost(kind: String, base: int) -> int:
	return int(round(base * (1.0 - 0.06 * level("bulk")) * Mastery.mult(kind, "cost")))


## Дальность турели: «Оптика» и мастерство этой турели.
static func turret_range(kind: String) -> float:
	return (1.0 + 0.05 * level("optics")) * Mastery.mult(kind, "range")


## Какую долю вложенного возвращает продажа турели в бою (между волнами — всё).
static func sell_share() -> float:
	return 0.5


static func gate_hp() -> int:
	return int(BASE_GATE_HP * (1.0 + 0.1 * level("tunnel_hp")))


## Монет за обычного врага (громила и босс стоят больше — horde.gd: bounty). Монеты в бою идут
## на ступени турелей; сами турели — из запаса.
static func coins_per_kill() -> float:
	return BASE_LOOT * (1.0 + 0.1 * level("bounty"))


## На старте локации: 200 монет и ещё 100 за каждый уровень «Снабжения».
static func start_coins() -> int:
	return 200 + 100 * level("supply")


## Доля ворот, которую плотники чинят после волны.
static func repair() -> float:
	return 0.1 + 0.05 * level("repair")


## Запас зарядов мушкетона и минигана («Запасливый») и их перезарядка («Быстрые руки»).
static func ammo_mult() -> float:
	return 1.0 + 0.25 * level("stockpile")


## Ракет в стволе сверх базовых («Боезапас»).
static func clip_bonus() -> int:
	return level("stockpile")


static func reload_mult() -> float:
	return 1.0 - 0.1 * level("hands")


## Пополнение запаса ракет («Подвоз ракет»; «Быстрая перезарядка» тоже ускоряет).
static func resupply_mult() -> float:
	return reload_mult() * (1.0 - 0.15 * level("resupply"))


## Ракетница: скорость ракеты, тройной выстрел, поджог, шанс второй ракеты.
static func rocket_speed() -> float:
	return 1.0 + 0.15 * level("rocket_speed")


static func double_chance() -> float:
	return 0.15 * level("double")


# --- герой ----------------------------------------------------------------------------------

static func fly_speed_mult() -> float:
	return 1.0 + 0.08 * level("fly_speed")


static func refuel_mult() -> float:
	return 1.0 / (1.0 + 0.2 * level("refuel"))


static func ceiling_bonus() -> float:
	return 8.0 * level("ceiling")


static func regen_mult() -> float:
	return 1.0 + 0.25 * level("regen")


static func regen_delay_cut() -> float:
	return 0.3 * level("regen")


static func spear_mult() -> float:
	return 1.0 - 0.1 * level("spear_guard")


static func hero_xp_mult() -> float:
	return 1.0 + 0.2 * level("hero_xp")


## Трофеи за рубежи орды («Бонус рубежей»).
static func milestone_mult() -> float:
	return 1.0 + 0.25 * level("milestone_bonus")


## Во сколько раз чаще стреляют все турели («Скорострельность»).
static func turret_rate() -> float:
	return 1.0 + 0.05 * level("rapid")


## Трофеи за бой («Трофейщик») и кристаллы сверху за каждого убитого босса («Охотник за головами»).
static func trophy_mult() -> float:
	return 1.0 + 0.1 * level("trophy_gain")


## Кристаллы сверху за босса (узла «Охотник за головами» больше нет).
static func boss_crystals() -> int:
	return 0


## Сколько турелей вида kind можно поставить за бой (если она открыта).
static func turret_stock(kind: String) -> int:
	if not Mastery.is_unlocked(kind):
		return 0
	return (2 if kind == "gatling" else 1) + level("stock_" + kind)


## Сколько ловушек вида kind ("spikes", "tar") можно положить за бой.
## Умение героя i (Q, E, R, F по порядку) открыто в древе.
## Секунд полёта на ранце сверх базовых («Время полёта»).
static func flight_bonus() -> float:
	return 2.0 * level("flight")


static func hero_hp_bonus() -> float:
	return 15.0 * level("hero_armor")


static func ability_cd_mult() -> float:
	return 1.0 - 0.06 * level("ab_speed")


static func trap_stock(kind: String) -> int:
	if kind == "barricade":
		return 2 + level("stock_barricade")
	return (2 + level("stock_spikes")) if kind == "spikes" else (1 + level("stock_tar"))


## Прочность баррикады: столько «секунд-врагов» держит (каждый упёршийся ломает 2 в секунду).
static func barricade_hp() -> float:
	return 1600.0 * (1.0 + 0.3 * level("barricade_hp"))


## Сила ловушек: шипы — во сколько раз чаще ранят, смола — во сколько раз тормозит.
static func spike_power() -> float:
	return 1.0 + 0.25 * level("spike_power")


static func tar_slow() -> float:
	return 0.7 - 0.07 * level("tar_power")
