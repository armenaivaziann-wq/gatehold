extends Node3D
## Орда: пустынные жуки (или гоблины — на локации с monster = "goblin") выходят из пещер
## и текут по каналам к воротам. Враги разных видов (TYPES): обычные, быстрые бегуны, крепкие
## громилы, босс; у каждого своя прочность — попадание снимает её, у кого не осталось, погибает.
##
## Оптимизация: жуки — не узлы, а строки в массивах; рисуются одним MultiMesh. Расчёт идёт
## шагами по TICK (30 раз в секунду), буфер MultiMesh пишется после шага, а между шагами
## шейдер сам сдвигает каждого по его скорости (параметр lag) — движение плавное при любом FPS.
## Ноги анимирует шейдер. Для запросов (кого задел выстрел, цель турели) жуки разложены по
## клеткам сетки — перебираются только клетки рядом, а не вся орда. Путь к воротам заранее просчитан по сетке
## (поле направлений), поэтому каждый жук просто читает направление из своей клетки.
## Расталкивание — через плотность: жуки уходят из переполненных клеток и от стенок,
## растекаются по ширине канала и сбиваются в плотные «реки».

const MapBuilder := preload("res://locations/map_builder.gd")
const MonsterShader := preload("res://mobs/shaders/horde_monster.gdshader")
const BossView := preload("res://mobs/boss_view.gd")
const Mobs := preload("res://mobs/mobs.gd")
const GoblinShader := preload("res://mobs/shaders/horde_goblin.gdshader")

## Сломана баррикада (номер ловушки) — turrets.gd убирает её модель.
signal trap_broken(id: int)
## Баррикада: во сколько раз медленнее идут сквозь неё; урон в секунду от каждого упёршегося
## (не больше BARRICADE_CROWD сразу).
const BARRICADE_SLOW := 0.03
const BARRICADE_DPS := 2.0
const BARRICADE_CROWD := 40
const MAX_UNITS := 12000
const CELL := 1.0               # клетка сетки пути и плотности, м
const SPEED := 5.0              # средняя скорость, м/с
const SPAWN_RATE := 60.0        # жуков в секунду из всех пещер вместе (волна может ускорить)
const PUSH := 0.9               # сила расталкивания
const WALL_DENSITY := 5.0       # стенка «давит», как пять жуков в клетке
const STRIDE := 16              # 12 чисел трансформации + 4 своих данных
const TICK := 1.0 / 20.0        # шаг расчёта орды, с (между шагами шейдер досчитывает движение)
const MAX_CORPSES := 1200       # трупики и брызги — кольцевые буферы, старые заменяются новыми
const NEAR_DISTANCE := 22.0     # м от камеры: ближе — подробная модель, дальше — упрощённая
const MAX_SPLATS := 2000

## Сколько жуков ещё выйдет из пещер (очередь волны).
var pending := 0
## Веса пещер (по одному на выход из лагеря): откуда сейчас идёт орда (waves.gd: фланги, натиски
## с одной стороны). Пусто — из всех поровну.
var spawn_weights := PackedFloat32Array()
## Скорость выхода из пещер, жуков в секунду.
var spawn_rate := SPAWN_RATE
## Виды врагов: скорость, размер, прочность (сколько попаданий держит), урон воротам, награда.
## Громилы держат больше попаданий (их прочность задают волны), босс — сотни; бегуны быстрые.
## Рост у всех рядовых одинаковый (орда — ровная масса), крупнее только боссы.
const TYPES := [
	{"name": "обычный", "speed": 1.0, "size": 1.15, "hp": 1, "gate": 1, "bounty": 1},
	{"name": "бегун", "speed": 1.6, "size": 1.15, "hp": 1, "gate": 1, "bounty": 1},
	{"name": "громила", "speed": 0.72, "size": 1.15, "hp": 4, "gate": 3, "bounty": 4},
	{"name": "босс", "speed": 0.5, "size": 3.4, "hp": 300, "gate": 120, "bounty": 200},
]
const BOSS := 3
const MINI_SPEED := 0.75          # вожак верхом — быстрее главного босса
const LINE_HEIGHT := 1.3         # м: пуля или луч задевает тех, чьё тело ближе к линии по высоте
const BOSS_BLAST := 8             # взрыв бьёт по боссу всем телом: урон ×8
const ARMORED := 4                # только для шейдера: обычный в доспехах

## Сколько жуков дошло до ворот и сколько прочности ворот они сняли (громила — больше).
var reached := 0
var gate_damage := 0
## Награда за убитых (монеты до прокачки): обычный — 1, громила — 4, босс — 200.
var bounty := 0
## Состав волны: доли обычных, бегунов и громил; прочность громил.
var mix := PackedFloat32Array([1.0, 0.0, 0.0])
var brute_hp := 4
## Доли обычных врагов в доспехах (держат 2 попадания) и в тяжёлых (3) — waves.gd.
var armor_share := 0.0
var heavy_share := 0.0
## Босс на поле: жив ли, сколько прочности осталось и сколько было.
var boss_alive := false
var boss_hp := 0
var boss_max := 1
## Сколько боссов дошло до ворот (для проверок) и сколько убито вожаков и главных боссов
## (за них кристаллы — main.gd).
var boss_escaped := 0
var minis_killed := 0
var bosses_killed := 0
var _boss_mini := false
## Свои модели главного босса и вожака локации (levels.gd: boss_model, mini_model; нет — просто
## большой враг орды).
var boss_scene: PackedScene
var mini_scene: PackedScene
var _boss_i := -1                 # индекс босса в массивах (−1 — нет)
var _boss_view: Node3D
## Сколько жуков убито — всего и по тому, кто убил (опыт мастерства: "musket", "gatling"…).
var kills := 0
var kills_by := {}
## Кто идёт: вид рядовых врагов локации (mobs.gd: KINDS; берётся из локации в setup).
var monster := "bug"
## Множитель скорости жуков на этой локации (на длинных серпантинах они бегут быстрее).
var speed_scale := 1.0
## Центр последнего попадания (среднее место убитых) — для эффектов.
var last_hit := Vector3.ZERO

