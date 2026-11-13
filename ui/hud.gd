extends CanvasLayer
## Интерфейс боя: слева вверху — волна и сколько жуков осталось, по центру — здоровье ворот,
## справа вверху — монеты, справа внизу — заряды или топливо оружия в руках, слева внизу —
## оружие по клавишам. В центре — надписи между волнами.
## Тёмные скруглённые плашки, белый жирный текст, иконки нарисованы кодом.

const TurretModels := preload("res://turrets/turret_models.gd")
const Progress := preload("res://core/progress.gd")
const Upgrades := preload("res://core/upgrades.gd")
const PANEL := Color(0.15, 0.14, 0.14, 0.88)
const PANEL_EDGE := Color(0.34, 0.31, 0.29, 0.95)
const TEXT := Color(1, 1, 1)
const GOLD := Color(0.98, 0.74, 0.22)
const RED := Color(0.86, 0.2, 0.17)
const STACK_SHOW := 2.0         # с виден столбик оружия после смены

var waves: Node
var gun: Node3D
## Название локации и следующей (пусто — эта последняя).
var level_name := ""
var next_name := ""
## Кто идёт — для счётчика «… осталось» («Жуков», «Гоблинов»).
var enemies := "Жуков"
## После победы: сколько звёзд за этот раз и сколько новых добавилось к прокачке.
var stars_got := 0
var stars_added := 0
## Трофеи и кристаллы за этот бой (main.gd).
var trophies_battle := 0
## Итоги боя (main.gd: _battle_summary): до какой волны дошёл, рекорд, сколько улучшений можно
## купить прямо сейчас.
var summary_wave := 0
var summary_best := 0
var summary_record := false
var summary_buy := 0
## Вместо крепости — вход в туннель (level gate: tunnel): свой значок над полосой и свои слова.
var tunnel := false
## Что купить прямо сейчас: «Боезапас (15) · Мощь ракет (20)».
var summary_offer := ""
## Трофеи, заработанные в этом бою к этой секунде (main.gd), — растут под черепом.
var trophies_live := 0
var _trophy_label: Label
var crystals_battle := 0
var weapons: Array[Node3D] = []
## Герой (player.gd: здоровье, уровень, опыт) и его умения (hero_abilities.gd).
var player: CharacterBody3D
var abilities: Node3D
var _hero_bar: Control
var _fuel_bar: Control
var _hero_name: Label
var _portrait: Control
var _kills_label: Label
## Счётчик убийств «крутится» к настоящему числу и вздрагивает, когда растёт; монеты — так же.
var _kills_shown := 0.0
var _kills_pulse := 0.0
var _coins_shown := 0.0
var _coins_pulse := 0.0
var _ability_slots: Array[Control] = []
var _ability_row: HBoxContainer
var _level_label: Label
var _xp_bar: Control
var _hero_shown := 1.0
var _hurt := 0.0

var _font: SystemFont
var _wave_label: Label
var _left_label: Label
var _coins_label: Label
var _ammo_label: Label
var _ammo_note: Label
var _ammo_icon: Control
var _slots: Array[PanelContainer] = []
var _stack: VBoxContainer
var _stack_gun: Node3D
var _stack_time := 0.0
## Идёт стройка (turrets.gd): внизу карточки — столбик оружия не показываем.
var building := false
var _gun_name: Label
var _banner: Label
var _toasts: VBoxContainer
var _boss_panel: PanelContainer
var _boss_name: Label
var _boss_bar: Control
var _boss_shown := 1.0
var _reward: PanelContainer
## Карточка «Новый уровень» справа под монетами и её значок (лучи вращаются).
var _level_card: Control
var _level_badge: Control
var _level_num := 0
var _reward_pivot: Node3D
var _bar: Control
var _vignette: TextureRect
var _shown_hp := 1.0           # полоса догоняет настоящее здоровье — виден «урон»
var _hit_flash := 0.0


