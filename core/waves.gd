extends Node
## Ход боя: одна большая орда, здоровье ворот и монеты.
## Волн нет: бой — это одна орда в тысячи врагов. Enter выпускает её, и враги идут из лагерей без
## остановки: поток со временем густеет, накатывает натисками, к концу в нём больше бегунов,
## громил и доспехов. Ворота пали — бой проигран, но трофеи за убитых остаются: прокачайся и
## снова в бой, пока не разобьёшь всю орду. Вся орда разбита — локация пройдена, а на следующей
## орда больше и злее (levels.gd: difficulty).
## Каждые 20 % пройденной орды — рубеж: бонус трофеев (main.gd), подвоз боеприпасов и ремонт ворот.
## Каждый враг у ворот отнимает их прочность; за каждого убитого — монеты на турели.

signal gate_hit(damage: int)
## Орда вышла (игрок нажал Enter).
signal started
## Пройден рубеж step (1..STEPS − 1; последний рубеж — победа).
signal milestone(step: int)
## В орде впервые появились враги в доспехах (heavy — в тяжёлых).
signal armor_appeared(heavy: bool)
## Конец боя, игрок нажал Enter — начать заново (сцену перезагружает main.gd).
signal restart_requested(won: bool)
## Вся орда разбита — локация пройдена (main.gd отмечает прохождение).
signal won
## Бой кончился (победа или ворота пали) — main.gd записывает опыт мастерства и итоги.
signal finished
## Пришёл босс (mini — вожак посреди боя).
signal boss_arrived(boss_name: String, mini: bool)

enum State { READY, FIGHT, WON, LOST }

const Upgrades := preload("res://core/upgrades.gd")

const STEPS := 5                # рубежи — каждые 20 % орды
## Боссы и вожаки пока выключены (вернём позже): только рядовая орда.
const BOSSES := false
const ARMOR_FROM := 5           # ступень (1..10), с которой в орде доспехи
const HEAVY_FROM := 9           # и тяжёлые доспехи
## Врагов в орде — как было в пяти прежних волнах вместе (на первой локации ~12 тыс.); орда для
## героя с ранцем и умениями на треть гуще, чем была для стрелка на стене.
const HORDE_BASE := 11600.0
const HORDE := 1.35
const HORDE_TIME := 180.0       # с — за столько из лагерей выходит вся орда
const RAMP := 5.0               # к концу поток в 1 + RAMP раз гуще, чем в начале (начало мягкое)
const SURGE := 0.4              # натиски: поток то гуще, то реже на ±40 %
const SURGE_PERIOD := 32.0      # с — от натиска до натиска

var state := State.READY
## Пройдено рубежей (0..STEPS).
var step := 0
## Врагов в орде этого боя (0 — орда ещё не вышла).
var total := 0
## Прочность ворот: полная (с прокачкой) и сколько осталось.
var gate_max := Upgrades.gate_hp()
var gate_hp := gate_max
var coins := Upgrades.start_coins()
var horde: Node3D
var weapons: Array[Node3D] = []

var _last_reached := 0
var _last_bounty := 0
var _coin_frac := 0.0
var _time := 0.0
var _mix_timer := 0.0
var _armor_told := false
var _heavy_told := false
var _mini_sent := false
var _boss_sent := false
var _stall := 0.0
var _stall_count := -1
var _final := 0.0               # доля пройденной орды в момент, когда ворота пали
## Имена босса и вожака локации (levels.gd: boss, mini).
var boss_name := "Босс"
var mini_name := "Вожак"

## Сложность локации: во сколько раз орда больше и злее, чем на первой.
var difficulty := 1.0
## Характер наступления локации (levels.gd: pattern) — ключ в PATTERNS.
var pattern := "steady"
var _rot_timer := 0.0
var _rot_cave := 0