var _w := 0                     # клеток по стороне
var _origin := 0.0              # мировая координата края сетки
var _solid := PackedByteArray() # 1 — нельзя идти (плато, стенки)
var _dist := PackedInt32Array() # шагов до ворот (0 — у ворот, -1 — недостижимо)
var _flow := PackedVector2Array()
var _floor_y := PackedFloat32Array()
var _counts := PackedInt32Array()
var _cell_head := PackedInt32Array()  # первый жук в клетке (−1 — пусто), дальше по _next
var _next := PackedInt32Array()
var _tick_acc := 0.0
var _mat: ShaderMaterial
var _spawns: Array[Vector2] = []

var _n := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _face := PackedVector2Array()
var _speed := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedFloat32Array()
var _type := PackedByteArray()
var _hp := PackedInt32Array()
## Постоянный номер каждого врага: индексы в массивах меняются при каждой смерти (на место убитого
## переезжает последний), а номер — нет. По нему турели и дрон узнают, что их цель всё та же.
var _uid := PackedInt32Array()
var _next_uid := 1
var _buffer := PackedFloat32Array()
var _spawn_acc := 0.0
## Ловушки на дне каналов (ставит turrets.gd): шипы ранят идущих по ним — не больше SPIKE_HITS
## попаданий в секунду на поле (× сила из древа), смола тормозит всех в луже (множитель
## скорости по клеткам — _slow).
const SPIKE_HITS := 3.0
var _traps: Array[Dictionary] = []   # {id, kind, center, radius, power, acc}
var _trap_id := 0
var _slow := PackedFloat32Array()
## Мороз (турель-заморозка, chill()): сколько ещё секунд враг идёт медленнее — и во сколько раз.
const CHILL_BOSS := 0.6           # босса мороз тормозит слабее: множитель ближе к 1
var _chill := PackedFloat32Array()
var _chill_mult := PackedFloat32Array()
var _mm: MultiMesh               # ближние — подробная модель
var _mm_far: MultiMesh           # дальние — упрощённая
var _corpses: MultiMesh
var _corpse_next := 0
var _splats: MultiMesh
var _splat_next := 0


## Построить сетку пути по готовой карте (вызвать до добавления в сцену).
func setup(map: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	monster = map.level.get("monster", "bug")
	_origin = -MapBuilder.HALF
	_w = int(MapBuilder.HALF * 2.0 / CELL)
	var cells := _w * _w
	_solid.resize(cells)
	_floor_y.resize(cells)
	_dist.resize(cells)
	_flow.resize(cells)
	_counts.resize(cells)
	_cell_head.resize(cells)
	_cell_head.fill(-1)
	_slow.resize(cells)
	_slow.fill(1.0)
	for z in _w:
		for x in _w:
			var p := _cell_center(x, z)
			var c := z * _w + x
			# Идти можно по дну канала, чуть отступив от подножия стенки
			_solid[c] = 0 if map.channel_dist(p) < -0.4 else 1
			_floor_y[c] = map.height(p)
	_build_flow()
	for cave in map.caves():
		var a: Vector2 = cave[0]
		var b: Vector2 = cave[1]
		_spawns.append(a + (b - a).normalized() * 3.0)
	print("сетка пути орды: %d мс" % (Time.get_ticks_msec() - t0))


func _ready() -> void:
	for arr in [_pos, _vel, _face]:
		arr.resize(MAX_UNITS)
	for arr in [_speed, _phase, _size, _chill, _chill_mult]:
		arr.resize(MAX_UNITS)
	_type.resize(MAX_UNITS)
	_hp.resize(MAX_UNITS)
	_uid.resize(MAX_UNITS)
	# Один буфер на оба слоя: первая половина — ближние, вторая — дальние
	_buffer.resize(MAX_UNITS * STRIDE * 2)
	_next.resize(MAX_UNITS)
	var mat := ShaderMaterial.new()
	mat.shader = GoblinShader if Mobs.rig(monster) == "biped" else MonsterShader
	_mat = mat
	var rig_params: Dictionary = Mobs.rig_params(monster)
	for key: String in rig_params:
		mat.set_shader_parameter(key, rig_params[key])
	_mm = _make_layer(Mobs.mesh(monster), MAX_UNITS, true, false, mat)
	_mm_far = _make_layer(Mobs.mesh(monster, true), MAX_UNITS, true, false, mat)
	# Трупики: тот же жук (гоблин) на спине; шейдер поджимает лапы и через время утапливает в песок
	var corpse_mat: ShaderMaterial = mat.duplicate()
	corpse_mat.set_shader_parameter("corpse", true)
	_corpses = _make_layer(_mm.mesh, MAX_CORPSES, true, false, corpse_mat)
	_splats = _make_layer(_splat_mesh(), MAX_SPLATS, false, true, null)


func _make_layer(mesh: Mesh, count: int, custom: bool, colors: bool, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-MapBuilder.HALF, -2, -MapBuilder.HALF), Vector3(MapBuilder.HALF * 2, 8, MapBuilder.HALF * 2))
	if mat:
		mmi.material_override = mat
	add_child(mmi)
	return mm