func _ready() -> void:
	layer = 1
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Arial"])
	_font.font_weight = 800
	_build_vignette()
	# Герой (слева вверху): портрет в ромбе и полоса здоровья
	var hero_panel := _panel(Control.PRESET_TOP_LEFT, Vector2(24, 20))
	var hero_box := HBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 12)
	hero_panel.add_child(hero_box)
	_portrait = _icon(_draw_portrait, Vector2(64, 64))
	hero_box.add_child(_portrait)
	var hero_info := VBoxContainer.new()
	hero_info.add_theme_constant_override("separation", 2)
	hero_info.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_box.add_child(hero_info)
	_hero_name = _label(18)
	_hero_name.modulate = GOLD
	hero_info.add_child(_hero_name)
	_hero_bar = Control.new()
	_hero_bar.custom_minimum_size = Vector2(300, 24)
	_hero_bar.draw.connect(_draw_hero_bar)
	hero_info.add_child(_hero_bar)
	# Топливо ранца — тонкая полоса под здоровьем
	_fuel_bar = Control.new()
	_fuel_bar.custom_minimum_size = Vector2(300, 12)
	_fuel_bar.draw.connect(_draw_fuel_bar)
	hero_info.add_child(_fuel_bar)
	# Волна и прочность ворот (по центру вверху)
	var gate_panel := _panel(Control.PRESET_CENTER_TOP, Vector2(0, 20))
	var center_box := VBoxContainer.new()
	center_box.add_theme_constant_override("separation", -2)
	gate_panel.add_child(center_box)
	_wave_label = _label(30)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_wave_label)
	var gate_box := HBoxContainer.new()
	gate_box.add_theme_constant_override("separation", 10)
	center_box.add_child(gate_box)
	gate_box.add_child(_icon(_draw_castle, Vector2(32, 32)))
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(380, 32)
	_bar.draw.connect(_draw_bar)
	gate_box.add_child(_bar)
	_left_label = _label(16)
	_left_label.modulate = Color(1, 1, 1, 0.75)
	_left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_left_label)
	# Убито за бой — череп (справа вверху), под ним монеты
	var kill_panel := _panel(Control.PRESET_TOP_RIGHT, Vector2(-24, 20))
	var kill_box := HBoxContainer.new()
	kill_box.add_theme_constant_override("separation", 12)
	kill_panel.add_child(kill_box)
	kill_box.add_child(_icon(_draw_skull, Vector2(40, 40)))
	var kill_text := VBoxContainer.new()
	kill_text.add_theme_constant_override("separation", -6)
	kill_box.add_child(kill_text)
	_kills_label = _label(30)
	kill_text.add_child(_kills_label)
	# Трофеи за этот бой — видно, как растёт награда, пока бьёшь орду
	_trophy_label = _label(16)
	_trophy_label.modulate = GOLD
	kill_text.add_child(_trophy_label)
	var coin_panel := _panel(Control.PRESET_TOP_RIGHT, Vector2(-24, 110))
	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 12)
	coin_panel.add_child(coin_box)
	coin_box.add_child(_icon(_draw_coin, Vector2(40, 40)))
	_coins_label = _label(30)
	coin_box.add_child(_coins_label)
	# Заряды (справа внизу)
	var ammo_panel := _panel(Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -104))
	var ammo_box := HBoxContainer.new()
	ammo_box.add_theme_constant_override("separation", 12)
	ammo_panel.add_child(ammo_box)
	_ammo_icon = _icon(_draw_ammo, Vector2(34, 40))
	ammo_box.add_child(_ammo_icon)
	var ammo_text := VBoxContainer.new()
	ammo_text.add_theme_constant_override("separation", -6)
	ammo_box.add_child(ammo_text)
	_gun_name = _label(15)
	_gun_name.modulate = GOLD
	ammo_text.add_child(_gun_name)
	_ammo_label = _label(30)
	ammo_text.add_child(_ammo_label)
	_ammo_note = _label(15)
	_ammo_note.modulate = Color(1, 0.8, 0.45)
	ammo_text.add_child(_ammo_note)
	# Надпись в центре (между волнами, победа, поражение)
	_banner = _label(34)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05, 0.85))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.position.y -= 140
	add_child(_banner)
	# Сообщения поверх боя (уровень мастерства и т. п.) — под полосой ворот, гаснут сами
	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.position.y += 140
	add_child(_toasts)
	# Полоса здоровья босса — под воротами, пока босс на поле
	_boss_panel = _panel(Control.PRESET_CENTER_TOP, Vector2(0, 140))
	var boss_box := VBoxContainer.new()
	boss_box.add_theme_constant_override("separation", 2)
	_boss_panel.add_child(boss_box)
	_boss_name = _label(20)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	boss_box.add_child(_boss_name)
	_boss_bar = Control.new()
	_boss_bar.custom_minimum_size = Vector2(520, 18)
	_boss_bar.draw.connect(_draw_boss_bar)
	boss_box.add_child(_boss_bar)
	_boss_panel.visible = false
	# Оружие — столбик слева внизу (номер клавиши, значок, название): всплывает при смене
	# оружия и через пару секунд гаснет, выбранное — с золотой рамкой
	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 6)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Над панелью умений
	_stack.position += Vector2(24, -150)
	rebuild_stack()
	waves.gate_hit.connect(func(_damage: int) -> void: _hit_flash = minf(_hit_flash + 0.12, 0.6))
	_build_abilities()
	_build_level()


## Столбик оружия заново (купили новое — в нём сразу появляется строка).
func rebuild_stack() -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	_stack_gun = null
	for i in weapons.size():
		var slot := PanelContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.custom_minimum_size.x = 220
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		slot.add_child(row)
		var key := _label(20)
		key.text = str(i + 1)
		key.modulate = GOLD
		row.add_child(key)
		row.add_child(_icon(_draw_weapon.bind(weapons[i].display_name), Vector2(34, 34)))
		var l := _label(20)
		l.text = weapons[i].display_name
		row.add_child(l)
		_stack.add_child(slot)
		_slots.append(slot)


## Подсказка, что делать с добычей: сколько улучшений уже по карману.
func _buy_text() -> String:
	if summary_buy <= 0:
		return "\nКопи трофеи — следующее улучшение уже близко"
	return "\nМожно купить: %s — U, «Прокачка»" % summary_offer


## Добыча за бой: «+120 трофеев · +2 кристалла».
func _loot_text() -> String:
	var t := "+%d трофеев (всего %d)" % [trophies_battle, Progress.trophies]
	if crystals_battle > 0:
		t += " · +%d ◆" % crystals_battle
	return t


## Пришёл босс: имя на полосе и большое красное сообщение.
func boss_arrived(boss_name: String) -> void:
	_boss_name.text = boss_name
	_boss_shown = 1.0
	toast("Идёт %s!" % boss_name, Color(1.0, 0.4, 0.3))


func _draw_boss_bar() -> void:
	var r := Rect2(Vector2.ZERO, _boss_bar.size)
	_boss_bar.draw_rect(r, Color(0.08, 0.05, 0.05))
	_boss_bar.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * _boss_shown, r.size.y - 4)), Color(0.85, 0.15, 0.1))
	_boss_bar.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * _boss_shown, 4)), Color(1, 0.5, 0.45, 0.6))


## Сообщение поверх боя на несколько секунд.
## 12345 → «12 345».
static func _group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func toast(text: String, color := Color(1.0, 0.85, 0.4)) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _label(22)
	l.text = text
	l.add_theme_color_override("font_color", color)
	panel.add_child(l)
	_toasts.add_child(panel)
	var tw := panel.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)


