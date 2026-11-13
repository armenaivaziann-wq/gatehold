extends Node3D
## Модель босса или вожака поверх орды (models/bosses/*.glb, исходник art_src/bosses/build_bosses.py).
## Сам босс — обычный враг в horde.gd (путь, прочность, по нему бьют турели), модель лишь идёт за
## ним. Два вида моделей:
##   двуногий (Hips, в нём Torso, в Torso — ArmL и ArmR; LegL, LegR) — шагает, машет руками, у
##     ворот замахивается дубиной; убит — падает навзничь;
##   верхом на звере (Body; LegFL, LegFR, LegBL, LegBR) — бежит рысью (ноги накрест), у ворот
##     встаёт на дыбы и бьёт передними лапами; убит — валится на бок.
## Убитый через несколько секунд уходит в землю; дошедший до ворот бьёт по ним и исчезает.
## У каждой части начало — в шарнире.

const MapBuilder := preload("res://locations/map_builder.gd")

const MODEL_HEIGHT := 2.0        # рост модели, м: масштаб — под размер босса в орде
const STRIDE := 0.9              # длина полушага модели, м (до масштаба)
const GATE_REACH := 10.0         # м до ворот: отсюда бьёт
const SWING_TIME := 1.3          # с на замах и удар
const LIE_TIME := 6.0            # с лежит, потом уходит в землю
const SINK_TIME := 3.0

var horde: Node3D
var scene: PackedScene
var size := 3.4

var _model: Node3D
var _quad := false
var _hips: Node3D
var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _body: Node3D
var _legs: Array[Node3D] = []    # у зверя: FL, FR, BL, BR
var _hip_y := 0.0
var _walk := 0.0
var _swing := 0.0
var _state := "walk"             # walk, dead, gone
var _t := 0.0


func _ready() -> void:
	_model = scene.instantiate()
	add_child(_model)
	scale = Vector3.ONE * size / MODEL_HEIGHT
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_quad = _model.find_child("LegFL") != null
	if _quad:
		_body = _model.find_child("Body")
		for leg in ["LegFL", "LegFR", "LegBL", "LegBR"]:
			_legs.append(_model.find_child(leg))
		_hip_y = _body.position.y
	else:
		_hips = _model.find_child("Hips")
		_torso = _model.find_child("Torso")
		_arm_l = _model.find_child("ArmL")
		_arm_r = _model.find_child("ArmR")
		_leg_l = _model.find_child("LegL")
		_leg_r = _model.find_child("LegR")
		_hip_y = _hips.position.y
	_follow(0.0, true)


## Убит: упасть, полежать и уйти в землю.
func die() -> void:
	_state = "dead"
	_t = 0.0


## Дошёл до ворот: последний удар — и исчезает.
func break_through() -> void:
	_state = "gone"
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	match _state:
		"walk":
			_follow(delta, false)
		"dead":
			var k := clampf(_t / 0.55, 0.0, 1.0)
			if _quad:
				# Зверь валится на бок, лапы вытянуты
				_model.rotation.z = ease(k, 2.2) * PI * 0.5
				for leg in _legs:
					leg.rotation.x = 0.3 * k
			else:
				# Валится назад на спину за полсекунды, руки раскинуты
				_model.rotation.x = ease(k, 2.2) * PI * 0.5
				_arm_l.rotation = Vector3(-2.2 * k, 0.0, -0.6 * k)
				_arm_r.rotation = Vector3(-2.2 * k, 0.0, 0.6 * k)
				_leg_l.rotation.x = 0.25 * k
				_leg_r.rotation.x = -0.15 * k
			if _t > LIE_TIME:
				_model.position.y = -(_t - LIE_TIME) / SINK_TIME * 1.2
			if _t > LIE_TIME + SINK_TIME:
				queue_free()
		"gone":
			# Удар по воротам и рывок сквозь них
			if _quad:
				_body.rotation.x = lerpf(0.6, -0.1, clampf(_t / 0.25, 0.0, 1.0))
			else:
				_arm_r.rotation.x = lerpf(3.0, 0.9, clampf(_t / 0.25, 0.0, 1.0))
			if _t > 0.35:
				_model.position.y = -(_t - 0.35) * 6.0
			if _t > 0.8:
				queue_free()


## Встать на место «своего» врага в орде; шаг, у ворот — удары.
func _follow(delta: float, snap: bool) -> void:
	var i: int = horde.boss_index()
	if i < 0:
		return
	var v: Vector3 = horde.velocity_of(i)
	var p: Vector3 = horde.position_of(i) + v * horde.lag()
	global_position = Vector3(p.x, p.y - 0.35, p.z)
	var speed := Vector2(v.x, v.z).length()
	if speed > 0.2:
		var want := atan2(-v.x, -v.z)
		rotation.y = want if snap else lerp_angle(rotation.y, want, 1.0 - exp(-5.0 * delta))
	_walk += delta * speed / (STRIDE * scale.x) * PI
	var step := sin(_walk) * minf(speed / 1.5, 1.0)
	var near_gate: bool = MapBuilder.GATE_Z - global_position.z < GATE_REACH
	if near_gate:
		_swing = fposmod(_swing + delta / SWING_TIME, 1.0)
	else:
		_swing = 0.0
	var raise := ease(clampf(_swing / 0.7, 0.0, 1.0), 0.5)
	var hit := clampf((_swing - 0.7) / 0.12, 0.0, 1.0)
	if _quad:
		_trot(step, raise, hit, near_gate)
	else:
		_stride(step, raise, hit, near_gate)


## Двуногий: ноги, корпус, свободная рука; дубина — в такт шагу или замах у ворот.
func _stride(step: float, raise: float, hit: float, near_gate: bool) -> void:
	_leg_l.rotation.x = step * 0.5
	_leg_r.rotation.x = -step * 0.5
	_hips.position.y = _hip_y + absf(sin(_walk)) * 0.05
	_torso.rotation.y = step * 0.1
	_arm_l.rotation.x = -step * 0.4
	if near_gate:
		_arm_r.rotation.x = lerpf(0.2 + raise * 2.8, 0.9, hit)
		_torso.rotation.x = -0.15 * raise + 0.25 * hit
	else:
		_arm_r.rotation.x = 0.15 + step * 0.2
		_torso.rotation.x = 0.06


## Зверь: рысь — левая передняя с правой задней; у ворот встаёт на дыбы и бьёт лапами.
func _trot(step: float, raise: float, hit: float, near_gate: bool) -> void:
	var swing := step * 0.6
	_legs[0].rotation.x = swing
	_legs[3].rotation.x = swing
	_legs[1].rotation.x = -swing
	_legs[2].rotation.x = -swing
	_body.position.y = _hip_y + absf(sin(_walk)) * 0.06
	_body.rotation.x = cos(_walk) * 0.04
	if near_gate:
		var rear := lerpf(raise * 0.55, -0.08, hit)
		_body.rotation.x = rear
		_legs[0].rotation.x = rear * 2.2
		_legs[1].rotation.x = rear * 2.0