## Убить жуков в конусе выстрела: сначала ближайших, не больше max_kills. Возвращает число убитых.
func kill_cone(origin: Vector3, dir: Vector3, max_range: float, half_angle: float, max_kills: int, source := "",
		damage := 1) -> int:
	var cos_half := cos(half_angle)
	var r2 := max_range * max_range
	var hits: Array[Vector2] = []
	# Конус целиком внутри цилиндра вокруг оси: по земле — отрезок оси, расширенный на радиус
	var o := Vector2(origin.x, origin.z)
	var tip := o + Vector2(dir.x, dir.z) * max_range
	var spread := max_range * (sin(half_angle) if half_angle < PI / 2 else 1.0) + 1.0
	for i in _gather(o.min(tip) - Vector2.ONE * spread, o.max(tip) + Vector2.ONE * spread):
		var p := _pos[i]
		var to := Vector3(p.x - origin.x, _floor_at(p) + 0.25 - origin.y, p.y - origin.z)
		var d2 := to.length_squared()
		if d2 > r2:
			continue
		var d := sqrt(d2)
		if to.dot(dir) >= cos_half * d:
			hits.append(Vector2(d, i))
	return _kill_sorted(hits, max_kills, source, damage)


## Убить жуков в радиусе от точки (по земле), ближних первыми. Возвращает число убитых.
func kill_area(center: Vector3, radius: float, max_kills: int, source := "", damage := 1) -> int:
	var c := Vector2(center.x, center.z)
	var r2 := radius * radius
	var hits: Array[Vector2] = []
	for i in _gather(c - Vector2.ONE * (radius + 2.0), c + Vector2.ONE * (radius + 2.0)):
		var d2 := _pos[i].distance_squared_to(c)
		# Босс огромный: задевает и краем взрыва
		if d2 <= r2 or (_type[i] == BOSS and d2 <= pow(radius + _size[i] * 0.35, 2.0)):
			hits.append(Vector2(d2, i))
	return _kill_sorted(hits, max_kills, source, damage, BOSS_BLAST)


## Жуки в прямоугольнике lo..hi (по земле) — кандидаты для запросов: из клеток сетки, а если
## прямоугольник больше, чем жуков, — просто все. Клетки раскладываются на шаге расчёта; кто
## погиб после этого, отсеивается (индекс за концом), а позицию запросы проверяют сами.
func _gather(lo: Vector2, hi: Vector2) -> PackedInt32Array:
	var inv := 1.0 / CELL
	var x0 := clampi(int((lo.x - _origin) * inv), 0, _w - 1)
	var x1 := clampi(int((hi.x - _origin) * inv), 0, _w - 1)
	var z0 := clampi(int((lo.y - _origin) * inv), 0, _w - 1)
	var z1 := clampi(int((hi.y - _origin) * inv), 0, _w - 1)
	var out := PackedInt32Array()
	if (x1 - x0 + 1) * (z1 - z0 + 1) > _n:
		out.resize(_n)
		for i in _n:
			out[i] = i
		return out
	for z in range(z0, z1 + 1):
		var row := z * _w
		for x in range(x0, x1 + 1):
			var k := _cell_head[row + x]
			while k >= 0:
				if k < _n:
					out.append(k)
				k = _next[k]
	return out


## Сколько жуков в радиусе от точки — по сетке плотности (быстро, без перебора жуков).
func count_near(center: Vector3, radius: float) -> int:
	var inv := 1.0 / CELL
	var cx := int((center.x - _origin) * inv)
	var cz := int((center.z - _origin) * inv)
	var r := int(ceil(radius * inv))
	var r2 := (radius * inv) * (radius * inv)
	var total := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var z := cz + dz
			if x >= 0 and z >= 0 and x < _w and z < _w and dx * dx + dz * dz <= r2:
				total += _counts[z * _w + x]
	return total


## Маршруты роя: от каждой пещеры по полю направлений до ворот, точки через ~1 м.
## По ним видно, где жуки реально идут (а где канал пустует — они выбирают короткий путь).
func route_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var inv := 1.0 / CELL
	# Спуск по числу шагов до ворот: каждый раз — в соседнюю клетку, где оно меньше всего
	for s in _spawns:
		var x := clampi(int((s.x - _origin) * inv), 1, _w - 2)
		var z := clampi(int((s.y - _origin) * inv), 1, _w - 2)
		for k in 2000:
			var c := z * _w + x
			if _dist[c] <= 0:
				break
			var best := c
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var n := (z + dz) * _w + x + dx
					if _dist[n] >= 0 and _dist[n] < _dist[best]:
						best = n
			if best == c:
				break
			x = best % _w
			z = best / _w
			out.append(_cell_center(x, z))
	return out


## Цель для турели: жук в радиусе от центра (по земле), ближе всех подобравшийся к воротам.
## Возвращает индекс жука или -1. Индексы меняются при каждой смерти — сразу берите позицию.
func pick_target(center: Vector3, max_range: float, min_range := 0.0) -> int:
	var c := Vector2(center.x, center.z)
	var r2 := max_range * max_range
	var m2 := min_range * min_range
	var inv := 1.0 / CELL
	var best := -1
	var best_d := 1 << 30
	for i in _gather(c - Vector2.ONE * max_range, c + Vector2.ONE * max_range):
		var d2 := _pos[i].distance_squared_to(c)
		if d2 > r2 or d2 < m2:
			continue
		var p := _pos[i]
		var steps := _dist[clampi(int((p.y - _origin) * inv), 0, _w - 1) * _w + clampi(int((p.x - _origin) * inv), 0, _w - 1)]
		if steps >= 0 and steps < best_d:
			best_d = steps
			best = i
	return best