## Новый уровень героя — карточка-награда справа под монетами: золотой значок с номером и
## вращающимися лучами, «НОВЫЙ УРОВЕНЬ» и что дал уровень (цветные строки). Выезжает сбоку с
## отскоком, рамка мерцает, через несколько секунд уезжает обратно. Новый уровень сменяет старую.
const LEVEL_CARD_TIME := 4.0
const LEVEL_PERKS := [["Здоровье восстановлено", Color(0.5, 0.95, 0.45)],
	["Взрывы ракет шире", Color(1.0, 0.62, 0.25)], ["Умения перезаряжаются быстрее", Color(0.5, 0.78, 1.0)]]

func level_up(lvl: int) -> void:
	if is_instance_valid(_level_card):
		_level_card.queue_free()
	_level_num = lvl
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	holder.position.y += 190
	add_child(holder)
	_level_card = holder
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.11, 0.09, 0.95)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(GOLD, 0.35)
	style.shadow_size = 12
	style.content_margin_left = 12
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	holder.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	_level_badge = _icon(_draw_level_badge, Vector2(92, 92))
	_level_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_level_badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var title := _label(24)
	title.text = "НОВЫЙ УРОВЕНЬ"
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)
	for perk: Array in LEVEL_PERKS:
		var line := _label(17)
		line.text = "+  " + String(perk[0])
		line.add_theme_color_override("font_color", perk[1])
		col.add_child(line)
	# Ширина известна после раскладки: карточка встаёт у правого края, начинает за ним
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var w := card.size.x
	card.position = Vector2(40.0, 0.0)
	card.modulate.a = 0.0
	var rest := Vector2(-w - 24.0, 0.0)
	card.pivot_offset = Vector2(w, card.size.y * 0.5)
	card.scale = Vector2.ONE * 1.15
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position", rest, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_property(card, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(LEVEL_CARD_TIME)
	tw.tween_property(card, "position", Vector2(40.0, 0.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(holder.queue_free)
	# Рамка мерцает золотом, пока карточка на экране
	var glow := card.create_tween().set_loops(int(LEVEL_CARD_TIME / 0.6) + 1)
	glow.tween_property(style, "border_color", Color(1.0, 0.95, 0.7), 0.3)
	glow.tween_property(style, "border_color", GOLD, 0.3)


## Значок уровня: вращающиеся золотые лучи, тёмный круг в золотом кольце, номер уровня.
func _draw_level_badge(c: Control) -> void:
	var center := c.size * 0.5
	var t := Time.get_ticks_msec() / 1000.0
	var rays := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0 + t * 0.6
		rays.append(center + Vector2.from_angle(a) * (46.0 if k % 2 == 0 else 34.0))
	c.draw_colored_polygon(rays, Color(GOLD, 0.55))
	c.draw_circle(center, 33.0, GOLD)
	c.draw_circle(center, 28.5, Color(0.16, 0.12, 0.08))
	c.draw_arc(center, 25.0, 0.0, TAU, 40, Color(GOLD, 0.45), 2.0, true)
	var text := str(_level_num)
	var fs := 34 if text.length() < 3 else 26
	var tsize := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var base := center + Vector2(-tsize.x * 0.5, tsize.y * 0.32)
	c.draw_string_outline(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.5))
	c.draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.55))


