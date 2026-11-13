extends Node3D
## Награда вылетает из убитых: над местом последних смертей (horde.last_hit) всплывает золотое
## «+N» — сколько монет принесли эти убийства — подлетает, растёт и тает. Раз в EVERY секунд,
## из пула надписей (их немного — сотни смертей в секунду не плодят узлы). Далеко от камеры не
## показываются. Ещё рубежи убийств (каждые MILESTONE): крупное сообщение и монеты в награду.

const EVERY := 0.14
const LIFE := 0.9
const POOL := 18
const SHOW_DISTANCE := 110.0
const MILESTONE := 1000
const MILESTONE_COINS := 30

var horde: Node3D
var waves: Node
var hud: CanvasLayer

var _labels: Array[Label3D] = []
var _ages: Array[float] = []
var _next := 0
var _timer := 0.0
var _last_kills := 0
var _last_coins := 0
var _milestone := 0


func _ready() -> void:
	for k in POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font_size = 40
		l.outline_size = 12
		l.modulate = Color(1.0, 0.84, 0.3)
		l.outline_modulate = Color(0.25, 0.12, 0.02, 0.9)
		l.visible = false
		add_child(l)
		_labels.append(l)
		_ages.append(LIFE)
	if horde:
		_last_kills = horde.kills
	if waves:
		_last_coins = waves.coins


## Новый бой (счёт с нуля).
func reset() -> void:
	_last_kills = horde.kills if horde else 0
	_last_coins = waves.coins if waves else 0
	_milestone = 0
	for l in _labels:
		l.visible = false


func _process(delta: float) -> void:
	for k in _labels.size():
		if _ages[k] >= LIFE:
			continue
		_ages[k] += delta
		var t := _ages[k] / LIFE
		var l := _labels[k]
		l.position.y += delta * 2.2 * (1.0 - t)
		l.scale = Vector3.ONE * (0.6 + 0.6 * ease(minf(t * 4.0, 1.0), 0.4))
		l.modulate.a = 1.0 - ease(t, 3.0)
		l.outline_modulate.a = l.modulate.a * 0.9
		l.visible = t < 1.0
	if not horde or not waves:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = EVERY
	var kills: int = horde.kills
	var coins: int = waves.coins
	var dk := kills - _last_kills
	var dc := coins - _last_coins
	_last_kills = kills
	_last_coins = coins
	if dk <= 0:
		return
	var cam := get_viewport().get_camera_3d()
	var at: Vector3 = horde.last_hit
	if cam and cam.global_position.distance_to(at) < SHOW_DISTANCE and dc > 0:
		_pop(at + Vector3(randf_range(-0.6, 0.6), 1.4, randf_range(-0.6, 0.6)), "+%d" % dc, dc)
	# Рубежи убийств: 1 000, 2 000, … — сообщение и монеты сверху
	var m := kills / MILESTONE
	if m > _milestone:
		_milestone = m
		waves.coins += MILESTONE_COINS
		if hud:
			hud.toast("%s убито! · +%d монет" % [_group(m * MILESTONE), MILESTONE_COINS], Color(1.0, 0.78, 0.25))


func _pop(at: Vector3, text: String, amount: int) -> void:
	var l := _labels[_next]
	_ages[_next] = 0.0
	_next = (_next + 1) % _labels.size()
	l.text = text
	l.font_size = 40 if amount < 5 else (52 if amount < 15 else 64)
	l.global_position = at
	l.modulate = Color(1.0, 0.84, 0.3, 1.0)
	l.visible = true


static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