## Несколько целей для турели: до count жуков в радиусе, ближних к воротам — первыми
## (турель проверяет, какого из них видно, и берёт первого видимого).
func pick_targets(center: Vector3, max_range: float, min_range: float, count: int) -> PackedInt32Array:
	var c := Vector2(center.x, center.z)
	var r2 := max_range * max_range
	var m2 := min_range * min_range
	var inv := 1.0 / CELL
	var found: Array[Vector2] = []
	for i in _gather(c - Vector2.ONE * max_range, c + Vector2.ONE * max_range):
		var d2 := _pos[i].distance_squared_to(c)
		if d2 > r2 or d2 < m2:
			continue
		var p := _pos[i]
		var steps := _dist[clampi(int((p.y - _origin) * inv), 0, _w - 1) * _w + clampi(int((p.x - _origin) * inv), 0, _w - 1)]
		if steps >= 0:
			found.append(Vector2(steps + randf() * 0.5, i))
	found.sort()
	var out := PackedInt32Array()
	for k in mini(found.size(), count):
		out.append(int(found[k].y))
	return out


## Постоянный номер врага с индексом i (0 — нет такого).
func uid_of(i: int) -> int:
	return _uid[i] if i >= 0 and i < _n else 0


## Всё ещё тот же враг: индекс i жив и под ним враг с номером uid.
func same(i: int, uid: int) -> bool:
	return uid > 0 and i >= 0 and i < _n and _uid[i] == uid


## Позиция жука на земле (центр тела) и его скорость.
func position_of(i: int) -> Vector3:
	var p := _pos[i]
	return Vector3(p.x, _floor_at(p) + 0.35, p.y)


func velocity_of(i: int) -> Vector3:
	return Vector3(_vel[i].x, 0.0, _vel[i].y)


## Убить жуков вдоль отрезка (по земле): ближе width к линии, от начала к концу, не больше max_kills.
func kill_line(a: Vector3, b: Vector3, width: float, max_kills: int, source := "", damage := 1) -> int:
	var a2 := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - a2
	var len2 := maxf(ab.length_squared(), 0.0001)
	var w2 := width * width
	var hits: Array[Vector2] = []
	var b2 := a2 + ab
	for i in _gather(a2.min(b2) - Vector2.ONE * width, a2.max(b2) + Vector2.ONE * width):
		var t := clampf((_pos[i] - a2).dot(ab) / len2, 0.0, 1.0)
		if _pos[i].distance_squared_to(a2 + ab * t) <= w2:
			# По высоте тоже: линия огня с вышки идёт над соседним каналом — те, кто под ней
			# глубоко внизу (за стенкой канала), не задеты
			var line_y := lerpf(a.y, b.y, t)
			if absf(line_y - (_floor_at(_pos[i]) + 0.6 * _size[i])) <= LINE_HEIGHT + 0.4 * _size[i]:
				hits.append(Vector2(t, i))
	return _kill_sorted(hits, max_kills, source, damage)


## Чёрная дыра: жуков в радиусе тянет к центру по спирали (чем ближе, тем быстрее), а дошедших
## до ядра (core, по земле) — забирает без трупов, не больше max_kills за вызов. Возвращает
## места, где они исчезли (чёрная дыра докручивает их внутрь сама).
func pull(center: Vector3, radius: float, speed: float, core: float, dt: float, max_kills: int,
		source := "") -> PackedVector3Array:
	var c := Vector2(center.x, center.z)
	var r2 := radius * radius
	var core2 := core * core
	var inv := 1.0 / CELL
	var gone: Array[Vector2] = []
	for i in _gather(c - Vector2.ONE * radius, c + Vector2.ONE * radius):
		var to := c - _pos[i]
		var d2 := to.length_squared()
		if d2 > r2:
			continue
		# Босса чёрная дыра не сдвинет — слишком тяжёлый
		if _type[i] == BOSS:
			continue
		if d2 <= core2:
			gone.append(Vector2(d2, i))
			continue
		var d := sqrt(d2)
		# Внутрь и чуть вбок — закручивает воронкой
		var dir := (to / d).rotated(0.45)
		var v := dir * speed * (0.35 + 0.65 * (1.0 - d / radius))
		var np := _pos[i] + v * dt
		var nc := clampi(int((np.y - _origin) * inv), 0, _w - 1) * _w + clampi(int((np.x - _origin) * inv), 0, _w - 1)
		if _solid[nc] == 0:
			_pos[i] = np
		_vel[i] = v
		_face[i] = dir
	gone.sort()
	var chosen: Array[int] = []
	for k in mini(gone.size(), max_kills):
		chosen.append(int(gone[k].y))
	chosen.sort()
	chosen.reverse()
	var out := PackedVector3Array()
	for i in chosen:
		out.append(Vector3(_pos[i].x, _floor_at(_pos[i]), _pos[i].y))
		_kill(i, false)
	_credit(source, chosen.size())
	return out


## Снаряд в толпе: в клетке есть жуки и снаряд ниже их спин.
func touches(p: Vector3) -> bool:
	var inv := 1.0 / CELL
	var x := int((p.x - _origin) * inv)
	var z := int((p.z - _origin) * inv)
	if x < 0 or z < 0 or x >= _w or z >= _w:
		return false
	var c := z * _w + x
	return _counts[c] > 0 and p.y < _floor_y[c] + 0.8


## Попадание по первым max_kills из hits: каждому damage прочности (боссу — ×boss_mult); у кого
## не осталось — погиб.
func _kill_sorted(hits: Array[Vector2], max_kills: int, source := "", damage := 1, boss_mult := 1) -> int:
	hits.sort()
	var chosen: Array[int] = []
	for k in mini(hits.size(), max_kills):
		chosen.append(int(hits[k].y))
	# Удаляем с больших индексов: на место убитого встаёт последний, младшие индексы не сдвигаются
	chosen.sort()
	chosen.reverse()
	if not chosen.is_empty():
		var sum := Vector2.ZERO
		for i in chosen:
			sum += _pos[i]
		sum /= chosen.size()
		last_hit = Vector3(sum.x, _floor_at(sum), sum.y)
	var killed := 0
	for i in chosen:
		_hp[i] -= damage * (boss_mult if _type[i] == BOSS else 1)
		if _type[i] == BOSS:
			boss_hp = maxi(_hp[i], 0)
		if _hp[i] <= 0:
			_kill(i)
			killed += 1
	_credit(source, killed)
	return killed


