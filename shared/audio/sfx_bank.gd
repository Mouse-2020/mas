class_name SfxBank
extends RefCounted

# 程序化音效：全部由正弦/方波/锯齿/噪声加包络合成，不引用任何外部 wav 素材。
# 想要正式素材时只需要把配方换成读文件，事件映射表不用动。

const SAMPLE_RATE := 22050

static var _recipes := {}

## 事件到音效名的映射。空串表示这个事件不出声（比如走路）。
static var _event_clips := {}


static func event_clips() -> Dictionary:
	if _event_clips.is_empty():
		_event_clips = {
			Enums.GameEventType.MOVE: "",
			Enums.GameEventType.BLOCKED: "error",
			Enums.GameEventType.ATTACK: "hit",
			Enums.GameEventType.MISS: "miss",
			Enums.GameEventType.KILL: "kill",
			Enums.GameEventType.LEVEL_UP: "levelup",
			Enums.GameEventType.LOOT: "pickup",
			Enums.GameEventType.EQUIP: "equip",
			Enums.GameEventType.UNEQUIP: "equip",
			Enums.GameEventType.CONSUME: "drink",
			Enums.GameEventType.DROP: "click",
			Enums.GameEventType.DEATH: "death",
			Enums.GameEventType.RESPAWN: "heal",
			Enums.GameEventType.INFO: "",
			Enums.GameEventType.SKILL: "cast",
			Enums.GameEventType.LEARN: "reward",
			Enums.GameEventType.BUFF: "buff",
			Enums.GameEventType.QUEST_ACCEPT: "quest",
			Enums.GameEventType.QUEST_PROGRESS: "click",
			Enums.GameEventType.QUEST_READY: "quest",
			Enums.GameEventType.QUEST_COMPLETE: "reward",
			Enums.GameEventType.TRAVEL: "travel",
			Enums.GameEventType.BUY: "coin",
			Enums.GameEventType.SELL: "coin",
			Enums.GameEventType.REPAIR: "equip",
			Enums.GameEventType.TALK: "click",
		}
	return _event_clips


static func names() -> Array:
	if _recipes.is_empty():
		_recipes = _build()
	return _recipes.keys()


static func knows(clip_name: String) -> bool:
	if _recipes.is_empty():
		_recipes = _build()
	return _recipes.has(clip_name)


## 技能自己的声音；没配就退回通用 click。
static func build(clip_name: String) -> AudioClip:
	if _recipes.is_empty():
		_recipes = _build()
	var notes: Array = _recipes.get(clip_name, _recipes["click"])
	var clip := AudioClip.new()
	clip.sample_rate = SAMPLE_RATE
	clip.samples = _render(notes)
	return clip


## 事件该放什么声；返回 null 表示这个事件是安静的。
static func clip_for(event_type: int) -> AudioClip:
	var clip_name: String = event_clips().get(event_type, "")
	if clip_name == "":
		return null
	return build(clip_name)


static func _note(from_hz: float, to_hz: float, seconds: float, wave: int, level: float) -> Dictionary:
	return { "from_hz": from_hz, "to_hz": to_hz, "seconds": seconds, "wave": wave, "level": level }


static func _one(from_hz: float, to_hz: float, seconds: float, wave: int, level: float) -> Array:
	return [_note(from_hz, to_hz, seconds, wave, level)]


static func _render(notes: Array) -> PackedInt32Array:
	var total := 0.0
	for note in notes:
		total += note["seconds"]
	var count := maxi(1, int(float(SAMPLE_RATE) * total))
	var buffer := PackedFloat64Array()
	buffer.resize(count)

	var offset := 0.0
	for note in notes:
		var length := maxi(1, int(float(SAMPLE_RATE) * note["seconds"]))
		var start := int(offset * float(SAMPLE_RATE))
		# 最后一段可能被四舍五入推出边界，截断而不是越界。
		var usable := mini(length, count - start)
		for i in usable:
			buffer[start + i] += _sample(note, i, length)
		offset += note["seconds"]

	var pcm := PackedInt32Array()
	pcm.resize(count)
	for i in count:
		# 首尾各淡入淡出 2ms，否则脉冲边界会"啪"一声。
		var edge := minf(1.0, float(mini(i, count - 1 - i)) / (float(SAMPLE_RATE) * 0.002))
		var v := clampf(buffer[i] * edge, -1.0, 1.0)
		pcm[i] = int(round(v * 31000.0))
	return pcm


static func _sample(note: Dictionary, index: int, length: int) -> float:
	var t := 0.0 if length <= 1 else float(index) / float(length - 1)
	var from_hz: float = note["from_hz"]
	var to_hz: float = note["to_hz"]
	var hz := from_hz + (to_hz - from_hz) * t
	var phase := TAU * hz * (float(index) / float(SAMPLE_RATE))
	var raw := 0.0
	match note["wave"]:
		Enums.Wave.SINE:
			raw = sin(phase)
		Enums.Wave.SQUARE:
			raw = 0.65 if sin(phase) >= 0.0 else -0.65
		Enums.Wave.SAW:
			raw = fmod(phase / PI, 2.0) - 1.0
		Enums.Wave.NOISE:
			# 噪声用固定种子，保证同一份代码在任何机器上跑出自同一份采样。
			raw = Rng.new(1000 + index).next_double() * 2.0 - 1.0
	return raw * _envelope(t) * float(note["level"])


