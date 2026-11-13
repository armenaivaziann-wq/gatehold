extends Node3D
## Стройка в бою. B — режим строительства: слева список турелей и баррикад (1–6 или колесо —
## выбрать). Турели ставятся только на плато у каналов (на стену и башни крепости — нельзя),
## баррикады — на дно каналов. Ставить бесплатно, но из запаса на бой: сколько чего —
## задаёт общее древо («Запас турелей», «Ловушки» — upgrades.gd). Монеты за убитых — на ступени
## турелей (I → II → III, ЛКМ по стоящей) и на турели сверх запаса: каждая следующая того же
## вида дороже (EXTRA_BASE, EXTRA_STEP) — это на крайний случай, основное — запас и ступени. ПКМ — убрать: турель или ловушка вернётся в запас, вложенные монеты —
## все между волнами, половина в бою. Под прицелом — «призрак» того, что
## встанет: зелёный — можно, красный — нельзя (почему — в строке над карточками), и круг
## дальности турели.

const FxBudget := preload("res://core/fx_budget.gd")

signal build_mode_changed(on: bool)

const MapBuilder := preload("res://locations/map_builder.gd")
const TurretScript := preload("res://turrets/turret.gd")
const TurretModels := preload("res://turrets/turret_models.gd")
const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")

## Ловушки: радиус поля, м; что делают.
const TRAPS := {
	"spikes": {"name": "Шипы", "radius": 2.6, "desc": "ранят идущих по ним"},
	"tar": {"name": "Смола", "radius": 3.2, "desc": "враги в ней вязнут"},
	"barricade": {"name": "Баррикада", "radius": 4.6, "desc": "держит толпу, пока не сломают"},
}
const TRAP_ORDER := ["spikes", "tar"]
const EXTRA_BASE := 1.5           # турель сверх запаса: первая — полторы цены вида,
const EXTRA_STEP := 1.0           # каждая следующая того же вида — ещё на цену дороже
const MIN_GAP := 3.3              # м между турелями
const BUILD_REACH := 26.0         # м от пути орды: дальше турель не достанет никого
const PLATEAU_EDGE := MapBuilder.WALL + 1.0  # турель — на ровном плато, не на откосе канала
const CAVE_CLEAR := 10.0          # м от выхода из лагеря: там ловушку не поставить
const PANEL := Color(0.15, 0.14, 0.14, 0.9)
const PANEL_EDGE := Color(0.34, 0.31, 0.29, 0.95)
const GOLD := Color(0.98, 0.74, 0.22)
const FREE := Color(0.55, 0.85, 1.0)
const PICKED := Color(1.0, 0.8, 0.3)
const GHOST_OK := Color(0.45, 1.0, 0.55)
const GHOST_BAD := Color(1.0, 0.32, 0.28)
const BAD := Color(1, 0.4, 0.3)
const TIERS := ["I", "II", "III"]
## Турель на плато стоит на деревянной сторожевой вышке с красным знаменем.
## Постамент под турелью на плато: низкий каменный, чтобы турель не казалась крепостью.
const TOWER_H := 0.55
static var _tower: ArrayMesh
const CHIP_GROUND := "B — стройка · U — прокачка"
const CHIP_AIR := CHIP_GROUND

var horde: Node3D
var waves: Node
var camera: Camera3D
var building := false
## Какие турели можно ставить (открытые наградой за локации, в порядке TurretScript.ORDER).
var kinds: Array[String] = []
## Карточки стройки: турели, потом ловушки.
var items: Array[String] = []
## Что ставить: индекс в items.
var choice := 0

var _map: Node3D
var _route: Array[Vector2] = []
## Турели: четыре постоянные площадки (fixed — башни и стена, есть и пустые) и поставленные на
## плато (появляются и исчезают вместе с турелью). {pos, turret, fixed, ring, pillar}
var _slots: Array[Dictionary] = []
var _traps: Array[Dictionary] = []    # {kind, pos, id, node}
var _hover := -1                      # площадка или турель под прицелом
var _hover_trap := -1
var _ghost: Node3D
var _ghost_kind := ""
var _ghost_mat: StandardMaterial3D
var _ghost_pos := Vector3.ZERO
var _ghost_why := ""                  # почему здесь нельзя ("" — можно)
var _range: Decal
var _ring_tex: ImageTexture
var _sector_tex: ImageTexture
var _ui: CanvasLayer
var _cards: Array[PanelContainer] = []
var _info: Label
var _chip: Label
var _font: SystemFont


## Постоянные площадки и путь орды (вызвать до добавления в сцену, после horde.setup).
func setup(map: Node3D) -> void:
	_map = map
	_route = horde.route_points()
	# Постоянных площадок на крепости (башни, стена) больше нет — турели только на плато у
	# каналов (просьба пользователя): защищать надо каналы, а не стену


func _distance_to(points: Array[Vector2], p: Vector2) -> float:
	var best := 1e9
	for q in points:
		best = minf(best, q.distance_squared_to(p))
	return sqrt(best)


func _ready() -> void:
	for kind: String in TurretScript.ORDER:
		if Mastery.is_unlocked(kind):
			kinds.append(kind)
	# Ловушки (шипы, смола) из игры убраны; из «ловушек» в стройке — только баррикады
	items.assign(kinds)
	items.append("barricade")
	horde.trap_broken.connect(_on_trap_broken)
	for slot in _slots:
		slot["turret"] = null
		_add_ring(slot)
		# Световой столб над пустой площадкой — видно издалека
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.9
		cyl.bottom_radius = 1.15
		cyl.height = 6.0
		cyl.radial_segments = 12
		cyl.cap_top = false
		cyl.cap_bottom = false
		pillar.mesh = cyl
		pillar.material_override = _pillar_mat(FREE)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.position = slot["pos"] + Vector3(0, 3.0, 0)
		pillar.visible = false
		add_child(pillar)
		slot["pillar"] = pillar
	_ghost_mat = _glow_mat(GHOST_OK, 0.45)
	_range = Decal.new()
	_ring_tex = _ring_texture()
	_sector_tex = _sector_texture()
	_range.texture_albedo = _ring_tex
	_range.cull_mask = MapBuilder.WORLD_LAYER
	_range.visible = false
	add_child(_range)
	_build_ui()


