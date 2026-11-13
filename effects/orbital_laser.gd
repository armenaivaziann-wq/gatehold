extends Node3D
## Орбитальный лазер (удар с неба, hero_abilities.gd): сначала наводка — по земле крутятся два
## кольца прицела, сужаются, из неба бьёт тонкий дрожащий луч-указатель и нарастает гул; затем
## удар — толстый столб света из космоса: белая сердцевина, голубое свечение, светящийся
## «прожиг» у земли, кольцо ударной волны, искры и обломки; луч медленно ведёт по земле вдоль dir
## и выжигает всё на пути, позади остаётся раскалённая борозда. В конце луч схлопывается в нить и
## гаснет. Ставить в точку на земле до добавления в сцену.

const FxBudget := preload("res://core/fx_budget.gd")
const HUM := preload("res://audio/sounds/laser_loop.wav")
const BOOM := preload("res://audio/sounds/explosion.wav")

const CHARGE := 1.1              # с наводки
const FIRE := 3.6                # с удара
const FADE := 0.45
const SWEEP := 14.0              # м, на сколько луч проходит по земле
const RADIUS := 3.4              # м, кого выжигает вокруг луча
const KILLS_PER_TICK := 14
const TICK := 0.1
const HEIGHT := 140.0
const CORE := Color(1.0, 0.98, 0.94)
const GLOW := Color(0.15, 0.65, 1.0)
const HOT := Color(1.0, 0.55, 0.18)

var horde: Node3D
## Куда ведёт луч по земле (единичный, горизонтальный).
var dir := Vector3.FORWARD

var _age := 0.0
var _tick := 0.0
var _start := Vector3.ZERO
var _map: Node3D
var _rings: Array[MeshInstance3D] = []
var _ring_mat: StandardMaterial3D
var _guide: MeshInstance3D
var _beam: Node3D
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _foot: MeshInstance3D
var _foot_mat: StandardMaterial3D
var _wave: MeshInstance3D
var _wave_mat: StandardMaterial3D
var _sparks: GPUParticles3D
var _debris: GPUParticles3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _trail: Array[Node3D] = []
var _trail_mat: StandardMaterial3D
var _trail_mesh: CylinderMesh
var _last_trail := Vector3.INF
var _fired := false
var _energy: Array[MeshInstance3D] = []   # кольца энергии бегут по лучу вниз
var _energy_mat: StandardMaterial3D
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D


func _ready() -> void:
	_map = get_tree().get_first_node_in_group("map")
	_start = global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	# Кольца прицела на земле
	_ring_mat = _add_mat(Color(GLOW, 0.9))
	for k in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(1.0, 0.9 if k == 0 else 0.82, 6 if k == 0 else 3)
		ring.material_override = _ring_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.25
		add_child(ring)
		_rings.append(ring)
	# Тонкий луч-указатель из неба
	_guide = _column(0.05, Color(GLOW, 0.7))
	add_child(_guide)
	# Сам луч: сердцевина, свечение, широкий ореол
	_beam = Node3D.new()
	_beam.visible = false
	add_child(_beam)
	_core = _column(0.8, Color(CORE, 1.0))
	_glow = _column(2.0, Color(GLOW, 0.8))
	_halo_mat = _add_mat(Color(GLOW, 0.18))
	_halo = MeshInstance3D.new()
	_halo.mesh = _cyl(3.4, 3.4, HEIGHT)
	_halo.material_override = _halo_mat
	_halo.position.y = HEIGHT * 0.5
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in [_core, _glow, _halo]:
		_beam.add_child(c)
	# Кольца энергии: плоские светящиеся обручи, сбегают по лучу к земле
	_energy_mat = _add_mat(Color(0.55, 0.9, 1.0, 0.9))
	var ring_mesh := _ring_mesh(1.0, 0.72, 1)
	for k in 6:
		var e := MeshInstance3D.new()
		e.mesh = ring_mesh
		e.material_override = _energy_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.add_child(e)
		_energy.append(e)
	# Вспышка удара: белый шар раздувается и гаснет
	_flash_mat = _add_mat(Color(1, 1, 1, 0.0))
	_flash = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 16
	sph.rings = 8
	_flash.mesh = sph
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	# Прожиг у земли: светящийся раскалённый диск
	_foot_mat = _add_mat(Color(1.0, 0.9, 0.7, 0.85))
	_foot = MeshInstance3D.new()
	_foot.mesh = _cyl(RADIUS, RADIUS * 1.15, 0.6)
	_foot.material_override = _foot_mat
	_foot.position.y = 0.3
	_foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(_foot)
	# Кольцо ударной волны (в момент удара разлетается)
	_wave_mat = _add_mat(Color(CORE, 0.8))
	_wave = MeshInstance3D.new()
	_wave.mesh = _ring_mesh(1.0, 0.86, 1)
	_wave.material_override = _wave_mat
	_wave.position.y = 0.4
	_wave.visible = false
	_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wave)
	_sparks = _particles(70, 0.7, Color(1, 0.95, 0.8), Color(1.0, 0.45, 0.1, 0.0), 0.09, Vector2(6, 16), -14.0, 75.0)
	_debris = _particles(40, 1.3, Color(0.25, 0.2, 0.18), Color(0.18, 0.15, 0.13, 0.0), 0.16, Vector2(5, 11), -18.0, 55.0)
	_beam.add_child(_sparks)
	_beam.add_child(_debris)
	# Раскалённая борозда позади луча
	_trail_mat = _add_mat(Color(HOT, 0.75))
	_trail_mesh = _cyl(RADIUS * 0.75, RADIUS * 0.85, 0.15)
	if FxBudget.take_light():
		_light = OmniLight3D.new()
		_light.light_color = GLOW
		_light.light_energy = 0.0
		_light.omni_range = 28.0
		_light.position.y = 4.0
		add_child(_light)
	_hum = AudioStreamPlayer3D.new()
	var loop: AudioStreamWAV = HUM.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(HUM.get_length() * HUM.mix_rate)
	_hum.stream = loop
	_hum.unit_size = 40.0
	_hum.pitch_scale = 0.45
	_hum.volume_db = -8.0
	add_child(_hum)
	_hum.play()