## Записать убийства на счёт того, кто убил (для опыта мастерства).
func _credit(source: String, count: int) -> void:
	if source != "" and count > 0:
		kills_by[source] = int(kills_by.get(source, 0)) + count


func _kill(i: int, leave_corpse := true) -> void:
	var p := _pos[i]
	bounty += int(TYPES[_type[i]]["bounty"])
	if _type[i] == BOSS:
		boss_alive = false
		boss_hp = 0
		_boss_i = -1
		if _boss_mini:
			minis_killed += 1
		else:
			bosses_killed += 1
		if _boss_view:
			# Своя модель падает сама — без трупика орды
			_boss_view.die()
			_boss_view = null
			leave_corpse = false
	if not leave_corpse:
		kills += 1
		_n -= 1
		_copy(_n, i)
		return
	var y := _floor_at(p)
	var s := _size[i]
	# Трупик на спине: жук — переворот вокруг продольной оси, гоблин — падает навзничь
	var basis := Basis(Vector3.UP, randf() * TAU)
	var lift := 0.42
	if Mobs.rig(monster) == "biped":
		basis *= Basis(Vector3.RIGHT, -PI / 2)
		lift = 0.15
	else:
		basis *= Basis(Vector3.FORWARD, PI)
	_corpses.set_instance_transform(_corpse_next, Transform3D(basis.scaled(Vector3.ONE * s), Vector3(p.x, y + lift * s, p.y)))
	_corpses.set_instance_custom_data(_corpse_next, Color(_phase[i] + _look(i) * 100.0, 0.0, 1.0, Time.get_ticks_msec() / 1000.0))
	_corpse_next = (_corpse_next + 1) % MAX_CORPSES
	_corpses.visible_instance_count = mini(_corpses.visible_instance_count + 1, MAX_CORPSES)
	# Брызги под ним
	var splat := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.7, 1.5))
	_splats.set_instance_transform(_splat_next, Transform3D(splat, Vector3(p.x + randf_range(-0.3, 0.3), y + 0.13, p.y + randf_range(-0.3, 0.3))))
	_splats.set_instance_color(_splat_next, Color(1, 1, 1).darkened(randf_range(0.0, 0.25)))
	_splat_next = (_splat_next + 1) % MAX_SPLATS
	_splats.visible_instance_count = mini(_splats.visible_instance_count + 1, MAX_SPLATS)
	kills += 1
	_n -= 1
	_copy(_n, i)


func _floor_at(p: Vector2) -> float:
	var inv := 1.0 / CELL
	return _floor_y[clampi(int((p.y - _origin) * inv), 0, _w - 1) * _w + clampi(int((p.x - _origin) * inv), 0, _w - 1)]


## Брызги: неровное пятно жёлто-зелёной слизи, лежит на земле.
func _splat_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var rim := []
	for k in 9:
		var a := TAU * k / 9.0
		rim.append(Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 0.95))
	var center := Color("c8d43c")
	var edge := Color("7a8a22")
	for k in 9:
		st.set_color(center)
		st.add_vertex(Vector3.ZERO)
		st.set_color(edge)
		st.add_vertex(rim[(k + 1) % 9])
		st.add_vertex(rim[k])
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.3
	mesh.surface_set_material(0, m)
	return mesh


func count() -> int:
	return _n


## Поставить в очередь волну: amount жуков выйдет из пещер со скоростью rate в секунду.
func send_wave(amount: int, rate: float) -> void:
	pending += amount
	spawn_rate = rate


## Последних отставших — убрать без награды и урона воротам (если волна встала: кто-то застрял).
func clear_stragglers() -> void:
	_n = 0
	boss_alive = false
	boss_hp = 0
	_drop_boss_view()


## Убрать всех жуков и очередь (новая игра).
func clear() -> void:
	_n = 0
	pending = 0
	reached = 0
	kills = 0
	kills_by.clear()
	gate_damage = 0
	bounty = 0
	minis_killed = 0
	bosses_killed = 0
	boss_alive = false
	_drop_boss_view()
	_corpses.visible_instance_count = 0
	_splats.visible_instance_count = 0


func _process(delta: float) -> void:
	_tick_acc += minf(delta, 0.1)
	var steps := 0
	while _tick_acc >= TICK and steps < 3:
		_tick_acc -= TICK
		steps += 1
		_tick(TICK)
	if steps == 3:
		# После долгой паузы не догоняем
		_tick_acc = 0.0
	if steps > 0:
		_write_buffer()
	# Между шагами шейдер сдвигает каждого по скорости на время от последнего шага
	_mat.set_shader_parameter("lag", _tick_acc)


func _tick(dt: float) -> void:
	if pending > 0:
		_spawn_acc += spawn_rate * dt
		while _spawn_acc >= 1.0 and pending > 0:
			_spawn_acc -= 1.0
			pending -= 1
			_spawn()
	else:
		_spawn_acc = 0.0
	_step(dt)
	_hurt_spikes(dt)


