extends Control
## Экран «Прокачка» — древо в духе исторических стратегий: на фоне — картина долины (ui/tree_bg.jpg,
## снимок первой локации), разделы (Герой, Ракетница, Турели, Добыча) стоят колонками, узлы —
## круглые медальоны со значками, связи — тонкие линии сверху вниз. Купленное горит золотым
## кольцом, доступное сейчас — светлое и мерцает, закрытое — тёмное с замком. В древе только то,
## что у игрока есть (upgrades.gd: is_shown). Наведи — подсказка, клик — купить, «Сбросить» —
## вернуть все трофеи. Вторая вкладка — «Оружие»: карточки оружия героя (картинка, что умеет,
## цена) — покупается за трофеи один раз и навсегда (upgrades.gd: WEAPONS).

const Lang := preload("res://core/lang.gd")

signal back_pressed

const Upgrades := preload("res://core/upgrades.gd")
const Mastery := preload("res://core/mastery.gd")
const Progress := preload("res://core/progress.gd")
const BG := preload("res://ui/tree_bg.jpg")
const Levels := preload("res://locations/levels.gd")

const DESIGN := Vector2(1600, 900)
const HEAD_Y := 192.0           # значок и название раздела
const TOP := 300.0              # первый ярус узлов
const DY := 122.0               # шаг ярусов
const COL_W := 108.0            # ширина колонки узлов (обычно)
const COL_W_MAX := 150.0        # на вкладках с немногими разделами — шире: подписи не налезают
## Вкладки: Герой, Способности, Турели — разделы общего древа (Upgrades.ROWS); «Улучшения оружия» —
## ракетница и ветки купленного оружия; «Оружие» — магазин.
const TAB_NAMES := ["Герой", "Способности", "Турели", "Улучшения оружия", "Оружие"]
const TAB_ROWS := [["hero"], ["skills", "strikes"], ["turrets", "spoils"]]
const WEAPONS_TAB := 3
const SHOP_TAB := 4
const TAB_HINTS := [
	"Ранец, броня и здоровье героя. Трофеи — за каждый бой, даже проигранный; ★ открывают дальние улучшения.",
	"Умения Q, E, R и удары с неба Z, X, C. ★ за пройденные локации открывают дальние улучшения.",
	"Запас турелей и баррикад, их сила, оборона ворот и добыча.",
	"Ракетница и ветка каждого купленного оружия. В конце — две финальные формы: выбери одну, вторая закроется.",
	"Новое оружие открывается за пройденные локации и покупается за трофеи — навсегда. В бою: клавиши 1–7 или колесо."]
const GAP := 22.0               # между разделами
const PAD := 10.0               # поля панели раздела
const R := 25.0                 # радиус медальона
const GOLD := Color(0.98, 0.76, 0.26)
const ORANGE := Color(0.93, 0.48, 0.18)
const PANEL := Color(0.1, 0.08, 0.07, 0.96)
const PANEL_EDGE := Color(0.36, 0.31, 0.27, 0.95)
const LINE_OPEN := Color(0.85, 0.82, 0.74, 0.75)
const LINE_SHUT := Color(0.42, 0.4, 0.37, 0.55)
const DIM := Color(0.42, 0.4, 0.38)
const VOID := Color(0.05, 0.04, 0.04)
const SHOP_COLUMNS := 7
const SHOP_MIN_CELLS := 14          # меньше оружия — остальные ячейки «Скоро»
const CARD_SIZE := Vector2(196, 212)
const GREEN := Color(0.55, 0.95, 0.55)

## Шрифты меню (задаёт menu.gd до добавления в сцену).
var font: Font
var title_font: Font

var _hover := ""
var _time := 0.0
var _flash := {}               # id узла → вспышка после покупки (1 → 0)
var _redraw_t := 0.0           # древо рисуется заново 20 раз в секунду (пульс), сразу — по событию
var _buttons := {}
var _tip: PanelContainer
var _tip_title: Label
var _tip_text: Label
var _counter: Label
var _back: Button
var _sub: Label
var _reset: Button
var _tab := 0
var _tab_buttons: Array[Button] = []
## Вкладка «Оружие»: сетка карточек (7 в ряд, прокрутка, если больше двух рядов) и под ней —
## панель выбранного оружия с описанием, ценой и кнопкой покупки.
var _shop: VBoxContainer
var _shop_grid: GridContainer
var _shop_info: PanelContainer
var _shop_sel := "rockets"         # выбранная карточка: "rockets", вид оружия из WEAPONS или "soon_N"
var _shop_cards := {}              # ключ → кнопка-карточка (рамка выделения)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := _label(50, GOLD, title_font)
	title.text = "ПРОКАЧКА"
	title.position = Vector2(60, 30)
	add_child(title)
	var sub := _label(17, Color(1, 0.93, 0.8))
	sub.position = Vector2(62, 96)
	add_child(sub)
	_sub = sub
	# Вкладки: древо и оружие
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.position = Vector2(440, 40)
	add_child(tabs)
	for i in TAB_NAMES.size():
		var b := _button(TAB_NAMES[i], 18, Vector2(0, 44))
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_counter = _label(30, GOLD)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_counter.position += Vector2(-60, 38)
	add_child(_counter)
	_build_tip()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.position += Vector2(-60, 92)
	add_child(row)
	var reset := _button("Сбросить всё", 20, Vector2(0, 46))
	reset.pressed.connect(func() -> void:
		Upgrades.reset()
		refresh())
	row.add_child(reset)
	_reset = reset
	_shop = VBoxContainer.new()
	_shop.add_theme_constant_override("separation", 14)
	_shop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop.offset_top = 168
	_shop.offset_bottom = -28
	_shop.offset_left = 40
	_shop.offset_right = -40
	_shop.visible = false
	add_child(_shop)
	# Сетка карточек — в прокрутке (появится, когда карточек больше двух рядов)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Ровно два ряда карточек (+ место под рамку выделения); больше — прокрутка вниз
	scroll.custom_minimum_size = Vector2(0, CARD_SIZE.y * 2 + 12 + 16)
	_shop.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_shop_grid = GridContainer.new()
	_shop_grid.columns = SHOP_COLUMNS
	_shop_grid.add_theme_constant_override("h_separation", 12)
	_shop_grid.add_theme_constant_override("v_separation", 12)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	center.add_child(pad)
	pad.add_child(_shop_grid)
	_shop_info = PanelContainer.new()
	# Панель описания — ровно по ширине сетки (на широких экранах не растягивается)
	_shop_info.custom_minimum_size = Vector2(CARD_SIZE.x * SHOP_COLUMNS + 12 * (SHOP_COLUMNS - 1), 196)
	_shop_info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_shop.add_child(_shop_info)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop.add_child(filler)
	_back = _button("Назад", 20, Vector2(150, 46))
	_back.pressed.connect(back_pressed.emit)
	row.add_child(_back)
	resized.connect(_layout)