## Награда за локацию: панель «Новое оружие» с крутящейся моделью, названием и описанием.
func show_reward(item_name: String, desc: String, model_path: String, turret: bool) -> void:
	_reward = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, 0.97)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	_reward.add_theme_stylebox_override("panel", style)
	_reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward.add_child(box)
	var head := _label(20)
	head.text = "НОВАЯ ТУРЕЛЬ" if turret else "НОВОЕ ОРУЖИЕ"
	head.add_theme_color_override("font_color", GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	# Модель крутится в своём маленьком мире
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(380, 210)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	holder.add_child(view)
	_reward_pivot = Node3D.new()
	view.add_child(_reward_pivot)
	var model: Node3D = TurretModels.scene(model_path.trim_prefix("turret:")).instantiate() \
		if model_path.begins_with("turret:") else load(model_path).instantiate()
	_reward_pivot.add_child(model)
	var bounds := _bounds(model)
	model.position = -bounds.get_center()
	var reach := bounds.size.length()
	var cam := Camera3D.new()
	cam.fov = 36.0
	var eye := Vector3(0, reach * 0.3, reach * 1.05)
	# Панель ещё не в дереве — смотрим на модель через базис, без look_at
	cam.transform = Transform3D(Basis.looking_at(-eye, Vector3.UP), eye)
	view.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	view.add_child(sun)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.7
	env.background_mode = Environment.BG_CLEAR_COLOR
	var world := WorldEnvironment.new()
	world.environment = env
	view.add_child(world)
	var name_label := _label(30)
	name_label.text = item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var desc_label := _label(17)
	desc_label.text = desc
	desc_label.modulate = Color(1, 1, 1, 0.8)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = 380
	box.add_child(desc_label)
	_reward.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_reward.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reward.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reward.position.y += 150
	add_child(_reward)


func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D"):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _process(delta: float) -> void:
	if _reward_pivot:
		_reward_pivot.rotation.y += delta * 0.9
	if is_instance_valid(_level_badge):
		_level_badge.queue_redraw()
	var w = waves
	var h: Node3D = w.horde
	_boss_panel.visible = h.boss_alive
	if h.boss_alive:
		var k := float(h.boss_hp) / maxf(h.boss_max, 1.0)
		_boss_shown = move_toward(_boss_shown, k, delta * 0.5) if _boss_shown > k else k
		_boss_bar.queue_redraw()
	# Пока висит полоса босса, сообщения — ниже неё
	_toasts.position.y = 140.0 + (66.0 if h.boss_alive else 0.0)
	_wave_label.text = "ОРДА · %d%%" % w.percent()
	# Счётчик догоняет настоящее число (быстрее, когда отстал сильнее) и вздрагивает
	var gap := float(h.kills) - _kills_shown
	if gap > 0.5:
		_kills_pulse = minf(_kills_pulse + gap * 0.01, 1.0)
	_kills_shown = move_toward(_kills_shown, h.kills, maxf(absf(gap) * delta * 8.0, delta * 30.0))
	_kills_label.text = _group(int(round(_kills_shown)))
	_kills_pulse = move_toward(_kills_pulse, 0.0, delta * 2.5)
	_kills_label.pivot_offset = _kills_label.size * Vector2(0.0, 0.5)
	_kills_label.scale = Vector2.ONE * (1.0 + 0.18 * _kills_pulse)
	_kills_label.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.85, 0.4), _kills_pulse)
	_trophy_label.text = "+%d трофеев" % trophies_live
	_update_hero(delta)
	_left_label.visible = w.state == w.State.FIGHT
	_left_label.text = "%s осталось: %d" % [enemies, w.remaining()]
	var cgap := float(w.coins) - _coins_shown
	if cgap > 0.5:
		_coins_pulse = 1.0
	_coins_shown = move_toward(_coins_shown, w.coins, maxf(absf(cgap) * delta * 8.0, delta * 20.0))
	_coins_label.text = _group(int(round(_coins_shown)))
	_coins_pulse = move_toward(_coins_pulse, 0.0, delta * 3.0)
	_coins_label.pivot_offset = _coins_label.size * Vector2(0.0, 0.5)
	_coins_label.scale = Vector2.ONE * (1.0 + 0.12 * _coins_pulse)
	_ammo_label.text = gun.ammo_text()
	_ammo_label.modulate = Color(1, 0.4, 0.3) if gun.ammo_empty() else TEXT
	_ammo_note.text = gun.ammo_note()
	_ammo_note.visible = _ammo_note.text != ""
	_ammo_icon.queue_redraw()
	_gun_name.text = gun.display_name
	# Сменили оружие — столбик всплывает, потом гаснет
	if gun != _stack_gun:
		_stack_gun = gun
		_stack_time = STACK_SHOW
		for i in _slots.size():
			var active := weapons[i] == gun
			_slots[i].add_theme_stylebox_override("panel", _slot_style(active))
			_slots[i].modulate.a = 1.0 if active else 0.55
	_stack_time = maxf(_stack_time - delta, 0.0)
	_stack.modulate.a = clampf(_stack_time / 0.4, 0.0, 1.0)
	# Столбик оружия слева убран по просьбе: текущее оружие видно на панели патронов справа
	_stack.visible = false
	var hp: float = float(w.gate_hp) / w.gate_max
	_shown_hp = move_toward(_shown_hp, hp, delta * 0.25) if _shown_hp > hp else hp
	_bar.queue_redraw()
	_hit_flash = move_toward(_hit_flash, 0.0, delta * 1.5)
	_hurt = move_toward(_hurt, 0.0, delta * 2.0)
	_vignette.modulate.a = maxf(_hit_flash * 0.8, _hurt)
	match w.state:
		w.State.READY:
			_banner.text = "«%s» · %s\nОрда: %s %s · Enter — выпустить" % [level_name, w.pattern_name(), _group(w.horde_size()),
				enemies.to_lower()]
		w.State.WON:
			var stars := "★".repeat(stars_got) + "☆".repeat(3 - stars_got)
			var gain := "+%d★ · " % stars_added if stars_added > 0 else ""
			gain += _loot_text() + " · "
			if next_name != "":
				_banner.text = "Победа! «%s» пройдена  %s\n%sОткрыта «%s» · Enter — туда%s" % [level_name, stars, gain, next_name, _buy_text()]
			else:
				_banner.text = "Победа! Рой отброшен — все локации пройдены  %s\n%sEnter — сыграть ещё раз%s" % [stars, gain, _buy_text()]
		w.State.LOST:
			var record := "новый рекорд!" if summary_record and summary_wave > 0 else "рекорд: %d%%" % summary_best
			_banner.text = "%s · пройдено %d%% орды · %s\nУбито %d · %s%s\nEnter — снова в бой" % [
				"Орда прорвалась в туннель" if tunnel else "Ворота пали", summary_wave, record, h.kills, _loot_text(), _buy_text()]
		_:
			_banner.text = ""


# --- элементы -------------------------------------------------------------------------------

func _panel(preset: int, offset: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.set_anchors_and_offsets_preset(preset)
	# Растёт от своего угла внутрь экрана
	match preset:
		Control.PRESET_TOP_RIGHT:
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position += offset
	return panel


func _slot_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = GOLD if active else PANEL_EDGE
	style.set_border_width_all(3 if active else 2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _icon(drawer: Callable, size: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(drawer.bind(c))
	return c


## Красная виньетка по краям экрана — вспыхивает, когда жуки бьют ворота.
func _build_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.8, 0.05, 0.02, 0.0), Color(0.8, 0.05, 0.02, 0.0), Color(0.8, 0.05, 0.02, 0.9)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)


# --- герой ----------------------------------------------------------------------------------

## Умения — квадраты слева внизу: значок, тёмная шторка перезарядки сверху вниз, клавиша под ним.
func _build_abilities() -> void:
	if not abilities:
		return
	var row := HBoxContainer.new()
	_ability_row = row
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position += Vector2(24, -24)
	for i in abilities.ABILITIES.size():
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(76, 100)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.draw.connect(_draw_ability.bind(slot, i))
		row.add_child(slot)
		_ability_slots.append(slot)


## Уровень героя в бою — ромб с числом и полоса опыта (справа внизу).
func _build_level() -> void:
	var panel := _panel(Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -24))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_level_label = _label(22)
	_level_label.modulate = GOLD
	box.add_child(_level_label)
	_xp_bar = Control.new()
	_xp_bar.custom_minimum_size = Vector2(260, 24)
	_xp_bar.draw.connect(_draw_xp)
	box.add_child(_xp_bar)


