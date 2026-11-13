extends CanvasLayer
## Главное меню и пауза. Слева — тёмная полоса с эмблемой (жук в золотом кольце), названием
## и кнопками; справа виден живой бой (его показывает main.gd). Те же плашки и шрифт, что в
## интерфейсе боя. Внутри — экраны «Настройки» и «Управление».
## Работает и на паузе (process_mode = ALWAYS).

const Lang := preload("res://core/lang.gd")

signal play_pressed
## Выбрана открытая локация из списка.
signal level_chosen(index: int)
signal resume_pressed
signal menu_pressed
signal quit_pressed

const Settings := preload("res://core/settings.gd")
const Levels := preload("res://locations/levels.gd")
const Progress := preload("res://core/progress.gd")
const UpgradeTree := preload("res://ui/upgrade_tree.gd")

const TITLE := "GATEHOLD"
const SUBTITLE := "Орда идёт. Держи оборону."
const VERSION := "v0.1 · ранняя сборка"
const GOLD := Color(0.98, 0.74, 0.22)
const GOLD_DARK := Color(0.55, 0.33, 0.08)
const ORANGE := Color(0.93, 0.48, 0.18)
const PANEL := Color(0.12, 0.1, 0.09, 0.86)
const PANEL_EDGE := Color(0.36, 0.31, 0.27, 0.95)
const TEXT := Color(1, 1, 1)
const CONTROLS := [
	["ЛКМ", "выстрел (миниган и электропушку — держать)"], ["Q E R", "умения: ракетный залп, напалм, боевой дрон"], ["T", "перезарядить"], ["1–6, колесо", "сменить оружие"],
	["Enter", "выпустить орду"], ["B", "стройка (ЛКМ — поставить или улучшить, ПКМ — убрать в запас)"], ["U", "прокачка"], ["Пробел", "взлететь на ранце, в воздухе — выше"],
	["WASD, Shift", "лететь (на земле — идти), в воздухе Shift — ниже"], ["H", "вернуться на стену или вышку"],
	["Tab", "вид сверху"], ["Esc", "пауза"],
]

## «main» — главное меню, «pause» — пауза в бою.
var mode := "main"

var _font: SystemFont
var _title_font: FontVariation
var _shade: TextureRect
var _dim: ColorRect
var _column: VBoxContainer
var _pages := {}
var _first_button := {}
var _version: Label
var _emblem: Control
var _left: Control
var _tree: Control
var _level_buttons: Array[Button] = []
var _level_info: Label
var _hint: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Arial"])
	_font.font_weight = 700
	var heavy := SystemFont.new()
	heavy.font_names = _font.font_names
	heavy.font_weight = 900
	_title_font = FontVariation.new()
	_title_font.base_font = heavy
	_title_font.spacing_glyph = 6
	# Затемнение: в меню — слева направо, на паузе — весь экран
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.32, 0.62, 1.0])
	grad.colors = PackedColorArray([Color(0.07, 0.05, 0.04, 0.92), Color(0.08, 0.05, 0.04, 0.78),
		Color(0.08, 0.05, 0.04, 0.0), Color(0.08, 0.05, 0.04, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_to = Vector2(1, 0)
	_shade = TextureRect.new()
	_shade.texture = tex
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.04, 0.03, 0.78)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	# Левая колонка: эмблема, название, страница (кнопки / настройки / управление)
	var margin := MarginContainer.new()
	_left = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.custom_minimum_size.x = 620
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 70)
	add_child(margin)
	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 14)
	margin.add_child(_column)
	_column.add_child(_logo())
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	_column.add_child(gap)
	_pages["main"] = _button_page("main", [["Играть", show_page.bind("levels")], ["Прокачка", show_page.bind("upgrades")],
		["Настройки", show_page.bind("settings")],
		["Управление", show_page.bind("controls")], ["Выход", quit_pressed.emit]])
	_pages["pause"] = _button_page("pause", [["Продолжить", resume_pressed.emit], ["Прокачка", show_page.bind("upgrades")],
		["Настройки", show_page.bind("settings")],
		["Управление", show_page.bind("controls")], ["В главное меню", menu_pressed.emit], ["Выход", quit_pressed.emit]])
	_pages["levels"] = _levels_page()
	_pages["settings"] = _settings_page()
	_pages["controls"] = _controls_page()
	for page in _pages.values():
		_column.add_child(page)
	# Древо прокачки — на весь экран, поверх всего
	_tree = UpgradeTree.new()
	_tree.font = _font
	_tree.title_font = _title_font
	_tree.back_pressed.connect(func() -> void: show_page(mode))
	add_child(_tree)
	_pages["upgrades"] = _tree
	_version = _label(15, Color(1, 1, 1, 0.45))
	_version.text = VERSION
	_version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.position += Vector2(96, -28)
	add_child(_version)
	_hint = _label(17, Color(1, 1, 1, 0.7))
	_hint.text = "Enter — играть"
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position += Vector2(-36, -28)
	add_child(_hint)


