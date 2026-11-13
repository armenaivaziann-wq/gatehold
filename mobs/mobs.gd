extends RefCounted
## Рядовые враги орды — свои на каждой локации (levels.gd: monster). Модели собираются в коде:
## гранёные низкополигональные части с плоским затенением, цвет в вершинах. Шейдер оживляет их
## по меткам вершин (UV.x): у шестиногих (horde_monster.gdshader) 0 — тело, 1 и 2 — две тройки
## ног (ходят в противофазе), 3 — глаза и всё, что светится; у двуногих (horde_goblin.gdshader)
## 0 — тело, 1 и 2 — ноги, 3 — глаза, 4 и 5 — руки. Все смотрят вдоль +Z, рост около метра.
## far — упрощённая модель для дальнего слоя (в разы меньше треугольников, силуэт тот же).

## rig — каким шейдером оживлять (bug — шестиногий, biped — двуногий); name — для надписи
## «… осталось» (родительный падеж, множественное число); who — для экрана поражения.
const KINDS := {
	"bug": {"rig": "bug", "name": "Жуков", "who": "Жуки прорвались"},
	"goblin": {"rig": "biped", "name": "Гоблинов", "who": "Гоблины прорвались"},
	"scarab": {"rig": "bug", "name": "Скарабеев", "who": "Скарабеи прорвались"},
	"crab": {"rig": "bug", "name": "Крабов", "who": "Крабы прорвались"},
	"ant": {"rig": "bug", "name": "Муравьёв", "who": "Муравьи прорвались"},
	"locust": {"rig": "bug", "name": "Саранчи", "who": "Саранча прорвалась"},
	"ice_spider": {"rig": "bug", "name": "Пауков", "who": "Пауки прорвались"},
	"scorpion": {"rig": "bug", "name": "Скорпионов", "who": "Скорпионы прорвались"},
	"imp": {"rig": "biped", "name": "Бесов", "who": "Бесы прорвались"},
	"crystal_mite": {"rig": "bug", "name": "Клещей", "who": "Клещи прорвались"},
	"wasp": {"rig": "bug", "name": "Ос", "who": "Осы прорвались"},
}


static func rig(kind: String) -> String:
	return KINDS.get(kind, KINDS["bug"])["rig"]


## Суставы двуногих для шейдера (horde_goblin.gdshader): высота таза и плеч, низ и ширина шлема.
## Нет в списке — значения по умолчанию из шейдера.
const RIGS := {
	"goblin": {"hip": 0.3, "shoulder": 0.5, "helmet_y": 0.84, "helmet_x": 0.22},
	"imp": {"hip": 0.3, "shoulder": 0.5, "helmet_y": 0.84, "helmet_x": 0.22},
}


static func rig_params(kind: String) -> Dictionary:
	return RIGS.get(kind, {})


## Кто прорвался — для экрана поражения («Гоблины прорвались»).
static func who(kind: String) -> String:
	return KINDS.get(kind, KINDS["bug"]).get("who", "Враги прорвались")


static func plural(kind: String) -> String:
	return KINDS.get(kind, KINDS["bug"])["name"]


static func mesh(kind: String, far := false) -> ArrayMesh:
	match kind:
		"goblin":
			return _goblin_mesh(far)
		"imp":
			return _imp_mesh(far)
		"scarab", "crab", "ant", "locust", "ice_spider", "scorpion", "crystal_mite", "wasp":
			return _critter_mesh(kind, far)
	return _bug_mesh(far)


# --- кубические враги локаций 2–10 ----------------------------------------------------------
# В том же простом стиле, что и гоблин первой локации: несколько кубиков и шипов, плоский цвет,
# 40–70 треугольников вблизи и 30–45 издалека (раньше — 120–200): тысячи на экране не едят FPS.
# Узнаваемость — силуэтом и цветом: рог скарабея, клешни краба, хвост скорпиона, полосы осы.