## Характер наступления: у каждой локации свой, чтобы бои не были одинаковыми.
##   surge, period — натиски: поток то гуще, то реже на ±surge, раз в period секунд;
##   ramp — во сколько раз (1 + ramp) поток к концу гуще начала;
##   armor, heavy — с какой ступени (1..10) доспехи и тяжёлые доспехи;
##   runners, brutes — множители доли бегунов и громил;
##   rotate — раз в столько секунд орда меняет фланг: почти вся идёт из одной пещеры (0 — отовсюду);
##   lull — первые столько долей времени поток жидкий (затишье перед бурей);
##   burst, burst_every, burst_len — извержения: каждые burst_every с поток в burst раз гуще burst_len с.
const PATTERNS := {
	"steady": {"name": "Ровный поток", "surge": 0.3, "period": 32.0, "ramp": 4.0, "armor": 6, "heavy": 10,
		"runners": 1.0, "brutes": 1.0},
	"surges": {"name": "Натиски", "surge": 0.85, "period": 22.0, "ramp": 3.5, "armor": 6, "heavy": 10,
		"runners": 1.1, "brutes": 1.0},
	"rush": {"name": "Стремительный рой", "surge": 0.45, "period": 18.0, "ramp": 4.0, "armor": 7, "heavy": 11,
		"runners": 2.2, "brutes": 0.5},
	"armored": {"name": "Бронированная колонна", "surge": 0.25, "period": 36.0, "ramp": 3.0, "armor": 3, "heavy": 7,
		"runners": 0.6, "brutes": 1.5},
	"flank": {"name": "Удары с флангов", "surge": 0.5, "period": 28.0, "ramp": 4.0, "armor": 5, "heavy": 9,
		"runners": 1.2, "brutes": 1.0, "rotate": 14.0},
	"tide": {"name": "Прилив", "surge": 0.2, "period": 40.0, "ramp": 9.0, "armor": 5, "heavy": 9,
		"runners": 0.9, "brutes": 1.1},
	"ambush": {"name": "Ночная засада", "surge": 0.6, "period": 20.0, "ramp": 4.0, "armor": 5, "heavy": 9,
		"runners": 1.4, "brutes": 1.0, "rotate": 9.0, "lull": 0.22},
	"eruption": {"name": "Извержения", "surge": 0.3, "period": 30.0, "ramp": 3.5, "armor": 5, "heavy": 8,
		"runners": 1.0, "brutes": 1.4, "burst": 3.0, "burst_every": 26.0, "burst_len": 5.0},
	"siege": {"name": "Осада", "surge": 0.2, "period": 34.0, "ramp": 3.0, "armor": 4, "heavy": 7,
		"runners": 0.8, "brutes": 1.4},
	"hive": {"name": "Весь рой", "surge": 0.7, "period": 20.0, "ramp": 6.0, "armor": 4, "heavy": 8,
		"runners": 1.4, "brutes": 1.3, "rotate": 11.0, "burst": 2.2, "burst_every": 34.0, "burst_len": 6.0},
}
## Врагов на карте одновременно — не больше этого: дальше лагеря придерживают выход (FPS).
const ON_MAP_CAP := 5000


func _pat(key: String, fallback: float) -> float:
	return float(PATTERNS.get(pattern, PATTERNS["steady"]).get(key, fallback))


func pattern_name() -> String:
	return PATTERNS.get(pattern, PATTERNS["steady"])["name"]


## За сколько секунд выходит вся орда: почти одинаково на всех локациях — бо́льшая орда идёт
## гуще (давит сильнее), а не дольше. Тесноту на карте держит ON_MAP_CAP.
func horde_time() -> float:
	return HORDE_TIME * pow(_size_scale(), 0.1)


## Во сколько раз больше врагов, чем на первой локации, и во сколько раз чаще доспехи и бегуны:
## сложность локации растёт плавнее, чем её множитель (иначе размер, броня и состав
## перемножаются и поздние локации непроходимы).
func _size_scale() -> float:
	return pow(difficulty, 0.6)


func _mix_scale() -> float:
	return sqrt(difficulty) * tough


## Живучесть орды локации (levels.gd: tough): больше брони, бегунов и громил — для карт, где
## длинные пути и турели успевают всех перебить.
var tough := 1.0
## Монеты за убитых на этой локации (levels.gd: coins): на картах с длинными путями турелей за
## монеты выходило так много, что орда не доходила до туннеля.
var coin_mult := 1.0


## Поправка размера орды локации (levels.gd: horde) — чтобы орда росла строго от локации к локации.
var horde_mult := 1.0


func horde_size() -> int:
	return int(HORDE_BASE * _size_scale() * HORDE * horde_mult)


