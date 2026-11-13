extends CanvasLayer
## Экран поражения. Орда прорвалась: мир выцветает в тёмно-красный, камера отлетает к туннелю
## (или воротам) и медленно плывёт, пока толпа вливается внутрь; сверху с тряской падает
## «ОБОРОНА ПАЛА» на кровавом мазке, ниже — итоги боя: полоса пройденной орды с рубежами и
## рекордом, сколько продержался, убито, трофеи, что уже по карману. Кнопки: снова в бой
## (Enter), прокачка (U), в меню. Показывает main.gd: show_loss().

const Lang := preload("res://core/lang.gd")

signal retry_pressed
signal upgrades_pressed
signal menu_pressed

const BONE := Color(1.0, 0.93, 0.84)
const BLOOD := Color(0.55, 0.04, 0.03)
const EMBER := Color(1.0, 0.42, 0.12)
const GOLD := Color(0.98, 0.76, 0.26)
const PANEL := Color(0.06, 0.03, 0.03, 0.88)
const GRADE_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 red = vec3(g * 1.25, g * 0.42, g * 0.36);
	c = mix(c, red, amount * 0.82);
	float v = distance(UV, vec2(0.5));
	c *= 1.0 - amount * smoothstep(0.25, 0.85, v) * 0.85;
	c *= 1.0 - amount * 0.18;
	COLOR = vec4(c, 1.0);
}
"""

## Показан ли экран (main.gd не даёт в это время включать вид сверху и стройку).
var active := false

var _t := 0.0
var _grade: ColorRect
var _grade_mat: ShaderMaterial
var _root: Control
var _smear: Control
var _caption: Label
var _title: Label
var _sub: Label
var _panel: PanelContainer
var _bar: Control
var _kills_label: Label
var _time_label: Label
var _loot_label: Label
var _offer_label: Label
var _killers_label: Label
var _buttons: HBoxContainer
var _retry: Button
var _font: SystemFont
var _heavy: FontVariation
var _bold: SystemFont
var _info := {}
var _cam: Camera3D
var _focus := Vector3.ZERO
var _smear_pts := PackedVector2Array()


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Arial"])
	_font.font_weight = 700
	var heavy := SystemFont.new()
	heavy.font_names = _font.font_names
	heavy.font_weight = 900
	_heavy = FontVariation.new()
	_heavy.base_font = heavy
	_heavy.spacing_glyph = 4
	_bold = heavy
	# Цветокоррекция мира: выцветает в тёмно-красный, края темнеют
	_grade = ColorRect.new()
	_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = GRADE_SHADER
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = sh
	_grade.material = _grade_mat
	add_child(_grade)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_caption = _label(22, Color(1.0, 0.55, 0.45), _heavy)
	_caption.text = "П О Р А Ж Е Н И Е"
	col.add_child(_caption)
	# Заголовок на кровавом мазке (мазок рисуется позади, тянется слева направо)
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(0, 130)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_box)
	_smear = Control.new()
	_smear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_smear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_smear.draw.connect(_draw_smear)
	title_box.add_child(_smear)
	_title = _label(104, BONE, _heavy)
	_title.text = "ОБОРОНА ПАЛА"
	_title.add_theme_constant_override("outline_size", 22)
	_title.add_theme_color_override("font_outline_color", Color(0.18, 0.01, 0.01, 0.95))
	_title.add_theme_constant_override("shadow_offset_y", 8)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_box.add_child(_title)
	_sub = _label(26, Color(1.0, 0.86, 0.78))
	col.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	# Итоги боя
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(center)
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL
	st.border_color = Color(0.6, 0.16, 0.1, 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(14)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 20
	st.content_margin_bottom = 22
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", st)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(640, 74)
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 14)
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(tiles)
	_kills_label = _tile(tiles, "УБИТО")
	_time_label = _tile(tiles, "ПРОДЕРЖАЛСЯ")
	_loot_label = _tile(tiles, "ТРОФЕИ")
	_killers_label = _label(17, Color(1.0, 0.92, 0.8))
	box.add_child(_killers_label)
	_offer_label = _label(17, Color(1.0, 0.8, 0.5))
	_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offer_label.custom_minimum_size.x = 640
	box.add_child(_offer_label)
	# Кнопки
	var bcenter := CenterContainer.new()
	bcenter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bcenter)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 16)
	bcenter.add_child(_buttons)
	_retry = _button("Снова в бой", "Enter", true)
	_retry.pressed.connect(func() -> void: retry_pressed.emit())
	var up := _button("Прокачка", "U", false)
	up.pressed.connect(func() -> void: upgrades_pressed.emit())
	var menu := _button("В меню", "", false)
	menu.pressed.connect(func() -> void: menu_pressed.emit())


## Показать поражение. info: reached, best, record, step, steps, kills, time, trophies, total,
## crystals, offers, offer_count, who («Гоблины прорвались»), tunnel. cam — камера, которой облетать точку прорыва focus.
func show_loss(info: Dictionary, cam: Camera3D, focus: Vector3) -> void:
	_info = info
	_cam = cam
	_focus = focus
	_t = 0.0
	active = true
	visible = true
	var who: String = info.get("who", "Враги прорвались")
	_sub.text = "%s %s" % [Lang.t(who), Lang.t("в туннель" if info.get("tunnel", false) else "через ворота")]
	_kills_label.text = _group(int(info["kills"]))
	var secs := int(info["time"])
	_time_label.text = "%d:%02d" % [secs / 60, secs % 60]
	var loot := "+%d" % int(info["trophies"])
	if int(info.get("crystals", 0)) > 0:
		loot += "  +%d ◆" % int(info["crystals"])
	_loot_label.text = loot
	var parts: Array[String] = []
	for row: Array in info.get("killers", []):
		parts.append("%s — %s" % [row[1], _group(int(row[0]))])
	_killers_label.text = (Lang.t("Больше всех убили: ") + Lang.t(" · ".join(parts))) if not parts.is_empty() else ""
	_killers_label.visible = not parts.is_empty()
	var n: int = info.get("offer_count", 0)
	if n > 0:
		_offer_label.text = "Трофеев всего %s — уже можно купить %d %s: %s" % [_group(int(info["total"])), n,
			_plural(n, "улучшение", "улучшения", "улучшений"), info.get("offers", "")]
	else:
		_offer_label.text = "Трофеев всего %s. Копи на следующее улучшение — трофеи дают за каждый бой." % _group(int(info["total"]))
	# Рваный мазок под заголовком — свой каждый раз
	_smear_pts.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var k := 22
	for i in k + 1:
		_smear_pts.append(Vector2(float(i) / k, rng.randf_range(0.0, 0.16)))
	for i in range(k, -1, -1):
		_smear_pts.append(Vector2(float(i) / k, 1.0 - rng.randf_range(0.0, 0.16)))
	_apply(0.0)
	_retry.grab_focus.call_deferred()


## После прокачки: трофеев стало меньше, по карману — другое.
func refresh_loot(total: int, offers: Array) -> void:
	_info["total"] = total
	_info["offer_count"] = offers[0]
	_info["offers"] = offers[1]
	var n: int = offers[0]
	if n > 0:
		_offer_label.text = "Трофеев всего %s — уже можно купить %d %s: %s" % [_group(total), n,
			_plural(n, "улучшение", "улучшения", "улучшений"), offers[1]]
	else:
		_offer_label.text = "Трофеев всего %s. Копи на следующее улучшение — трофеи дают за каждый бой." % _group(total)


func hide_screen() -> void:
	active = false
	visible = false


func _process(delta: float) -> void:
	if not active or not visible:
		return
	_t += delta
	_apply(delta)


## Анимация по времени _t: цвет мира, удар заголовка, итоги, кнопки; облёт камерой.
func _apply(delta: float) -> void:
	var t := _t
	_grade_mat.set_shader_parameter("amount", ease(clampf(t / 0.7, 0.0, 1.0), 0.6))
	_caption.modulate.a = clampf((t - 0.15) / 0.4, 0.0, 1.0)
	# Заголовок падает сверху крупным и бьёт с тряской
	var s := clampf((t - 0.3) / 0.2, 0.0, 1.0)
	_title.modulate.a = s
	_title.pivot_offset = _title.size / 2.0
	_title.scale = Vector2.ONE * lerpf(2.6, 1.0, ease(s, 0.35))
	var shake := maxf(0.0, 1.0 - (t - 0.5) / 0.5) if t > 0.5 else 0.0
	# Тряска — сдвигом отступов (якоря на весь блок остаются, надпись по центру)
	var j := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * shake * shake
	_title.offset_left = j.x
	_title.offset_right = j.x
	_title.offset_top = j.y
	_title.offset_bottom = j.y
	_smear.queue_redraw()
	_sub.modulate.a = clampf((t - 0.75) / 0.4, 0.0, 1.0)
	var p := clampf((t - 0.95) / 0.45, 0.0, 1.0)
	_panel.modulate.a = p
	_panel.position.y = (1.0 - ease(p, 0.4)) * 50.0
	_bar.queue_redraw()
	var b := clampf((t - 1.7) / 0.4, 0.0, 1.0)
	_buttons.modulate.a = b
	for c in _buttons.get_children():
		(c as Button).disabled = b < 0.6
	# Камера медленно плывёт вокруг места прорыва
	if _cam and is_instance_valid(_cam):
		var a := -0.35 + _t * 0.035
		var r := 30.0 - minf(_t, 8.0) * 0.6
		_cam.global_position = _focus + Vector3(sin(a) * r, 12.0 + minf(_t, 8.0) * 0.3, -cos(a) * r)
		_cam.look_at(_focus + Vector3(0, 2.0, 0), Vector3.UP)


## Кровавый мазок за заголовком: рваная полоса, вытягивается слева направо.
func _draw_smear() -> void:
	if _smear_pts.is_empty():
		return
	var grow := ease(clampf((_t - 0.38) / 0.35, 0.0, 1.0), 0.4)
	if grow <= 0.0:
		return
	var sz := _smear.size
	var w := minf(sz.x * 0.62, 900.0)
	var x0 := (sz.x - w) / 2.0
	var y0 := sz.y * 0.16
	var h := sz.y * 0.7
	var pts := PackedVector2Array()
	for v in _smear_pts:
		pts.append(Vector2(x0 + v.x * w * grow, y0 + v.y * h))
	_smear.draw_colored_polygon(pts, Color(BLOOD, 0.88))
	# Тонкие светлые царапины по краям
	_smear.draw_line(Vector2(x0, y0 + h * 0.08), Vector2(x0 + w * grow, y0 + h * 0.05), Color(EMBER, 0.55), 2.0, true)
	_smear.draw_line(Vector2(x0 + w * 0.05, y0 + h * 0.94), Vector2(x0 + w * grow, y0 + h * 0.9), Color(EMBER, 0.4), 2.0, true)


## Полоса пройденной орды: заливка до «пройдено», рубежи каждые 20 %, золотая метка рекорда.
func _draw_bar() -> void:
	if _info.is_empty():
		return
	var c := _bar
	var reached: float = float(_info["reached"]) / 100.0
	var best: float = float(_info["best"]) / 100.0
	var fill := reached * ease(clampf((_t - 1.1) / 0.9, 0.0, 1.0), 0.4)
	var top := 30.0
	var rect := Rect2(0, top, c.size.x, 22)
	c.draw_rect(rect, Color(0.12, 0.05, 0.04, 0.95))
	if fill > 0.0:
		var fr := Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y))
		c.draw_rect(fr, Color(0.75, 0.14, 0.06))
		c.draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.42)), Color(1.0, 0.45, 0.2, 0.55))
	c.draw_rect(rect, Color(0.6, 0.2, 0.12), false, 2.0)
	var steps: int = _info.get("steps", 5)
	for k in range(1, steps):
		var x := rect.size.x * k / steps
		var got := k <= int(_info.get("step", 0))
		c.draw_line(Vector2(x, rect.position.y - 4), Vector2(x, rect.end.y + 4), Color(GOLD, 0.9) if got else Color(1, 1, 1, 0.3), 2.0)
	# Рекорд — золотой треугольник над полосой
	if best > 0.0:
		var bx := rect.size.x * best
		c.draw_colored_polygon(PackedVector2Array([Vector2(bx - 7, rect.position.y - 12), Vector2(bx + 7, rect.position.y - 12),
			Vector2(bx, rect.position.y - 2)]), GOLD)
	var shown := int(round(fill * 100.0))
	var head := "ПРОЙДЕНО ОРДЫ: %d%%" % shown
	c.draw_string(_heavy, Vector2(0, 20), Lang.t(head), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, BONE)
	var rec := "НОВЫЙ РЕКОРД!" if _info.get("record", false) else "рекорд %d%%" % int(_info["best"])
	c.draw_string(_font, Vector2(0, 20), Lang.t(rec), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x, 18,
		GOLD if _info.get("record", false) else Color(1, 0.85, 0.6))
	c.draw_string(_font, Vector2(0, rect.end.y + 20), Lang.t("Каждые 20% орды — рубеж: трофеи, подвоз и ремонт"), HORIZONTAL_ALIGNMENT_CENTER,
		c.size.x, 14, Color(1, 0.85, 0.75, 0.6))


func _tile(parent: Control, caption: String) -> Label:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.05, 0.04, 0.9)
	st.set_corner_radius_all(10)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 8
	st.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(200, 0)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	p.add_child(v)
	var cap := _label(14, Color(1.0, 0.6, 0.5))
	cap.text = caption
	v.add_child(cap)
	var val := _label(34, BONE, _heavy)
	v.add_child(val)
	return val


func _button(text: String, key: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text + ("  ·  " + key if key != "" else "")
	b.custom_minimum_size = Vector2(250 if primary else 200, 58)
	b.add_theme_font_override("font", _bold)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.15, 0.04, 0.02) if primary else BONE)
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.02, 0.0) if primary else Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(0.15, 0.04, 0.02) if primary else Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	var bg := EMBER if primary else Color(0.14, 0.06, 0.05, 0.92)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = bg.lightened(0.15) if state == "hover" else (bg.darkened(0.15) if state == "pressed" else bg)
		st.border_color = GOLD if state in ["hover", "focus"] else Color(0.6, 0.2, 0.12)
		st.set_border_width_all(3 if state in ["hover", "focus"] else 2)
		st.set_corner_radius_all(12)
		b.add_theme_stylebox_override(state, st)
	_buttons.add_child(b)
	return b


func _label(size: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font if font else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.01, 0.01, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 12345 → «12 345».
static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
		return few
	return many