## Шесть прямых ног-шипов от бёдер к земле; тройки (передняя и задняя одной стороны со средней
## другой) ходят в противофазе — метки 1 и 2 для шейдера. rear — длиннее задние (саранча).
static func _legs6(st: SurfaceTool, col: Color, hip_y: float, reach: float, rear := 1.0, hip_x := 0.12,
		zs := [0.16, 0.02, -0.12]) -> void:
	var tips := [0.26, 0.0, -0.28]
	for s in [-1.0, 1.0]:
		for k in 3:
			var group := (1.0 if k != 1 else 2.0) if s > 0.0 else (2.0 if k != 1 else 1.0)
			var kk := rear if k == 2 else 1.0
			_spike(st, Vector3(s * hip_x, hip_y, zs[k]), Vector3(s * reach * kk, 0.0, tips[k] * kk), 0.045, col, group)


## Пара светящихся глаз-квадратиков на передней грани (z) кубика головы.
static func _eyes2(st: SurfaceTool, z: float, y: float, x: float, size: float, col: Color) -> void:
	for s in [-1.0, 1.0]:
		var e := Vector3(s * x, y, z + 0.004)
		var back := e - Vector3(0, 0, 0.1)
		var h := size * 0.5
		_tri_out(st, e + Vector3(-h, -h, 0), e + Vector3(h, -h, 0), e + Vector3(h, h, 0), back, col, 3.0)
		_tri_out(st, e + Vector3(-h, -h, 0), e + Vector3(h, h, 0), e + Vector3(-h, h, 0), back, col, 3.0)


## Плоский четырёхугольник, видный с обеих сторон (крылья).
static func _sheet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var mid := (a + b + c + d) / 4.0
	for side in [Vector3.UP, Vector3.DOWN]:
		var inside: Vector3 = mid - side * 0.1
		_tri_out(st, a, b, c, inside, col, 0.0)
		_tri_out(st, a, c, d, inside, col, 0.0)


