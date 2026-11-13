extends Node3D
## Общее для оружия от первого лица (дочерний узел камеры): модель с руками в перчатках,
## прицеливание лучом из камеры, метка на земле, смена оружия (опустить и поднять).
## Наследники: blunderbuss.gd, flamethrower.gd. Интерфейс для HUD и волн:
## ammo_text(), ammo_note(), ammo_empty(), reload_progress(), restock(), targets.

const Hands := preload("res://hero/fp_hands.gd")

const AIM_DISTANCE := 120.0
# Первые метры луча прицела пропускаем — парапет под носом не мешает целиться
const SAFE_DISTANCE := 2.5
const EQUIP_TIME := 0.35
const MARKER_IDLE := Color(1.0, 0.92, 0.7, 0.75)
const MARKER_TARGET := Color(1.0, 0.25, 0.12, 0.9)
const MARKER_SCALE := 0.45       # метка прицела — доля радиуса поражения

var horde: Node3D
## Название для панели оружия.
var display_name := ""
## «shells» или «fuel» — какую иконку рисует HUD.
var ammo_kind := "shells"
## Сколько жуков в зоне поражения под прицелом — для прицела и метки.
var targets := 0

var _camera: Camera3D
var _model: Node3D
var _marker: Decal
var _equip := 1.0
var _was_captured := false


func _ready() -> void:
	_camera = get_parent()
	_ensure_action("fire", null, MOUSE_BUTTON_LEFT)
	# R занята умением героя (hero_abilities.gd) — перезарядка на T
	_ensure_action("reload", KEY_T, 0)


## Достать или убрать оружие: убранное не видно и не работает, доставание — с анимацией.
func set_active(on: bool) -> void:
	visible = on
	set_process(on)
	_was_captured = false
	if on:
		_equip = 0.0
	if _marker:
		_marker.visible = false


func ammo_text() -> String:
	return ""


func ammo_note() -> String:
	return ""


func ammo_empty() -> bool:
	return false


func reload_progress() -> float:
	return 1.0


func restock() -> void:
	pass


## Параметры из прокачки заново (main.gd зовёт у всего оружия после покупок); у кого их нет — ничего.
func refresh_stats() -> void:
	pass


## Загрузить модель, уменьшить для кадра и поставить на неё руки.
## Руки — массивы [точка, ось хвата, радиус, направление локтя] в осях модели.
func _setup_model(scene: PackedScene, view_scale: float, right_hand: Array, left_hand: Array) -> void:
	_model = scene.instantiate()
	_model.scale = Vector3.ONE * view_scale
	add_child(_model)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for right in [true, false]:
		var hand := Hands.make(right)
		_model.add_child(hand)
		var g: Array = right_hand if right else left_hand
		# Пятый элемент хвата (если есть) — размер руки: у крупного оружия руки крупнее в кадре
		Hands.place(hand, g[0], g[1], g[2], g[3], g[4] if g.size() > 4 else 1.0)


## Доставание: 0 — оружие внизу за кадром, 1 — в руках. Наследник добавляет к позе.
func _tick_equip(delta: float) -> float:
	_equip = minf(_equip + delta / EQUIP_TIME, 1.0)
	return pow(1.0 - _equip, 3.0)


## Можно ли стрелять в этом кадре: мышь захвачена не этим кликом, оружие уже в руках.
func _can_shoot() -> bool:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var ok := captured and _was_captured and _equip >= 1.0
	_was_captured = captured
	return ok


## Навести ствол точно в прицел: ствол модели (её −Z) поворачиваем так, чтобы линия от дула шла в
## точку под прицелом (по лучу из камеры; расстояние сглажено, чтобы оружие не дёргалось, когда
## прицел скачет с ближней земли на дальнюю). Поправка считается от позы покоя (rest_pos, rest_rot),
## а прикладывается ко всей позе — отдача и перезарядка поверх неё остаются.
var _aim_dist := 30.0
var _muzzle_node: Node3D


func _point_at_crosshair(rest_pos: Vector3, rest_rot: Vector3, delta: float) -> void:
	if not _model:
		return
	if not _muzzle_node:
		_muzzle_node = _model.find_child("Muzzle")
		if not _muzzle_node:
			return
	var aim := _aim()
	var d := 60.0
	if aim["hit"]:
		d = clampf(_camera.global_position.distance_to(aim["point"]), 8.0, 90.0)
	_aim_dist = lerpf(_aim_dist, d, minf(delta * 5.0, 1.0))
	var rest := Basis.from_euler(rest_rot)
	var muzzle_cam := rest_pos + rest * (_model.transform * _muzzle_node.position)
	var cur := (rest * (_model.basis * Vector3(0, 0, -1))).normalized()
	var want := (Vector3(0, 0, -_aim_dist) - muzzle_cam).normalized()
	transform.basis = Basis(Quaternion(cur, want)) * transform.basis


func _player() -> CollisionObject3D:
	return _camera.get_parent().get_parent() as CollisionObject3D


## Точка под прицелом: первое препятствие на луче из камеры (или далеко вперёд, если небо).
func _aim() -> Dictionary:
	var dir := -_camera.global_basis.z
	var from := _camera.global_position + dir * SAFE_DISTANCE
	var to := _camera.global_position + dir * AIM_DISTANCE
	# Только мир: ограждения стены прицел не задевают
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if _player():
		query.exclude = [_player().get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"point": to, "hit": false}
	return {"point": hit.position, "hit": true}


## Метка на земле: кольцо радиуса radius с лёгкой заливкой (проецируется сверху на землю,
## стены и жуков).
func _make_marker(radius: float) -> void:
	_marker = Decal.new()
	_marker.top_level = true
	# Метка — аккуратное тонкое кольцо меньше зоны поражения, без заливки: не закрывает толпу
	var r := radius * MARKER_SCALE
	_marker.size = Vector3(r * 2.0, 10.0, r * 2.0)
	_marker.texture_albedo = _radial([0.0, 0.84, 0.88, 0.94, 1.0], [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	# Свечение — только у самого кольца (у декали свечение не учитывает прозрачность)
	_marker.texture_emission = _radial([0.0, 0.86, 0.89, 0.93, 1.0],
		[Color.BLACK, Color.BLACK, Color.WHITE, Color.WHITE, Color.BLACK])
	_marker.emission_energy = 0.35
	_marker.upper_fade = 0.2
	_marker.lower_fade = 0.2
	_marker.visible = false
	# Только земля и орда — деревья и камни (слой 2, map_builder.PROPS_LAYER) не красим
	_marker.cull_mask = 1
	add_child(_marker)


## Поставить метку в точку прицела (если она ближе max_distance), посчитать жуков в радиусе.
## dim — метка бледнее (оружие не готово). Возвращает данные прицела.
func _update_marker(radius: float, max_distance: float, dim: bool) -> Dictionary:
	var aim := _aim()
	var at: Vector3 = aim["point"]
	var near: bool = aim["hit"] and at.distance_to(_camera.global_position) <= max_distance
	_marker.visible = near
	targets = 0
	if near:
		_marker.global_position = at
		if horde:
			targets = horde.count_near(at, radius)
		var col := MARKER_TARGET if targets > 0 else MARKER_IDLE
		col.a *= 0.45 if dim else 1.0
		_marker.modulate = col
	aim["near"] = near
	return aim


func _radial(offsets: Array, colors: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(offsets)
	grad.colors = PackedColorArray(colors)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _ensure_action(action: String, key, mouse_button: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	if key != null:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	else:
		var ev := InputEventMouseButton.new()
		ev.button_index = mouse_button
		InputMap.action_add_event(action, ev)