func _add_ring(slot: Dictionary) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.3
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = _glow_mat(FREE, 0.9)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = slot["pos"] + Vector3(0, 0.12, 0)
	ring.scale = Vector3(1, 0.4, 1)
	ring.visible = building
	add_child(ring)
	slot["ring"] = ring


func slot_count() -> int:
	return _slots.size()


func turret_count() -> int:
	var n := 0
	for slot in _slots:
		if slot["turret"]:
			n += 1
	return n


func is_trap(kind: String) -> bool:
	return TRAPS.has(kind)


func display_name(kind: String) -> String:
	return TRAPS[kind]["name"] if is_trap(kind) else TurretScript.TYPES[kind]["name"]


## Сколько турелей или ловушек этого вида дают на бой (древо) и сколько ещё можно поставить.
func stock(kind: String) -> int:
	return Upgrades.trap_stock(kind) if is_trap(kind) else Upgrades.turret_stock(kind)


func stock_left(kind: String) -> int:
	var used := 0
	if is_trap(kind):
		for trap in _traps:
			if trap["kind"] == kind:
				used += 1
	else:
		for slot in _slots:
			if slot["turret"] and slot["turret"].kind == kind:
				used += 1
	return stock(kind) - used


## Включить или выключить режим строительства.
func set_building(on: bool) -> void:
	building = on
	for slot in _slots:
		slot["ring"].visible = on
		if slot["fixed"]:
			slot["pillar"].visible = on and not slot["turret"]
	_ui.get_node("Build").visible = on
	_chip.visible = not on
	_hover = -1
	_hover_trap = -1
	if not on:
		_show_ghost(false)
	build_mode_changed.emit(on)


## Подсказка в углу: на стене или в полёте (sky_platform.gd).
func set_flying_hint(on: bool) -> void:
	_chip.text = CHIP_AIR if on else CHIP_GROUND


func set_ui_visible(on: bool) -> void:
	_ui.visible = on


# --- поставить, улучшить, убрать ------------------------------------------------------------

## Можно ли поставить kind в точку p (на земле): "" — можно, иначе — почему нельзя.
func check(kind: String, p: Vector3) -> String:
	if stock_left(kind) <= 0:
		if is_trap(kind):
			return "«%s» кончились: запас на бой растёт в древе (U)" % display_name(kind)
		if waves.coins < extra_cost(kind):
			return "Запас кончился, ещё один «%s» — %d монет" % [display_name(kind), extra_cost(kind)]
	var q := Vector2(p.x, p.z)
	if absf(q.x) > MapBuilder.HALF - 6.0 or q.y < -MapBuilder.HALF + 6.0:
		return "Это край карты"
	if MapBuilder.in_base(q) or q.y > MapBuilder.GATE_Z - 5.0:
		return "Слишком близко к стене"
	var d: float = _map.channel_dist(q)
	if is_trap(kind):
		if d > -0.6:
			return "Ловушки ставят на дно канала, где идёт орда"
		if not horde.trap_ok(q):
			return "Здесь орда не ходит" if q.y < MapBuilder.GATE_Z - 12.0 else "Слишком близко к воротам"
		for cave in _map.caves():
			if (cave[0] as Vector2).distance_to(q) < CAVE_CLEAR:
				return "Слишком близко к лагерю"
		var r: float = TRAPS[kind]["radius"]
		for trap in _traps:
			if Vector2(trap["pos"].x, trap["pos"].z).distance_to(q) < (r + TRAPS[trap["kind"]]["radius"]) * 0.8:
				return "Тесно: рядом другая ловушка"
		return ""
	if d < 0.0:
		return "В канал — ловушки, турели — на плато"
	if d < PLATEAU_EDGE:
		return "Слишком близко к краю канала"
	if _distance_to(_route, q) > BUILD_REACH:
		return "Далеко от пути орды"
	for slot in _slots:
		if (slot["turret"] or slot["fixed"]) and Vector2(slot["pos"].x, slot["pos"].z).distance_to(q) < MIN_GAP:
			return "Тесно: рядом другая турель"
	if _map.prop_near(q, 1.2):
		return "Мешает камень или дерево"
	return ""


## Поставить турель или ловушку kind в точку p из запаса. Возвращает успех.
func place(kind: String, p: Vector3) -> bool:
	if check(kind, p) != "":
		return false
	var q := Vector2(p.x, p.z)
	var at := Vector3(p.x, _map.height(q), p.z)
	if is_trap(kind):
		var power := Upgrades.spike_power() if kind == "spikes" else Upgrades.tar_slow()
		if kind == "barricade":
			power = Upgrades.barricade_hp()
		var node := _trap_node(kind)
		node.position = Vector3(at.x, _floor_top(q, TRAPS[kind]["radius"]), at.z)
		if kind == "barricade":
			node.rotation.y = _across_flow(q)
		add_child(node)
		_traps.append({"kind": kind, "pos": at, "node": node,
			"id": horde.add_trap(kind, q, TRAPS[kind]["radius"], power)})
		return true
	var slot := {"pos": at, "fixed": false, "turret": null}
	_add_ring(slot)
	_slots.append(slot)
	_put_turret(slot, kind)
	return true


## Цена турели сверх запаса: цена вида, и каждая следующая сверх запаса дороже.
func extra_cost(kind: String) -> int:
	var extra := maxi(-stock_left(kind), 0)
	return int(cost_of(kind) * (EXTRA_BASE + EXTRA_STEP * extra))


## Поставить турель kind на постоянную площадку index (башня, стена) из запаса.
func buy(index: int, kind: String) -> bool:
	var slot: Dictionary = _slots[index]
	if slot["turret"]:
		return false
	if not slot["fixed"]:
		return false
	if stock_left(kind) <= 0 and waves.coins < extra_cost(kind):
		return false
	_put_turret(slot, kind)
	return true