## Показать заново: узлы, счётчик, фокус — на первый узел, который можно купить.
func refresh() -> void:
	# Покупка, сброс или другая вкладка — раскладку считаем заново (дальше она из кэша)
	_cache.clear()
	_rebuild_buttons()
	_rebuild_shop()
	_update_header()
	_set_hover("")
	for id: String in _buttons:
		_buttons[id].visible = _tab != SHOP_TAB and Upgrades.get_node(id)["row"] in _row_order()
	_shop.visible = _tab == SHOP_TAB
	_reset.visible = _tab < WEAPONS_TAB
	_sub.text = TAB_HINTS[_tab]
	for i in _tab_buttons.size():
		var picked := i == _tab
		_tab_buttons[i].add_theme_stylebox_override("normal", _style(Color(0.3, 0.17, 0.07, 0.95) if picked else PANEL,
			GOLD if picked else PANEL_EDGE, 2))
		_tab_buttons[i].add_theme_color_override("font_color", GOLD if picked else Color(1, 1, 1))
	var first: Control = _back
	if _tab == SHOP_TAB and _shop_cards.has(_shop_sel):
		first = _shop_cards[_shop_sel]
	if _tab != SHOP_TAB:
		for id: String in _buttons:
			if _buttons[id].visible and Upgrades.can_buy(id):
				first = _buttons[id]
				break
	first.grab_focus.call_deferred()
	# Фокус ставим для клавиатуры и геймпада, но подсказку при открытии не показываем — мышь её позовёт
	_set_hover.call_deferred("")
	queue_redraw()


func _select_tab(i: int) -> void:
	_tab = i
	refresh()


# --- вкладка «Оружие» -------------------------------------------------------------------------

## Карточки оружия: ракетница (есть всегда) и всё из Upgrades.WEAPONS — картинка, название,
## что умеет, цена; кнопка «Купить» или отметка, что уже твоё.
func _rebuild_shop() -> void:
	for c in _shop_grid.get_children():
		c.queue_free()
	_shop_cards.clear()
	var keys: Array[String] = ["rockets"]
	for item: String in Upgrades.WEAPONS:
		keys.append(item)
	# Пустые ячейки до полной сетки (не меньше двух рядов) — «Скоро»: место под новое оружие
	var cells := maxi(SHOP_MIN_CELLS, int(ceil(keys.size() / float(SHOP_COLUMNS))) * SHOP_COLUMNS)
	for k in range(keys.size(), cells):
		keys.append("soon_%d" % k)
	if not _shop_sel in keys:
		_shop_sel = "rockets"
	for key in keys:
		var card := _shop_card(key)
		_shop_grid.add_child(card)
		_shop_cards[key] = card
	_show_weapon(_shop_sel)


## Что известно о ячейке магазина: название, картинка, описание, характеристики, куплено ли.
func _shop_entry(key: String) -> Dictionary:
	if key == "rockets":
		return {"name": "Ракетница", "icon": "res://ui/icons/weapon_rockets.png", "owned": true, "item": "",
			"desc": "Главное оружие героя: ракета взрывается в толпе. Качается в разделе «Ракетница» на вкладке «Прокачка».",
			"stats": "Клавиша 1 · Взрыв по площади · 3 ракеты в стволе"}
	if key.begins_with("soon_"):
		return {"name": "Новое оружие", "icon": "", "owned": false, "item": "", "soon": true,
			"desc": "Новое оружие появится в следующих обновлениях.", "stats": "Новое оружие"}
	var w: Dictionary = Upgrades.WEAPONS[key]
	var after := int(w.get("after", -1))
	return {"name": w["name"], "icon": w["icon"], "owned": Upgrades.owns_weapon(key), "item": key,
		"desc": w["desc"], "stats": w["stats"], "cost": int(w["cost"]), "open": Upgrades.weapon_open(key),
		"after": after, "after_name": Levels.get_level(after)["name"] if after >= 0 else ""}


## Компактная карточка: витрина, название, внизу — цена или «Куплено». Клик (или фокус с
## клавиатуры/геймпада) выбирает её — описание и покупка в панели под сеткой.
func _shop_card(key: String) -> Button:
	var e := _shop_entry(key)
	var owned: bool = e["owned"]
	var soon: bool = e.get("soon", false)
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_ALL
	_style_card(b, key == _shop_sel, owned, soon)
	b.pressed.connect(_pick_weapon.bind(key))
	b.focus_entered.connect(_pick_weapon.bind(key))
	b.mouse_entered.connect(b.grab_focus)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	box.add_child(_showcase(_tex(e["icon"]) if e["icon"] != "" else null, owned, Vector2(176, 122), soon))
	var locked: bool = not owned and not soon and not e.get("open", true)
	var name_label := _label(18, GOLD if owned else (Color(0.78, 0.68, 0.45) if soon else Color(0.86, 0.82, 0.76)))
	name_label.text = e["name"]
	if locked:
		# Ещё не открыто: название не показываем — только где откроется
		name_label.text = "Откроется на"
		name_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		name_label.add_theme_font_size_override("font_size", 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	box.add_child(name_label)
	var foot := _label(16, GREEN)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if owned:
		foot.text = "✓ Куплено" if key != "rockets" else "✓ Твоё"
	elif soon:
		foot.text = "в обновлении"
		foot.add_theme_color_override("font_color", Color(0.5, 0.48, 0.44))
	elif locked:
		# Ещё не открыто: имя локации, которую надо пройти
		foot.text = "«%s»" % e["after_name"]
		foot.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		foot.clip_text = true
	else:
		var cost: int = e["cost"]
		foot.text = "🏆 %d" % cost
		foot.add_theme_color_override("font_color", GOLD if Progress.trophies >= cost else Color(1, 0.55, 0.45))
	box.add_child(foot)
	return b


## Рамки карточки: выбранная — жёлтая и толще; купленная — золотистая; закрытая — тёмно-серая.
func _style_card(b: Button, picked: bool, owned: bool, soon: bool) -> void:
	var bg := Color(0.09, 0.07, 0.06, 0.95) if owned else Color(0.06, 0.06, 0.07, 0.95)
	var edge := Color(GOLD, 0.7) if owned else Color(0.26, 0.26, 0.28, 0.9)
	if soon:
		bg = Color(0.05, 0.05, 0.055, 0.85)
		edge = Color(0.2, 0.2, 0.22, 0.8)
	var normal := _style(bg, Color(1.0, 0.86, 0.2) if picked else edge, 4 if picked else 2)
	var hover := _style(bg.lightened(0.06), Color(1.0, 0.86, 0.2) if picked else ORANGE, 4 if picked else 3)
	for st: StyleBoxFlat in [normal, hover]:
		st.content_margin_left = 0
		st.content_margin_right = 0
		if picked:
			st.shadow_color = Color(1.0, 0.75, 0.2, 0.35)
			st.shadow_size = 10
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)


