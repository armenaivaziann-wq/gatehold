extends Node3D
## Взрыв снаряда: белая вспышка, клубы огня, дым, кольцо песка, обломки, свет, опалина на земле.
## Убивает жуков в радиусе и трясёт камеру игрока (тем сильнее, чем ближе).

const SOUND := preload("res://audio/sounds/explosion.wav")
const FirePatch := preload("res://effects/fire_patch.gd")
const FxBudget := preload("res://core/fx_budget.gd")

const RADIUS := 3.5
const MAX_KILLS := 90
const DAMAGE := 3
const FIRE_TIME := 0.9
# Общий размер картинки взрыва (огонь, дым, песок, обломки)
const VISUAL := 0.9
const SCORCH_TIME := 8.0
const LIGHT_TIME := 0.5
const PARTICLES_TIME := 3.0      # дольше всех живёт дым

# Общие для всех взрывов: материалы частиц, меши, текстура подпалины — создаются один раз
# (новые текстуры и материалы на каждый взрыв давали рывки)
static var _bursts := {}
static var _puff_mesh: SphereMesh
static var _flash_mesh: SphereMesh
static var _scorch_tex: GradientTexture2D

var horde: Node3D
## Радиус поражения и сколько врагов взрыв может задеть (растут с мастерством).
var radius := RADIUS
var max_kills := MAX_KILLS
## Чей взрыв — на чей счёт идут убийства (опыт мастерства): "musket", "mortar"…
var source := ""
## Поджечь землю после взрыва (зажигательные ядра, напалм).
var ignite := false
## Без звука (взрывы на фоне главного меню — там только музыка).
var silent := false
## Цвет взрыва (ядерная боеголовка — зелёный); прозрачный — обычный огонь.
var tint := Color(0, 0, 0, 0)
## Сила тряски камеры (мортиры бьют часто и далеко — трясут слабее и только вблизи).
var shake := 1.0

var _age := 0.0
var _vis := 1.0                 # крупные взрывы (ядерная) — и клубы крупнее
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _puffs: Array = []          # [узел, материал, скорость, размер]
var _light: OmniLight3D
var _scorch: Decal
var _puff_mat: StandardMaterial3D
var _full := false              # занят слот «полного» взрыва (дым, песок, обломки) в FxBudget


func _ready() -> void:
	if horde:
		# Взрыв бьёт сильно: громилу почти валит, боссу — заметный урон
		horde.kill_area(global_position, radius, max_kills, source, DAMAGE)
	if ignite:
		var fire := FirePatch.new()
		fire.horde = horde
		fire.source = source
		fire.scale_size = radius / RADIUS
		fire.position = position
		get_parent().add_child.call_deferred(fire)
	_vis = maxf(radius / RADIUS, 1.0) ** 0.7
	if not _flash_mesh:
		_flash_mesh = _sphere_mesh(2)
		_puff_mesh = _sphere_mesh(1)
	# Вспышка: шар, раздувается и гаснет за четверть секунды
	_flash_mat = _unshaded(Color(1.0, 0.95, 0.7, 1.0) if tint.a == 0.0 else Color(tint.lightened(0.6), 1.0))
	_flash = _sphere(_flash_mesh, _flash_mat)
	_flash.position.y = 0.8
	# Огненные клубы: гранёные шары, разлетаются и поднимаются, жёлтый → оранжевый → тёмный
	# (цвет у всех клубов один и меняется со временем — материал общий на взрыв)
	_puff_mat = _unshaded(Color(1.0, 0.8, 0.3, 1.0))
	# Полный взрыв — пока их на экране немного; остальные облегчённые: вспышка и меньше клубов
	_full = FxBudget.take_explosion()
	for k in (8 if _full else 4):
		var node := _sphere(_puff_mesh, _puff_mat)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.4, 1.6), randf_range(-1, 1)).normalized()
		node.position = (dir * 0.4 + Vector3.UP * 0.5) * VISUAL * _vis
		_puffs.append([node, dir * randf_range(3.0, 6.0) * VISUAL * _vis, randf_range(1.2, 2.0) * VISUAL * _vis])
	if FxBudget.take_light():
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.65, 0.3) if tint.a == 0.0 else tint
		_light.light_energy = 14.0
		_light.omni_range = 16.0
		_light.position.y = 1.0
		add_child(_light)
	# Дым, песок и обломки — только у полного взрыва; искры (мелкие, без прозрачных слоёв) — у всех
	if _full and not FxBudget.lite():
		_bursts_full()
	if not FxBudget.lite():
		_burst(3, FxBudget.amount(34), 0.5, Vector3(0, 1, 0), 75.0, Vector2(7.0, 14.0), Vector3(0, -6.0, 0), 0.05, 0.09,
			[Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.45, 0.1, 0.0)], true, 0.0)
	_finish_ready()