## Поставить турель на площадку: из запаса — даром, сверх него — за extra_cost.
func _put_turret(slot: Dictionary, kind: String) -> void:
	var price := 0
	if stock_left(kind) <= 0:
		price = extra_cost(kind)
		waves.coins -= price
	var t := TurretScript.new()
	t.kind = kind
	t.spent = price
	t.horde = horde
	t.facing = facing_at(slot["pos"], slot["fixed"])
	t.position = slot["pos"]
	if not slot["fixed"]:
		# На плато — на вышку: выше бьёт над толпой и видно издалека
		var tower := MeshInstance3D.new()
		tower.mesh = _tower_mesh()
		tower.position = slot["pos"]
		tower.rotation.y = randf() * TAU
		add_child(tower)
		slot["tower"] = tower
		t.position += Vector3(0, TOWER_H, 0)
	add_child(t)
	slot["turret"] = t
	if slot["fixed"]:
		slot["pillar"].visible = false


## Цена следующей ступени турели index; -1 — пусто или уже высшая ступень.
func upgrade_cost(index: int) -> int:
	var t: Node3D = _slots[index]["turret"]
	if not t or t.tier >= TurretScript.MAX_TIER:
		return -1
	return int(cost_of(t.kind) * TurretScript.TIER_COST[t.tier])


## Улучшить турель index, если хватает монет. Возвращает успех.
func upgrade(index: int) -> bool:
	var cost := upgrade_cost(index)
	if cost < 0 or waves.coins < cost:
		return false
	waves.coins -= cost
	var t: Node3D = _slots[index]["turret"]
	t.spent += cost
	t.upgrade()
	return true


## Сколько монет вернёт уборка турели: между волнами — всё вложенное (покупка сверх запаса и
## ступени), в бою — долю.
func refund(index: int) -> int:
	var t: Node3D = _slots[index]["turret"]
	if not t:
		return 0
	var share := Upgrades.sell_share() if waves.state == waves.State.FIGHT else 1.0
	return int(t.spent * share)


## Убрать турель index: она вернётся в запас, монеты — refund().
func remove(index: int) -> void:
	var slot: Dictionary = _slots[index]
	var t: Node3D = slot["turret"]
	if not t:
		return
	waves.coins += refund(index)
	t.queue_free()
	slot["turret"] = null
	if slot["fixed"]:
		slot["pillar"].visible = building
	else:
		slot["ring"].queue_free()
		if slot.has("tower"):
			slot["tower"].queue_free()
		_slots.remove_at(index)


## Старое имя (тесты): продать — то же, что убрать.
func sell(index: int) -> void:
	remove(index)


func remove_trap(k: int) -> void:
	var trap: Dictionary = _traps[k]
	horde.remove_trap(trap["id"])
	trap["node"].queue_free()
	_traps.remove_at(k)


## Баррикада поперёк канала (локальная ось X — поперёк, враги идут со стороны +Z): частокол из
## заточенных брёвен, наклонённых навстречу толпе, две поперечные жерди и колья-рогатки впереди.
func _barricade_mesh(st: SurfaceTool, r: float) -> void:
	var wood := Color(0.5, 0.33, 0.18)
	var dark := Color(0.32, 0.2, 0.11)
	var tip := Color(0.78, 0.66, 0.48)
	var n := 9
	for k in n:
		var x := lerpf(-r, r, (k + 0.5) / n)
		var h := 1.7 + 0.25 * sin(k * 2.3)
		var lean := Vector3(0, h, 0.55)
		var base := Vector3(x, -0.2, 0)
		_log(st, base, base + lean * 0.86, 0.17, wood if k % 2 == 0 else wood.darkened(0.1))
		_log_tip(st, base + lean * 0.86, base + lean * 1.05, 0.17, tip)
	for y in [0.45, 1.15]:
		_log(st, Vector3(-r - 0.2, y, 0.16 + y * 0.3), Vector3(r + 0.2, y, 0.16 + y * 0.3), 0.1, dark)
	# Рогатки впереди: скрещённые колья
	for k in 4:
		var x := lerpf(-r * 0.8, r * 0.8, k / 3.0)
		var c := Vector3(x, 0.0, 1.5)
		_log(st, c + Vector3(-0.45, 0, -0.3), c + Vector3(0.45, 0.9, 0.5), 0.07, dark)
		_log(st, c + Vector3(0.45, 0, -0.3), c + Vector3(-0.45, 0.9, 0.5), 0.07, dark)


## Бревно-шестигранник от a к b радиуса rad.
func _log(st: SurfaceTool, a: Vector3, b: Vector3, rad: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var d0 := (side * cos(a0) + up * sin(a0)) * rad
		var d1 := (side * cos(a1) + up * sin(a1)) * rad
		var nrm := (d0 + d1).normalized()
		for v in [a + d0, b + d0, b + d1, a + d0, b + d1, a + d1]:
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(v)


## Заточенный конец бревна: конус от a (радиус rad) к острию b.
func _log_tip(st: SurfaceTool, a: Vector3, b: Vector3, rad: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var d0 := (side * cos(a0) + up * sin(a0)) * rad
		var d1 := (side * cos(a1) + up * sin(a1)) * rad
		for v in [a + d0, b, a + d1]:
			st.set_color(col)
			st.set_normal((d0 + d1).normalized())
			st.add_vertex(v)


## Баррикаду сломали: модель разлетается щепками и исчезает.
func _on_trap_broken(id: int) -> void:
	for k in _traps.size():
		if _traps[k]["id"] == id:
			var node: Node3D = _traps[k]["node"]
			_splinters(node.global_position)
			node.queue_free()
			_traps.remove_at(k)
			return


## Поворот баррикады поперёк хода орды в точке q.
func _across_flow(q: Vector2) -> float:
	var f: Vector2 = horde._flow[horde._cell_of(q)]
	if f.length_squared() < 0.001:
		return 0.0
	return atan2(-f.x, -f.y)


## Щепки и пыль, когда баррикада ломается.
func _splinters(at: Vector3) -> void:
	var p := FxBudget.cosmetic(GPUParticles3D.new())
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 40
	p.lifetime = 1.3
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -16, 0)
	pm.angular_velocity_min = -500.0
	pm.angular_velocity_max = 500.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.2, 0.6, 0.4)
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.33, 0.18)
	mesh.material = m
	p.draw_pass_1 = mesh
	add_child(p)
	p.global_position = at + Vector3(0, 0.8, 0)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Докупили «Острые шипы» или «Вязкую смолу» посреди боя — стоящие ловушки сразу сильнее.