## Насколько далеко зашла орда — «ступень» 1..10 по доле уже вышедших врагов p (0..1):
## состав, доспехи и громилы нарастают по ней.
func _stage(p: float) -> float:
	return 1.0 + 9.0 * clampf(p, 0.0, 1.0)


## Состав орды на доле p: доли обычных, бегунов и громил. Чем дальше и сложнее локация, тем
## бегунов и громил больше.
func wave_mix(p: float) -> PackedFloat32Array:
	var s := _stage(p)
	var runners := clampf(0.035 * (s - 1.0) * _mix_scale() * _pat("runners", 1.0), 0.0, 0.45)
	var brutes := clampf(0.02 * (s - 2.0) * _mix_scale() * _pat("brutes", 1.0), 0.0, 0.25)
	return PackedFloat32Array([1.0 - runners - brutes, runners, brutes])


## Доспехи: с середины орды часть обычных врагов в доспехах (держат два попадания), дальше —
## больше; к концу часть — в тяжёлых (три попадания). Бегуны всегда хрупкие. Так конец орды
## тяжелее, а врагов на экране не больше. На сложных локациях доспехов больше.
func armor_share(p: float) -> float:
	return clampf((_stage(p) - _pat("armor", ARMOR_FROM) + 1) * 0.12 * _mix_scale(), 0.0, 1.0)


func heavy_share(p: float) -> float:
	return clampf((_stage(p) - _pat("heavy", HEAVY_FROM) + 1) * 0.12 * _mix_scale(), 0.0, 1.0)


## Прочность громил растёт со сложностью локации и по ходу орды.
func brute_hp(p: float) -> int:
	return 3 + int(_mix_scale() * 1.5) + floori((_stage(p) - 1.0) / 2.0)


func boss_hp(mini: bool) -> int:
	return int((200.0 if mini else 1000.0) * difficulty)


## Сколько врагов в секунду выходит из лагерей: в начале реже, к концу в 1 + RAMP раз гуще,
## поверх — натиски. Начальный поток подобран так, чтобы вся орда вышла за HORDE_TIME.
func spawn_rate(p: float, t: float) -> float:
	var ramp := _pat("ramp", RAMP)
	var base := total * log(1.0 + ramp) / (ramp * horde_time())
	var surge := 1.0 - _pat("surge", SURGE) * cos(t * TAU / _pat("period", SURGE_PERIOD))
	var rate := base * (1.0 + ramp * p) * surge
	# Затишье перед бурей: в начале поток жидкий
	if t < horde_time() * _pat("lull", 0.0):
		rate *= 0.3
	# Извержения: раз в burst_every секунд поток резко гуще
	var burst := _pat("burst", 1.0)
	if burst > 1.0 and t > 12.0 and fmod(t, _pat("burst_every", 30.0)) < _pat("burst_len", 5.0):
		rate *= burst
	# Карта переполнена — лагеря придерживают выход, пока толпу не проредят (FPS)
	if horde.count() > ON_MAP_CAP:
		rate = 0.0
	return rate


## Доля орды, что уже вышла из лагерей (0..1).
func spawned() -> float:
	return clampf(1.0 - float(horde.pending) / total, 0.0, 1.0) if total > 0 else 0.0


## Доля пройденной орды (0..1): кого уже нет — убиты или дошли до ворот.
func progress() -> float:
	return clampf(1.0 - float(remaining()) / total, 0.0, 1.0) if total > 0 else 0.0


func percent() -> int:
	match state:
		State.WON:
			return 100
		State.LOST:
			return int(_final * 100.0)
	return int(progress() * 100.0)


## Всё с начала: орда не вышла, целые ворота, без монет (орду очищает main.gd).
func reset() -> void:
	state = State.READY
	step = 0
	total = 0
	_time = 0.0
	_armor_told = false
	_heavy_told = false
	_mini_sent = false
	_boss_sent = false
	gate_hp = gate_max
	coins = Upgrades.start_coins()
	_coin_frac = 0.0
	_last_reached = horde.gate_damage
	_last_bounty = horde.bounty


## Сколько врагов осталось: на карте и ещё в лагерях.
func remaining() -> int:
	return horde.count() + horde.pending


