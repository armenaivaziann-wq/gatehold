extends CanvasLayer
## Обучение на первой локации: слева панель с подсказкой текущего шага, шаг сменяется, когда
## игрок сделал то, о чём просили (выстрелил, выпустил волну, поставил турель…). Пройдено до
## конца или скрыто по H — больше не показывается (progress.gd: tutorial_done).
## main.gd добавляет его, только если это первая локация и обучение ещё не пройдено.

const Progress := preload("res://core/progress.gd")

const GOLD := Color(0.98, 0.74, 0.22)
const PANEL := Color(0.15, 0.14, 0.14, 0.92)
const KEY := "#f9bd38"

## Игра (main.gd): меню, оружие, волны, турели.
var game: Node

var _step := 0
var _timer := 0.0
var _panel: PanelContainer
var _title: Label
var _text: RichTextLabel
var _shown := ""


func _ready() -> void:
	layer = 2
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue", "Segoe UI", "Arial"])
	font.font_weight = 700
	_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = PANEL
	st.border_color = GOLD
	st.border_width_left = 5
	st.set_border_width(SIDE_TOP, 1)
	st.set_border_width(SIDE_RIGHT, 1)
	st.set_border_width(SIDE_BOTTOM, 1)
	st.set_corner_radius_all(12)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", st)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size.x = 440
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.position += Vector2(24, -40)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", font)
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", GOLD)
	box.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.x = 400
	_text.add_theme_font_override("normal_font", font)
	_text.add_theme_font_override("bold_font", font)
	_text.add_theme_font_size_override("normal_font_size", 20)
	_text.add_theme_font_size_override("bold_font_size", 20)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	var skip := Label.new()
	skip.text = "H — скрыть обучение"
	skip.add_theme_font_override("font", font)
	skip.add_theme_font_size_override("font_size", 13)
	skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	box.add_child(skip)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H \
			and not game.in_menu:
		_finish()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_panel.visible = not game.in_menu
	if game.in_menu:
		return
	_timer += delta
	var waves: Node = game.waves
	var turrets: Node3D = game.turrets
	var text := ""
	match _step:
		0:
			text = "Ты на стене у ворот. Двигай [b]мышью[/b] — осмотрись. %s — выстрел мушкетоном: ядро взрывается там, где круглая метка." % _k("ЛКМ")
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("fire"):
				_next()
		1:
			text = "Враги идут из лагерей по тропам к воротам. Нажми %s — выпустить орду." % _k("Enter")
			if waves.state != waves.State.READY:
				_next()
		2:
			if turrets.building:
				text = "Наведи прицел на плато у канала: зелёный призрак — можно ставить. %s — встанет пулемёт. %s — выйти из стройки." % [
					_k("ЛКМ"), _k("B")]
			else:
				text = "Турели ставятся бесплатно, из запаса на бой. Нажми %s — стройка, и поставь пулемёт у канала." % _k("B")
			if _has_turret(turrets):
				_next()
		3:
			text = "Турели стреляют сами. Монеты за убитых — на ступени турелей II и III: в стройке %s по турели. Мушкетон перезаряжается сам, %s — раньше." % [_k("ЛКМ"), _k("R")]
			if _timer > 9.0:
				_next()
		4:
			text = "Полоса вверху — прочность ворот. Каждый враг у ворот отнимает её. Пали по толпе, пока она в каналах."
			if waves.step >= 1:
				_next()
		5:
			text = "Пройдено 20%% орды! Каждые 20%% — бонус трофеев, подвоз боеприпасов и ремонт ворот. Турели можно переставлять (%s — убрать в запас)." % _k("ПКМ")
			if waves.step >= 2:
				_next()
		6:
			text = "За каждый бой — трофеи, даже при поражении; за вожаков и боссов — кристаллы. В «Прокачке» (%s) на них — больше турелей и ловушек в запас. За победу — звёзды и новое оружие." % _k("U")
			if _timer > 12.0:
				_finish()
				return
	_title.text = "ОБУЧЕНИЕ · %d / 7" % (_step + 1)
	if text != _shown:
		_shown = text
		_text.text = text
		# Новый шаг — панель мягко появляется
		_panel.modulate.a = 0.0
		create_tween().tween_property(_panel, "modulate:a", 1.0, 0.35)


func _next() -> void:
	_step += 1
	_timer = 0.0


## Обучение пройдено или скрыто — запомнить и убрать.
func _finish() -> void:
	Progress.tutorial_done = true
	Progress.save()
	queue_free()


func _has_turret(turrets: Node3D) -> bool:
	for slot: Dictionary in turrets._slots:
		if slot["turret"]:
			return true
	return false


func _k(key: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [KEY, key]