func refresh_traps() -> void:
	horde.set_trap_power("spikes", Upgrades.spike_power())
	horde.set_trap_power("tar", Upgrades.tar_slow())


## Первая свободная постоянная площадка (башня, стена), -1 если нет.
func free_slot() -> int:
	for i in _slots.size():
		if _slots[i]["fixed"] and not _slots[i]["turret"]:
			return i
	return -1


## Хорошие места для kind, лучшие — первыми (для бота и подсказок): турели — край плато у
## канала, ближе к воротам; ловушки — на пути орды метрах в 30 от стены.
func suggestions(kind: String, count := 12) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if is_trap(kind):
		var r: float = TRAPS[kind]["radius"]
		var pts: Array[Vector2] = _route.duplicate()
		# Лучше там, где орда уже под огнём турелей, но ещё не у самых ворот: ~30 м от стены
		var best_z := MapBuilder.GATE_Z - 30.0
		pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return absf(a.y - best_z) < absf(b.y - best_z))
		for q in pts:
			var p := Vector3(q.x, 0.0, q.y)
			if check(kind, p) != "":
				continue
			var ok := true
			for o in out:
				if Vector2(o.x, o.z).distance_to(q) < r * 2.4:
					ok = false
					break
			if ok:
				out.append(p)
				if out.size() >= count:
					break
		return out
	for z in range(92, 15, -2):
		for x in range(-100, 101, 2):
			var q := Vector2(x, z)
			var d: float = _map.channel_dist(q)
			if d < PLATEAU_EDGE + 0.6 or d > PLATEAU_EDGE + 2.5:
				continue
			if _distance_to(_route, q) > 14.0:
				continue
			var p := Vector3(q.x, _map.height(q), q.y)
			var ok := true
			for o in out:
				if Vector2(o.x, o.z).distance_to(q) < 9.0:
					ok = false
					break
			if ok and check(kind, p) == "":
				out.append(p)
				if out.size() >= count:
					return out
	return out


# --- прицел и ввод --------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Баррикады проседают и кренятся по мере того, как их ломают
	for trap in _traps:
		if trap["kind"] == "barricade":
			var hp: float = horde.trap_health(trap["id"])
			var node: Node3D = trap["node"]
			if not node.has_meta("y0"):
				node.set_meta("y0", node.position.y)
			node.position.y = float(node.get_meta("y0")) - (1.0 - hp) * 0.7
			node.rotation.x = (1.0 - hp) * -0.35 + (sin(Time.get_ticks_msec() * 0.02) * 0.02 if hp < 0.99 else 0.0)
	if not building:
		return
	var kind: String = items[choice]
	_hover = _aimed_slot(not is_trap(kind))
	_hover_trap = -1
	_ghost_why = ""
	var show := false
	if _hover >= 0 and not _slots[_hover]["turret"]:
		# Пустая площадка на башне или стене: призрак — на неё
		show = true
		_ghost_pos = _slots[_hover]["pos"]
		if stock_left(kind) <= 0 and waves.coins < extra_cost(kind):
			_ghost_why = "Запас кончился, ещё один «%s» — %d монет" % [display_name(kind), extra_cost(kind)]
	elif _hover < 0:
		var hit: Variant = _ground_hit()
		if hit != null:
			var p: Vector3 = hit
			_hover_trap = _trap_at(p)
			if _hover_trap < 0:
				show = true
				_ghost_pos = p
				_ghost_why = check(kind, p)
	_show_ghost(show)
	if show and kind == "barricade" and _ghost:
		_ghost.rotation.y = _across_flow(Vector2(_ghost_pos.x, _ghost_pos.z))
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var col := PICKED if i == _hover else FREE
		if slot["turret"] and i != _hover:
			col = Color(1, 1, 1, 0.6)
		(slot["ring"].material_override as StandardMaterial3D).albedo_color = col
		slot["ring"].scale = Vector3(1, 0.4, 1) * (1.3 if i == _hover else 1.0)
		if slot["fixed"]:
			(slot["pillar"].material_override as StandardMaterial3D).albedo_color = Color(col, 0.35 if i == _hover else 0.08)
	for k in _traps.size():
		_traps[k]["node"].scale = Vector3.ONE * (1.08 if k == _hover_trap else 1.0)
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not building:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 \
			and event.keycode <= KEY_9 and event.keycode - KEY_1 < items.size():
		choice = event.keycode - KEY_1
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			choice = posmod(choice + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), items.size())
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if _hover >= 0 and _slots[_hover]["turret"]:
					upgrade(_hover)
				elif _hover >= 0:
					buy(_hover, items[choice])
				elif _ghost and _ghost.visible and _ghost_why == "":
					place(items[choice], _ghost_pos)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if _hover >= 0:
					remove(_hover)
				elif _hover_trap >= 0:
					remove_trap(_hover_trap)
				get_viewport().set_input_as_handled()