## Enter: выпустить орду, а после конца боя — новый бой.
func start() -> void:
	match state:
		State.FIGHT:
			return
		State.WON, State.LOST:
			restart_requested.emit(state == State.WON)
			return
	state = State.FIGHT
	total = horde_size()
	_time = 0.0
	_apply_mix(0.0)
	horde.send_wave(total, spawn_rate(0.0, 0.0))
	started.emit()
	for w in weapons:
		w.restock()


## Фланги: раз в rotate секунд орда переключается на другую пещеру — почти вся идёт оттуда.
func _update_flanks(delta: float) -> void:
	var rot := _pat("rotate", 0.0)
	var n: int = horde.spawn_count()
	if rot <= 0.0 or n < 2:
		if horde.spawn_weights.size() > 0:
			horde.spawn_weights = PackedFloat32Array()
		return
	_rot_timer -= delta
	if _rot_timer > 0.0 and horde.spawn_weights.size() == n:
		return
	_rot_timer = rot
	var next := randi() % n
	if n > 1 and next == _rot_cave:
		next = (next + 1) % n
	_rot_cave = next
	var w := PackedFloat32Array()
	w.resize(n)
	w.fill(0.12)
	w[_rot_cave] = 1.0
	horde.spawn_weights = w


## Состав орды для тех, кто выходит сейчас.
func _apply_mix(p: float) -> void:
	horde.mix = wave_mix(p)
	horde.brute_hp = brute_hp(p)
	horde.armor_share = armor_share(p)
	horde.heavy_share = heavy_share(p)
	if not _armor_told and armor_share(p) > 0.0:
		_armor_told = true
		armor_appeared.emit(false)
	if not _heavy_told and heavy_share(p) > 0.0:
		_heavy_told = true
		armor_appeared.emit(true)


func _process(delta: float) -> void:
	# Урон воротам — по видам врагов (громила бьёт сильнее, босс — очень сильно)
	var reached: int = horde.gate_damage
	if reached > _last_reached:
		var damage := reached - _last_reached
		_last_reached = reached
		if state != State.LOST:
			gate_hp = maxi(gate_hp - damage, 0)
			gate_hit.emit(damage)
	var bounty: int = horde.bounty
	# На поздних локациях врагов больше, а монет за бой — столько же: награда за врага делится
	# на рост орды. Иначе больше врагов → больше ступеней турелей → ещё легче
	_coin_frac += (bounty - _last_bounty) * Upgrades.coins_per_kill() / _size_scale() * coin_mult
	coins += int(_coin_frac)
	_coin_frac -= int(_coin_frac)
	_last_bounty = bounty
	if state != State.FIGHT:
		return
	_time += delta
	_update_flanks(delta)
	var out := spawned()
	if horde.pending > 0:
		horde.spawn_rate = spawn_rate(out, _time)
	_mix_timer -= delta
	if _mix_timer <= 0.0:
		_mix_timer = 0.5
		_apply_mix(out)
	if BOSSES:
		if not _mini_sent and out >= 0.5:
			_mini_sent = true
			horde.spawn_boss(boss_hp(true), 3.0, true)
			boss_arrived.emit(mini_name, true)
		if not _boss_sent and out >= 0.9:
			_boss_sent = true
			horde.spawn_boss(boss_hp(false), 4.2, false)
			boss_arrived.emit(boss_name, false)
	# Рубежи: каждые 20 % пройденной орды — подвоз боеприпасов и плотники чинят ворота
	var p := progress()
	while step < STEPS - 1 and p >= float(step + 1) / STEPS and gate_hp > 0:
		step += 1
		gate_hp = mini(gate_max, gate_hp + int(gate_max * Upgrades.repair()))
		for w in weapons:
			w.restock()
		milestone.emit(step)
	# Страховка: орда вышла, остались единицы и долго никуда не деваются — значит, застряли
	if horde.pending == 0 and horde.count() <= 20:
		if horde.count() != _stall_count:
			_stall_count = horde.count()
			_stall = 0.0
		_stall += delta
		if _stall > 40.0:
			horde.clear_stragglers()
	else:
		_stall = 0.0
		_stall_count = -1
	if gate_hp <= 0:
		_final = progress()
		state = State.LOST
		horde.pending = 0
		finished.emit()
	elif remaining() == 0:
		step = STEPS
		state = State.WON
		won.emit()
		finished.emit()
