extends Node3D
## Заряд гравипушки и чёрная дыра из него.
## Сначала летит маленькое чёрное ядро в фиолетовом ореоле — по прямой к точке под прицелом
## (или, если прицел смотрел в небо, до земли под концом полёта). Там раскрывается чёрная дыра:
## ядро со светящимся ободком, вращающийся диск и полосы, затягиваемые по спирали. LIFE секунд
## она тянет к себе всех в радиусе RADIUS (horde.pull) и забирает дошедших до ядра — их модели
## докручиваются внутрь и исчезают. Потом схлопывается со вспышкой.

const LOOP_SOUND := preload("res://audio/sounds/blackhole_loop.wav")
const ExplosionScript := preload("res://effects/explosion.gd")
const COLLAPSE_SOUND := preload("res://audio/sounds/blackhole_collapse.wav")
const CoreShader := preload("res://effects/shaders/black_hole_core.gdshader")
const DiskShader := preload("res://effects/shaders/black_hole_disk.gdshader")
const SwirlShader := preload("res://effects/shaders/black_hole_swirl.gdshader")

const RADIUS := 9.0          # м: кого тянет
const CORE := 1.3            # м: кого забирает (по земле)
const PULL_SPEED := 11.0     # м/с у самого ядра (с краю — треть)
const LIFE := 4.0            # с: сколько держится
const OPEN_TIME := 0.35      # с: раскрытие и схлопывание
const KILLS_PER_FRAME := 6
const HOVER := 1.1           # м над землёй
const FLIGHT_SPEED := 45.0
const MAX_FLIGHT := 2.5      # с
const SAFE_DISTANCE := 2.5   # первые метры полёта о стены не бьётся
const SWALLOW_TIME := 0.6    # с: жертва докручивается в ядро
const MAX_VICTIMS := 64

var horde: Node3D
## С мастерством гравипушки: радиус затягивания, ядро, сила, сколько держится, взрыв в конце.
var radius := RADIUS
var core := CORE
var pull_speed := PULL_SPEED
var life := LIFE
var collapse_blast := false
## Сила взрыва при коллапсе («Сверхновая» — огромный золотой).
var blast_scale := 0.6
var blast_kills := 140
var blast_tint := Color(0, 0, 0, 0)
## Точка под прицелом и попал ли прицел во что-то (иначе — летим прямо до земли).
var target := Vector3.ZERO
var has_target := false
var velocity := Vector3.ZERO
var exclude: Array[RID] = []

var _flying := true
var _collapsed := false
var _age := 0.0
var _flight := 0.0
var _travelled := 0.0
var _body: Node3D             # раскрывающаяся часть (масштаб 0 → 1)
var _core: MeshInstance3D
var _orb: MeshInstance3D
var _light: OmniLight3D
var _loop: AudioStreamPlayer3D
var _victims: MultiMesh
var _victim_list: Array[Dictionary] = []   # {from: Vector3, angle, spin, t}


func _ready() -> void:
	_orb = MeshInstance3D.new()
	_orb.mesh = _sphere(0.22, 10, 5)
	_orb.material_override = _core_material(4.0)
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.65, 0.35, 1.0)
	_light.light_energy = 2.0
	_light.omni_range = 4.0
	add_child(_light)
	_body = Node3D.new()
	_body.scale = Vector3.ONE * 0.001
	_body.visible = false
	add_child(_body)
	_core = MeshInstance3D.new()
	_core.mesh = _sphere(0.85, 16, 8)
	_core.material_override = _core_material(5.0)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_core)
	# Два диска под разными наклонами и спиральные полосы по всему радиусу затягивания
	for tilt in [Vector3(0.25, 0.0, 0.1), Vector3(-0.35, 1.2, -0.2)]:
		var disk := MeshInstance3D.new()
		disk.mesh = _annulus(0.85, 3.4, 32)
		var m := ShaderMaterial.new()
		m.shader = DiskShader
		m.set_shader_parameter("inner", 0.85)
		m.set_shader_parameter("outer", 3.4)
		disk.material_override = m
		disk.rotation = tilt
		disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body.add_child(disk)
	var swirl := MeshInstance3D.new()
	swirl.mesh = swirl_mesh(140)
	var sm := ShaderMaterial.new()
	sm.shader = SwirlShader
	sm.set_shader_parameter("radius", radius)
	sm.set_shader_parameter("core", 0.8)
	swirl.material_override = sm
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Полосы — в своём масштабе (не раскрываются вместе с ядром), гаснут по общей яркости
	swirl.position.y = -HOVER + 0.3
	swirl.visible = false
	swirl.name = "Swirl"
	add_child(swirl)
	# Затянутые: та же модель, что у орды, докручивается в ядро
	_victims = MultiMesh.new()
	_victims.transform_format = MultiMesh.TRANSFORM_3D
	_victims.mesh = horde._mm.mesh if horde else null
	_victims.instance_count = MAX_VICTIMS
	_victims.visible_instance_count = 0
	var vmi := MultiMeshInstance3D.new()
	vmi.multimesh = _victims
	var vm := StandardMaterial3D.new()
	vm.vertex_color_use_as_albedo = true
	vmi.material_override = vm
	vmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vmi.top_level = true
	vmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(vmi)
	_loop = AudioStreamPlayer3D.new()
	var loop: AudioStreamWAV = LOOP_SOUND.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(LOOP_SOUND.get_length() * LOOP_SOUND.mix_rate)
	_loop.stream = loop
	_loop.unit_size = 16.0
	_loop.volume_db = -4.0
	add_child(_loop)


