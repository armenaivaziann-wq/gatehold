extends Node3D
## Копья орков: кто стоит под героем, метает в него копья. Чем ниже он летит и чем гуще толпа
## под ним, тем чаще. Выше REACH над землёй копья не долетают — там безопасно, но и бить сверху
## далеко. Копьё летит навесом в точку, где герой будет через время полёта; попало — урон.
## Только пока идёт волна и только в полёте: на стене за зубцами копья не достают.

const REACH := 22.0              # м: дальше (по прямой от орка до героя) не бросают
const SPEED := 26.0
const DAMAGE := 4.0
const EVERY := 0.5               # с между залпами
const PER_CROWD := 40            # врагов рядом на одно копьё в залпе
const MAX_PER_VOLLEY := 3
const HIT_RADIUS := 1.5

var horde: Node3D
var waves: Node
var player: CharacterBody3D

var _timer := 0.0
var _flying: Array = []          # [узел, откуда, куда, время, всего]
static var _mesh: ArrayMesh


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = EVERY
		if waves.state == waves.State.FIGHT and player.down_left <= 0.0 and player.active and player.flying:
			_volley()
	var k := 0
	while k < _flying.size():
		var s: Array = _flying[k]
		s[3] += delta
		var t: float = s[3] / s[4]
		var node: Node3D = s[0]
		var from: Vector3 = s[1]
		var to: Vector3 = s[2]
		var p := from.lerp(to, minf(t, 1.0)) + Vector3.UP * 3.0 * 4.0 * t * (1.0 - t)
		var ahead := from.lerp(to, minf(t + 0.03, 1.0)) + Vector3.UP * 3.0 * 4.0 * (t + 0.03) * (1.0 - t - 0.03)
		node.global_position = p
		if p.distance_to(ahead) > 0.001:
			var along := (ahead - p).normalized()
			node.look_at(ahead, Vector3.UP if absf(along.y) < 0.98 else Vector3.FORWARD)
		if t >= 1.0:
			# Долетело: попало, если герой ещё рядом с точкой
			if player.global_position.distance_to(to) < HIT_RADIUS + 0.6 or \
					(player.global_position + Vector3.UP).distance_to(to) < HIT_RADIUS:
				player.take_hit(DAMAGE)
			node.queue_free()
			_flying.remove_at(k)
			continue
		k += 1


func _volley() -> void:
	var at := player.global_position
	var near: int = horde.count_near(at, REACH)
	if near < 8:
		return
	var n := mini(near / PER_CROWD + 1, MAX_PER_VOLLEY)
	var picks: PackedInt32Array = horde.pick_targets(at, REACH, 0.0, n * 6)
	for k in n:
		if picks.is_empty():
			return
		var i: int = picks[randi() % picks.size()]
		var from: Vector3 = horde.position_of(i) + Vector3(0, 1.2, 0)
		var dist := from.distance_to(at)
		if dist > REACH:
			continue
		var time := dist / SPEED
		# В точку, где герой будет, с небольшим разбросом
		var to := at + player.velocity * time + Vector3(randf_range(-0.8, 0.8), 0.9 + randf_range(-0.5, 0.5), randf_range(-0.8, 0.8))
		var node := MeshInstance3D.new()
		node.mesh = _spear_mesh()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.global_position = from
		_flying.append([node, from, to, 0.0, maxf(time, 0.2)])


## Копьё: древко и железный наконечник (нос — к -Z).
static func _spear_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.45, 0.3, 0.16)
	var iron := Color(0.55, 0.55, 0.58)
	var r := 0.035
	for k in 4:
		var a0 := k * TAU / 4.0
		var a1 := (k + 1) * TAU / 4.0
		var d0 := Vector3(cos(a0), sin(a0), 0) * r
		var d1 := Vector3(cos(a1), sin(a1), 0) * r
		for v in [d0 + Vector3(0, 0, 0.9), d1 + Vector3(0, 0, 0.9), d1 + Vector3(0, 0, -0.6),
				d0 + Vector3(0, 0, 0.9), d1 + Vector3(0, 0, -0.6), d0 + Vector3(0, 0, -0.6)]:
			st.set_color(wood)
			st.set_normal(Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0))
			st.add_vertex(v)
		for v in [d0 * 2.2 + Vector3(0, 0, -0.6), d1 * 2.2 + Vector3(0, 0, -0.6), Vector3(0, 0, -0.95)]:
			st.set_color(iron)
			st.set_normal(Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), -0.5).normalized())
			st.add_vertex(v)
	_mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.surface_set_material(0, mat)
	return _mesh