## Показать меню: mode — «main» или «pause».
func open(menu_mode: String) -> void:
	mode = menu_mode
	visible = true
	_shade.visible = mode == "main"
	_dim.visible = mode == "pause"
	_hint.visible = mode == "main"
	_version.visible = mode == "main"
	show_page(mode)


func close() -> void:
	visible = false


func show_page(page: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page
	# Список локаций высокий — эмблему над названием прячем; древо — на весь экран вместо колонки
	_emblem.visible = page != "levels"
	_left.visible = page != "upgrades"
	_hint.visible = mode == "main" and page != "upgrades"
	_version.visible = mode == "main" and page != "upgrades"
	if page == "levels":
		_refresh_levels()
	if page == "upgrades":
		_tree.refresh()
	if _first_button.has(page):
		_first_button[page].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not _pages[mode].visible:
			show_page(mode)
		elif mode == "pause":
			resume_pressed.emit()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and mode == "main" and _pages["main"].visible:
		get_viewport().set_input_as_handled()
		play_pressed.emit()


# --- страницы ------------------------------------------------------------------------------

func _button_page(key: String, items: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	for item in items:
		var b := _button(item[0])
		b.pressed.connect(item[1])
		box.add_child(b)
	_first_button[key] = box.get_child(0)
	return box


## Выбор локации: 10 кнопок в два столбца (закрытые — тусклые, с замком), под ними описание
## той, на которую наведена мышь.
func _levels_page() -> VBoxContainer:
	var box := _card("Локации")
	var inner: VBoxContainer = box.get_meta("inner")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	inner.add_child(grid)
	for i in Levels.count():
		var b := _button("")
		b.custom_minimum_size = Vector2(250, 46)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", _style(PANEL, PANEL_EDGE, 2, 14))
		b.add_theme_stylebox_override("disabled", _style(Color(0.08, 0.07, 0.06, 0.75), Color(0.2, 0.18, 0.16), 2, 14))
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
		b.pressed.connect(level_chosen.emit.bind(i))
		b.mouse_entered.connect(_show_level_info.bind(i))
		b.focus_entered.connect(_show_level_info.bind(i))
		grid.add_child(b)
		_level_buttons.append(b)
	_level_info = _label(17, Color(1, 0.93, 0.8))
	_level_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_info.custom_minimum_size = Vector2(510, 48)
	inner.add_child(_level_info)
	var back := _button("Назад")
	back.pressed.connect(show_page.bind(mode))
	box.add_child(back)
	return box


func _refresh_levels() -> void:
	Progress.load_progress()
	for i in _level_buttons.size():
		var b := _level_buttons[i]
		var open := Progress.is_unlocked(i)
		var got := int(Progress.stars.get(i, 0))
		var mark := "  " + "★".repeat(got) + "☆".repeat(3 - got) if Progress.is_completed(i) else ""
		b.text = "%d. %s%s" % [i + 1, Levels.get_level(i)["name"], mark] if open else "%d. закрыто" % (i + 1)
		b.disabled = not open
	var first := _level_buttons[Progress.last_unlocked()]
	first.grab_focus.call_deferred()
	_show_level_info(Progress.last_unlocked())


func _show_level_info(i: int) -> void:
	var level: Dictionary = Levels.get_level(i)
	if Progress.is_unlocked(i):
		var stars := "★".repeat(clampi(int(round((level["difficulty"] - 1.2) / 0.75)) + 1, 1, 6))
		var pat: Dictionary = load("res://core/waves.gd").PATTERNS.get(level.get("pattern", "steady"), {})
		_level_info.text = "%s\nНаступление: %s · Сложность %s" % [level["desc"], pat.get("name", "Ровный поток"), stars]
	else:
		_level_info.text = "Пройди «%s», чтобы открыть." % Levels.get_level(i - 1)["name"]


func _settings_page() -> VBoxContainer:
	var box := _card("Настройки")
	var inner: VBoxContainer = box.get_meta("inner")
	inner.add_child(_slider_row("Чувствительность мыши", 0.3, 2.5, Settings.sensitivity,
		func(v: float) -> void: Settings.sensitivity = v, func(v: float) -> String: return "%.1f×" % v))
	inner.add_child(_slider_row("Громкость", 0.0, 1.0, Settings.volume,
		func(v: float) -> void:
			Settings.volume = v
			Settings.apply(),
		func(v: float) -> String: return "%d%%" % int(round(v * 100))))
	inner.add_child(_slider_row("Музыка", 0.0, 1.0, Settings.music_volume,
		func(v: float) -> void:
			Settings.music_volume = v
			Settings.apply(),
		func(v: float) -> String: return "%d%%" % int(round(v * 100))))
	inner.add_child(_check_row("Полный экран", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply()))
	inner.add_child(_check_row("Показывать FPS", Settings.show_fps, func(on: bool) -> void: Settings.show_fps = on))
	inner.add_child(_cycle_row("Качество графики", Settings.QUALITY_NAMES, Settings.quality, func(i: int) -> void:
		Settings.quality = i
		Settings.apply()))
	inner.add_child(_cycle_row("Язык / Language", Lang.LANG_NAMES, maxi(Lang.LANGS.find(Lang.language), 0), func(i: int) -> void:
		Settings.language = Lang.LANGS[i]
		Settings.apply()
		Settings.save()))
	inner.add_child(_check_row("Авто-качество (держит FPS в большом бою)", Settings.auto_quality, func(on: bool) -> void:
		Settings.auto_quality = on
		Settings.apply()))
	var back := _button("Назад")
	back.pressed.connect(func() -> void:
		Settings.save()
		show_page(mode))
	box.add_child(back)
	_first_button["settings"] = back
	return box


func _controls_page() -> VBoxContainer:
	var box := _card("Управление")
	var inner: VBoxContainer = box.get_meta("inner")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	for row in CONTROLS:
		var key := _label(19, GOLD)
		key.text = row[0]
		grid.add_child(key)
		var what := _label(19, TEXT)
		what.text = row[1]
		grid.add_child(what)
	inner.add_child(grid)
	var back := _button("Назад")
	back.pressed.connect(show_page.bind(mode))
	box.add_child(back)
	_first_button["controls"] = back
	return box


## Карточка с заголовком: тёмная плашка, внутри — столбец для строк (в meta «inner»).
func _card(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, PANEL_EDGE, 2, 18))
	box.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	panel.add_child(inner)
	var head := _label(30, GOLD)
	head.text = title
	inner.add_child(head)
	box.set_meta("inner", inner)
	return box


func _slider_row(title: String, lo: float, hi: float, value: float, on_change: Callable, fmt: Callable) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	var name := _label(20, TEXT)
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var shown := _label(20, GOLD)
	shown.text = fmt.call(value)
	top.add_child(shown)
	row.add_child(top)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(420, 26)
	slider.add_theme_stylebox_override("slider", _style(Color(0.06, 0.05, 0.05), Color(0, 0, 0, 0), 0, 6, 6))
	slider.add_theme_stylebox_override("grabber_area", _style(ORANGE, Color(0, 0, 0, 0), 0, 6, 6))
	slider.add_theme_stylebox_override("grabber_area_highlight", _style(GOLD, Color(0, 0, 0, 0), 0, 6, 6))
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		shown.text = fmt.call(v))
	row.add_child(slider)
	return row