## Турель или пустая площадка под прицелом — ближайшая к лучу взгляда (с допуском по
## расстоянию; пустые площадки — только если ставим турель).
func _aimed_slot(empty_too: bool) -> int:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var best := -1
	var best_d := 1e9
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		if not slot["turret"] and not empty_too:
			continue
		var top: Vector3 = slot["turret"].position if slot["turret"] else slot["pos"]
		var to: Vector3 = top + Vector3(0, 0.9, 0) - from
		var along := to.dot(dir)
		if along <= 0.5:
			continue
		var miss := (to - dir * along).length()
		# Постоянные площадки стоят особняком — допуск шире; на плато турели бывают тесно
		var tol := maxf(2.2, along * 0.06) if slot["fixed"] else clampf(along * 0.035, 1.5, 2.6)
		if miss < tol and miss < best_d:
			best_d = miss
			best = i
	return best


## Точка на земле, куда смотрит прицел (null — в небо). Шагаем по лучу до рельефа, потом
## уточняем делением пополам.
func _ground_hit() -> Variant:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	if dir.y > -0.005:
		return null
	var prev := 0.0
	var t := 0.5
	while t < 170.0:
		var p := from + dir * t
		if p.y <= _map.height(Vector2(p.x, p.z)):
			var lo := prev
			var hi := t
			for k in 7:
				var mid := (lo + hi) * 0.5
				var m := from + dir * mid
				if m.y <= _map.height(Vector2(m.x, m.z)):
					hi = mid
				else:
					lo = mid
			var h := from + dir * hi
			return Vector3(h.x, _map.height(Vector2(h.x, h.z)), h.z)
		prev = t
		t += 0.6 + t * 0.012
	return null


## Высота, на которую класть ловушку: чуть выше самого высокого бугорка дна под ней — иначе
## земля проступает сквозь лужу.
func _floor_top(c: Vector2, r: float) -> float:
	var top: float = _map.height(c)
	for k in 12:
		var a := k * TAU / 12.0
		for f in [0.5, 0.95]:
			var q: Vector2 = c + Vector2(cos(a), sin(a)) * r * f
			# Только дно: край лужи, что заходит на откос, просто прячется в нём
			if _map.channel_dist(q) < -0.3:
				top = maxf(top, _map.height(q))
	return top + 0.03


func _trap_at(p: Vector3) -> int:
	for k in _traps.size():
		var c: Vector3 = _traps[k]["pos"]
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < TRAPS[_traps[k]["kind"]]["radius"]:
			return k
	return -1


## Призрак выбранного под прицелом: модель турели или ловушки, зелёная или красная, и круг
## дальности на земле.
func _show_ghost(on: bool) -> void:
	if not on:
		if _ghost:
			_ghost.visible = false
		_range.visible = false
		return
	var kind: String = items[choice]
	if kind != _ghost_kind:
		if _ghost:
			_ghost.queue_free()
		_ghost_kind = kind
		if is_trap(kind):
			_ghost = _trap_node(kind)
		else:
			# Призрак турели — вместе с вышкой (на стене и башнях вышка прячется)
			_ghost = Node3D.new()
			var model: Node3D = TurretModels.scene(kind).instantiate()
			model.name = "Model"
			model.scale = Vector3.ONE * TurretScript.MODEL_SCALE
			_ghost.add_child(model)
			var tower := MeshInstance3D.new()
			tower.name = "Tower"
			tower.mesh = _tower_mesh()
			_ghost.add_child(tower)
		add_child(_ghost)
		for mi: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = _ghost_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _ghost is MeshInstance3D:
			(_ghost as MeshInstance3D).material_override = _ghost_mat
			(_ghost as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = true
	_ghost.position = _ghost_pos
	if not is_trap(kind):
		var on_wall: bool = _hover >= 0 and _slots[_hover]["fixed"]
		_ghost.get_node("Tower").visible = not on_wall
		_ghost.get_node("Model").position.y = 0.0 if on_wall else TOWER_H
		_ghost.get_node("Model/Head").rotation.y = facing_at(_ghost_pos, on_wall)
	if is_trap(kind):
		_ghost.position.y = _floor_top(Vector2(_ghost_pos.x, _ghost_pos.z), TRAPS[kind]["radius"])
	var col := GHOST_OK if _ghost_why == "" else GHOST_BAD
	_ghost_mat.albedo_color = Color(col, 0.45)
	var r: float = TRAPS[kind]["radius"] if is_trap(kind) else \
		TurretScript.TYPES[kind]["range"] * Upgrades.turret_range(kind)
	_range.visible = true
	_range.position = _ghost_pos
	_range.size = Vector3(r * 2.0, 24.0, r * 2.0)
	_range.modulate = Color(col, 0.9)
	# Турель бьёт только в своём секторе — его и показываем (ловушки — кругом)
	_range.texture_albedo = _ring_tex if is_trap(kind) else _sector_tex
	_range.rotation.y = 0.0 if is_trap(kind) else facing_at(_ghost_pos, _hover >= 0 and _slots[_hover]["fixed"])


## Куда развернуть турель в точке p: к ближайшему месту на пути орды впереди неё (откуда идут
## враги, а не к воротам за спиной); на стене и башнях — вперёд, к пещерам.
func facing_at(p: Vector3, fixed: bool) -> float:
	if fixed:
		return 0.0
	var q := Vector2(p.x, p.z)
	var best := q + Vector2(0, -1)
	var best_d := 1e9
	for r in _route:
		# Только то, что впереди (дальше от ворот, чем турель), и не вплотную
		if r.y > q.y - 3.0:
			continue
		var d := r.distance_squared_to(q)
		if d < best_d and d > 4.0:
			best_d = d
			best = r
	var dir := best - q
	return atan2(-dir.x, -dir.y)


# --- постамент под турелью ---------------------------------------------------------------------

## Невысокий каменный постамент: широкий шестигранный цоколь, над ним площадка поуже с тёмным
## железным ободом. Общий меш на все постаменты.
func _tower_mesh() -> ArrayMesh:
	if _tower:
		return _tower
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.52, 0.5, 0.46)
	var stone_top := Color(0.6, 0.58, 0.54)
	var iron := Color(0.24, 0.22, 0.22)
	_hex(st, -0.3, 0.28, 1.2, 1.08, stone)
	_hex(st, 0.28, 0.46, 0.98, 0.94, stone_top)
	_hex(st, 0.46, TOWER_H, 0.96, 0.96, iron)
	_tower = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	_tower.surface_set_material(0, mat)
	return _tower


