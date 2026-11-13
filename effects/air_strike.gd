extends Node3D
## Удары с неба (hero_abilities.gd), ставится в точку на земле до добавления в сцену:
##   kind = "napalm" — низко над полем с рёвом проносится штурмовик и сбрасывает вдоль dir цепочку
##     напалмовых бомб: каждая — огненный взрыв и горящая земля;
##   kind = "rockets" — ракетный дождь: по земле вспыхивает красный круг-предупреждение, затем с
##     неба наискось один за другим падают ракеты с дымными хвостами и рвутся по всей площади.

const ShellScript := preload("res://weapons/shell.gd")
const ExplosionScript := preload("res://effects/explosion.gd")
const FirePatch := preload("res://effects/fire_patch.gd")
const ENGINE := preload("res://audio/sounds/flame_loop.wav")

const PLANE_HEIGHT := 24.0
const PLANE_SPEED := 62.0
const BOMBS := 7
const BOMB_STEP := 4.2           # м между бомбами
const RAIN := 20
const RAIN_RADIUS := 11.0
const RAIN_DELAY := 0.65         # с от круга-предупреждения до первой ракеты

var kind := "napalm"
var horde: Node3D
var dir := Vector3.FORWARD
## Сила (прокачка): больше бомб и ракет.
var power := 1.0

var _age := 0.0
var _map: Node3D
var _plane: Node3D
var _plane_from := Vector3.ZERO
var _dropped := 0
var _bombs: Array = []            # [узел, скорость]
var _warn: MeshInstance3D
var _warn_mat: StandardMaterial3D
var _fired := 0
var _engine: AudioStreamPlayer3D


func _ready() -> void:
	_map = get_tree().get_first_node_in_group("map")
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	if kind == "napalm":
		_plane = _plane_model()
		add_child(_plane)
		_plane_from = global_position - dir * 90.0 + Vector3(0, PLANE_HEIGHT, 0)
		_plane.global_position = _plane_from
		_plane.look_at(_plane_from + dir, Vector3.UP)
		_engine = AudioStreamPlayer3D.new()
		var loop: AudioStreamWAV = ENGINE.duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = int(ENGINE.get_length() * ENGINE.mix_rate)
		_engine.stream = loop
		_engine.unit_size = 45.0
		_engine.pitch_scale = 1.6
		_engine.volume_db = 4.0
		_plane.add_child(_engine)
		_engine.play()
	else:
		_warn_mat = StandardMaterial3D.new()
		_warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_warn_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_warn_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_warn_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.8)
		_warn = MeshInstance3D.new()
		_warn.mesh = _ring(RAIN_RADIUS, RAIN_RADIUS - 0.5)
		_warn.material_override = _warn_mat
		_warn.position.y = 0.3
		_warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_warn)


func _process(delta: float) -> void:
	_age += delta
	if kind == "napalm":
		_fly(delta)
	else:
		_rain()


# --- штурмовик с напалмом -------------------------------------------------------------------------

func _fly(delta: float) -> void:
	if _plane:
		var p := _plane_from + dir * PLANE_SPEED * _age
		_plane.global_position = p + Vector3(0, sin(_age * 3.0) * 0.4, 0)
		_plane.rotation.z = sin(_age * 2.0) * 0.06
		# Сброс: бомбы начинают падать, не долетая до точки, чтобы цепочка легла через неё
		var bombs := int(BOMBS * power)
		var first := 90.0 - BOMB_STEP * bombs * 0.5 - PLANE_SPEED * 0.55
		var along := PLANE_SPEED * _age
		while _dropped < bombs and along >= first + _dropped * BOMB_STEP:
			_drop(p)
			_dropped += 1
		if along > 200.0:
			_plane.queue_free()
			_plane = null
	# Бомбы падают с инерцией самолёта
	var k := 0
	while k < _bombs.size():
		var b: Array = _bombs[k]
		var node: Node3D = b[0]
		var v: Vector3 = b[1]
		v.y -= 30.0 * delta
		b[1] = v
		node.global_position += v * delta
		node.look_at(node.global_position + v, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.FORWARD)
		var ground: float = _map.height(Vector2(node.global_position.x, node.global_position.z)) if _map else 0.0
		if node.global_position.y <= ground + 0.2:
			_burst(Vector3(node.global_position.x, ground, node.global_position.z))
			node.queue_free()
			_bombs.remove_at(k)
			continue
		k += 1
	if not _plane and _bombs.is_empty() and _dropped > 0:
		queue_free()


func _drop(from: Vector3) -> void:
	var bomb := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 1.1
	mesh.radial_segments = 8
	mesh.rings = 2
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.24, 0.2)
	mesh.material = m
	bomb.mesh = mesh
	bomb.rotation.x = PI / 2.0
	var holder := Node3D.new()
	holder.add_child(bomb)
	get_parent().add_child(holder)
	holder.global_position = from + Vector3(0, -1.0, 0)
	_bombs.append([holder, dir * PLANE_SPEED * 0.45 + Vector3(0, -3.0, 0)])