func _spawn() -> void:
	if _n >= MAX_UNITS:
		return
	var i := _n
	_n += 1
	var s: Vector2 = _spawns[_pick_spawn()]
	# Разброс у выхода из пещеры — только на проходимую землю (иначе застрянет в стенке)
	_pos[i] = s
	for k in 4:
		var p := s + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
		var c := clampi(int((p.y - _origin) / CELL), 0, _w - 1) * _w + clampi(int((p.x - _origin) / CELL), 0, _w - 1)
		if _dist[c] > 0:
			_pos[i] = p
			break
	_vel[i] = Vector2.ZERO
	_face[i] = Vector2(0, 1)
	# Вид — по составу волны
	var roll := randf()
	var t := 0
	if roll < mix[1]:
		t = 1
	elif roll < mix[1] + mix[2]:
		t = 2
	_type[i] = t
	_hp[i] = brute_hp if t == 2 else int(TYPES[t]["hp"])
	_uid[i] = _next_uid
	_next_uid += 1
	_chill[i] = 0.0
	if t == 0:
		var r := randf()
		_hp[i] = 3 if r < heavy_share else (2 if r < armor_share else 1)
	_speed[i] = SPEED * speed_scale * float(TYPES[t]["speed"]) * randf_range(0.8, 1.2)
	_phase[i] = randf() * TAU
	_size[i] = float(TYPES[t]["size"]) * randf_range(0.96, 1.04)


## Пещера для нового врага: по весам spawn_weights или любая.
func _pick_spawn() -> int:
	if spawn_weights.size() != _spawns.size():
		return randi() % _spawns.size()
	var total := 0.0
	for w in spawn_weights:
		total += w
	var r := randf() * total
	for k in spawn_weights.size():
		r -= spawn_weights[k]
		if r <= 0.0:
			return k
	return _spawns.size() - 1


## Сколько пещер (выходов из лагерей).
func spawn_count() -> int:
	return _spawns.size()


## Индекс босса в орде (−1 — нет) и сдвиг между шагами расчёта — для его модели (boss_view.gd).
func boss_index() -> int:
	return _boss_i


func lag() -> float:
	return _tick_acc


func _drop_boss_view() -> void:
	_boss_i = -1
	if _boss_view:
		_boss_view.queue_free()
		_boss_view = null


## Выпустить босса (mini — вожака: поменьше и быстрее) из случайной пещеры — в своей модели, если
## она есть у локации.
func spawn_boss(hp: int, size := 3.4, mini := false) -> void:
	# Орда упёрлась в предел — босс встаёт на место последнего рядового (босса терять нельзя)
	if _n >= MAX_UNITS:
		_n -= 1
	var i := _n
	_n += 1
	_pos[i] = _spawns[randi() % _spawns.size()]
	_vel[i] = Vector2.ZERO
	_face[i] = Vector2(0, 1)
	_type[i] = BOSS
	_hp[i] = hp
	_uid[i] = _next_uid
	_next_uid += 1
	_chill[i] = 0.0
	# Вожак на волке — быстрее орды, главный босс — тяжёлый и медленный
	_speed[i] = SPEED * speed_scale * (MINI_SPEED if mini else float(TYPES[BOSS]["speed"]))
	_phase[i] = randf() * TAU
	_size[i] = size
	boss_alive = true
	boss_hp = hp
	boss_max = hp
	_boss_i = i
	_boss_mini = mini
	var model := mini_scene if mini else boss_scene
	if model:
		_drop_boss_view()
		_boss_i = i
		_boss_view = BossView.new()
		_boss_view.horde = self
		_boss_view.scene = model
		_boss_view.size = size
		add_child(_boss_view)


func _step(dt: float) -> void:
	_counts.fill(0)
	_cell_head.fill(-1)
	var w := _w
	var inv := 1.0 / CELL
	for k in _n:
		var p := _pos[k]
		var cell := clampi(int((p.y - _origin) * inv), 0, w - 1) * w + clampi(int((p.x - _origin) * inv), 0, w - 1)
		_counts[cell] += 1
		_next[k] = _cell_head[cell]
		_cell_head[cell] = k
	var blend := minf(dt * 5.0, 1.0)
	# Только читаемые массивы — в локальные переменные (быстрее, чем через self каждый раз)
	var counts := _counts
	var solid := _solid
	var dist := _dist
	var flow := _flow
	var cell_slow := _slow
	var origin := _origin
	var i := 0
	while i < _n:
		var p := _pos[i]
		var cx := clampi(int((p.x - origin) * inv), 1, w - 2)
		var cz := clampi(int((p.y - origin) * inv), 1, w - 2)
		var c := cz * w + cx
		if dist[c] == 0:
			# Дошёл до ворот — бьёт по ним и убирается (на его место встаёт последний)
			reached += 1
			gate_damage += int(TYPES[_type[i]]["gate"])
			if _type[i] == BOSS:
				boss_alive = false
				boss_hp = 0
				boss_escaped += 1
				_boss_i = -1
				if _boss_view:
					_boss_view.break_through()
					_boss_view = null
			_n -= 1
			_copy(_n, i)
			continue
		var crowd := counts[c]
		# Толкаются от тесноты: стенка «давит», как WALL_DENSITY жуков
		var gx := counts[c + 1] - counts[c - 1] + (solid[c + 1] - solid[c - 1]) * WALL_DENSITY
		var gz := counts[c + w] - counts[c - w] + (solid[c + w] - solid[c - w]) * WALL_DENSITY
		# В толпе тормозят — образуется плотная очередь, а не каша
		var slow := clampf(1.5 - crowd * 0.1, 0.35, 1.0) * cell_slow[c]
		if _chill[i] > 0.0:
			_chill[i] -= dt
			slow *= _chill_mult[i]
		var desired := flow[c] * _speed[i] * slow - Vector2(gx, gz) * PUSH
		var v := _vel[i].lerp(desired, blend)
		var np := p + v * dt
		var nc := clampi(int((np.y - origin) * inv), 0, w - 1) * w + clampi(int((np.x - origin) * inv), 0, w - 1)
		if solid[nc] == 1 and solid[c] == 0:
			# Упёрся в стенку — скользит вдоль неё по одной оси (сначала по той, куда движется
			# быстрее); в глухом углу стоит. Из стенки же — наоборот, выбирается
			var sx := cz * w + clampi(int((np.x - origin) * inv), 0, w - 1)
			var sz := clampi(int((np.y - origin) * inv), 0, w - 1) * w + cx
			var x_first := absf(v.x) >= absf(v.y)
			if solid[sx] == 0 and (x_first or solid[sz] == 1):
				np = Vector2(np.x, p.y)
				v.y *= 0.3
			elif solid[sz] == 0:
				np = Vector2(p.x, np.y)
				v.x *= 0.3
			else:
				np = p
				v *= 0.3
		_pos[i] = np
		_vel[i] = v
		var sp := v.length()
		if sp > 0.3:
			_face[i] = _face[i].lerp(v / sp, blend).normalized()
		i += 1