func _bursts_full() -> void:
	# Столб тёмного дыма — хорошо виден на светлом песке
	_burst(0, FxBudget.amount(22), 2.4, Vector3(0, 1, 0), 28.0, Vector2(2.5, 5.5), Vector3(0, 1.2, 0), 0.3, 0.75,
		[Color(0.2, 0.17, 0.15, 0.9), Color(0.38, 0.34, 0.3, 0.6), Color(0.55, 0.52, 0.48, 0.0)], false, 2.2)
	# Кольцо песка по земле
	_burst(1, FxBudget.amount(30), 1.2, Vector3(0, 0.15, 0), 88.0, Vector2(5.0, 9.0), Vector3(0, -2.0, 0), 0.2, 0.45,
		[Color(0.85, 0.6, 0.32, 0.95), Color(0.85, 0.62, 0.38, 0.0)], false, 3.5)
	# Обломки и комья земли
	_burst(2, FxBudget.amount(24), 1.3, Vector3(0, 1, 0), 50.0, Vector2(6.0, 12.0), Vector3(0, -16.0, 0), 0.07, 0.15,
		[Color(0.22, 0.14, 0.08, 1.0), Color(0.22, 0.14, 0.08, 1.0)], false, 0.0)


func _finish_ready() -> void:
	# Опалина на земле — проекция сверху, тёмное пятно с мягким краем (если есть место в бюджете)
	if FxBudget.take_decal():
		if not _scorch_tex:
			var grad := Gradient.new()
			grad.set_color(0, Color(0.08, 0.05, 0.03, 0.85))
			grad.set_color(1, Color(0.1, 0.06, 0.03, 0.0))
			_scorch_tex = GradientTexture2D.new()
			_scorch_tex.gradient = grad
			_scorch_tex.fill = GradientTexture2D.FILL_RADIAL
			_scorch_tex.fill_from = Vector2(0.5, 0.5)
			_scorch_tex.fill_to = Vector2(1.0, 0.5)
			_scorch_tex.width = 128
			_scorch_tex.height = 128
		_scorch = Decal.new()
		_scorch.size = Vector3(radius * 1.6, 3.0, radius * 1.6)
		_scorch.texture_albedo = _scorch_tex
		_scorch.rotation.y = randf() * TAU
		add_child(_scorch)
	if not silent:
		var audio := AudioStreamPlayer3D.new()
		audio.stream = SOUND
		audio.unit_size = 25.0
		audio.pitch_scale = randf_range(0.9, 1.08)
		add_child(audio)
		audio.play()
	# Тряска камеры: рядом — сильно, вдалеке — едва заметно
	var cam := get_viewport().get_camera_3d()
	if cam and shake > 0.0:
		var d := cam.global_position.distance_to(global_position)
		var amount := clampf(1.2 - d / 40.0, 0.1, 1.0) * shake
		if shake >= 1.0 or d < 25.0:
			get_tree().call_group("player", "shake", amount)