## Напалмовая бомба упала: огненный взрыв и горящая земля.
func _burst(at: Vector3) -> void:
	var boom := ExplosionScript.new()
	boom.horde = horde
	boom.radius = 4.0
	boom.max_kills = 22
	boom.source = "airstrike"
	boom.ignite = false
	boom.silent = _fired % 2 == 1
	boom.tint = Color(1.0, 0.45, 0.08)
	boom.position = at
	get_parent().add_child(boom)
	var fire := FirePatch.new()
	fire.horde = horde
	fire.source = "airstrike"
	fire.scale_size = 1.7
	fire.burn_time = 6.0
	fire.position = at
	get_parent().add_child(fire)
	_fired += 1


# --- ракетный дождь -----------------------------------------------------------------------------

func _rain() -> void:
	var count := int(RAIN * power)
	# Круг-предупреждение мигает, пока падают ракеты
	_warn_mat.albedo_color.a = 0.45 + 0.45 * absf(sin(_age * 14.0))
	_warn.rotation.y = _age * 0.8
	var t := _age - RAIN_DELAY
	while t > 0.0 and _fired < count and t >= _fired * 0.075:
		_rocket()
		_fired += 1
	if _fired >= count and _age > RAIN_DELAY + count * 0.075 + 1.2:
		queue_free()


func _rocket() -> void:
	var off := Vector2.from_angle(randf() * TAU) * RAIN_RADIUS * sqrt(randf())
	var to := global_position + Vector3(off.x, 0.0, off.y)
	# Крупнее всего — в гущу: половина ракет целится во врагов в круге
	if horde and randf() < 0.5:
		var picks: PackedInt32Array = horde.pick_targets(global_position, RAIN_RADIUS, 0.0, 30)
		if not picks.is_empty():
			to = horde.position_of(picks[randi() % picks.size()])
	if _map:
		to.y = _map.height(Vector2(to.x, to.z))
	var from := to - dir * 30.0 + Vector3(randf_range(-6, 6), 75.0, randf_range(-6, 6))
	var shell := ShellScript.new()
	shell.horde = horde
	shell.rocket = true
	shell.source = "rocketrain"
	shell.blast_radius = 3.2
	shell.max_kills = 18
	shell.velocity = (to - from).normalized() * 95.0
	shell.target = to
	shell.has_target = true
	get_parent().add_child(shell)
	shell.global_position = from


# --- модели -----------------------------------------------------------------------------------

## Штурмовик из простых форм: фюзеляж, стреловидные крылья, хвост, светящиеся сопла. Нос — к -Z.
func _plane_model() -> Node3D:
	var root := Node3D.new()
	var body := Color(0.32, 0.36, 0.3)
	var dark := Color(0.18, 0.2, 0.18)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, 0, 0), Vector3(1.3, 1.1, 8.0), body)
	_box(st, Vector3(0, 0.15, -4.6), Vector3(0.9, 0.8, 1.4), body)
	_box(st, Vector3(0, 0.55, -2.4), Vector3(0.7, 0.45, 1.6), Color(0.45, 0.65, 0.75))
	for s in [-1.0, 1.0]:
		# Крыло — треугольник со стреловидностью
		_wing(st, Vector3(s * 0.6, 0, -1.2), Vector3(s * 6.5, 0, 1.4), Vector3(s * 0.6, 0, 2.2), body)
		_wing(st, Vector3(s * 0.6, 0, 3.2), Vector3(s * 2.6, 0, 4.4), Vector3(s * 0.6, 0, 4.4), dark)
		_box(st, Vector3(s * 2.8, -0.35, 0.6), Vector3(0.4, 0.4, 1.6), dark)
	_wing(st, Vector3(0, 0.5, 2.8), Vector3(0, 2.6, 4.4), Vector3(0, 0.5, 4.4), dark)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	root.add_child(mi)
	# Светящиеся сопла
	for s in [-0.35, 0.35]:
		var glow := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.3
		sp.height = 0.6
		glow.mesh = sp
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1.0, 0.6, 0.2)
		glow.material_override = gm
		glow.position = Vector3(s, 0, 4.1)
		root.add_child(glow)
	root.scale = Vector3.ONE * 0.9
	return root


func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var v := []
	for i in 8:
		v.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for q in [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(v[q[i]])


func _wing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _ring(outer: float, inner: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for k in n:
		if k % 4 == 3:
			continue
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		for p in [o0 * inner, o0 * outer, o1 * outer, o0 * inner, o1 * outer, o1 * inner]:
			st.add_vertex(p)
	return st.commit()
