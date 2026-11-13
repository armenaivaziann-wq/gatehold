extends Node3D
## Звуки орды:
##   рой — несколько источников стрекота и щёлканья лапок встают на ближайшие к слушателю
##   скопления жуков (громче, где жуков больше), плюс далёкий общий гул всей орды;
##   ворота — глухой удар с хрустом, когда жуки врезаются в ворота;
##   рог — тревожный гудок при приходе босса (на старте боя не звучит);
##   смерть — хруст хитина там, где погибли жуки.
## На локации с гоблинами вместо стрекота — ворчание и топот толпы, вместо хруста — визг.

const SWARM := preload("res://audio/sounds/swarm_loop.wav")
const GATE_HIT := preload("res://audio/sounds/gate_hit.wav")
const HORN := preload("res://audio/sounds/wave_horn.wav")
const SQUISH := preload("res://audio/sounds/squish.wav")
const GOBLIN_CROWD := preload("res://audio/sounds/goblin_loop.wav")
const GOBLIN_DIE := preload("res://audio/sounds/goblin_die.wav")
const MapBuilder := preload("res://locations/map_builder.gd")

const VOICES := 4                 # источников роя
const VOICE_SPACING := 14.0       # м между источниками
const HEAR_DISTANCE := 85.0       # дальше — только общий гул
const UPDATE := 0.35              # с между перестановкой источников
const GATE_COOLDOWN := 0.12
const SQUISH_COOLDOWN := 0.07

var horde: Node3D
var waves: Node

var _voices: Array[AudioStreamPlayer3D] = []
var _targets: Array[Vector3] = []
var _levels: Array[float] = []
var _distant: AudioStreamPlayer
var _gate: AudioStreamPlayer3D
var _horn: AudioStreamPlayer
var _squish: AudioStreamPlayer3D
var _timer := 0.0
var _gate_cool := 0.0
var _squish_cool := 0.0
var _last_kills := 0


func _ready() -> void:
	var goblins: bool = horde and horde.monster == "goblin"
	var crowd: AudioStreamWAV = GOBLIN_CROWD if goblins else SWARM
	var loop: AudioStreamWAV = crowd.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(crowd.get_length() * crowd.mix_rate)
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.stream = loop
		v.unit_size = 9.0
		v.max_distance = HEAR_DISTANCE + 20.0
		v.volume_db = -80.0
		v.pitch_scale = 0.9 + i * 0.07
		v.top_level = true
		add_child(v)
		v.play(randf() * crowd.get_length())
		_voices.append(v)
		_targets.append(Vector3.ZERO)
		_levels.append(0.0)
	_distant = AudioStreamPlayer.new()
	_distant.stream = loop
	_distant.volume_db = -80.0
	_distant.pitch_scale = 0.75
	add_child(_distant)
	_distant.play()
	_gate = AudioStreamPlayer3D.new()
	_gate.stream = GATE_HIT
	_gate.unit_size = 22.0
	_gate.max_polyphony = 4
	_gate.position = Vector3(0, 2.5, MapBuilder.GATE_Z - 1.5)
	add_child(_gate)
	_horn = AudioStreamPlayer.new()
	_horn.stream = HORN
	_horn.volume_db = -5.0
	add_child(_horn)
	_squish = AudioStreamPlayer3D.new()
	_squish.stream = GOBLIN_DIE if goblins else SQUISH
	_squish.unit_size = 14.0
	_squish.max_polyphony = 6
	_squish.top_level = true
	add_child(_squish)
	if waves:
		waves.gate_hit.connect(_on_gate_hit)
		# Рога на старте боя больше нет: низкий гудок звучал как жужжание (просьба пользователя).
		# Сам _horn остался — его зовёт приход босса (main.gd), когда боссы снова включат.


func _process(delta: float) -> void:
	if not horde:
		return
	_gate_cool = maxf(_gate_cool - delta, 0.0)
	_squish_cool = maxf(_squish_cool - delta, 0.0)
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE
		_place_voices()
	# Источники плавно переезжают и меняют громкость — без щелчков и скачков
	for i in VOICES:
		var v := _voices[i]
		v.global_position = v.global_position.lerp(_targets[i], minf(delta * 3.0, 1.0))
		var want := linear_to_db(maxf(_levels[i], 0.0001)) - 3.0
		v.volume_db = move_toward(v.volume_db, want, delta * 90.0)
	var total: float = horde.count()
	var far := clampf(total / 2500.0, 0.0, 1.0) * 0.35
	_distant.volume_db = move_toward(_distant.volume_db, linear_to_db(maxf(far, 0.0001)), delta * 30.0)
	# Хруст там, где только что погибли жуки
	var kills: int = horde.kills
	if kills > _last_kills and _squish_cool == 0.0:
		_squish_cool = SQUISH_COOLDOWN
		_squish.global_position = horde.last_hit + Vector3(0, 0.5, 0)
		_squish.pitch_scale = randf_range(0.8, 1.3)
		_squish.volume_db = linear_to_db(clampf(0.4 + (kills - _last_kills) * 0.05, 0.4, 1.0)) - 2.0
		_squish.play()
	_last_kills = kills


## Источники роя — на ближайшие к слушателю скопления жуков, не теснее VOICE_SPACING.
func _place_voices() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var ear := cam.global_position
	var n: int = horde.count()
	var step := maxi(1, n / 500)
	var near: Array[Vector2] = []
	for i in range(0, n, step):
		var p: Vector3 = horde.position_of(i)
		var d := ear.distance_to(p)
		if d < HEAR_DISTANCE:
			near.append(Vector2(d, i))
	near.sort()
	var picked: Array[Vector3] = []
	for item in near:
		if picked.size() >= VOICES:
			break
		var p: Vector3 = horde.position_of(int(item.y))
		var ok := true
		for q in picked:
			if q.distance_to(p) < VOICE_SPACING:
				ok = false
				break
		if ok:
			picked.append(p)
	for i in VOICES:
		if i < picked.size():
			var count: int = horde.count_near(picked[i], 7.0)
			# Источник, которого не было, сразу ставим на место — без «перелёта» через карту
			if _levels[i] < 0.01:
				_voices[i].global_position = picked[i]
			_targets[i] = picked[i]
			_levels[i] = clampf(count / 30.0, 0.2, 1.0)
		else:
			_levels[i] = 0.0


func _on_gate_hit(damage: int) -> void:
	if _gate_cool > 0.0:
		return
	_gate_cool = GATE_COOLDOWN
	_gate.pitch_scale = randf_range(0.85, 1.15)
	_gate.volume_db = linear_to_db(clampf(0.5 + damage * 0.1, 0.5, 1.0))
	_gate.play()