func _process(delta: float) -> void:
	_age += delta
	if _flash:
		var f := clampf(_age / 0.25, 0.0, 1.0)
		_flash.scale = Vector3.ONE * lerpf(0.8, 4.5, ease(f, 0.4)) * VISUAL * _vis
		_flash_mat.albedo_color.a = 1.0 - f
		if f >= 1.0:
			_flash.queue_free()
			_flash = null
	var t := clampf(_age / FIRE_TIME, 0.0, 1.0)
	if not _puffs.is_empty():
		# Жёлтое ядро → оранжевый → красный → тёмный дым
		var col := Color(1.0, 0.9, 0.45).lerp(Color(1.0, 0.45, 0.05), clampf(t * 3.0, 0.0, 1.0))
		col = col.lerp(Color(0.7, 0.15, 0.03), clampf(t * 3.0 - 1.0, 0.0, 1.0))
		col = col.lerp(Color(0.18, 0.12, 0.1), clampf(t * 3.0 - 2.0, 0.0, 1.0))
		if tint.a > 0.0:
			col = Color(col.lerp(tint, 0.7 * (1.0 - t)), col.a)
		col.a = 1.0 - ease(t, 3.0)
		_puff_mat.albedo_color = col
		for puff in _puffs:
			var node: MeshInstance3D = puff[0]
			var vel: Vector3 = puff[1]
			node.position += (vel * (1.0 - t) + Vector3.UP * 2.0 * t) * delta
			node.scale = Vector3.ONE * float(puff[2]) * lerpf(0.5, 1.7, ease(t, 0.4))
		if t >= 1.0:
			# Клубы догорели — убираем их совсем
			for puff in _puffs:
				puff[0].queue_free()
			_puffs.clear()
	if _light:
		_light.light_energy = 16.0 * maxf(1.0 - _age / LIGHT_TIME, 0.0)
		if _age > LIGHT_TIME:
			_light.queue_free()
			_light = null
			FxBudget.free_light()
	if _scorch:
		# Опалина медленно выцветает
		_scorch.modulate.a = clampf(1.0 - (_age - SCORCH_TIME * 0.6) / (SCORCH_TIME * 0.4), 0.0, 1.0)
	if _full and _age > PARTICLES_TIME:
		_full = false
		FxBudget.free_explosion()
	if _age > (SCORCH_TIME if _scorch else PARTICLES_TIME):
		queue_free()


func _exit_tree() -> void:
	if _full:
		FxBudget.free_explosion()
		_full = false
	if _light:
		FxBudget.free_light()
		_light = null
	if _scorch:
		FxBudget.free_decal()
		_scorch = null


static func _sphere_mesh(subdivisions: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6 + subdivisions * 2
	mesh.rings = 3 + subdivisions
	return mesh


func _sphere(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	return m


## Разовый выброс частиц: amount штук, вверх по direction с разбросом spread (градусы).
## Материал и меш выброса key общие для всех взрывов — создаются при первом взрыве.
func _burst(key: int, amount: int, lifetime: float, direction: Vector3, spread: float, speed: Vector2, gravity: Vector3,
		size_min: float, size_max: float, colors: Array, unshaded: bool, damping: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _bursts.has(key):
		p.process_material = _bursts[key][0]
		p.draw_pass_1 = _bursts[key][1]
		add_child(p)
		p.emitting = true
		return
	var pm := ParticleProcessMaterial.new()
	pm.direction = direction
	pm.spread = spread
	pm.initial_velocity_min = speed.x * VISUAL
	pm.initial_velocity_max = speed.y * VISUAL
	pm.gravity = gravity
	pm.damping_min = damping
	pm.damping_max = damping * 1.5
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5 * VISUAL
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for k in colors.size():
		grad.add_point(float(k) / (colors.size() - 1), colors[k])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	pm.color_ramp = tex
	if not unshaded and damping > 0.0:
		# Дым и песок разрастаются
		var curve := Curve.new()
		curve.max_value = 8.0  # по умолчанию кривая обрезана сверху единицей
		curve.add_point(Vector2(0.0, 0.5))
		curve.add_point(Vector2(1.0, 2.2))
		var curve_tex := CurveTexture.new()
		curve_tex.curve = curve
		pm.scale_curve = curve_tex
	pm.scale_min = 1.0
	pm.scale_max = size_max / size_min
	p.process_material = pm
	var mesh: Mesh
	if damping == 0.0 and not unshaded:
		# Обломки — угловатые камешки
		var box := BoxMesh.new()
		box.size = Vector3.ONE * size_min * 2.0 * VISUAL
		mesh = box
	else:
		var sphere := SphereMesh.new()
		sphere.radius = size_min * VISUAL
		sphere.height = size_min * 2.0 * VISUAL
		sphere.radial_segments = 6
		sphere.rings = 3
		mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	p.draw_pass_1 = mesh
	_bursts[key] = [pm, mesh]
	add_child(p)
	p.emitting = true