## Выбрать карточку: жёлтая рамка на ней, описание и покупка — в панели под сеткой.
func _pick_weapon(key: String) -> void:
	if key == _shop_sel and _shop_info.get_child_count() > 0:
		return
	var old := _shop_sel
	_shop_sel = key
	for k: String in [old, key]:
		if _shop_cards.has(k):
			var e := _shop_entry(k)
			_style_card(_shop_cards[k], k == key, e["owned"], e.get("soon", false))
	_show_weapon(key)


## Панель выбранного оружия: крупная витрина, название, характеристики, описание; справа — цена
## и «Купить» (та же покупка, что и раньше: Upgrades.buy_weapon) или «Куплено».
func _show_weapon(key: String) -> void:
	for c in _shop_info.get_children():
		c.queue_free()
	var e := _shop_entry(key)
	var owned: bool = e["owned"]
	var soon: bool = e.get("soon", false)
	var st := _style(Color(0.07, 0.06, 0.05, 0.94), Color(GOLD, 0.55) if owned else PANEL_EDGE, 2)
	st.content_margin_left = 18
	st.content_margin_right = 22
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	_shop_info.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_shop_info.add_child(row)
	row.add_child(_showcase(_tex(e["icon"]) if e["icon"] != "" else null, owned, Vector2(250, 164), soon))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	row.add_child(text)
	var locked: bool = not owned and not soon and not e.get("open", true)
	var title := _label(30, GOLD if owned else Color(0.9, 0.86, 0.8), title_font)
	title.text = "Закрытое оружие" if locked else e["name"]
	text.add_child(title)
	var stats := _label(16, Color(0.7, 0.85, 1.0))
	stats.text = ("Откроется на «%s»" % e["after_name"]) if locked else e["stats"]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(stats)
	var desc := _label(16, Color(1, 0.95, 0.88))
	desc.text = ("Пройди локацию «%s», чтобы открыть это оружие. Потом его можно купить за трофеи." % e["after_name"]) \
		if locked else e["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(250, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 10)
	row.add_child(side)
	if owned:
		var have := _label(26, GREEN)
		have.text = "✓ Твоё" if key == "rockets" else "✓ Куплено"
		have.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(have)
		var hint := _label(14, Color(0.8, 0.78, 0.72))
		hint.text = "В бою: клавиша или колесо мыши"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(hint)
	elif soon:
		var later := _label(22, Color(0.55, 0.53, 0.5))
		later.text = "Скоро"
		later.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(later)
	elif not e.get("open", true):
		var lock := _label(18, Color(0.75, 0.78, 0.86))
		lock.text = "🔒 Откроется после локации %d\n«%s»" % [int(e["after"]) + 1, e["after_name"]]
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(lock)
		var price := _label(16, Color(0.8, 0.72, 0.5))
		price.text = "Цена: %d трофеев" % int(e["cost"])
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(price)
	else:
		var item: String = e["item"]
		var cost: int = e["cost"]
		var can := Progress.trophies >= cost
		var price := _label(20, GOLD if can else Color(1, 0.6, 0.5))
		price.text = "Цена: %d трофеев" % cost
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(price)
		var buy := _button("Купить" if can else "Нужно ещё %d" % (cost - Progress.trophies), 20, Vector2(250, 54))
		buy.disabled = not can
		if not can:
			buy.add_theme_color_override("font_disabled_color", Color(1, 0.6, 0.5))
			buy.add_theme_stylebox_override("disabled", _style(PANEL, PANEL_EDGE, 2))
		buy.pressed.connect(func() -> void:
			if Upgrades.buy_weapon(item):
				var main := get_tree().current_scene
				if main and main.has_method("refresh_arsenal"):
					main.refresh_arsenal()
				refresh())
		side.add_child(buy)


## Витрина оружия в карточке: подложка со свечением за моделью. Купленное — в цвете на тёплом
## золотом свечении; некупленное — чёрный силуэт с тонкой светящейся обводкой, холодная
## подложка и замок в углу.
func _showcase(tex: Texture2D, owned: bool, box := Vector2(168, 124), soon := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = box
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, c.size)
		var bg := StyleBoxFlat.new()
		bg.set_corner_radius_all(12)
		bg.bg_color = Color(0.16, 0.11, 0.06, 0.95) if owned else Color(0.06, 0.07, 0.09, 0.95)
		bg.border_color = Color(GOLD, 0.55) if owned else Color(0.3, 0.33, 0.38, 0.6)
		bg.set_border_width_all(1)
		c.draw_style_box(bg, r)
		# Мягкое свечение за моделью: несколько кругов с убывающей яркостью
		var glow := Color(1.0, 0.72, 0.28) if owned else Color(0.45, 0.55, 0.7)
		var mid := r.get_center() + Vector2(0, 4)
		for k in 6:
			c.draw_circle(mid, 56.0 - k * 8.0, Color(glow, (0.05 if owned else 0.03) + k * (0.025 if owned else 0.012)))
		# Пол витрины — светлая полоска внизу
		c.draw_rect(Rect2(14, r.size.y - 16, r.size.x - 28, 2), Color(glow, 0.35 if owned else 0.18))
		if not tex:
			# Ячейка «Скоро»: косые полосы «в разработке» и табличка «СКОРО» по центру
			var stripe := Color(0.95, 0.68, 0.14, 0.07)
			var x := -r.size.y
			while x < r.size.x:
				c.draw_colored_polygon(PackedVector2Array([Vector2(x, r.size.y - 3), Vector2(x + 12, r.size.y - 3),
					Vector2(x + 12 + r.size.y - 6, 3), Vector2(x + r.size.y - 6, 3)]), stripe)
				x += 26.0
			var plate := Rect2(r.size.x * 0.5 - 52, r.size.y * 0.5 - 17, 104, 34)
			var ps := StyleBoxFlat.new()
			ps.set_corner_radius_all(8)
			ps.bg_color = Color(0.1, 0.09, 0.08, 0.95)
			ps.border_color = Color(0.95, 0.68, 0.14, 0.55)
			ps.set_border_width_all(2)
			c.draw_style_box(ps, plate)
			var f: Font = title_font if title_font else font
			c.draw_string(f, Vector2(plate.position.x, plate.position.y + 24), Lang.t("СКОРО"), HORIZONTAL_ALIGNMENT_CENTER,
				plate.size.x, 20, Color(0.95, 0.72, 0.25, 0.85))
			return
		var ts := tex.get_size()
		var k := minf((r.size.x - 12.0) / ts.x, (r.size.y - 10.0) / ts.y)
		var size := ts * k
		var at := r.get_center() - size / 2.0
		if owned:
			c.draw_texture_rect(tex, Rect2(at, size), false)
			return
		# Силуэт рисует дочерний узел с шейдером (ниже) — здесь только замок
		_draw_lock(c, Vector2(r.size.x - 22, 22)))
	if tex and not owned:
		# Закрытое оружие — строго чёрный силуэт (только форма, без цветов и деталей) с тонкой
		# ровной голубоватой обводкой по контуру
		var sil := TextureRect.new()
		sil.texture = tex
		sil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sil.offset_left = 6
		sil.offset_right = -6
		sil.offset_top = 5
		sil.offset_bottom = -5
		sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sil.material = _silhouette_material(tex.get_width() / maxf(box.x, 1.0))
		c.add_child(sil)
	return c