## Герой ранен — красная вспышка по краям.
func hurt() -> void:
	_hurt = minf(_hurt + 0.35, 0.7)


func _update_hero(delta: float) -> void:
	if not player:
		return
	var k: float = player.hp / player.hp_max
	_hero_shown = move_toward(_hero_shown, k, delta * 0.4) if _hero_shown > k else k
	_hero_name.text = ("Сбит! Обратно через %d с" % ceili(player.down_left)) if player.down_left > 0.0 \
		else "Герой · %d / %d" % [ceili(player.hp), int(player.hp_max)]
	_hero_bar.queue_redraw()
	_fuel_bar.queue_redraw()
	_portrait.queue_redraw()
	_level_label.text = "Ур. %d" % player.level
	_xp_bar.queue_redraw()
	# В стройке внизу карточки турелей — умения прячем
	if _ability_row:
		_ability_row.visible = not building
	for slot in _ability_slots:
		slot.queue_redraw()


func _draw_hero_bar() -> void:
	var size := _hero_bar.size
	var rect := Rect2(Vector2.ZERO, size)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.08, 0.07, 0.07)
	frame.set_corner_radius_all(5)
	_hero_bar.draw_style_box(frame, rect)
	var inner := rect.grow(-3)
	var hp: float = player.hp / player.hp_max if player else 1.0
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(3)
	if _hero_shown > hp:
		fill.bg_color = Color(1.0, 0.85, 0.7)
		_hero_bar.draw_style_box(fill, Rect2(inner.position, Vector2(inner.size.x * _hero_shown, inner.size.y)))
	if hp > 0.0:
		fill.bg_color = Color(0.82, 0.16, 0.14)
		var w := maxf(inner.size.x * hp, 6.0)
		_hero_bar.draw_style_box(fill, Rect2(inner.position, Vector2(w, inner.size.y)))
		_hero_bar.draw_rect(Rect2(inner.position + Vector2(3, 2), Vector2(maxf(w - 6, 0), 4)), Color(1, 0.5, 0.45, 0.5))


## Ранец: янтарная полоса топлива; мало — краснеет, пусто — мигает.
func _draw_fuel_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _fuel_bar.size)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.08, 0.07, 0.07)
	frame.set_corner_radius_all(4)
	_fuel_bar.draw_style_box(frame, rect)
	var fuel: float = player.fuel if player else 1.0
	var inner := rect.grow(-2)
	var col := Color(1.0, 0.72, 0.25) if fuel > 0.25 else Color(1.0, 0.36, 0.18)
	if fuel <= 0.0:
		col.a = 0.35 + 0.65 * absf(sin(Time.get_ticks_msec() / 160.0))
		_fuel_bar.draw_rect(inner, col * Color(1, 1, 1, 0.35))
	elif fuel > 0.0:
		var fill := StyleBoxFlat.new()
		fill.set_corner_radius_all(3)
		fill.bg_color = col
		_fuel_bar.draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.x * fuel, 4.0), inner.size.y)))


func _draw_xp() -> void:
	var size := _xp_bar.size
	var rect := Rect2(Vector2(0, (size.y - 14) / 2), Vector2(size.x, 14))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.08, 0.07, 0.07)
	frame.set_corner_radius_all(4)
	_xp_bar.draw_style_box(frame, rect)
	if not player:
		return
	var k := clampf(float(player.xp) / player.xp_needed(), 0.0, 1.0) if player.level < player.MAX_LEVEL else 1.0
	var inner := rect.grow(-2)
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(3)
	fill.bg_color = GOLD
	if k > 0.0:
		_xp_bar.draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.x * k, 4.0), inner.size.y)))


## Портрет героя: ромб в золотой рамке, внутри — голова в капюшоне (лицо в тени, глаза
## светятся); сбит — портрет серый.
func _draw_portrait(c: Control) -> void:
	var s := c.size
	var m := s / 2
	var gone: bool = player != null and player.down_left > 0.0
	var diamond := PackedVector2Array([m + Vector2(0, -s.y * 0.5), m + Vector2(s.x * 0.5, 0), m + Vector2(0, s.y * 0.5), m + Vector2(-s.x * 0.5, 0)])
	c.draw_colored_polygon(diamond, GOLD.darkened(0.3))
	var inner := PackedVector2Array()
	for p in diamond:
		inner.append(m + (p - m) * 0.86)
	c.draw_colored_polygon(inner, Color(0.3, 0.2, 0.17) if not gone else Color(0.25, 0.25, 0.25))
	var cloak := Color(0.55, 0.13, 0.1) if not gone else Color(0.4, 0.4, 0.4)
	var hood := Color(0.2, 0.18, 0.18) if not gone else Color(0.35, 0.35, 0.35)
	# Плечи в красном плаще и капюшон
	c.draw_colored_polygon(PackedVector2Array([m + Vector2(-s.x * 0.3, s.y * 0.3), m + Vector2(s.x * 0.3, s.y * 0.3),
		m + Vector2(s.x * 0.15, s.y * 0.08), m + Vector2(-s.x * 0.15, s.y * 0.08)]), cloak)
	c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s.y * 0.3), m + Vector2(s.x * 0.18, -s.y * 0.02),
		m + Vector2(s.x * 0.15, s.y * 0.14), m + Vector2(-s.x * 0.15, s.y * 0.14), m + Vector2(-s.x * 0.18, -s.y * 0.02)]), hood)
	c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s.y * 0.12), m + Vector2(s.x * 0.1, 0),
		m + Vector2(s.x * 0.08, s.y * 0.1), m + Vector2(-s.x * 0.08, s.y * 0.1), m + Vector2(-s.x * 0.1, 0)]), Color(0.06, 0.05, 0.05))
	if not gone:
		for sx in [-1.0, 1.0]:
			c.draw_circle(m + Vector2(sx * s.x * 0.04, -s.y * 0.01), 1.6, Color(1.0, 0.75, 0.35))