func _process(delta: float) -> void:
	_age += delta
	var t := _age
	if t < CHARGE:
		_charge(t / CHARGE)
		return
	if not _fired:
		_fired = true
		_ignite()
	var f := t - CHARGE
	if f < FIRE:
		_burn(f, delta)
	elif f < FIRE + FADE:
		_fade((f - FIRE) / FADE)
	else:
		_beam.visible = false
		if _light:
			FxBudget.free_light()
			_light = null
		_hum.stop()
	# Вспышка удара
	if _flash.visible:
		var fk := clampf(f / 0.22, 0.0, 1.0)
		_flash.scale = Vector3(1.0, 0.55, 1.0) * lerpf(1.5, 6.5, ease(fk, 0.3))
		_flash_mat.albedo_color = Color(0.7, 0.92, 1.0, 0.65 * (1.0 - fk))
		_flash.visible = fk < 1.0
	# Кольцо ударной волны
	if _wave.visible:
		var w := clampf(f / 0.6, 0.0, 1.0)
		var r := lerpf(2.0, 22.0, ease(w, 0.4))
		_wave.scale = Vector3(r, 1.0 + 3.0 * (1.0 - w), r)
		_wave_mat.albedo_color.a = 0.8 * (1.0 - w)
		_wave.visible = w < 1.0
	# Борозда остывает: оранжевая → тёмная
	for k in _trail.size():
		var node: Node3D = _trail[k]
		var age: float = node.get_meta("age") + delta
		node.set_meta("age", age)
		node.scale = Vector3.ONE * lerpf(1.0, 0.7, clampf(age / 4.0, 0.0, 1.0))
	_trail_mat.albedo_color = Color(HOT.lerp(Color(0.6, 0.12, 0.04), clampf((f - FIRE) / 3.0, 0.0, 1.0)),
		0.75 * clampf(1.0 - (f - FIRE - 2.0) / 3.0, 0.0, 1.0))
	if f > FIRE + 5.5:
		queue_free()


## Наводка: кольца сужаются и крутятся, указатель мерцает всё чаще, гул нарастает.
func _charge(k: float) -> void:
	var r := lerpf(9.0, RADIUS, ease(k, 0.6))
	_rings[0].scale = Vector3(r, 1, r)
	_rings[1].scale = Vector3(r * 1.25, 1, r * 1.25)
	_rings[0].rotation.y = k * 7.0
	_rings[1].rotation.y = -k * 11.0
	_ring_mat.albedo_color.a = 0.5 + 0.5 * absf(sin(k * k * 40.0))
	_guide.visible = randf() < 0.4 + 0.6 * k
	_guide.scale = Vector3(1.0 + k * 2.0, 1.0, 1.0 + k * 2.0)
	_hum.pitch_scale = lerpf(0.45, 1.1, k)
	if _light:
		_light.light_energy = 2.0 * k


