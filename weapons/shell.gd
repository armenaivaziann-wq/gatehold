extends Node3D
## Снаряд мушкетона: раскалённое ядро с огненным хвостом и дымным следом.
## Если под прицелом была точка (земля, стена, жуки), ядро летит к ней строго по прямой и
## взрывается ровно в ней — там, где лежала метка. Если прицел смотрел в небо — летит прямо,
## пока не ударится обо что-нибудь или не истечёт время.

const ExplosionScript := preload("res://effects/explosion.gd")
const FxBudget := preload("res://core/fx_budget.gd")

# Материалы и меши следа — общие для всех ядер (создаются при первом выстреле)
static var _shared := {}
static var _ball_mesh: SphereMesh

const LIFETIME := 4.0
# Первые метры полёта о стены не бьётся — не взрывается о парапет перед игроком
const SAFE_DISTANCE := 2.5

var velocity := Vector3.ZERO
## Точка, в которой ядро взорвётся (если задана).
var target := Vector3.ZERO
var has_target := false
var horde: Node3D
var exclude: Array[RID] = []
## Взрыв с мастерством: радиус, сколько задевает, поджигает ли землю.
var blast_radius := ExplosionScript.RADIUS
var max_kills := ExplosionScript.MAX_KILLS
var ignite := false
## Ракета героя: вытянутый корпус с красной боеголовкой и густой дымный след.
var rocket := false
## Чей выстрел — на чей счёт убитые (опыт мастерства).
var source := "musket"
## Цвет взрыва (ядерная — зелёный).
var tint := Color(0, 0, 0, 0)
## «Кассета»: после взрыва вокруг рвутся ещё столько малых бомб.
var bombs := 0

static var _rocket_mesh: ArrayMesh

var _age := 0.0
var _travelled := 0.0
var _dead := false
var _ball: MeshInstance3D
var _trail: GPUParticles3D
var _glow: OmniLight3D
var _smoke: GPUParticles3D


func _ready() -> void:
	# Ядро: тёмный железный шар с раскалённой светящейся сердцевиной
	_ball = MeshInstance3D.new()
	if not _ball_mesh:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 0.15
		_ball_mesh.height = 0.3
		_ball_mesh.radial_segments = 8
		_ball_mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.12, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.1)
		mat.emission_energy_multiplier = 6.0
		_ball_mesh.material = mat
	_ball.mesh = _rocket() if rocket else _ball_mesh
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)
	if FxBudget.take_light():
		_glow = OmniLight3D.new()
		_glow.light_color = Color(1.0, 0.6, 0.25)
		_glow.light_energy = 2.0
		_glow.omni_range = 3.0
		add_child(_glow)
	# Огненный хвост и дымный след остаются в мире позади ядра
	_trail = _particles(90, 0.4, 0.15, [Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.5, 0.1, 0.9), Color(0.5, 0.2, 0.08, 0.0)], true)
	if rocket:
		_smoke = _particles(70, 1.6, 0.22, [Color(0.75, 0.72, 0.68, 0.5), Color(0.7, 0.68, 0.65, 0.0)], false)
	else:
		_smoke = _particles(30, 0.8, 0.08, [Color(0.55, 0.5, 0.45, 0.35), Color(0.6, 0.58, 0.55, 0.0)], false)
	# След включается, когда ядро отлетит от лица — иначе дым у самой камеры закрывает экран
	_trail.emitting = false
	_smoke.emitting = false


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	var from := global_position
	var to := from + velocity * delta
	_travelled += from.distance_to(to)
	if has_target:
		# Долетели до точки прицела (или пролетели бы её за этот кадр) — взрыв ровно в ней
		if (target - from).dot(velocity) <= 0.0 or from.distance_to(target) <= velocity.length() * delta:
			_explode(target)
			return
	elif _travelled > SAFE_DISTANCE:
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_explode(hit.position)
			return
	global_position = to
	if not _trail.emitting and _travelled > SAFE_DISTANCE:
		_trail.emitting = true
		_smoke.emitting = true
	if velocity.length_squared() > 0.01:
		# Отвесно вниз (бьём с высоты под себя) «верх» — вперёд, иначе разворот не определён
		look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.FORWARD)
	if _age > LIFETIME:
		_explode(to)


func _explode(at: Vector3) -> void:
	_dead = true
	global_position = at
	var boom := ExplosionScript.new()
	boom.horde = horde
	boom.radius = blast_radius
	boom.max_kills = max_kills
	boom.ignite = ignite
	boom.source = source
	boom.tint = tint
	# Место задаём до добавления в сцену: взрыв считает урон уже в _ready
	boom.transform = get_parent().global_transform.affine_inverse() * Transform3D(Basis(), at)
	get_parent().add_child(boom)
	if bombs > 0:
		_scatter_bombs(at)
	# Ядро исчезает, след догорает и гаснет
	_ball.visible = false
	_drop_glow()
	_trail.emitting = false
	_smoke.emitting = false
	get_tree().create_timer(1.3).timeout.connect(queue_free)