static var _sil_shader: Shader


## Материал силуэта: внутри картинки — чёрный, вокруг — обводка; width — на сколько пикселей
## картинки на один пиксель экрана (обводка ~2 px на экране при любом размере).
func _silhouette_material(texels_per_px: float) -> ShaderMaterial:
	if not _sil_shader:
		_sil_shader = Shader.new()
		_sil_shader.code = """
shader_type canvas_item;
uniform vec4 rim : source_color = vec4(0.6, 0.74, 0.95, 0.85);
uniform float width = 6.0;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float n = 0.0;
	for (int k = 0; k < 8; k++) {
		float ang = float(k) * 0.785398;
		n = max(n, texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px).a);
	}
	if (a > 0.5) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = vec4(rim.rgb, rim.a * n);
	}
}
"""
	var m := ShaderMaterial.new()
	m.shader = _sil_shader
	m.set_shader_parameter("width", 2.0 * texels_per_px)
	return m


## Маленький замок в кружке (закрытое оружие).
func _draw_lock(c: Control, at: Vector2) -> void:
	c.draw_circle(at, 13.0, Color(0.04, 0.04, 0.05, 0.92))
	c.draw_arc(at, 13.0, 0.0, TAU, 24, Color(0.4, 0.42, 0.46, 0.9), 1.5, true)
	c.draw_arc(at + Vector2(0, -3), 4.5, PI, TAU, 10, Color(0.85, 0.8, 0.7), 2.0, true)
	c.draw_rect(Rect2(at + Vector2(-6, -2), Vector2(12, 9)), Color(0.85, 0.8, 0.7))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	for id in _flash.keys():
		_flash[id] -= delta * 1.6
		if _flash[id] <= 0.0:
			_flash.erase(id)
	# Медленный пульс доступных узлов не требует перерисовки каждый кадр — а она дорогая
	# (десятки медальонов с текстом); вспышку после покупки рисуем плавно
	_redraw_t += delta
	if not _flash.is_empty() or _redraw_t >= 0.05:
		_redraw_t = 0.0
		queue_redraw()


# --- раскладка --------------------------------------------------------------------------------
# Раскладка (какие разделы и колонки видны, ширина колонки, левые края разделов) считается один
# раз и лежит в _cache, пока refresh() его не очистит: древо перерисовывается каждый кадр, а
# пересчёт перебирает все узлы — без кэша меню с семью ветками оружия тормозило.
var _cache := {}


## Разделы текущей вкладки: общее древо или ветки оружия (только оружие, которое есть).
func _row_order() -> Array:
	if _tab < TAB_ROWS.size():
		return TAB_ROWS[_tab]
	if _tab != WEAPONS_TAB:
		return []
	if _cache.has("rows"):
		return _cache["rows"]
	# Ракетница (общая ветка «rockets») — первой, рядом с веткой её финалов
	var out := ["rockets"]
	for r: String in Upgrades.WEAPON_ROW_ORDER:
		if not _nodes_of(r).is_empty():
			out.append(r)
	_cache["rows"] = out
	return out


func _row_info(row: String) -> Dictionary:
	return Upgrades.ROWS[row] if Upgrades.ROWS.has(row) else Upgrades.WEAPON_ROWS[row]


## Узлы раздела, которые видны (турели — когда открыты).
func _nodes_of(row: String) -> Array:
	var key := "nodes:" + row
	if _cache.has(key):
		return _cache[key]
	var out := []
	for n: Dictionary in Upgrades.NODES:
		if n["row"] == row:
			var item: String = n.get("item", "")
			if item == "" or Mastery.is_unlocked(item):
				out.append(n)
	_cache[key] = out
	return out


func _offset() -> Vector2:
	return ((size - DESIGN) / 2.0).max(Vector2.ZERO)


