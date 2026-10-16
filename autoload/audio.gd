extends Node

# 音乐和音效管理：把 shared/audio/sfx_bank.gd 合成的 PCM 变成能播的 AudioStreamWAV，并订阅事件总线自动发声。
# "哪个事件该发什么声"这张表在 shared/audio/sfx_bank.gd，这里只管发声和防打耳。

const VOICES := 8

## 同一段音效两次播放的最小间隔，一刀四五个事件不至于叠成爆音。
const SAME_CLIP_GAP := 0.045

var _streams := {}
var _last_played := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _clock := 0.0
var _muted := false

var muted: bool:
	get:
		return _muted


func _ready() -> void:
	Event.raised.connect(_on_event)

	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -9.0
		add_child(voice)
		_voices.append(voice)

	var music := AudioStreamPlayer.new()
	music.volume_db = -22.0
	add_child(music)
	music.stream = _stream("music", true)
	music.play()


func _process(delta: float) -> void:
	_clock += delta


func play(clip_name: String) -> void:
	if _muted or clip_name.is_empty():
		return
	if _last_played.has(clip_name) and _clock - float(_last_played[clip_name]) < SAME_CLIP_GAP:
		return
	_last_played[clip_name] = _clock
	# 轮询发声通道：同一个 player 被再次 Play 会把上一声掐断，打起来就只剩最后一下。
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	voice.stream = _stream(clip_name)
	voice.play()


## 技能自己的声音由出手处直接放，事件里只留伤害音。
func _on_event(event: GameEvent) -> void:
	if event.type == Enums.GameEventType.SKILL:
		return
	var clip_name: String = SfxBank.event_clips().get(event.type, "")
	if clip_name != "":
		play(clip_name)


func toggle_mute() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _muted)


func _stream(clip_name: String, do_loop := false) -> AudioStreamWAV:
	var key := clip_name + "#loop" if do_loop else clip_name
	if _streams.has(key):
		return _streams[key]

	var clip := SfxBank.build(clip_name)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = clip.sample_rate
	wav.data = _pcm(clip.samples)
	if do_loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = clip.samples.size()
	_streams[key] = wav
	return wav


static func _pcm(samples: PackedInt32Array) -> PackedByteArray:
	# 手写小端，不依赖字节序假设。
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := clampi(samples[i], -32768, 32767)
		bytes[i * 2] = value & 0xFF
		bytes[i * 2 + 1] = (value >> 8) & 0xFF
	return bytes