## Как выглядит враг i для шейдера: его вид, а обычный в доспехах (держит ещё попадание) — 4,
## стальной. После первого попадания доспех слетает — снова обычный.
func _look(i: int) -> int:
	return ARMORED if _type[i] == 0 and _hp[i] >= 2 else _type[i]


func _copy(from: int, to: int) -> void:
	if from == _boss_i:
		_boss_i = to
	_pos[to] = _pos[from]
	_vel[to] = _vel[from]
	_face[to] = _face[from]
	_speed[to] = _speed[from]
	_phase[to] = _phase[from]
	_size[to] = _size[from]
	_type[to] = _type[from]
	_hp[to] = _hp[from]
	_uid[to] = _uid[from]
	_chill[to] = _chill[from]
	_chill_mult[to] = _chill_mult[from]


## Буфер MultiMesh: на каждого жука 12 чисел (базис по строкам + позиция) и 4 своих (фаза,
## скорость, сдвиг по земле). Ближние к камере — в слой подробной модели, дальние — в упрощённый.
func _write_buffer() -> void:
	var buf := _buffer
	var w := _w
	var inv := 1.0 / CELL
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var near2 := NEAR_DISTANCE * NEAR_DISTANCE if cam else INF
	var far_base := MAX_UNITS * STRIDE
	var nn := 0
	var nf := 0
	var skip := _boss_i if _boss_view else -1
	for i in _n:
		if i == skip:
			continue
		var p := _pos[i]
		var f := _face[i] * _size[i]
		var s := _size[i]
		var y := _floor_y[clampi(int((p.y - _origin) * inv), 0, w - 1) * w + clampi(int((p.x - _origin) * inv), 0, w - 1)]
		var dx := p.x - eye.x
		var dy := y - eye.y
		var dz := p.y - eye.z
		var o := 0
		if dx * dx + dy * dy + dz * dz < near2:
			o = nn * STRIDE
			nn += 1
		else:
			o = far_base + nf * STRIDE
			nf += 1
		# Локальная +Z смотрит по направлению f, X — вправо от неё
		buf[o] = f.y
		buf[o + 1] = 0.0
		buf[o + 2] = f.x
		buf[o + 3] = p.x
		buf[o + 4] = 0.0
		buf[o + 5] = s
		buf[o + 6] = 0.0
		buf[o + 7] = y
		buf[o + 8] = -f.x
		buf[o + 9] = 0.0
		buf[o + 10] = f.y
		buf[o + 11] = p.y
		# Вид врага — в сотнях фазы: шейдер красит бегунов, громил, босса и доспехи по-своему
		buf[o + 12] = _phase[i] + _look(i) * 100.0
		buf[o + 13] = minf(_vel[i].length() / SPEED, 1.7)
		buf[o + 14] = _vel[i].x
		buf[o + 15] = _vel[i].y
	_mm.buffer = buf.slice(0, far_base)
	_mm.visible_instance_count = nn
	_mm_far.buffer = buf.slice(far_base)
	_mm_far.visible_instance_count = nf


# --- мороз ---------------------------------------------------------------------------------

## Заморозить всех в радиусе от точки на time секунд: идут в mult раз медленнее (босс — слабее).
## Возвращает, скольких задело.
func chill(center: Vector3, radius: float, mult: float, time: float) -> int:
	var c := Vector2(center.x, center.z)
	var r2 := radius * radius
	var n := 0
	for i in _gather(c - Vector2.ONE * radius, c + Vector2.ONE * radius):
		if _pos[i].distance_squared_to(c) <= r2:
			_chill[i] = maxf(_chill[i], time)
			_chill_mult[i] = lerpf(mult, 1.0, CHILL_BOSS) if _type[i] == BOSS else mult
			n += 1
	return n


# --- ловушки --------------------------------------------------------------------------------

## Можно ли поставить ловушку в точке: дно канала, по которому идёт орда, не у самых ворот.
func trap_ok(p: Vector2) -> bool:
	var c := _cell_of(p)
	return _solid[c] == 0 and _dist[c] > 6


## Поставить ловушку (kind — "spikes" или "tar"); power — сила шипов или множитель скорости
## в смоле. Возвращает номер — по нему убирать.
func add_trap(kind: String, center: Vector2, radius: float, power: float) -> int:
	_trap_id += 1
	# Баррикада: power — её прочность (hp), max_hp — для полоски и вида трещин
	_traps.append({"id": _trap_id, "kind": kind, "center": center, "radius": radius, "power": power, "acc": 0.0,
		"hp": power, "max_hp": power})
	_rebuild_slow()
	return _trap_id


func remove_trap(id: int) -> void:
	for k in _traps.size():
		if _traps[k]["id"] == id:
			_traps.remove_at(k)
			break
	_rebuild_slow()


## Сила ловушек поменялась (докупили в древе посреди боя).
func set_trap_power(kind: String, power: float) -> void:
	for trap in _traps:
		if trap["kind"] == kind:
			trap["power"] = power
	_rebuild_slow()


