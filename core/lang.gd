extends Translation
## Язык игры. Тексты в коде написаны по-русски; английский — словарь i18n/en.gd (ключ — русский
## текст). Этот перевод подключается к TranslationServer, и все надписи (Label, Button, тексты
## подсказок) Godot переводит сам. Кроме точного совпадения понимает:
##   шаблоны — «Цена: %d трофеев» ловит «Цена: 900 трофеев», числа и имена подставляет (имена —
##     тоже переводом: «Откроется на «Солончак»» → Unlocks at "Salt Flats");
##   составные надписи — по строкам (\n) и по частям « · »; обрамление («+  », «🔒 », кавычки).
## Русский игрок перевода не касается: на русском он вообще не подключён.
## Текст, который рисуется вручную (draw_string), переводить явно: Lang.t("…").

const EnTable := preload("res://i18n/en.gd")
const LANGS := ["ru", "en"]
const LANG_NAMES := ["Русский", "English"]
const CACHE_MAX := 4000

static var language := "ru"
static var _instance: Translation
static var _active := false

var _exact := {}
var _templates: Array = []        # [префикс, RegEx полный, RegEx с хвостом или null, английский шаблон]
var _cache := {}
var _cyr := RegEx.new()
var _spec := RegEx.new()


func _init() -> void:
	locale = "en"
	_cyr.compile("[А-Яа-яЁё]")
	_spec.compile("%[-+0-9.]*[dsf]")
	_exact = EnTable.EN
	for key: String in _exact:
		if _spec.search(key):
			_templates.append(_template(key, _exact[key]))
	# Длинные префиксы — первыми: «Нужно ещё %d» раньше, чем «Нужно %d…»
	_templates.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]).length() > String(b[0]).length())


## Переведённый текст (для того, что рисуется вручную: draw_string и т.п.).
static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


## Включить язык: "ru" или "en". Надписи интерфейса перестраиваются сами.
static func set_language(code: String) -> void:
	language = code if code in LANGS else "ru"
	if language == "en":
		if not _instance:
			_instance = load("res://core/lang.gd").new()
		if not _active:
			TranslationServer.add_translation(_instance)
			_active = true
		TranslationServer.set_locale("en")
	else:
		if _active:
			TranslationServer.remove_translation(_instance)
			_active = false
		TranslationServer.set_locale("ru")


## Язык по умолчанию — по языку системы (русскоязычным — русский, остальным — английский).
static func system_language() -> String:
	return "ru" if OS.get_locale_language() in ["ru", "uk", "be", "kk"] else "en"


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(translate_text(String(src_message)))


func translate_text(s: String) -> String:
	if s.is_empty() or not _cyr.search(s):
		return s
	if _exact.has(s):
		return _exact[s]
	if _cache.has(s):
		return _cache[s]
	var out := _case_variant(s)
	if out == "":
		out = _compose(s)
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[s] = out
	return out


## Тот же текст в другом регистре: «ГЕРОЙ» (заголовок .to_upper()) → HERO, «ос» (в строке
## .to_lower()) → wasps. Пусто — такого варианта в словаре нет.
func _case_variant(s: String) -> String:
	var cap := s.substr(0, 1).to_upper() + s.substr(1).to_lower()
	if cap == s or not _exact.has(cap):
		return ""
	var en: String = _exact[cap]
	if s == s.to_upper():
		return en.to_upper()
	if s == s.to_lower():
		return en.to_lower()
	return en


func _compose(s: String) -> String:
	# Шаблон целиком
	for tpl: Array in _templates:
		if not s.begins_with(tpl[0]):
			continue
		var m: RegExMatch = (tpl[1] as RegEx).search(s)
		if m:
			return _fill(tpl[3], m, m.get_group_count())
	# Шаблон и хвост за ним (к надписи что-то дописали)
	for tpl: Array in _templates:
		if tpl[2] == null or not s.begins_with(tpl[0]):
			continue
		var m: RegExMatch = (tpl[2] as RegEx).search(s)
		if m:
			var n := m.get_group_count()
			return _fill(tpl[3], m, n - 1) + translate_text(m.get_string(n))
	# По строкам и по частям
	if "\n" in s:
		var lines := s.split("\n")
		for i in lines.size():
			lines[i] = translate_text(lines[i])
		return "\n".join(lines)
	if " · " in s:
		var parts := s.split(" · ")
		for i in parts.size():
			parts[i] = translate_text(parts[i])
		return " · ".join(parts)
	# Обрамление: «+  …», «🔒 …», кавычки, знаки — переводим середину от первой до последней буквы
	var first := -1
	var last := -1
	for i in s.length():
		if _cyr.search(s[i]):
			if first < 0:
				first = i
			last = i
	if first >= 0 and (first > 0 or last < s.length() - 1):
		var core := s.substr(first, last - first + 1)
		var tr_core := translate_text(core)
		if tr_core != core:
			# Ёлочки — русские кавычки; в английском — обычные
			return (s.substr(0, first) + tr_core + s.substr(last + 1)).replace("«", "\"").replace("»", "\"")
	return s


## Английский шаблон с подставленными группами: имена с русскими буквами — тоже переводом.
func _fill(en: String, m: RegExMatch, groups: int) -> String:
	var out := ""
	var g := 1
	var i := 0
	while i < en.length():
		var c := en[i]
		if c == "%" and i + 1 < en.length() and en[i + 1] == "%":
			out += "%"
			i += 2
			continue
		if c == "%":
			var sm := _spec.search(en, i)
			if sm and sm.get_start() == i and g <= groups:
				out += translate_text(m.get_string(g))
				g += 1
				i = sm.get_end()
				continue
		out += c
		i += 1
	return out


## Из русского шаблона — префикс до первой подстановки и регулярные выражения.
func _template(key: String, en: String) -> Array:
	var pattern := ""
	var prefix := ""
	var seen_spec := false
	var ends_with_text := true
	var i := 0
	while i < key.length():
		var c := key[i]
		if c == "%" and i + 1 < key.length() and key[i + 1] == "%":
			pattern += "%"
			if not seen_spec:
				prefix += "%"
			i += 2
			ends_with_text = true
			continue
		if c == "%":
			var sm := _spec.search(key, i)
			if sm and sm.get_start() == i:
				var kind := key[sm.get_end() - 1]
				pattern += "([-+]?[\\d\\s ,.]*\\d)" if kind in ["d", "f"] else "(.+?)"
				seen_spec = true
				ends_with_text = kind != "s"
				i = sm.get_end()
				continue
		pattern += _escape(c)
		if not seen_spec:
			prefix += c
		ends_with_text = true
		i += 1
	var full := RegEx.new()
	full.compile("^" + pattern + "$")
	var tail: RegEx = null
	if ends_with_text:
		tail = RegEx.new()
		tail.compile("^" + pattern + "(.+)$")
	return [prefix, full, tail, en]


func _escape(c: String) -> String:
	return "\\" + c if c in [".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|", "\\", "/"] else c