## Колонки раздела: x тех узлов, что видны, по порядку (закрытая турель колонку не занимает).
func _cols(row: String) -> Array:
	var key := "cols:" + row
	if _cache.has(key):
		return _cache[key]
	var cols := []
	for n: Dictionary in _nodes_of(row):
		if not int(n["x"]) in cols:
			cols.append(int(n["x"]))
	cols.sort()
	_cache[key] = cols
	return cols


## Самый нижний ярус среди видимых узлов — по нему высота панелей.
func _max_tier() -> int:
	var top := 0
	for row: String in _row_order():
		for n: Dictionary in _nodes_of(row):
			top = maxi(top, int(n["y"]))
	return top


## Ширина колонки: обычно COL_W, а если разделов столько, что не влезают в экран (7 веток
## оружия), — уже, чтобы все поместились.
func _col_w() -> float:
	var key := "colw:%d" % _tab
	if _cache.has(key):
		return _cache[key]
	var cols := 0
	for r: String in _row_order():
		cols += _cols(r).size()
	var n := _row_order().size()
	if cols == 0:
		return COL_W
	var fit := (DESIGN.x - 40.0 - GAP * (n - 1) - 2.0 * PAD * n) / cols
	_cache[key] = minf(COL_W_MAX if n <= 3 else COL_W, fit)
	return _cache[key]


## Левый край раздела (без полей панели) — разделы по центру экрана.
func _section_x(row: String) -> float:
	var key := "x:%d:%s" % [_tab, row]
	if _cache.has(key):
		return float(_cache[key]) + _offset().x
	var total := 0.0
	for r: String in _row_order():
		total += _cols(r).size() * _col_w() + 2.0 * PAD
	total += GAP * (_row_order().size() - 1)
	var x := (DESIGN.x - total) / 2.0 + PAD
	for r: String in _row_order():
		if r == row:
			break
		x += _cols(r).size() * _col_w() + 2.0 * PAD + GAP
	_cache[key] = x
	return x + _offset().x


func _section_w(row: String) -> float:
	return _cols(row).size() * _col_w()


func _pos(id: String) -> Vector2:
	var n: Dictionary = _cache.get("node:" + id, {})
	if n.is_empty():
		n = Upgrades.get_node(id)
		_cache["node:" + id] = n
	var col := _cols(n["row"]).find(int(n["x"]))
	return Vector2(_section_x(n["row"]) + (col + 0.5) * _col_w(), TOP + int(n["y"]) * DY + _offset().y)


func _rebuild_buttons() -> void:
	for b: Button in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for row: String in _row_order():
		for n: Dictionary in _nodes_of(row):
			var id: String = n["id"]
			var b := Button.new()
			b.flat = true
			b.size = Vector2(R * 2.3, R * 2.3)
			for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
				b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			b.mouse_entered.connect(_set_hover.bind(id))
			b.focus_entered.connect(_set_hover.bind(id))
			b.mouse_exited.connect(func() -> void:
				if _hover == id and not b.has_focus():
					_set_hover(""))
			b.pressed.connect(_buy.bind(id))
			add_child(b)
			_buttons[id] = b
	move_child(_tip, -1)
	_layout()


func _layout() -> void:
	for id: String in _buttons:
		var b: Button = _buttons[id]
		b.position = _pos(id) - b.size / 2.0
	if _hover != "":
		_place_tip(_hover)


func _update_header() -> void:
	_counter.text = "Трофеи %d  ·  ★ %d" % [Progress.trophies, Upgrades.stars_total()]


func _buy(id: String) -> void:
	if Upgrades.buy(id):
		_flash[id] = 1.0
		_update_header()
	_set_hover(id)


# --- подсказка --------------------------------------------------------------------------------

func _set_hover(id: String) -> void:
	_hover = id
	queue_redraw()
	_tip.visible = id != ""
	if id == "":
		return
	var n := Upgrades.get_node(id)
	if n.is_empty():
		# Такого узла нет (убран из древа) — подсказку не показываем
		_hover = ""
		_tip.visible = false
		return
	var lv := Upgrades.level(id)
	var top: int = n["max"]
	_tip_title.text = n["name"]
	var status := ""
	if Upgrades.stars_total() < int(n.get("gate", 0)):
		status = "Нужно ★ %d всего (есть %d) — проходи локации." % [int(n["gate"]), Upgrades.stars_total()]
	elif n.has("excl") and Upgrades.level(n["excl"]) > 0:
		status = "Выбрана другая финальная форма — «%s». Сбросить можно на вкладке «Прокачка»." % Upgrades.get_node(n["excl"])["name"]
	elif not Upgrades.is_open(id):
		status = "Сначала купи «%s»." % Upgrades.get_node(n["needs"])["name"]
	elif lv >= top:
		status = "Куплено полностью."
	elif not Upgrades.can_buy(id):
		status = "Нужно %d трофеев (есть %d) — трофеи дают за каждый бой." % [Upgrades.cost_at(id), Progress.trophies]
	else:
		status = "Клик — купить за %d трофеев." % Upgrades.cost_at(id)
	_tip_text.text = "Уровень %d из %d\n%s\n%s" % [lv, top, n["desc"], status]
	_place_tip(id)


func _place_tip(id: String) -> void:
	_tip.reset_size()
	var at := _pos(id) + Vector2(R + 18, -R - 6)
	if at.x + _tip.size.x > size.x - 20:
		at.x = _pos(id).x - R - 18 - _tip.size.x
	at.y = clampf(at.y, 20, size.y - _tip.size.y - 20)
	_tip.position = at


# --- рисование --------------------------------------------------------------------------------

func _draw() -> void:
	_draw_backdrop()
	if _tab == SHOP_TAB:
		return
	for row: String in _row_order():
		_draw_section(row)
	for row: String in _row_order():
		for n: Dictionary in _nodes_of(row):
			if n["needs"] != "" and Upgrades.is_shown(n["needs"]):
				_link(n["needs"], n["id"])
	for row: String in _row_order():
		for n: Dictionary in _nodes_of(row):
			_draw_node(n["id"], _row_info(row)["color"])
			# Развилка финальных форм: «ИЛИ» между ними
			if n.has("excl") and int(n["x"]) == 0 and _buttons.has(n["excl"]):
				var mid := (_pos(n["id"]) + _pos(n["excl"])) / 2.0
				var plate := StyleBoxFlat.new()
				plate.bg_color = Color(0.05, 0.04, 0.03, 0.9)
				plate.set_corner_radius_all(8)
				draw_style_box(plate, Rect2(mid - Vector2(22, 14), Vector2(44, 24)))
				_text(mid + Vector2(0, 6), "ИЛИ", 15, GOLD)