func _rebuild_slow() -> void:
	_slow.fill(1.0)
	for trap in _traps:
		if trap["kind"] != "tar" and trap["kind"] != "barricade":
			continue
		# Баррикада — почти стена: толпа упирается и стоит, пока не сломает
		var slow: float = BARRICADE_SLOW if trap["kind"] == "barricade" else trap["power"]
		var c: Vector2 = trap["center"]
		var r: float = trap["radius"]
		var lo := _cell_xz(c - Vector2.ONE * r)
		var hi := _cell_xz(c + Vector2.ONE * r)
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if _cell_center(x, z).distance_to(c) <= r:
					_slow[z * _w + x] = minf(_slow[z * _w + x], slow)


## Шипы: каждое поле ранит случайных из тех, кто сейчас на нём (клетки разложены в _step).
func _hurt_spikes(dt: float) -> void:
	_hurt_barricades(dt)
	for trap in _traps:
		if trap["kind"] != "spikes":
			continue
		trap["acc"] = minf(trap["acc"] + SPIKE_HITS * trap["power"] * dt, 3.0)
		var n := int(trap["acc"])
		if n <= 0:
			continue
		var c: Vector2 = trap["center"]
		var r2: float = trap["radius"] * trap["radius"]
		var hits: Array[Vector2] = []
		for i in _gather(c - Vector2.ONE * trap["radius"], c + Vector2.ONE * trap["radius"]):
			if _pos[i].distance_squared_to(c) <= r2:
				hits.append(Vector2(randf(), i))
		if hits.is_empty():
			continue
		trap["acc"] -= n
		_kill_sorted(hits, n, "spikes")


## Баррикады: каждый, кто в неё упёрся, ломает её понемногу; сломали — убрать и сообщить
## (turrets.gd убирает модель).
func _hurt_barricades(dt: float) -> void:
	var k := 0
	while k < _traps.size():
		var trap: Dictionary = _traps[k]
		if trap["kind"] != "barricade":
			k += 1
			continue
		var c: Vector2 = trap["center"]
		var r: float = trap["radius"] + 0.8
		var n := 0
		for i in _gather(c - Vector2.ONE * r, c + Vector2.ONE * r):
			if _pos[i].distance_squared_to(c) <= r * r:
				n += 1
		trap["hp"] = float(trap["hp"]) - minf(n, BARRICADE_CROWD) * BARRICADE_DPS * dt
		if trap["hp"] <= 0.0:
			var id: int = trap["id"]
			_traps.remove_at(k)
			_rebuild_slow()
			trap_broken.emit(id)
			continue
		k += 1


## Сколько прочности осталось у ловушки id (0..1; 1 — у не-баррикад).
func trap_health(id: int) -> float:
	for trap in _traps:
		if trap["id"] == id:
			return clampf(float(trap["hp"]) / maxf(float(trap["max_hp"]), 1.0), 0.0, 1.0) if trap["kind"] == "barricade" else 1.0
	return 0.0


func _cell_xz(p: Vector2) -> Vector2i:
	var inv := 1.0 / CELL
	return Vector2i(clampi(int((p.x - _origin) * inv), 0, _w - 1), clampi(int((p.y - _origin) * inv), 0, _w - 1))


func _cell_of(p: Vector2) -> int:
	var c := _cell_xz(p)
	return c.y * _w + c.x


# --- путь к воротам -------------------------------------------------------------------------

## Поиск в ширину от клеток у ворот: в каждой клетке — число шагов до ворот;
## направление — вниз по этому числу (сглаженное по восьми соседям).
func _build_flow() -> void:
	_dist.fill(-1)
	var queue := PackedInt32Array()
	for z in _w:
		for x in _w:
			var c := z * _w + x
			var p := _cell_center(x, z)
			if _solid[c] == 0 and p.y > MapBuilder.GATE_Z - 3.0 and p.y < MapBuilder.GATE_Z - 1.6:
				_dist[c] = 0
				queue.append(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var x := c % _w
		var z := c / _w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var nz := z + d.y
			if nx < 0 or nz < 0 or nx >= _w or nz >= _w:
				continue
			var n := nz * _w + nx
			if _solid[n] == 0 and _dist[n] == -1:
				_dist[n] = _dist[c] + 1
				queue.append(n)
	for z in range(1, _w - 1):
		for x in range(1, _w - 1):
			var c := z * _w + x
			if _dist[c] <= 0:
				_flow[c] = Vector2.ZERO
				continue
			var g := Vector2.ZERO
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var n := (z + dz) * _w + x + dx
					if (dx != 0 or dz != 0) and _dist[n] >= 0:
						g += Vector2(dx, dz).normalized() * float(_dist[c] - _dist[n])
			_flow[c] = g.normalized() if g.length_squared() > 0.0001 else Vector2.ZERO
	# Клетки, откуда до ворот пути нет (в стенке, в закутке): направление — к ближайшей клетке с
	# путём, чтобы застрявший выбрался обратно на тропу, а не стоял там вечно
	var rescue := PackedInt32Array()
	for c in _dist.size():
		if _dist[c] >= 0:
			rescue.append(c)
	var seen := PackedByteArray()
	seen.resize(_dist.size())
	for c in rescue:
		seen[c] = 1
	head = 0
	while head < rescue.size():
		var c := rescue[head]
		head += 1
		var x := c % _w
		var z := c / _w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var nz := z + d.y
			if nx < 0 or nz < 0 or nx >= _w or nz >= _w:
				continue
			var n := nz * _w + nx
			if seen[n] == 0:
				seen[n] = 1
				_flow[n] = Vector2(-d.x, -d.y)
				rescue.append(n)


func _cell_center(x: int, z: int) -> Vector2:
	return Vector2(_origin + (x + 0.5) * CELL, _origin + (z + 0.5) * CELL)
