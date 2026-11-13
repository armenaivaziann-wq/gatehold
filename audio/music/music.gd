extends Node
## Музыка на шине «Music» — её громкость отдельно в настройках. Треки пользователя (Suno):
## меню — «Calme avant la bataille» (music_menu.mp3), стройка обороны до выхода орды — «The Last
## Stand» (music_build.mp3), бой — «The Last Line» (music_fight.mp3). Смена трека — с плавным
## угасанием. Победа и поражение — короткие заставки, музыка на это время замолкает.
## Старая синтезированная тема боя (music_battle.wav, tools/make_music.py) больше не играет.

const MENU := preload("res://audio/music/music_menu.mp3")
const BUILD := preload("res://audio/music/music_build.mp3")
const FIGHT := preload("res://audio/music/music_fight.mp3")
const WIN := preload("res://audio/music/sting_win.wav")
const LOSE := preload("res://audio/music/sting_lose.wav")
const FADE := 1.2               # с на полное угасание или нарастание

var _player: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _want: AudioStream
var _want_level := 0.0
var _level := 0.0
var _hold := 0.0                # с тишины после заставки
var _loops := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.volume_db = -80.0
	add_child(_player)
	_sting = AudioStreamPlayer.new()
	_sting.bus = "Music"
	add_child(_sting)


## Что должно играть сейчас и насколько громко (0..1).
func want(stream: AudioStream, level: float) -> void:
	_want = _loop(stream) if stream else null
	_want_level = level


## Заставка победы или поражения; музыка замолкает на это время.
func sting(win: bool) -> void:
	_sting.stream = WIN if win else LOSE
	_sting.play()
	_hold = 4.0


func _process(delta: float) -> void:
	_hold = maxf(_hold - delta, 0.0)
	var target := 0.0 if _hold > 0.0 else _want_level
	# Другой трек — сначала угасаем, потом меняем и нарастаем
	if _player.stream != _want:
		target = 0.0
		if _level <= 0.01:
			_player.stream = _want
			if _want:
				_player.play()
	_level = move_toward(_level, target, delta / FADE)
	_player.volume_db = linear_to_db(maxf(_level, 0.0001))


## Тот же звук, но зацикленный (копия на каждый трек — один раз).
func _loop(stream: AudioStream) -> AudioStream:
	if not _loops.has(stream):
		var copy: AudioStream = stream.duplicate()
		if copy is AudioStreamWAV:
			copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
			copy.loop_end = int(stream.get_length() * stream.mix_rate)
		elif copy is AudioStreamMP3:
			copy.loop = true
		_loops[stream] = copy
	return _loops[stream]