## Картина долины на весь экран (с обрезкой по краям), притушенная, сверху и снизу — темнее.
func _draw_backdrop() -> void:
	var tex_size := Vector2(BG.get_size())
	var k := maxf(size.x / tex_size.x, size.y / tex_size.y)
	var draw_size := tex_size * k
	draw_texture_rect(BG, Rect2((size - draw_size) / 2.0, draw_size), false, Color(0.62, 0.6, 0.56))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.03, 0.45))
	var top_h := 190.0 + _offset().y
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, top_h), Vector2(0, top_h)]),
		PackedColorArray([Color(0.03, 0.02, 0.02, 0.92), Color(0.03, 0.02, 0.02, 0.92), Color(0.03, 0.02, 0.02, 0.0),
			Color(0.03, 0.02, 0.02, 0.0)]))
	var bot := size.y - 150.0
	draw_polygon(PackedVector2Array([Vector2(0, bot), Vector2(size.x, bot), size, Vector2(0, size.y)]),
		PackedColorArray([Color(0.03, 0.02, 0.02, 0.0), Color(0.03, 0.02, 0.02, 0.0), Color(0.03, 0.02, 0.02, 0.85),
			Color(0.03, 0.02, 0.02, 0.85)]))


## Панель раздела: полупрозрачная колонна, сверху — медальон со значком и название.
func _draw_section(row: String) -> void:
	var info: Dictionary = _row_info(row)
	var color: Color = info["color"]
	var x := _section_x(row) - PAD
	var w := _section_w(row) + 2.0 * PAD
	var y0 := HEAD_Y - 48.0 + _offset().y
	var y1 := TOP + _max_tier() * DY + 92.0 + _offset().y
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.035, 0.03, 0.62)
	panel.border_color = Color(color, 0.45)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(16)
	draw_style_box(panel, Rect2(x, y0, w, y1 - y0))
	# Цветная полоса под названием
	var cx := x + w / 2.0
	var hy := HEAD_Y + _offset().y
	draw_circle(Vector2(cx, hy - 14.0), 23.0, Color(0, 0, 0, 0.55))
	draw_circle(Vector2(cx, hy - 14.0), 20.0, color.darkened(0.7))
	draw_arc(Vector2(cx, hy - 14.0), 20.0, 0.0, TAU, 40, color, 2.5, true)
	_icon(info["icon"], Vector2(cx, hy - 14.0), color.lightened(0.25))
	var title: String = info["name"].to_upper()
	var lines := _wrap(title, 17, w - 16.0)
	for k in lines.size():
		_text(Vector2(cx, hy + 28.0 + k * 19.0), lines[k], 17, color.lightened(0.15))
	var line_y := hy + 38.0 + (lines.size() - 1) * 19.0
	draw_line(Vector2(x + 14.0, line_y), Vector2(x + w - 14.0, line_y), Color(color, 0.6), 2.0, true)


## Связь от узла к следующему: вниз, вбок над самым медальоном, вниз (в одной колонке — просто
## вниз) — так линия не режет подписи соседних узлов. Купленное —
## золотом и толще, доступное — светлой линией, закрытое — тёмной.
func _link(from: String, to: String) -> void:
	var a := _pos(from) + Vector2(0, R + 3.0)
	var b := _pos(to) - Vector2(0, R + 3.0)
	var pts := PackedVector2Array()
	if absf(a.x - b.x) < 1.0:
		pts.append_array([a, b])
	else:
		var bend := b.y - 14.0
		pts.append_array([a, Vector2(a.x, bend), Vector2(b.x, bend), b])
	var lit := Upgrades.level(to) > 0
	var col := GOLD if lit else (LINE_OPEN if Upgrades.is_open(to) else LINE_SHUT)
	draw_polyline(pts, Color(0, 0, 0, 0.55), 6.0 if lit else 4.5, true)
	draw_polyline(pts, col, 3.0 if lit else 2.0, true)