## Строка выбора: название слева, справа кнопка с текущим вариантом — клик листает варианты.
func _cycle_row(title: String, options: Array, index: int, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := _label(20, TEXT)
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var pick := Button.new()
	pick.custom_minimum_size = Vector2(150, 36)
	pick.add_theme_font_override("font", _font)
	pick.add_theme_font_size_override("font_size", 18)
	pick.add_theme_color_override("font_color", TEXT)
	pick.add_theme_color_override("font_hover_color", GOLD)
	pick.add_theme_stylebox_override("normal", _style(ORANGE.darkened(0.15), GOLD, 2, 14, 18))
	pick.add_theme_stylebox_override("hover", _style(ORANGE, GOLD, 2, 14, 18))
	pick.add_theme_stylebox_override("pressed", _style(ORANGE, GOLD, 2, 14, 18))
	pick.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pick.text = options[index]
	var current := [index]
	pick.pressed.connect(func() -> void:
		current[0] = (current[0] + 1) % options.size()
		pick.text = options[current[0]]
		on_change.call(current[0]))
	row.add_child(pick)
	return row


## Строка-переключатель: название слева, справа кнопка «Вкл» (оранжевая) или «Выкл».
func _check_row(title: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name := _label(20, TEXT)
	name.text = title
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = value
	toggle.custom_minimum_size = Vector2(112, 36)
	toggle.add_theme_font_override("font", _font)
	toggle.add_theme_font_size_override("font_size", 18)
	toggle.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	toggle.add_theme_color_override("font_pressed_color", TEXT)
	toggle.add_theme_color_override("font_hover_pressed_color", TEXT)
	toggle.add_theme_color_override("font_hover_color", GOLD)
	toggle.add_theme_stylebox_override("normal", _style(Color(0.06, 0.05, 0.05), PANEL_EDGE, 2, 14, 18))
	toggle.add_theme_stylebox_override("hover", _style(Color(0.1, 0.07, 0.05), ORANGE, 2, 14, 18))
	toggle.add_theme_stylebox_override("pressed", _style(ORANGE.darkened(0.15), GOLD, 2, 14, 18))
	toggle.add_theme_stylebox_override("hover_pressed", _style(ORANGE, GOLD, 2, 14, 18))
	toggle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	toggle.text = "Вкл" if value else "Выкл"
	toggle.toggled.connect(func(on: bool) -> void:
		toggle.text = "Вкл" if on else "Выкл"
		on_change.call(on))
	row.add_child(toggle)
	return row


# --- элементы ------------------------------------------------------------------------------

## Эмблема и название: жук в золотом кольце, крупное золотое имя с тёмной обводкой, подзаголовок.
func _logo() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var emblem := Control.new()
	emblem.custom_minimum_size = Vector2(110, 110)
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	emblem.draw.connect(_draw_emblem.bind(emblem))
	box.add_child(emblem)
	_emblem = emblem
	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_override("font", _title_font)
	title.add_theme_font_size_override("font_size", 86)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_constant_override("outline_size", 16)
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.09, 0.03))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 6)
	box.add_child(title)
	var line := ColorRect.new()
	line.color = GOLD
	line.custom_minimum_size = Vector2(420, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(line)
	var sub := _label(24, Color(1, 0.93, 0.8))
	sub.text = SUBTITLE
	box.add_child(sub)
	return box


## Эмблема: в золотом кольце — голова нашего гоблина (кубик с ушами и чёрными глазами), за ней
## наискосок — ракета героя.
func _draw_emblem(c: Control) -> void:
	var center := c.size / 2
	var r := minf(c.size.x, c.size.y) * 0.47
	c.draw_circle(center, r, Color(0.16, 0.1, 0.06, 0.95))
	c.draw_arc(center, r, 0.0, TAU, 64, GOLD, 5.0, true)
	c.draw_arc(center, r - 9.0, 0.0, TAU, 64, GOLD_DARK, 2.0, true)
	var s := r / 50.0
	# Ракета наискосок: оливковая труба, красная боеголовка, хвост пламени
	var dir := Vector2(1, -1).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tail := center - dir * 34.0 * s
	var head := center + dir * 26.0 * s
	var tube := PackedVector2Array([tail + side * 6.0 * s, head + side * 6.0 * s, head - side * 6.0 * s, tail - side * 6.0 * s])
	c.draw_colored_polygon(tube, Color(0.42, 0.45, 0.24))
	c.draw_colored_polygon(PackedVector2Array([head + side * 6.0 * s, head + dir * 12.0 * s, head - side * 6.0 * s]),
		Color(0.8, 0.18, 0.12))
	c.draw_colored_polygon(PackedVector2Array([tail + side * 5.0 * s, tail - side * 5.0 * s, tail - dir * 13.0 * s]),
		Color(1.0, 0.62, 0.2))
	# Голова гоблина: зелёный кубик, уши в стороны, два тёмных глаза
	var skin := Color(0.44, 0.63, 0.25)
	var skin_dark := Color(0.33, 0.48, 0.18)
	for sx in [-1.0, 1.0]:
		c.draw_colored_polygon(PackedVector2Array([center + Vector2(sx * 14.0, -8.0) * s, center + Vector2(sx * 40.0, -20.0) * s,
			center + Vector2(sx * 14.0, 4.0) * s]), skin_dark)
	var face := Rect2(center + Vector2(-17.0, -20.0) * s, Vector2(34.0, 32.0) * s)
	c.draw_rect(face.grow(2.0 * s), Color(0.12, 0.08, 0.05))
	c.draw_rect(face, skin)
	c.draw_rect(Rect2(face.position, Vector2(face.size.x, 6.0 * s)), skin.lightened(0.15))
	for sx in [-1.0, 1.0]:
		c.draw_rect(Rect2(center + Vector2(sx * 7.5 - 3.0, -8.0) * s, Vector2(6.0, 8.0) * s), Color(0.1, 0.08, 0.06))
	# Рубаха под головой
	c.draw_rect(Rect2(center + Vector2(-12.0, 13.0) * s, Vector2(24.0, 12.0) * s), Color(0.62, 0.58, 0.5))


func _ellipse(c: Control, center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	c.draw_colored_polygon(pts, color)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 27)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color(1, 0.85, 0.6))
	b.add_theme_stylebox_override("normal", _style(PANEL, PANEL_EDGE, 2, 26))
	b.add_theme_stylebox_override("hover", _style(Color(0.25, 0.14, 0.07, 0.95), ORANGE, 3, 34))
	b.add_theme_stylebox_override("focus", _style(Color(0.25, 0.14, 0.07, 0.95), ORANGE, 3, 34))
	b.add_theme_stylebox_override("pressed", _style(Color(0.35, 0.18, 0.07, 0.95), GOLD, 3, 34))
	b.mouse_entered.connect(b.grab_focus)
	return b


func _style(bg: Color, border: Color, width: int, left: float, radius := 12) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	st.content_margin_left = left
	st.content_margin_right = left if left < 20 else 22
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return st


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	return l