## 攻击段 8% 线性起音，其余指数衰减——打击感全靠这条尾巴。
static func _envelope(t: float) -> float:
	var attack := 0.08
	if t < 0.0 or t > 1.0:
		return 0.0
	if t < attack:
		return t / attack
	var decay := (t - attack) / (1.0 - attack)
	return pow(1.0 - decay, 1.9)


static func _build() -> Dictionary:
	var hits: Array = [
		_note(420.0, 90.0, 0.11, Enums.Wave.SAW, 0.8),
		_note(60.0, 40.0, 0.06, Enums.Wave.NOISE, 0.5),
	]
	var slash: Array = [
		_note(900.0, 180.0, 0.07, Enums.Wave.NOISE, 0.55),
		_note(300.0, 120.0, 0.1, Enums.Wave.SAW, 0.6),
	]

	return {
		"click": _one(880.0, 700.0, 0.05, Enums.Wave.SQUARE, 0.35),
		"error": [
			_note(180.0, 150.0, 0.08, Enums.Wave.SQUARE, 0.4),
			_note(0.0, 0.0, 0.03, Enums.Wave.SINE, 0.0),
			_note(170.0, 120.0, 0.1, Enums.Wave.SQUARE, 0.4),
		],
		"hit": hits,
		"slash": slash,
		"miss": _one(260.0, 180.0, 0.09, Enums.Wave.SINE, 0.28),
		"kill": [
			_note(520.0, 200.0, 0.14, Enums.Wave.SQUARE, 0.5),
			_note(300.0, 120.0, 0.14, Enums.Wave.SAW, 0.4),
		],
		"levelup": [
			_note(523.0, 523.0, 0.1, Enums.Wave.SINE, 0.5),
			_note(659.0, 659.0, 0.1, Enums.Wave.SINE, 0.5),
			_note(784.0, 784.0, 0.18, Enums.Wave.SINE, 0.55),
		],
		"pickup": _one(880.0, 1320.0, 0.09, Enums.Wave.SINE, 0.4),
		"coin": [
			_note(1046.0, 1046.0, 0.05, Enums.Wave.SQUARE, 0.35),
			_note(1568.0, 1568.0, 0.09, Enums.Wave.SQUARE, 0.35),
		],
		"equip": [
			_note(300.0, 520.0, 0.06, Enums.Wave.SQUARE, 0.35),
			_note(520.0, 640.0, 0.07, Enums.Wave.NOISE, 0.25),
		],
		"drink": [
			_note(420.0, 620.0, 0.09, Enums.Wave.SINE, 0.4),
			_note(620.0, 760.0, 0.09, Enums.Wave.SINE, 0.3),
		],
		"cast": _one(320.0, 900.0, 0.2, Enums.Wave.SINE, 0.45),
		"bolt": [
			_note(1400.0, 220.0, 0.05, Enums.Wave.NOISE, 0.6),
			_note(700.0, 120.0, 0.16, Enums.Wave.SAW, 0.5),
		],
		"fire": [
			_note(200.0, 700.0, 0.12, Enums.Wave.NOISE, 0.5),
			_note(500.0, 120.0, 0.22, Enums.Wave.SAW, 0.55),
		],
		"heal": [
			_note(660.0, 990.0, 0.16, Enums.Wave.SINE, 0.4),
			_note(990.0, 1180.0, 0.14, Enums.Wave.SINE, 0.3),
		],
		"buff": _one(220.0, 640.0, 0.3, Enums.Wave.SAW, 0.35),
		"quest": [
			_note(659.0, 659.0, 0.1, Enums.Wave.SQUARE, 0.35),
			_note(784.0, 784.0, 0.16, Enums.Wave.SQUARE, 0.4),
		],
		"reward": [
			_note(523.0, 523.0, 0.09, Enums.Wave.SINE, 0.45),
			_note(659.0, 659.0, 0.09, Enums.Wave.SINE, 0.45),
			_note(784.0, 784.0, 0.09, Enums.Wave.SINE, 0.45),
			_note(1046.0, 1046.0, 0.22, Enums.Wave.SINE, 0.5),
		],
		"travel": [
			_note(120.0, 900.0, 0.28, Enums.Wave.NOISE, 0.35),
			_note(900.0, 240.0, 0.18, Enums.Wave.SINE, 0.35),
		],
		"death": [
			_note(220.0, 60.0, 0.5, Enums.Wave.SAW, 0.55),
			_note(120.0, 40.0, 0.4, Enums.Wave.SINE, 0.4),
		],
		# 背景音乐：一段能循环的五声音阶铺底，音量刻意压得很低。
		"music": [
			_note(196.0, 196.0, 0.5, Enums.Wave.SINE, 0.16),
			_note(220.0, 220.0, 0.5, Enums.Wave.SINE, 0.15),
			_note(262.0, 262.0, 0.5, Enums.Wave.SINE, 0.16),
			_note(294.0, 294.0, 0.5, Enums.Wave.SINE, 0.15),
			_note(262.0, 262.0, 0.5, Enums.Wave.SINE, 0.16),
			_note(220.0, 220.0, 0.5, Enums.Wave.SINE, 0.15),
			_note(392.0, 392.0, 0.6, Enums.Wave.SINE, 0.18),
			_note(294.0, 196.0, 1.0, Enums.Wave.SINE, 0.14),
		],
	}