## Череп — счётчик убитых.
func _draw_skull(c: Control) -> void:
	var s := c.size
	var m := Vector2(s.x * 0.5, s.y * 0.44)
	var bone := Color(0.95, 0.94, 0.9)
	c.draw_circle(m, s.x * 0.34, bone)
	c.draw_rect(Rect2(m.x - s.x * 0.2, m.y + s.y * 0.12, s.x * 0.4, s.y * 0.26), bone)
	for sx in [-1.0, 1.0]:
		c.draw_circle(m + Vector2(sx * s.x * 0.13, s.y * 0.02), s.x * 0.1, PANEL)
	c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, s.y * 0.1), m + Vector2(-s.x * 0.05, s.y * 0.2),
		m + Vector2(s.x * 0.05, s.y * 0.2)]), PANEL)
	for k in 3:
		c.draw_rect(Rect2(m.x - s.x * 0.13 + k * s.x * 0.1, m.y + s.y * 0.28, s.x * 0.03, s.y * 0.1), PANEL)


## Квадрат умения: рамка (готово — золотая), значок, шторка перезарядки с секундами, клавиша.
## Слот умения: круглая иконка (ui/icons). Закрыто — тёмная, с замком и ценой; перезарядка —
## тёмный сектор по часовой и секунды; готово — золотое кольцо.
func _draw_ability(c: Control, i: int) -> void:
	var box := Rect2(Vector2(2, 2), Vector2(72, 72))
	var m := box.get_center()
	var r := 35.0
	var info: Dictionary = abilities.ABILITIES[i]
	var k: float = abilities.progress(i)
	var open: bool = abilities.is_open(i)
	var ready := open and k >= 1.0
	c.draw_circle(m, r + 3.0, Color(0, 0, 0, 0.55))
	if info["tex"] != "":
		var tex: Texture2D = _ability_tex(info["tex"])
		c.draw_texture_rect(tex, Rect2(m - Vector2(r, r), Vector2(r, r) * 2.0), false,
			Color(1, 1, 1) if open else Color(0.32, 0.32, 0.34))
	else:
		_draw_strike_icon(c, m, r, info["icon"], open)
	if not open:
		# Замок и цена в трофеях: золотая — уже по карману (покупка — U, «Прокачка»)
		c.draw_rect(Rect2(m + Vector2(-11, -2), Vector2(22, 16)), Color(0.82, 0.82, 0.85))
		c.draw_arc(m + Vector2(0, -3), 7.0, PI, TAU, 12, Color(0.82, 0.82, 0.85), 3.5)
		var id: String = info["id"]
		c.draw_string_outline(_font, Vector2(box.position.x, box.end.y - 3), str(Upgrades.cost_at(id)),
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, 4, Color(0, 0, 0, 0.8))
		c.draw_string(_font, Vector2(box.position.x, box.end.y - 3), str(Upgrades.cost_at(id)),
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, GOLD if Upgrades.can_buy(id) else Color(1, 1, 1, 0.55))
	elif not ready:
		# Перезарядка: тёмный сектор на оставшуюся долю
		var pts := PackedVector2Array([m])
		var steps := 32
		for s in steps + 1:
			var a := -PI / 2.0 + TAU * k + TAU * (1.0 - k) * s / steps
			pts.append(m + Vector2.from_angle(a) * r)
		if pts.size() >= 3 and k < 0.999:
			c.draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
		c.draw_string_outline(_font, Vector2(box.position.x, m.y + 9), str(ceili(abilities.seconds_left(i))),
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 26, 5, Color(0, 0, 0, 0.8))
		c.draw_string(_font, Vector2(box.position.x, m.y + 9), str(ceili(abilities.seconds_left(i))),
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 26, TEXT)
	if ready:
		c.draw_arc(m, r + 1.5, 0.0, TAU, 40, GOLD, 3.0, true)
	var key_box := Rect2(Vector2(26, 78), Vector2(24, 22))
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(0.08, 0.07, 0.07, 0.9)
	ks.set_corner_radius_all(4)
	c.draw_style_box(ks, key_box)
	c.draw_string(_font, key_box.position + Vector2(0, 17), info["letter"], HORIZONTAL_ALIGNMENT_CENTER, 24, 16,
		GOLD if open else Color(1, 1, 1, 0.4))