## Медальон узла: тёмный круг со значком, кольцо по состоянию, под ним — точки уровней, цена и
## название.
func _draw_node(id: String, color: Color) -> void:
	var c := _pos(id)
	var n := Upgrades.get_node(id)
	var lv := Upgrades.level(id)
	var top: int = n["max"]
	var open := Upgrades.is_open(id)
	var can := Upgrades.can_buy(id)
	var full := lv >= top
	var hover := _hover == id
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	# Свечение купленного и доступного
	if lv > 0:
		for k in 4:
			draw_circle(c, R + 12.0 - k * 3.0, Color(GOLD, 0.05 + k * 0.03))
	elif can:
		draw_circle(c, R + 8.0, Color(1, 1, 1, 0.06 + 0.08 * pulse))
	draw_circle(c, R + 4.0, Color(0, 0, 0, 0.6))
	var fill := color.darkened(0.72) if lv > 0 else (Color(0.13, 0.12, 0.11) if open else Color(0.07, 0.065, 0.06))
	draw_circle(c, R, fill)
	var ring: Color
	var width := 3.0
	if full:
		ring = GOLD
		width = 4.5
	elif lv > 0:
		ring = GOLD.lerp(Color.WHITE, 0.15 * pulse) if can else GOLD
		width = 3.5
	elif can:
		ring = Color(1, 1, 1).lerp(GOLD, 0.35 * pulse)
	elif open:
		ring = Color(0.7, 0.68, 0.64)
		width = 2.5
	else:
		ring = Color(0.3, 0.29, 0.28)
		width = 2.5
	if hover:
		width += 1.5
	draw_arc(c, R, 0.0, TAU, 48, ring, width, true)
	# Значок (у умений — иконка-картинка); закрытое — замок
	if n.has("tex"):
		var tex: Texture2D = _tex(n["tex"])
		draw_texture_rect(tex, Rect2(c - Vector2(R, R) * 0.92, Vector2(R, R) * 1.84), false,
			Color(1, 1, 1) if open else Color(0.35, 0.35, 0.37))
		if not open:
			_icon("lock", c + Vector2(R * 0.62, R * 0.62), Color(0.8, 0.78, 0.74))
	elif not open:
		_icon(n["icon"], c, Color(DIM, 0.35))
		_icon("lock", c + Vector2(R * 0.62, R * 0.62), Color(0.8, 0.78, 0.74))
	else:
		_icon(n["icon"], c, GOLD.lightened(0.2) if lv > 0 else (Color(0.95, 0.93, 0.88) if can else Color(0.68, 0.66, 0.62)))
	# Вспышка после покупки
	if _flash.has(id):
		var f: float = _flash[id]
		draw_arc(c, R + (1.0 - f) * 26.0, 0.0, TAU, 48, Color(GOLD, f), 3.0, true)
	# Точки уровней
	if top > 1:
		var w := (top - 1) * 8.0
		for k in top:
			var p := c + Vector2(-w / 2.0 + k * 8.0, R + 9.0)
			draw_circle(p, 3.2, Color(0, 0, 0, 0.7))
			draw_circle(p, 2.4, GOLD if k < lv else Color(0.35, 0.33, 0.31))
	# Цена следующего уровня
	var name_y := R + 30.0
	if not full and open:
		_text(c + Vector2(0, R + 29.0), "%d" % Upgrades.cost_at(id), 14, GOLD if can else Color(0.75, 0.55, 0.45))
		name_y += 15.0
	elif full:
		_text(c + Vector2(0, R + 29.0), "макс.", 13, Color(GOLD, 0.85))
		name_y += 15.0
	# Название — в две строки, если длинное
	var name: String = n["name"]
	var lines := _wrap(name, 13, _col_w() - 8.0)
	for k in lines.size():
		_text(c + Vector2(0, name_y + k * 15.0), lines[k], 13, Color(1, 0.95, 0.86) if open else Color(0.62, 0.6, 0.57))


var _textures := {}


func _tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


## Разбить название на строки не шире width.
func _wrap(text: String, font_size: int, width: float) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	# Переводим целиком до разбиения на строки (по кускам перевод не найдётся)
	for word in Lang.t(text).split(" "):
		var test := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out


## Текст с обводкой по центру точки at (базовая линия).
func _text(at: Vector2, text: String, font_size: int, col: Color) -> void:
	var w := 300.0
	var p := at - Vector2(w / 2.0, 0)
	text = Lang.t(text)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, 5, Color(0, 0, 0, 0.8))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, col)