static func _critter_mesh(kind: String, far: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	match kind:
		"scarab":
			# Скарабей: золотой кубик-панцирь, тёмная голова с рогом
			var gold := Color("d6a83c")
			var dark := Color("3a2614")
			_box(st, Vector3(0, 0.38, -0.08), Vector3(0.56, 0.36, 0.62), gold, 0.0, 0.8, true)
			_box(st, Vector3(0, 0.32, 0.3), Vector3(0.3, 0.22, 0.2), dark, 0.0, 0.9, true)
			_spike(st, Vector3(0, 0.4, 0.34), Vector3(0, 0.66, 0.5), 0.06, dark, 0.0)
			if not far:
				_eyes2(st, 0.4, 0.33, 0.08, 0.06, Color("ffd040"))
			_legs6(st, dark, 0.3, 0.52)
		"crab":
			# Краб: широкий плоский панцирь, две большие клешни вперёд, глаза на стебельках
			var shell := Color("f0d2c4")
			var pink := Color("d07a6a")
			var dark := Color("4a2a28")
			_box(st, Vector3(0, 0.3, 0), Vector3(0.82, 0.22, 0.56), shell, 0.0, 0.85, true)
			for s in [-1.0, 1.0]:
				if far:
					_spike(st, Vector3(s * 0.26, 0.32, 0.24), Vector3(s * 0.36, 0.34, 0.6), 0.09, pink, 0.0)
					continue
				_box(st, Vector3(s * 0.34, 0.34, 0.46), Vector3(0.2, 0.16, 0.24), pink, 0.0, 0.9, true)
				_spike(st, Vector3(s * 0.12, 0.38, 0.22), Vector3(s * 0.15, 0.56, 0.26), 0.035, dark, 3.0)
			_legs6(st, pink, 0.26, 0.6, 1.0, 0.2)
		"ant":
			# Огненный муравей: брюшко, тонкая грудь, голова с жвалами
			var red := Color("cc3420")
			var deep := Color("7a160c")
			var dark := Color("2a0e08")
			_box(st, Vector3(0, 0.4, -0.32), Vector3(0.38, 0.32, 0.44), red, 0.0, 0.8, true)
			if not far:
				_box(st, Vector3(0, 0.34, 0.02), Vector3(0.16, 0.14, 0.24), deep, 0.0, 1.0, true)
			_box(st, Vector3(0, 0.38, 0.28), Vector3(0.3, 0.26, 0.24), red, 0.0, 0.85, true)
			for s in [-1.0, 1.0]:
				_spike(st, Vector3(s * 0.08, 0.3, 0.38), Vector3(s * 0.02, 0.27, 0.6), 0.045, dark, 0.0)
			if not far:
				_eyes2(st, 0.4, 0.42, 0.08, 0.06, Color("ffd040"))
			_legs6(st, dark, 0.32, 0.5)
		"locust":
			# Саранча: длинное зелёное тело, светлые сложенные крылья, мощные задние ноги
			var green := Color("a2ac40")
			var wing := Color("d8c886")
			var dark := Color("3a3a18")
			_box(st, Vector3(0, 0.34, -0.08), Vector3(0.26, 0.26, 0.86), green, 0.0, 0.85, true)
			_box(st, Vector3(0, 0.38, 0.42), Vector3(0.24, 0.28, 0.2), green.darkened(0.15), 0.0, 0.85, true)
			_sheet(st, Vector3(-0.17, 0.49, 0.2), Vector3(0.17, 0.49, 0.2), Vector3(0.2, 0.47, -0.58), Vector3(-0.2, 0.47, -0.58), wing)
			if not far:
				_eyes2(st, 0.52, 0.42, 0.07, 0.06, Color("ffe060"))
			_legs6(st, dark, 0.3, 0.48, 1.5)
		"ice_spider":
			# Ледяной паук: голубой кубик с кристаллами на спине, длинные лапы
			var ice := Color("9cc2ea")
			var blue := Color("3e64a0")
			var crystal := Color("eef8ff")
			_box(st, Vector3(0, 0.42, -0.1), Vector3(0.52, 0.36, 0.52), ice, 0.0, 0.8, true)
			_box(st, Vector3(0, 0.36, 0.24), Vector3(0.26, 0.2, 0.2), blue, 0.0, 0.9, true)
			for c in ([Vector3(0, 0.58, -0.1), Vector3(0.12, 0.58, -0.2), Vector3(-0.12, 0.58, -0.02)] if not far else [Vector3(0, 0.58, -0.1)]):
				_spike(st, c, c + Vector3(c.x * 0.8, 0.28, -0.03), 0.08, crystal, 0.0)
			if not far:
				_eyes2(st, 0.34, 0.38, 0.06, 0.05, Color("7ad8ff"))
			_legs6(st, blue, 0.4, 0.7, 1.0, 0.16)
		"scorpion":
			# Скорпион: плоское тёмное тело, клешни, хвост дугой и светящееся жало
			var shell := Color("4a3a66")
			var band := Color("6c5a8e")
			var dark := Color("1c1628")
			_box(st, Vector3(0, 0.26, 0), Vector3(0.4, 0.18, 0.66), shell, 0.0, 0.85, true)
			if far:
				_spike(st, Vector3(0, 0.3, -0.3), Vector3(0, 0.82, -0.32), 0.08, band, 0.0)
				for s in [-1.0, 1.0]:
					_spike(st, Vector3(s * 0.16, 0.28, 0.3), Vector3(s * 0.26, 0.3, 0.6), 0.07, band, 0.0)
			else:
				_limb(st, Vector3(0, 0.3, -0.3), Vector3(0, 0.66, -0.48), 0.08, 0.065, band, 0.0, false, 3)
				_limb(st, Vector3(0, 0.66, -0.48), Vector3(0, 0.86, -0.26), 0.065, 0.05, band, 0.0, false, 3)
				_spike(st, Vector3(0, 0.86, -0.26), Vector3(0, 0.72, -0.1), 0.05, Color("ff7ad8"), 3.0)
				for s in [-1.0, 1.0]:
					_box(st, Vector3(s * 0.26, 0.3, 0.46), Vector3(0.16, 0.12, 0.22), band, 0.0, 0.9, true)
			_legs6(st, dark, 0.24, 0.5)
		"crystal_mite":
			# Кристальный клещ: тёмно-фиолетовый кубик и пучок светлых кристаллов
			var body := Color("43306a")
			var crystal := Color("cfa4f8")
			_box(st, Vector3(0, 0.32, -0.04), Vector3(0.5, 0.3, 0.56), body, 0.0, 0.8, true)
			_box(st, Vector3(0, 0.28, 0.3), Vector3(0.24, 0.18, 0.16), body.darkened(0.25), 0.0, 0.9, true)
			for c in ([Vector3(0, 0.46, -0.04), Vector3(0.12, 0.46, -0.16), Vector3(-0.12, 0.46, -0.12)] if not far else [Vector3(0, 0.46, -0.04)]):
				_spike(st, c, c + Vector3(c.x * 0.9, 0.34, c.z * 0.4), 0.09, crystal, 0.0)
			if not far:
				_eyes2(st, 0.38, 0.3, 0.06, 0.05, Color("e0a8ff"))
			_legs6(st, Color("241a3a"), 0.28, 0.52)
		"wasp":
			# Оса: жёлтое брюшко с чёрным концом и жалом, чёрная грудь, жёлтая голова, крылья
			var yellow := Color("f2c21e")
			var black := Color("221a12")
			var wing := Color("c4d4e2")
			_box(st, Vector3(0, 0.44, -0.3), Vector3(0.32, 0.3, 0.36), yellow, 0.0, 0.85, true)
			_box(st, Vector3(0, 0.46, 0.02), Vector3(0.22, 0.22, 0.22), black, 0.0, 0.9, true)
			if not far:
				_box(st, Vector3(0, 0.42, -0.56), Vector3(0.22, 0.22, 0.16), black, 0.0, 0.8, true)
				_box(st, Vector3(0, 0.48, 0.24), Vector3(0.22, 0.22, 0.2), yellow, 0.0, 0.9, true)
				_spike(st, Vector3(0, 0.42, -0.64), Vector3(0, 0.36, -0.82), 0.04, black, 0.0)
			for s in [-1.0, 1.0]:
				var w := [Vector3(s * 0.08, 0.58, 0.08), Vector3(s * 0.46, 0.64, 0.0), Vector3(s * 0.44, 0.62, -0.16),
					Vector3(s * 0.08, 0.58, -0.08)]
				if far:
					# Издалека крылья видно только сверху — одна сторона
					_tri_out(st, w[0], w[1], w[2], Vector3(0, 0.3, 0), wing, 0.0)
					_tri_out(st, w[0], w[2], w[3], Vector3(0, 0.3, 0), wing, 0.0)
				else:
					_sheet(st, w[0], w[1], w[2], w[3], wing)
			if not far:
				_eyes2(st, 0.34, 0.5, 0.06, 0.06, Color("ff5030"))
			_legs6(st, black, 0.38, 0.42)
	st.generate_normals()
	return st.commit()


# --- двуногие ------------------------------------------------------------------------------

## Магмовый бес — как гоблин (тот же шейдер и суставы, RIGS), но тёмно-красный: голова-кубик с
## рожками и жёлтыми горящими глазами, лавовое брюхо, хвост с остриём.
static func _imp_mesh(far := false) -> ArrayMesh:
	var skin := Color("5a2420")
	var lava := Color("ff7a22")
	var horn := Color("e8c090")
	var dark := Color("2a1210")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for s in [-1.0, 1.0]:
		_limb(st, Vector3(s * 0.08, 0.3, 0.0), Vector3(s * 0.085, 0.0, 0.02), 0.065, 0.06, dark,
				1.0 if s < 0.0 else 2.0, false, 4)
		_spike(st, Vector3(s * 0.12, 0.88, 0.02), Vector3(s * 0.22, 1.08, -0.02), 0.06, horn, 0.0)
		if not far:
			_limb(st, Vector3(s * 0.17, 0.5, 0.0), Vector3(s * 0.21, 0.3, 0.06), 0.05, 0.045, skin,
					4.0 if s < 0.0 else 5.0, false, 3)
	_box(st, Vector3(0, 0.42, 0.0), Vector3(0.3, 0.26, 0.2), lava if not far else skin, 0.0, 0.9, true)
	_box(st, Vector3(0, 0.73, 0.0), Vector3(0.38, 0.32, 0.34), skin, 0.0, 0.8, true)
	if not far:
		_eyes2(st, 0.17, 0.75, 0.085, 0.07, Color("ffdc40"))
		_spike(st, Vector3(0, 0.36, -0.1), Vector3(0, 0.22, -0.46), 0.04, dark, 0.0)


	st.generate_normals()
	return st.commit()


# --- жук и гоблин --------------------------------------------------------------------------

## Пустынный жук длиной около метра: брюшко в полоску, грудь, голова с жвалами,
## светящиеся глаза и шесть ног из двух сегментов. Смотрит вдоль +Z.
static func _bug_mesh(far := false) -> ArrayMesh:
	var shell := Color("3a2618")
	var band := Color("8a5a2b")
	var dark := Color("24170f")
	var eye := Color("ffd040")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Плоское затенение — гранёный low-poly панцирь
	st.set_smooth_group(-1)
	var legs := [[0.16, 0.2, 1.0], [0.06, 0.0, 2.0], [-0.04, -0.22, 1.0]]
	if far:
		# Издалека: одно вытянутое тело и прямые ноги — силуэт тот же, треугольников в разы меньше
		_blob(st, Vector3(0, 0.33, -0.08), Vector3(0.22, 0.15, 0.5), shell, band, 0.0, 2, 4)
		for s in [-1.0, 1.0]:
			for leg in legs:
				var group: float = leg[2] if s > 0.0 else 3.0 - leg[2]
				_spike(st, Vector3(s * 0.12, 0.38, leg[0]), Vector3(s * 0.55, 0.0, leg[1]), 0.04, dark, group)
		st.generate_normals()
		return st.commit()
	# Брюшко с поперечными полосами, грудь, голова
	_blob(st, Vector3(0, 0.34, -0.3), Vector3(0.26, 0.17, 0.32), shell, band, 0.0, 3, 5)
	_blob(st, Vector3(0, 0.33, 0.07), Vector3(0.16, 0.12, 0.15), shell, shell, 0.0, 2, 5)
	_blob(st, Vector3(0, 0.3, 0.29), Vector3(0.14, 0.11, 0.12), shell, shell, 0.0, 2, 5)
	for s in [-1.0, 1.0]:
		# Жвалы и глаза
		_spike(st, Vector3(s * 0.07, 0.25, 0.37), Vector3(s * 0.02, 0.22, 0.56), 0.035, dark, 0.0)
		_spike(st, Vector3(s * 0.085, 0.34, 0.33), Vector3(s * 0.11, 0.36, 0.38), 0.04, eye, 3.0)
	# Ноги: передняя, средняя, задняя с каждой стороны; тройки ходят в противофазе
	for s in [-1.0, 1.0]:
		for leg in legs:
			var group: float = leg[2] if s > 0.0 else 3.0 - leg[2]
			var hip := Vector3(s * 0.12, 0.3, leg[0])
			var knee := Vector3(s * 0.36, 0.45, leg[1] * 0.6 + leg[0] * 0.4)
			var tip := Vector3(s * 0.55, 0.0, leg[1])
			_spike(st, hip, knee, 0.035, dark, group)
			_spike(st, knee, tip, 0.03, dark, group)
	st.generate_normals()
	return st.commit()


## Гоблин ростом около метра: зелёная кожа, большие уши и нос, жёлтые глаза, рубаха,
## дубина в правой руке. Метки (UV.x) для шейдера: 1 и 2 — левая и правая нога,
## 4 и 5 — левая и правая рука (с дубиной), 3 — глаза. far — упрощённый, для дальних.
static func _goblin_mesh(far := false) -> ArrayMesh:
	var skin := Color("6fa03e")
	var shirt := Color("8c8473")
	var pants := Color("3b2b20")
	var eye := Color("1b1a15")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# Простой гоблин для орды: большая голова-кубик с ушами, рубаха, тёмные ножки, ручки.
	# Светлая рубаха и тёмные ноги — чтобы толпу было видно на земле и траве. Дальний — без рук
	# и глаз (58 / 42 треугольника).
	for s in [-1.0, 1.0]:
		_limb(st, Vector3(s * 0.08, 0.3, 0.0), Vector3(s * 0.085, 0.0, 0.02), 0.065, 0.06, pants,
				1.0 if s < 0.0 else 2.0, false, 4)
		_spike(st, Vector3(s * 0.19, 0.76, 0.0), Vector3(s * 0.43, 0.88, -0.04), 0.07, skin, 0.0)
		if not far:
			_limb(st, Vector3(s * 0.17, 0.5, 0.0), Vector3(s * 0.21, 0.3, 0.06), 0.05, 0.045, skin,
					4.0 if s < 0.0 else 5.0, false, 3)
			# Глаз — тёмный квадратик на лице
			var e := Vector3(s * 0.085, 0.75, 0.182)
			var back := e - Vector3(0, 0, 0.1)
			_tri_out(st, e + Vector3(-0.03, -0.04, 0), e + Vector3(0.03, -0.04, 0), e + Vector3(0.03, 0.04, 0), back, eye, 0.0)
			_tri_out(st, e + Vector3(-0.03, -0.04, 0), e + Vector3(0.03, 0.04, 0), e + Vector3(-0.03, 0.04, 0), back, eye, 0.0)
	_box(st, Vector3(0, 0.42, 0.0), Vector3(0.3, 0.26, 0.2), shirt, 0.0, 0.9, true)
	_box(st, Vector3(0, 0.73, 0.0), Vector3(0.4, 0.34, 0.36), skin, 0.0, 0.8, true)
	st.generate_normals()
	return st.commit()


## Кубик с центром c и размерами s; низ сужен в taper раз; без нижней грани, если no_bottom
## (её всё равно закрывает то, что ниже).
static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, tag: float, taper := 1.0,
		no_bottom := false) -> void:
	var h := s * 0.5
	var p: Array[Vector3] = []
	for y in [-1.0, 1.0]:
		var k := taper if y < 0.0 else 1.0
		for v in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			p.append(c + Vector3(v.x * h.x * k, y * h.y, v.y * h.z * k))
	var faces := [[4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	if not no_bottom:
		faces.append([0, 1, 2, 3])
	for f in faces:
		_tri_out(st, p[f[0]], p[f[1]], p[f[2]], c, col, tag)
		_tri_out(st, p[f[0]], p[f[2]], p[f[3]], c, col, tag)


## Конечность: гранёный (sides граней) усечённый конус от a (радиус r0) к b (радиус r1); торцы —
## только если caps (обычно их прячут суставы, кисти и ступни).
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, tag: float, caps := false,
		sides := 5) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var ra := []
	var rb := []
	for k in sides:
		var ang := TAU * k / sides
		var off := side * cos(ang) + up * sin(ang)
		ra.append(a + off * r0)
		rb.append(b + off * r1)
	var mid := (a + b) * 0.5
	for k in sides:
		var k2 := (k + 1) % sides
		_tri_out(st, ra[k], rb[k], rb[k2], mid, col, tag)
		_tri_out(st, ra[k], rb[k2], ra[k2], mid, col, tag)
		if caps:
			_tri_out(st, a, ra[k], ra[k2], mid, col, tag)
			_tri_out(st, b, rb[k2], rb[k], mid, col, tag)


## Низкополигональный эллипсоид; кольца по длине чередуют два цвета (полоски брюшка).
static func _blob(st: SurfaceTool, center: Vector3, r: Vector3, c1: Color, c2: Color, tag: float,
		rings := 4, segs := 6) -> void:
	var pts := []
	for k in rings + 1:
		var a := PI * k / rings
		var row := []
		for j in segs:
			var b := TAU * j / segs
			row.append(center + Vector3(r.x * sin(a) * cos(b), r.y * sin(a) * sin(b), r.z * cos(a)))
		pts.append(row)
	for k in rings:
		var col: Color = c1 if k % 2 == 0 else c2
		for j in segs:
			var j2 := (j + 1) % segs
			_tri_out(st, pts[k][j], pts[k + 1][j], pts[k + 1][j2], center, col, tag)
			_tri_out(st, pts[k][j], pts[k + 1][j2], pts[k][j2], center, col, tag)


## Тонкий трёхгранный шип от a к b (сегмент ноги, жвало, глаз).
static func _spike(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, col: Color, tag: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var base := []
	for k in 3:
		var ang := TAU * k / 3.0
		base.append(a + (side * cos(ang) + up * sin(ang)) * radius)
	var mid := (a + b) * 0.5
	for k in 3:
		_tri_out(st, base[k], base[(k + 1) % 3], b, mid, col, tag)


## Треугольник лицевой стороной наружу от точки inside (порядок вершин подбирается сам).
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color, tag: float) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		var t := b
		b = c
		c = t
	var lin := col.srgb_to_linear()
	if tag > 2.5:
		lin.a = 0.4
	st.set_color(lin)
	st.set_uv(Vector2(tag, 0))
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