## Значки ударов с неба (картинок для них нет — рисуются фигурами): небо-круг, сверху — что падает.
func _draw_strike_icon(c: Control, m: Vector2, r: float, icon: String, open: bool) -> void:
	var dim := 1.0 if open else 0.35
	var sky := {"airstrike": Color(0.55, 0.22, 0.08), "rocketrain": Color(0.35, 0.1, 0.1), "orbital": Color(0.08, 0.2, 0.38)}
	var base: Color = sky.get(icon, Color(0.2, 0.2, 0.2))
	for k in 6:
		c.draw_circle(m, r - k * 4.0, base.lightened(k * 0.06).darkened(1.0 - dim))
	var w := Color(1, 1, 1, dim)
	match icon:
		"airstrike":
			# Самолёт сверху и три огненные капли под ним
			var p := m + Vector2(0, -12)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(4, 0), p + Vector2(18, 4),
				p + Vector2(4, 6), p + Vector2(3, 12), p + Vector2(-3, 12), p + Vector2(-4, 6), p + Vector2(-18, 4),
				p + Vector2(-4, 0)]), Color(0.85, 0.88, 0.85, dim))
			for k in 3:
				var q := m + Vector2(-10 + k * 10, 12 + (k % 2) * 4)
				c.draw_circle(q, 5.0, Color(1.0, 0.55, 0.1, dim))
				c.draw_circle(q + Vector2(0, -1), 2.5, Color(1.0, 0.9, 0.4, dim))
		"rocketrain":
			# Три ракеты наискось вниз с хвостами
			for k in 3:
				var tip := m + Vector2(-12 + k * 12, 10 + (k % 2) * -6)
				var tail := tip + Vector2(-9, -16)
				c.draw_line(tail + Vector2(-6, -10), tail, Color(1.0, 0.7, 0.3, 0.6 * dim), 4.0)
				c.draw_line(tail, tip, w, 5.0)
				c.draw_circle(tip, 3.0, Color(1.0, 0.3, 0.2, dim))
		"orbital":
			# Столб света сверху до земли и кольцо удара
			c.draw_rect(Rect2(m.x - 7, m.y - r + 4, 14, r + 8), Color(0.4, 0.85, 1.0, 0.55 * dim))
			c.draw_rect(Rect2(m.x - 3, m.y - r + 4, 6, r + 8), w)
			c.draw_arc(m + Vector2(0, 12), 13.0, 0.0, TAU, 24, Color(0.5, 0.9, 1.0, dim), 3.0, true)


var _ability_textures := {}


func _ability_tex(path: String) -> Texture2D:
	if not _ability_textures.has(path):
		_ability_textures[path] = load(path)
	return _ability_textures[path]


# --- рисунки --------------------------------------------------------------------------------

## Полоса здоровья ворот: тёмная рамка, красная заливка с бликом, светлый «след» урона.
func _draw_bar() -> void:
	var size := _bar.size
	var rect := Rect2(Vector2(0, (size.y - 24) / 2), Vector2(size.x, 24))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.08, 0.07, 0.07)
	frame.set_corner_radius_all(6)
	_bar.draw_style_box(frame, rect)
	var inner := rect.grow(-3)
	var hp: float = float(waves.gate_hp) / waves.gate_max
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(4)
	if _shown_hp > hp:
		fill.bg_color = Color(1.0, 0.85, 0.7)
		_bar.draw_style_box(fill, Rect2(inner.position, Vector2(inner.size.x * _shown_hp, inner.size.y)))
	if hp > 0.0:
		fill.bg_color = RED.lerp(Color(1, 0.6, 0.55), _hit_flash * 0.6)
		var w := maxf(inner.size.x * hp, 8.0)
		_bar.draw_style_box(fill, Rect2(inner.position, Vector2(w, inner.size.y)))
		_bar.draw_rect(Rect2(inner.position + Vector2(4, 3), Vector2(maxf(w - 8, 0), 4)), Color(1, 0.55, 0.5, 0.55))


## Иконка ворот: две башни с зубцами, стена между ними и арка ворот. У туннеля — каменная арка
## с тёмным проёмом.
func _draw_castle(c: Control) -> void:
	var s := c.size
	var white := Color(0.95, 0.94, 0.92)
	if tunnel:
		var m := Vector2(s.x * 0.5, s.y * 0.62)
		var pts := PackedVector2Array()
		for k in 13:
			var a := PI + PI * k / 12.0
			pts.append(m + Vector2(cos(a), sin(a)) * s.x * 0.46)
		pts.append(m + Vector2(s.x * 0.46, s.y * 0.34))
		pts.append(m + Vector2(-s.x * 0.46, s.y * 0.34))
		c.draw_colored_polygon(pts, white)
		var hole := PackedVector2Array()
		for k in 13:
			var a := PI + PI * k / 12.0
			hole.append(m + Vector2(cos(a), sin(a)) * s.x * 0.27)
		hole.append(m + Vector2(s.x * 0.27, s.y * 0.34))
		hole.append(m + Vector2(-s.x * 0.27, s.y * 0.34))
		c.draw_colored_polygon(hole, PANEL)
		return
	# Стена между башнями
	c.draw_rect(Rect2(s.x * 0.22, s.y * 0.36, s.x * 0.56, s.y * 0.56), white)
	for k in 2:
		c.draw_rect(Rect2(s.x * (0.38 + k * 0.14), s.y * 0.28, s.x * 0.08, s.y * 0.1), white)
	# Башни с зубцами
	for x in [0.06, 0.68]:
		c.draw_rect(Rect2(s.x * x, s.y * 0.22, s.x * 0.26, s.y * 0.7), white)
		for k in 3:
			c.draw_rect(Rect2(s.x * (x + k * 0.09), s.y * 0.1, s.x * 0.08, s.y * 0.14), white)
		c.draw_rect(Rect2(s.x * (x + 0.1), s.y * 0.36, s.x * 0.06, s.y * 0.12), PANEL)
	# Арка ворот
	c.draw_rect(Rect2(s.x * 0.38, s.y * 0.62, s.x * 0.24, s.y * 0.3), PANEL)
	c.draw_circle(Vector2(s.x * 0.5, s.y * 0.62), s.x * 0.12, PANEL)


## Иконка монеты: золотой кружок с ободком и бликом.
func _draw_coin(c: Control) -> void:
	var center := c.size / 2
	var r := minf(c.size.x, c.size.y) * 0.45
	c.draw_circle(center, r, Color(0.78, 0.5, 0.1))
	c.draw_circle(center, r * 0.86, GOLD)
	c.draw_circle(center, r * 0.6, Color(1.0, 0.82, 0.35))
	c.draw_arc(center, r * 0.6, PI * 1.1, PI * 1.6, 12, Color(1, 0.96, 0.8), 2.5, true)