## Ракета (общая для всех) — по эскизу: красный круглый нос, белый корпус с двумя
## красными полосами, серый хвост и четыре стреловидных стабилизатора. Нос — к -Z.
func _rocket() -> ArrayMesh:
	if _rocket_mesh:
		return _rocket_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var red := Color(0.8, 0.22, 0.19)
	var white := Color(0.92, 0.9, 0.86)
	var grey := Color(0.45, 0.45, 0.47)
	var fin := Color(0.78, 0.76, 0.72)
	var r := 0.09
	# Корпус по участкам: [z0, z1, радиус у z0, радиус у z1, цвет]
	var parts := [[-0.25, -0.15, r, r, white], [-0.15, -0.1, r, r, red], [-0.1, 0.0, r, r, white],
		[0.0, 0.05, r, r, red], [0.05, 0.22, r, r, white], [0.22, 0.3, r, 0.065, grey], [0.3, 0.34, 0.065, 0.06, grey.darkened(0.3)]]
	var sides := 14
	for part in parts:
		for k in sides:
			var a0 := k * TAU / sides
			var a1 := a0 + TAU / sides
			var d0 := Vector3(cos(a0), sin(a0), 0)
			var d1 := Vector3(cos(a1), sin(a1), 0)
			var z0: float = part[0]
			var z1: float = part[1]
			# Гладко: нормаль в вершине — по радиусу
			var quad := [[d0 * part[2] + Vector3(0, 0, z0), d0], [d1 * part[2] + Vector3(0, 0, z0), d1], [d1 * part[3] + Vector3(0, 0, z1), d1],
				[d0 * part[2] + Vector3(0, 0, z0), d0], [d1 * part[3] + Vector3(0, 0, z1), d1], [d0 * part[3] + Vector3(0, 0, z1), d0]]
			for v in quad:
				st.set_color(part[4])
				st.set_normal(v[1])
				st.add_vertex(v[0])
	# Нос
	for k in sides:
		var a0 := k * TAU / sides
		var a1 := a0 + TAU / sides
		var mid := (a0 + a1) * 0.5
		for v in [[Vector3(cos(a0), sin(a0), 0) * r + Vector3(0, 0, -0.25), a0], [Vector3(cos(a1), sin(a1), 0) * r + Vector3(0, 0, -0.25), a1],
				[Vector3(0, 0, -0.5), mid]]:
			st.set_color(red)
			st.set_normal(Vector3(cos(v[1]), sin(v[1]), -0.5).normalized())
			st.add_vertex(v[0])
	# Стабилизаторы
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var d := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-d.y, d.x, 0)
		var q := [d * r + Vector3(0, 0, 0.08), d * 0.2 + Vector3(0, 0, 0.27), d * 0.2 + Vector3(0, 0, 0.34), d * 0.065 + Vector3(0, 0, 0.32)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(fin)
			st.set_normal(side)
			st.add_vertex(q[i])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.6
	mesh.surface_set_material(0, mat)
	_rocket_mesh = mesh
	return mesh


## Кассета: малые бомбы разлетаются вокруг и рвутся одна за другой (за доли секунды).
func _scatter_bombs(at: Vector3) -> void:
	var parent := get_parent()
	var map := get_tree().get_first_node_in_group("map")
	var a0 := randf() * TAU
	for k in bombs:
		var a := a0 + TAU * k / bombs + randf_range(-0.3, 0.3)
		var p := at + Vector3(cos(a), 0.0, sin(a)) * blast_radius * randf_range(0.9, 1.4)
		if map:
			p.y = map.height(Vector2(p.x, p.z))
		get_tree().create_timer(0.18 + 0.12 * k).timeout.connect(func() -> void:
			if not is_instance_valid(parent):
				return
			var small := ExplosionScript.new()
			small.horde = horde
			small.radius = blast_radius * 0.55
			small.max_kills = maxi(max_kills / 4, 4)
			small.source = source
			small.silent = k > 0
			small.tint = tint
			small.transform = parent.global_transform.affine_inverse() * Transform3D(Basis(), p)
			parent.add_child(small))


func _drop_glow() -> void:
	if _glow:
		_glow.queue_free()
		_glow = null
		FxBudget.free_light()


func _exit_tree() -> void:
	_drop_glow()


func _particles(amount: int, lifetime: float, size: float, colors: Array, unshaded: bool) -> GPUParticles3D:
	var p := FxBudget.cosmetic(GPUParticles3D.new())
	p.amount = FxBudget.amount(amount)
	p.lifetime = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _shared.has(unshaded):
		p.process_material = _shared[unshaded][0]
		p.draw_pass_1 = _shared[unshaded][1]
		add_child(p)
		return p
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.5, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for k in colors.size():
		grad.add_point(float(k) / (colors.size() - 1), colors[k])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	pm.color_ramp = tex
	var curve := Curve.new()
	curve.max_value = 8.0  # по умолчанию кривая обрезана сверху единицей
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.3 if unshaded else 1.8))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 1.0
	mesh.material = mat
	p.draw_pass_1 = mesh
	_shared[unshaded] = [pm, mesh]
	add_child(p)
	return p