## Шестигранная призма от y0 (радиус r0) до y1 (r1) с крышкой; грани плоские.
func _hex(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, col: Color) -> void:
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := ((d0 + d1) * 0.5).normalized()
		n.y = (r0 - r1) / maxf(y1 - y0, 0.01) * 0.5
		n = n.normalized()
		var shade := col.darkened(0.06 * (k % 2))
		for v in [d0 * r0 + Vector3(0, y0, 0), d1 * r0 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y1, 0),
				d0 * r0 + Vector3(0, y0, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0)]:
			st.set_color(shade)
			st.set_normal(n)
			st.add_vertex(v)
		for v in [Vector3(0, y1, 0), d1 * r1 + Vector3(0, y1, 0), d0 * r1 + Vector3(0, y1, 0)]:
			st.set_color(col.lightened(0.06))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


## Брус из a в b: сечение w × (d или w).
func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color, d := -1.0) -> void:
	if d < 0.0:
		d = w
	var x := (b - a).normalized()
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var z := x.cross(up).normalized() * w * 0.5
	var y := z.cross(x).normalized() * d * 0.5
	var v := [a - y - z, a + y - z, a + y + z, a - y + z, b - y - z, b + y - z, b + y + z, b - y + z]
	for q in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [0, 3, 2, 1], [4, 5, 6, 7]]:
		var n: Vector3 = ((v[q[1]] - v[q[0]]).cross(v[q[2]] - v[q[0]])).normalized()
		var shade := col.darkened(0.2 if n.y < -0.3 else (0.08 if absf(n.y) < 0.3 else 0.0))
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(shade)
			st.set_normal(n)
			st.add_vertex(v[q[i]])


# --- ловушки: модели ------------------------------------------------------------------------