## Иконка зарядов: два латунных патрона, у огнемёта — капля огня, у гравипушки — чёрная
## сфера в фиолетовом ободке.
## Значок оружия в столбике: мушкетон — взрыв, огнемёт — пламя, гравипушка — воронка,
## миниган — блок стволов.
func _draw_weapon(c: Control, weapon_name: String) -> void:
	var m := c.size / 2
	match weapon_name:
		"Мушкетон":
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				c.draw_line(m + d * 5.0, m + d * (15.0 if k % 2 == 0 else 10.0), GOLD, 3.0, true)
			c.draw_circle(m, 5.0, Color(1, 0.55, 0.2))
		"Огнемёт":
			var pts := PackedVector2Array()
			for k in 14:
				var a := lerpf(-PI * 0.5, PI * 1.5, k / 13.0)
				var p := Vector2(cos(a) * 9.0, sin(a) * 8.0)
				if p.y < 0.0:
					p.x *= 1.0 + p.y / 10.0
					p.y *= 2.0
				pts.append(m + Vector2(0, 5) + p)
			c.draw_colored_polygon(pts, Color(1, 0.5, 0.15))
			c.draw_circle(m + Vector2(0, 7), 4.0, GOLD)
		"Гравипушка":
			for k in 3:
				c.draw_arc(m, 14.0 - k * 4.5, k * 1.1, k * 1.1 + PI * 1.4, 16, Color(0.72, 0.5, 1.0), 2.5, true)
			c.draw_circle(m, 3.0, Color(0.1, 0.05, 0.15))
		"Миниган":
			for k in 3:
				c.draw_rect(Rect2(m.x - 14.0, m.y - 8.0 + k * 6.0, 26.0, 3.5), Color(0.75, 0.75, 0.8))
			c.draw_rect(Rect2(m.x - 4.0, m.y - 10.0, 5.0, 20.0), GOLD)
		"Электропушка":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(3, -13), m + Vector2(-8, 2), m + Vector2(0, 2),
				m + Vector2(-4, 13), m + Vector2(9, -3), m + Vector2(1, -3)]), Color(0.45, 0.75, 1.0))
		"Молот":
			_draw_hammer(c, m, 1.0)


## Молот: серая голова с ромбом и деревянная рукоять наискось (иконка в стопке и у патронов).
func _draw_hammer(c: Control, m: Vector2, k: float) -> void:
	var dir := Vector2(0.55, -0.83)
	var side := Vector2(dir.y, -dir.x)
	c.draw_line(m - dir * 13.0 * k, m + dir * 6.0 * k, Color(0.62, 0.36, 0.2), 4.0 * k)
	var head := m + dir * 8.0 * k
	var pts := PackedVector2Array([head + side * 11.0 * k + dir * 5.0 * k, head - side * 11.0 * k + dir * 5.0 * k,
		head - side * 11.0 * k - dir * 5.0 * k, head + side * 11.0 * k - dir * 5.0 * k])
	c.draw_colored_polygon(pts, Color(0.62, 0.62, 0.68))
	c.draw_circle(head, 2.5 * k, Color(0.85, 0.85, 0.9))


func _draw_ammo(c: Control) -> void:
	var s := c.size
	if gun and gun.ammo_kind == "melee":
		_draw_hammer(c, s * 0.5, s.x / 34.0)
		return
	if gun and gun.ammo_kind == "charge":
		var mid := Vector2(s.x * 0.5, s.y * 0.55)
		var r := s.x * 0.42
		c.draw_circle(mid, r, Color(0.55, 0.25, 1.0))
		c.draw_circle(mid, r * 0.78, Color(0.85, 0.7, 1.0))
		c.draw_circle(mid, r * 0.62, Color(0.05, 0.03, 0.08))
		c.draw_arc(mid, r * 0.95, PI * 1.1, PI * 1.6, 10, Color(1, 1, 1, 0.8), 2.0, true)
		return
	if gun and gun.ammo_kind == "energy":
		# Электропушка: голубая молния
		var pts := PackedVector2Array([Vector2(s.x * 0.62, s.y * 0.05), Vector2(s.x * 0.22, s.y * 0.55),
			Vector2(s.x * 0.48, s.y * 0.55), Vector2(s.x * 0.36, s.y * 0.98), Vector2(s.x * 0.8, s.y * 0.4),
			Vector2(s.x * 0.54, s.y * 0.4)])
		c.draw_colored_polygon(pts, Color(0.45, 0.75, 1.0))
		return
	if gun and gun.ammo_kind == "fuel":
		var center := Vector2(s.x * 0.5, s.y * 0.62)
		c.draw_circle(center, s.x * 0.36, Color(0.95, 0.4, 0.1))
		c.draw_colored_polygon(PackedVector2Array([center + Vector2(-s.x * 0.34, -s.y * 0.06),
			Vector2(s.x * 0.5, s.y * 0.06), center + Vector2(s.x * 0.34, -s.y * 0.06)]), Color(0.95, 0.4, 0.1))
		c.draw_circle(center + Vector2(0, s.y * 0.05), s.x * 0.18, Color(1.0, 0.82, 0.35))
		return
	for k in 2:
		var x := s.x * (0.12 + k * 0.44)
		var w := s.x * 0.34
		var body := Rect2(x, s.y * 0.35, w, s.y * 0.55)
		c.draw_rect(body, Color(0.9, 0.72, 0.38))
		c.draw_rect(Rect2(x, s.y * 0.8, w, s.y * 0.1), Color(0.7, 0.52, 0.25))
		# Скруглённая пуля сверху
		c.draw_circle(Vector2(x + w / 2, s.y * 0.33), w / 2, Color(0.95, 0.85, 0.65))
		c.draw_rect(Rect2(x, s.y * 0.3, w, s.y * 0.06), Color(0.95, 0.85, 0.65))