## Значок узла — простые фигуры в цвет кольца.
func _icon(icon: String, c: Vector2, col: Color) -> void:
	match icon:
		"wing":
			# Ранец: два баллона и струи вниз
			for sx in [-1.0, 1.0]:
				var x: float = c.x + sx * 8.0
				draw_rect(Rect2(x - 5.0, c.y - 12.0, 10.0, 17.0), col)
				draw_circle(Vector2(x, c.y - 12.0), 5.0, col)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, c.y + 8.0), Vector2(x + 4.0, c.y + 8.0),
					Vector2(x, c.y + 19.0)]), col)
		"snow":
			for j in 6:
				var d := Vector2.from_angle(TAU * j / 6.0 - PI / 2.0)
				draw_line(c, c + d * 17.0, col, 3.0, true)
				draw_line(c + d * 10.0, c + d * 10.0 + d.rotated(0.8) * 6.0, col, 2.2, true)
				draw_line(c + d * 10.0, c + d * 10.0 + d.rotated(-0.8) * 6.0, col, 2.2, true)
		"eye":
			var pts := PackedVector2Array()
			for k in 24:
				var a := TAU * k / 24.0
				pts.append(c + Vector2(cos(a) * 17.0, sin(a) * 9.5))
			draw_colored_polygon(pts, col)
			draw_circle(c, 6.5, VOID)
			draw_circle(c, 2.5, col)
		"gatling":
			for k in 3:
				draw_rect(Rect2(c.x - 16.0, c.y - 9.0 + k * 6.5, 26.0, 4.5), col)
			draw_rect(Rect2(c.x + 8.0, c.y - 12.0, 8.0, 23.0), col)
		"lock":
			draw_arc(c + Vector2(0, -4), 8.0, PI, TAU, 16, col, 3.5, true)
			draw_rect(Rect2(c.x - 11.0, c.y - 4.0, 22.0, 17.0), col)
			draw_circle(c + Vector2(0, 4), 2.5, VOID)
		"blast", "star":
			var pts := PackedVector2Array()
			var spikes := 16 if icon == "blast" else 10
			for k in spikes:
				var a := TAU * k / spikes - PI / 2.0
				pts.append(c + Vector2.from_angle(a) * (17.0 if k % 2 == 0 else (7.0 if icon == "blast" else 8.0)))
			draw_colored_polygon(pts, col)
		"drum", "cells":
			var count := 6 if icon == "drum" else 3
			draw_arc(c, 15.0, 0.0, TAU, 32, col, 3.5, true)
			for k in count:
				draw_circle(c + Vector2.from_angle(TAU * k / count - PI / 2.0) * 8.5, 3.5 if count == 6 else 4.5, col)
		"fire":
			_flame(c + Vector2(0, 4), 1.0, col)
		"wall":
			for k in 3:
				_flame(c + Vector2(-11.0 + k * 11.0, 7), 0.55, col)
		"core":
			draw_circle(c, 14.0, col)
			draw_circle(c, 9.0, VOID)
			for k in 3:
				draw_arc(c, 19.0, TAU * k / 3.0, TAU * k / 3.0 + 1.2, 12, col, 2.5, true)
		"rate":
			for k in 3:
				var x := c.x - 12.0 + k * 12.0
				draw_rect(Rect2(x - 4.0, c.y - 4.0, 8.0, 16.0), col)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, c.y - 4.0), Vector2(x, c.y - 13.0),
					Vector2(x + 4.0, c.y - 4.0)]), col)
		"coin":
			draw_circle(c, 15.0, col)
			draw_rect(Rect2(c.x - 8.0, c.y - 2.0, 16.0, 4.0), PANEL)
		"loot":
			draw_circle(c, 15.0, col)
			draw_arc(c, 9.0, 0.0, TAU, 24, PANEL, 2.5, true)
		"ring":
			draw_arc(c, 13.0, 0.0, TAU, 32, col, 4.0, true)
			for k in 6:
				_flame(c + Vector2.from_angle(TAU * k / 6.0) * 13.0 + Vector2(0, 2), 0.32, col)
		"range":
			draw_arc(c, 13.0, 0.0, TAU, 32, col, 3.0, true)
			for k in 4:
				var d := Vector2.from_angle(k * PI / 2.0)
				draw_line(c + d * 8.0, c + d * 19.0, col, 3.0, true)
			draw_circle(c, 2.5, col)
		"clock":
			draw_arc(c, 14.0, 0.0, TAU, 32, col, 3.0, true)
			draw_line(c, c + Vector2(0, -9), col, 3.0, true)
			draw_line(c, c + Vector2(7, 3), col, 3.0, true)
		"boxes":
			draw_rect(Rect2(c.x - 15.0, c.y + 1.0, 14.0, 12.0), col)
			draw_rect(Rect2(c.x + 1.0, c.y + 1.0, 14.0, 12.0), col)
			draw_rect(Rect2(c.x - 7.0, c.y - 13.0, 14.0, 12.0), col)
		"cluster":
			for k in 3:
				draw_circle(c + Vector2.from_angle(TAU * k / 3.0 - PI / 2.0) * 9.0, 6.0, col)
		"bigball":
			draw_circle(c + Vector2(0, 2), 13.0, col)
			draw_circle(c + Vector2(-4, -2), 4.0, PANEL)
		"tank":
			draw_rect(Rect2(c.x - 9.0, c.y - 10.0, 18.0, 24.0), col)
			draw_rect(Rect2(c.x - 4.0, c.y - 15.0, 8.0, 6.0), col)
			_flame(c + Vector2(0, 5), 0.45, PANEL)
		"spin":
			draw_arc(c, 13.0, 0.3, PI - 0.3, 16, col, 3.5, true)
			draw_arc(c, 13.0, PI + 0.3, TAU - 0.3, 16, col, 3.5, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13, -6), c + Vector2(-19, 2), c + Vector2(-7, 2)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(13, 6), c + Vector2(19, -2), c + Vector2(7, -2)]), col)
		"pierce":
			draw_line(c + Vector2(-16, 10), c + Vector2(14, -10), col, 3.5, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(18, -13), c + Vector2(6, -11), c + Vector2(12, -2)]), col)
			for k in 2:
				draw_circle(c + Vector2(-6 + k * 10, 3 - k * 7), 4.0, PANEL)
		"book":
			draw_rect(Rect2(c.x - 15.0, c.y - 11.0, 14.0, 22.0), col)
			draw_rect(Rect2(c.x + 1.0, c.y - 11.0, 14.0, 22.0), col)
			draw_line(c + Vector2(0, -11), c + Vector2(0, 11), PANEL, 2.0)
		"medal":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -16), c + Vector2(-2, -16), c + Vector2(3, -2),
				c + Vector2(-4, -2)]), col.darkened(0.25))
			draw_colored_polygon(PackedVector2Array([c + Vector2(9, -16), c + Vector2(2, -16), c + Vector2(-3, -2),
				c + Vector2(4, -2)]), col.darkened(0.25))
			draw_circle(c + Vector2(0, 6), 10.0, col)
			draw_circle(c + Vector2(0, 6), 4.0, PANEL)
		"gate":
			draw_rect(Rect2(c.x - 13.0, c.y - 6.0, 26.0, 20.0), col)
			for k in 3:
				draw_rect(Rect2(c.x - 13.0 + k * 10.0, c.y - 13.0, 6.0, 8.0), col)
			draw_rect(Rect2(c.x - 4.0, c.y + 4.0, 8.0, 10.0), PANEL)
		"chest":
			draw_rect(Rect2(c.x - 15.0, c.y - 4.0, 30.0, 17.0), col)
			draw_rect(Rect2(c.x - 15.0, c.y - 12.0, 30.0, 7.0), col.darkened(0.2))
			draw_rect(Rect2(c.x - 3.0, c.y - 6.0, 6.0, 7.0), PANEL)
		"repair":
			var d := Vector2.from_angle(-PI / 4.0)
			draw_line(c - d * 14.0, c + d * 6.0, col, 4.0, true)
			var head := c + d * 9.0
			var side := d.orthogonal()
			draw_colored_polygon(PackedVector2Array([head + side * 11.0 - d * 4.0, head + side * 11.0 + d * 4.0,
				head - side * 7.0 + d * 4.0, head - side * 7.0 - d * 4.0]), col)


## Язычок пламени: капля остриём вверх.
func _flame(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 14:
		var t := k / 13.0
		var a := lerpf(-PI * 0.5, PI * 1.5, t)
		var r := 9.0 * s
		var p := Vector2(cos(a) * r, sin(a) * r * 0.9)
		if p.y < 0.0:
			p.x *= 1.0 + p.y / (r * 1.1)
			p.y *= 2.1
		pts.append(c + p)
	draw_colored_polygon(pts, col)



# --- элементы -------------------------------------------------------------------------------

func _build_tip() -> void:
	_tip = PanelContainer.new()
	var st := _style(PANEL, GOLD, 2)
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	_tip.add_theme_stylebox_override("panel", st)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_tip.add_child(box)
	_tip_title = _label(24, GOLD)
	box.add_child(_tip_title)
	_tip_text = _label(17, Color(1, 0.95, 0.88))
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_text.custom_minimum_size.x = 320
	box.add_child(_tip_text)
	add_child(_tip)


func _label(font_size: int, col: Color, f: Font = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f if f else font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(width)
	st.set_corner_radius_all(12)
	st.content_margin_left = 16
	st.content_margin_right = 16
	return st


func _button(text: String, font_size: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_stylebox_override("normal", _style(PANEL, PANEL_EDGE, 2))
	for state in ["hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(state, _style(Color(0.25, 0.14, 0.07, 0.95), ORANGE, 3))
	b.mouse_entered.connect(b.grab_focus)
	return b