## Модель ловушки: шипы — частокол железных пик на досках, смола — чёрная лужа с пузырями.
func _trap_node(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _trap_mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _trap_mesh(kind: String) -> ArrayMesh:
	var r: float = TRAPS[kind]["radius"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if kind == "spikes" else 11
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "spikes":
		# Дощатый настил-восьмиугольник, по краю — тёмная обвязка
		var segs := 8
		for k in segs:
			var a0 := k * TAU / segs + PI / 8.0
			var a1 := (k + 1) * TAU / segs + PI / 8.0
			var o0 := Vector3(cos(a0), 0, sin(a0)) * r
			var o1 := Vector3(cos(a1), 0, sin(a1)) * r
			st.set_normal(Vector3.UP)
			st.set_color(Color(0.55, 0.38, 0.22) if k % 2 == 0 else Color(0.5, 0.34, 0.2))
			st.add_vertex(Vector3(0, 0.12, 0))
			st.add_vertex(o1 * 0.9 + Vector3(0, 0.12, 0))
			st.add_vertex(o0 * 0.9 + Vector3(0, 0.12, 0))
			# Обвязка: скос от настила к земле
			st.set_color(Color(0.32, 0.22, 0.14))
			st.set_normal(((o0 + o1).normalized() + Vector3.UP).normalized())
			for v in [o0 * 0.9 + Vector3(0, 0.12, 0), o1 * 0.9 + Vector3(0, 0.12, 0), o1 + Vector3(0, -0.05, 0),
					o0 * 0.9 + Vector3(0, 0.12, 0), o1 + Vector3(0, -0.05, 0), o0 + Vector3(0, -0.05, 0)]:
				st.add_vertex(v)
		# Пики рядами по кругу: в центре, кольцо из 7 и из 13 — железо с ржавчиной
		var spots: Array[Vector3] = [Vector3.ZERO]
		for k in 7:
			var a := k * TAU / 7.0
			spots.append(Vector3(cos(a), 0, sin(a)) * r * 0.42)
		for k in 13:
			var a := k * TAU / 13.0 + 0.2
			spots.append(Vector3(cos(a), 0, sin(a)) * r * 0.76)
		for c in spots:
			c += Vector3(rng.randf_range(-0.1, 0.1), 0.12, rng.randf_range(-0.1, 0.1))
			var h := rng.randf_range(0.6, 0.85)
			var w := rng.randf_range(0.13, 0.17)
			var tip := c + Vector3(rng.randf_range(-0.06, 0.06), h, rng.randf_range(-0.06, 0.06))
			var base := [c + Vector3(w, 0, 0), c + Vector3(0, 0, w), c + Vector3(-w, 0, 0), c + Vector3(0, 0, -w)]
			var iron := Color(0.5, 0.5, 0.53) if rng.randf() < 0.7 else Color(0.55, 0.36, 0.22)
			for e in 4:
				st.set_color(iron.darkened(0.25 * (e % 2)))
				st.set_normal((((base[e] + base[(e + 1) % 4]) * 0.5 - c) + Vector3.UP * 0.3).normalized())
				st.add_vertex(base[e])
				st.add_vertex(tip)
				st.add_vertex(base[(e + 1) % 4])
	elif kind == "barricade":
		_barricade_mesh(st, r)
	else:
		# Лужа: неровный многоугольник, по краю чуть светлее
		var segs := 22
		var ring: Array[Vector3] = []
		for k in segs:
			var a := k * TAU / segs
			ring.append(Vector3(cos(a), 0, sin(a)) * r * (0.92 + 0.08 * sin(a * 3.0 + 1.3) * rng.randf_range(0.6, 1.0)))
		for k in segs:
			st.set_normal(Vector3.UP)
			st.set_color(Color(0.08, 0.07, 0.06))
			st.add_vertex(Vector3(0, 0.03, 0))
			st.set_color(Color(0.16, 0.13, 0.1))
			st.add_vertex(ring[(k + 1) % segs])
			st.add_vertex(ring[k])
		# Пузыри — низкие пирамидки
		for k in 6:
			var ang := rng.randf() * TAU
			var c := Vector3(cos(ang), 0.02, sin(ang)) * r * sqrt(rng.randf()) * 0.7
			var w := rng.randf_range(0.12, 0.26)
			var top := c + Vector3(0, w * 0.6, 0)
			for e in 5:
				var a0 := e * TAU / 5.0
				var a1 := (e + 1) * TAU / 5.0
				st.set_color(Color(0.2, 0.17, 0.13))
				st.set_normal((Vector3(cos(a0 + 0.6), 0.8, sin(a0 + 0.6))).normalized())
				st.add_vertex(c + Vector3(cos(a0), 0, sin(a0)) * w)
				st.add_vertex(top)
				st.add_vertex(c + Vector3(cos(a1), 0, sin(a1)) * w)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == "tar":
		mat.roughness = 0.12
		mat.metallic_specular = 0.9
	else:
		mat.roughness = 0.75
	mesh.surface_set_material(0, mat)
	return mesh


# --- интерфейс ------------------------------------------------------------------------------

func _build_ui() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Arial"])
	_font.font_weight = 800
	_ui = CanvasLayer.new()
	_ui.layer = 2
	add_child(_ui)
	# Подсказка в бою (над панелью оружия)
	_chip = _label(18, Color(1, 1, 1, 0.85))
	_chip.text = CHIP_GROUND
	_chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Над панелью умений героя
	_chip.position += Vector2(28, -132)
	_ui.add_child(_chip)
	var build := Control.new()
	build.name = "Build"
	build.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build.visible = false
	_ui.add_child(build)
	# Строка состояния над карточками
	_info = _label(22, Color(1, 1, 1))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.position.y -= 200
	build.add_child(_info)
	# Список построек — столбиком слева, между панелью героя и умениями (центр и низ экрана
	# свободны, сколько бы турелей ни открылось): цветной значок с номером клавиши, название,
	# запас или цена; у выбранной — золотая рамка и описание.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.position = Vector2(24, 178)
	build.add_child(list)
	for i in items.size():
		var kind := items[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(286, 0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(54, 54)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_draw_build_icon.bind(icon, kind, i + 1))
		row.add_child(icon)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(box)
		var head := _label(20, Color(1, 1, 1))
		head.text = display_name(kind)
		box.add_child(head)
		var left := _label(16, FREE)
		left.name = "Stock"
		box.add_child(left)
		var desc := _label(14, Color(1.0, 0.9, 0.7, 0.85))
		desc.name = "Desc"
		desc.text = TRAPS[kind]["desc"] if is_trap(kind) else TurretScript.TYPES[kind]["desc"]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(200, 0)
		box.add_child(desc)
		list.add_child(card)
		_cards.append(card)
	var title := _label(20, GOLD)
	title.text = "Стройка · ЛКМ — поставить или улучшить · ПКМ — убрать в запас · B — выйти"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y += 96
	build.add_child(title)


func _update_ui() -> void:
	for i in _cards.size():
		var picked := i == choice
		var accent := _kind_color(items[i])
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.11, 0.1, 0.09, 0.94) if picked else Color(PANEL, 0.82)
		style.border_color = GOLD if picked else Color(accent, 0.55)
		style.set_border_width_all(3 if picked else 1)
		# Слева — цветная полоса турели
		style.border_width_left = 6
		if not picked:
			style.border_color = Color(accent, 0.75)
		style.set_corner_radius_all(12)
		style.content_margin_left = 16 if picked else 10
		style.content_margin_right = 12
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		if picked:
			style.shadow_color = Color(GOLD, 0.3)
			style.shadow_size = 8
		_cards[i].add_theme_stylebox_override("panel", style)
		_cards[i].modulate.a = 1.0 if picked else 0.85
		(_cards[i].find_child("Desc", true, false) as Label).visible = picked
		var left: Label = _cards[i].find_child("Stock", true, false)
		var n := stock_left(items[i])
		if n > 0 or is_trap(items[i]):
			left.text = "запас %d / %d" % [maxi(n, 0), stock(items[i])]
			left.add_theme_color_override("font_color", FREE if n > 0 else BAD)
		else:
			# Запас кончился — турель можно докупить за монеты
			var price := extra_cost(items[i])
			left.text = "ещё ● %d" % price
			left.add_theme_color_override("font_color", GOLD if waves.coins >= price else BAD)
	var kind: String = items[choice]
	if _hover >= 0 and _slots[_hover]["turret"]:
		var here: Node3D = _slots[_hover]["turret"]
		var name := "%s %s" % [TurretScript.TYPES[here.kind]["name"], TIERS[here.tier - 1]]
		var back := refund(_hover)
		var remove_text := "ПКМ — убрать" + (" (+%d)" % back if back > 0 else "")
		var up := upgrade_cost(_hover)
		if up < 0:
			_info.text = "%s — высшая ступень · %s" % [name, remove_text]
		elif waves.coins < up:
			_info.text = "%s · до %s нужно %d монет · %s" % [name, TIERS[here.tier], up, remove_text]
		else:
			_info.text = "%s · ЛКМ — улучшить до %s за %d · %s" % [name, TIERS[here.tier], up, remove_text]
	elif _hover_trap >= 0:
		_info.text = "%s · ПКМ — убрать в запас" % TRAPS[_traps[_hover_trap]["kind"]]["name"]
	elif not _ghost or not _ghost.visible:
		_info.text = "Наведи прицел на плато (турели) или на дно канала (ловушки)"
	elif _ghost_why != "":
		_info.text = _ghost_why
	elif stock_left(kind) > 0:
		_info.text = "ЛКМ — поставить «%s» · в запасе %d" % [display_name(kind), stock_left(kind)]
	else:
		_info.text = "ЛКМ — поставить ещё «%s» за %d монет" % [display_name(kind), extra_cost(kind)]
	_info.add_theme_color_override("font_color", BAD if _ghost_why != "" and _hover_trap < 0 and \
		(_hover < 0 or not _slots[_hover]["turret"]) else Color(1, 1, 1))


## Цвет постройки в списке стройки (как броня модели).
func _kind_color(kind: String) -> Color:
	match kind:
		"gatling": return Color(0.95, 0.68, 0.14)
		"freeze": return Color(0.45, 0.75, 1.0)
		"flame": return Color(1.0, 0.45, 0.12)
		"laser": return Color(0.95, 0.2, 0.15)
		"mortar": return Color(0.55, 0.66, 0.26)
		"barricade": return Color(0.72, 0.5, 0.28)
	return GOLD


## Значок постройки: тёмный круг в цветном кольце, простой рисунок турели, номер клавиши в углу.
func _draw_build_icon(c: Control, kind: String, key: int) -> void:
	var col := _kind_color(kind)
	var m := c.size * 0.5
	c.draw_circle(m, 26.0, Color(0.06, 0.06, 0.07, 0.95))
	c.draw_arc(m, 25.0, 0.0, TAU, 32, col, 2.5, true)
	var w := Color(1, 1, 1, 0.92)
	match kind:
		"gatling":
			c.draw_rect(Rect2(m + Vector2(2, -8), Vector2(12, 16)), col)
			for k in 3:
				c.draw_rect(Rect2(m + Vector2(-15, -7 + k * 5.5), Vector2(18, 3)), w)
		"freeze":
			for k in 3:
				var d := Vector2.from_angle(k * PI / 3.0) * 14.0
				c.draw_line(m - d, m + d, col, 3.0, true)
				for e in [-1.0, 1.0]:
					var tip: Vector2 = m + d * 0.6 * e
					c.draw_line(tip, tip + (d * e).normalized().rotated(0.7) * 5.0, col, 2.0, true)
					c.draw_line(tip, tip + (d * e).normalized().rotated(-0.7) * 5.0, col, 2.0, true)
		"flame":
			var pts := PackedVector2Array()
			for k in 16:
				var a := TAU * k / 16.0
				var r := 10.0 * (1.0 + 0.9 * maxf(-sin(a), 0.0) ** 3)
				pts.append(m + Vector2(cos(a) * r * 0.85, -sin(a) * r * 1.1) + Vector2(0, 4))
			c.draw_colored_polygon(pts, col)
			c.draw_circle(m + Vector2(0, 6), 5.0, Color(1.0, 0.85, 0.3))
		"laser":
			c.draw_line(m + Vector2(-2, 0), m + Vector2(18, 0), Color(1.0, 0.75, 0.7), 3.0)
			c.draw_rect(Rect2(m + Vector2(-16, -7), Vector2(12, 14)), Color(0.35, 0.33, 0.36))
			c.draw_circle(m + Vector2(-3, 0), 6.0, col)
		"mortar":
			# Трасса навесом и ядро, внизу толстая наклонная труба
			for k in 7:
				var t := k / 6.0
				c.draw_circle(m + Vector2(-6 + t * 22.0, -4 - 16.0 * 4.0 * t * (1.0 - t) * 0.6), 1.3, Color(1, 1, 1, 0.6))
			c.draw_circle(m + Vector2(16, -2), 4.0, Color(0.12, 0.12, 0.13))
			c.draw_arc(m + Vector2(16, -2), 4.0, 0.0, TAU, 12, Color(1, 1, 1, 0.5), 1.0, true)
			c.draw_line(m + Vector2(-12, 14), m + Vector2(-2, 2), col, 9.0)
			c.draw_rect(Rect2(m + Vector2(-17, 13), Vector2(14, 4)), Color(0.35, 0.33, 0.36))
		"barricade":
			for k in 3:
				var x := -10.0 + k * 10.0
				c.draw_colored_polygon(PackedVector2Array([m + Vector2(x - 3, 13), m + Vector2(x + 3, 13),
					m + Vector2(x + 3, -8), m + Vector2(x, -14), m + Vector2(x - 3, -8)]), col)
			c.draw_line(m + Vector2(-15, 2), m + Vector2(15, -2), col.darkened(0.35), 3.0)
	# Номер клавиши — кружок в левом верхнем углу значка
	var kp := Vector2(7, 7)
	c.draw_circle(kp, 9.0, Color(0.06, 0.06, 0.07))
	c.draw_arc(kp, 9.0, 0.0, TAU, 16, GOLD, 1.5, true)
	var txt := str(key)
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	c.draw_string(_font, kp + Vector2(-ts.x * 0.5, 4.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)


## Цена турели (от неё — цена ступеней) с учётом скидки из древа прокачки.
func cost_of(kind: String) -> int:
	return Upgrades.turret_cost(kind, TurretScript.TYPES[kind]["cost"])


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _glow_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, alpha)
	m.no_depth_test = false
	return m


func _pillar_mat(color: Color) -> StandardMaterial3D:
	var m := _glow_mat(color, 0.08)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Круг дальности для декали на земле: яркий обод и едва видная заливка.
## Сектор огня турели для декали: заливка и яркий край, середина сектора — вверх картинки
## (вперёд, -Z у декали).
func _sector_texture() -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := n * 0.5
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5 - half, y + 0.5 - half)
			var d := v.length() / half
			var ang := atan2(v.x, -v.y)
			var a := 0.0
			if d <= 1.0 and absf(ang) <= TurretScript.ARC:
				var edge := clampf(1.0 - absf(d - 0.975) / 0.025, 0.0, 1.0)
				var side := clampf(1.0 - (TurretScript.ARC - absf(ang)) * d * half / 3.0, 0.0, 1.0)
				a = 0.12 + 0.85 * maxf(edge, side)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _ring_texture() -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var a := 0.0
			if d <= 1.0:
				a = 0.04 + 0.06 * d * d + 0.85 * clampf(1.0 - absf(d - 0.975) / 0.025, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