func _physics_process(delta: float) -> void:
	if not _flying:
		return
	_flight += delta
	var from := global_position
	var to := from + velocity * delta
	_travelled += from.distance_to(to)
	if has_target:
		if (target - from).dot(velocity) <= 0.0 or from.distance_to(target) <= velocity.length() * delta:
			_open(target)
			return
	elif _travelled > SAFE_DISTANCE:
		var hit := _ray(from, to)
		if not hit.is_empty():
			_open(hit.position)
			return
	global_position = to
	if _flight > MAX_FLIGHT:
		# Улетел в небо — раскрываемся на земле под концом полёта
		var ground := _ray(to, to + Vector3.DOWN * 200.0)
		_open(ground.position if not ground.is_empty() else to)


func _process(delta: float) -> void:
	_orb.rotation.y += delta * 6.0
	if _flying:
		return
	_age += delta
	var open := clampf(_age / OPEN_TIME, 0.0, 1.0)
	var close := clampf((life - _age) / OPEN_TIME, 0.0, 1.0)
	var k := ease(minf(open, close), 0.5)
	_body.scale = Vector3.ONE * maxf(k, 0.001)
	_body.rotation.y += delta * 1.5
	_light.light_energy = 6.0 * k + sin(_age * 9.0) * 0.6 * k
	var swirl: MeshInstance3D = get_node("Swirl")
	(swirl.material_override as ShaderMaterial).set_shader_parameter("energy", 2.0 * k)
	if horde and _age < life - OPEN_TIME * 0.5:
		var p := global_position
		for at in horde.pull(Vector3(p.x, p.y - HOVER, p.z), radius * k, pull_speed, core, delta, KILLS_PER_FRAME, "gravigun"):
			_swallow(at)
	_update_victims(delta)
	if _age >= life - OPEN_TIME and not _collapsed:
		_collapsed = true
		if collapse_blast:
			# Коллапс: схлопываясь, дыра взрывается
			var boom := ExplosionScript.new()
			boom.horde = horde
			boom.radius = radius * blast_scale
			boom.max_kills = blast_kills
			boom.tint = blast_tint
			boom.source = "gravigun"
			boom.position = global_position - Vector3(0, HOVER, 0)
			get_parent().add_child(boom)
		_loop.stop()
		var boom := AudioStreamPlayer3D.new()
		boom.stream = COLLAPSE_SOUND
		boom.unit_size = 18.0
		add_child(boom)
		boom.play()
	if _age >= life + 1.0:
		queue_free()


## Раскрыться в точке at (над землёй на HOVER).
func _open(at: Vector3) -> void:
	_flying = false
	global_position = at + Vector3(0, HOVER, 0)
	_orb.visible = false
	_body.visible = true
	_light.omni_range = 12.0
	(get_node("Swirl") as Node3D).visible = true
	_loop.play()


func _swallow(at: Vector3) -> void:
	if _victim_list.size() >= MAX_VICTIMS:
		return
	var off := at - global_position
	_victim_list.append({"from": off, "angle": 0.0, "spin": randf_range(6.0, 11.0), "t": 0.0,
		"yaw": randf() * TAU, "size": randf_range(0.85, 1.15)})


## Затянутые летят в ядро по сужающейся спирали, кувыркаясь и уменьшаясь.
func _update_victims(delta: float) -> void:
	var i := 0
	while i < _victim_list.size():
		var v: Dictionary = _victim_list[i]
		v["t"] += delta / SWALLOW_TIME
		if v["t"] >= 1.0:
			_victim_list.remove_at(i)
			continue
		i += 1
	var center := global_position
	for k in _victim_list.size():
		var v: Dictionary = _victim_list[k]
		var t: float = v["t"]
		var shrink := (1.0 - t) * (1.0 - t)
		var off: Vector3 = v["from"]
		var pos := center + off.rotated(Vector3.UP, t * 4.0) * shrink
		var basis := Basis(Vector3.UP, v["yaw"] + t * v["spin"]) * Basis(Vector3.RIGHT, t * v["spin"] * 0.7)
		_victims.set_instance_transform(k, Transform3D(basis.scaled(Vector3.ONE * v["size"] * maxf(1.0 - t, 0.05)), pos))
	_victims.visible_instance_count = _victim_list.size()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query)


func _core_material(rim: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CoreShader
	m.set_shader_parameter("rim_energy", rim)
	return m


func _sphere(r: float, segs: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


## Плоское кольцо в плоскости XZ.
func _annulus(r0: float, r1: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		for v in [p0 * r0, p0 * r1, p1 * r1, p0 * r0, p1 * r1, p1 * r0]:
			st.add_vertex(v)
	return st.commit()


## Меш спиральных полос для black_hole_swirl.gdshader: count лент по 4 вершины; в UV —
## начальный угол и сдвиг фазы, в UV2 — угол вершины ленты (вдоль, поперёк).
static func swirl_mesh(count: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in count:
		var a := rng.randf() * TAU
		var ph := rng.randf()
		var base := verts.size()
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			verts.append(Vector3.ZERO)
			uv.append(Vector2(a, ph))
			uv2.append(c)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Вершины двигает шейдер — границы задаём сами, чтобы полосы не отсекались
	mesh.custom_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 8, 24))
	return mesh