## Удар: луч появляется, вспышка, волна, тряска, грохот.
func _ignite() -> void:
	_beam.visible = true
	_flash.visible = true
	_flash.position.y = 1.5
	_guide.visible = false
	for ring in _rings:
		ring.visible = false
	_wave.visible = true
	_sparks.emitting = true
	_debris.emitting = true
	_hum.pitch_scale = 0.7
	_hum.volume_db = 0.0
	var boom := AudioStreamPlayer3D.new()
	boom.stream = BOOM
	boom.unit_size = 60.0
	boom.pitch_scale = 0.6
	add_child(boom)
	boom.play()
	get_tree().call_group("player", "shake", 1.0)
	if horde:
		horde.kill_area(_start, RADIUS * 1.6, 60, "orbital", 4)


## Горит: ведёт по земле, дрожит, выжигает, оставляет борозду.
func _burn(f: float, delta: float) -> void:
	var k := f / FIRE
	var at := _start + dir * SWEEP * ease(k, 0.9)
	if _map:
		at.y = _map.height(Vector2(at.x, at.z))
	_beam.global_position = at
	var jitter := 1.0 + 0.12 * sin(f * 53.0) + 0.08 * sin(f * 31.0)
	_core.scale = Vector3(jitter, 1, jitter)
	_glow.scale = Vector3(1.0 + 0.2 * sin(f * 17.0), 1, 1.0 + 0.2 * sin(f * 17.0))
	_halo_mat.albedo_color.a = 0.14 + 0.06 * sin(f * 9.0)
	_foot_mat.albedo_color.a = 0.75 + 0.2 * sin(f * 41.0)
	# Кольца энергии бегут сверху вниз и сжимаются у земли
	for e in _energy.size():
		var ph := fmod(f * 0.9 + float(e) / _energy.size(), 1.0)
		var node := _energy[e]
		node.position.y = lerpf(45.0, 0.6, ph)
		var rr := lerpf(2.6, 4.6, ph)
		node.scale = Vector3(rr, 1, rr)
		node.rotation.y = f * 3.0 + e
	_energy_mat.albedo_color.a = 0.9
	if _light:
		_light.global_position = at + Vector3(0, 4, 0)
		_light.light_energy = 14.0 + 4.0 * sin(f * 23.0)
	get_tree().call_group("player", "shake", 0.25)
	_tick += delta
	while _tick >= TICK:
		_tick -= TICK
		if horde:
			horde.kill_area(at, RADIUS, KILLS_PER_TICK, "orbital", 4)
	# Борозда — раскалённые пятна каждые полтора метра
	if _last_trail == Vector3.INF or _last_trail.distance_to(at) > 1.5:
		_last_trail = at
		var spot := MeshInstance3D.new()
		spot.mesh = _trail_mesh
		spot.material_override = _trail_mat
		spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.set_meta("age", 0.0)
		get_parent().add_child(spot)
		spot.global_position = at + Vector3(0, 0.08, 0)
		spot.tree_exiting.connect(func() -> void: _trail.erase(spot))
		_trail.append(spot)


## Гаснет: луч схлопывается в нить, свет тухнет.
func _fade(k: float) -> void:
	var s := 1.0 - ease(k, 0.5)
	_core.scale = Vector3(s, 1, s)
	_glow.scale = Vector3(s * 0.6, 1, s * 0.6)
	_halo_mat.albedo_color.a = 0.18 * s
	_energy_mat.albedo_color.a = 0.9 * s
	_foot_mat.albedo_color.a = 0.8 * s
	_sparks.emitting = false
	_debris.emitting = false
	if _light:
		_light.light_energy = 14.0 * s
	_hum.volume_db = linear_to_db(maxf(s, 0.001))
	if k > 0.95:
		_beam.visible = false


func _exit_tree() -> void:
	if _light:
		FxBudget.free_light()
		_light = null
	for node in _trail:
		if is_instance_valid(node):
			node.queue_free()


# --- сборка ------------------------------------------------------------------------------------

func _column(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _cyl(r, r, HEIGHT)
	mi.material_override = _add_mat(col)
	mi.position.y = HEIGHT * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _cyl(r0: float, r1: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	return c


func _add_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


## Плоское кольцо радиуса 1 (масштабируется) с внутренним радиусом inner; dashes > 1 — пунктир.
func _ring_mesh(outer: float, inner: float, dashes: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for k in n:
		if dashes > 1 and (k * dashes / n) % 2 == 1:
			continue
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		for v in [o0 * inner, o0 * outer, o1 * outer, o0 * inner, o1 * outer, o1 * inner]:
			st.add_vertex(v)
	return st.commit()


func _particles(amount: int, life: float, c0: Color, c1: Color, size: float, speed: Vector2, grav: float,
		spread: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 20, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = RADIUS * 0.6
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0, grav, 0)
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = m
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position.y = 0.5
	return p
