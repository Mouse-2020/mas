class_name PlayerCharacter
extends CharacterBody2D

# 玩家角色本体：物理驱动的 8 向 × 6 态逐帧角色。
#
# 素材在 shared/resource/new_wcx001/，文件名是 <朝向>_<状态>_<帧>.png，共 264 张、一律 215x241。
# 朝向序号沿用 Enums.Direction（0=朝上、顺时针数过去 2=右、4=朝下、6=左），和素材的目录号一一对上。
#
# 节点原点 = 脚底。这不是随手挑的：画布 215x241 里身体只占 y 32..129，脚底在 y=129，
# 底下还空着 112 像素——把原点定在脚底，碰撞体才落在人真正站着的地方，
# Y 排序也才拿得到"脚底在哪一排"这个正确的键（否则人会浮在身后的树上）。
# 锚点数值由 264 帧的 alpha 包围盒量出来：站立八向脚底 y 全在 127..130，水平中心 102.0..103.0。

const ART_FOLDER := "res://shared/resource/new_wcx001/"

enum State { STAND, RUN, ATTACK, HIT, DEATH, SKILL }

# 下面四张表的下标都对上 State 序号。帧数是素材实测值，换素材要连这里一起改。
const STATE_NAMES: Array[String] = ["stand", "run", "attack", "hit", "death", "skill"]
const FRAME_COUNT: Array[int] = [4, 8, 7, 3, 4, 7]
const ANIM_FPS: Array[float] = [5.0, 16.0, 20.0, 12.0, 8.0, 14.0]
const ANIM_LOOP: Array[bool] = [true, true, false, false, false, false]

# 出手、放招、受击这三态期间钉在原地：不认移动、不换朝向，播完自己回站立。
# 死亡故意不在里面——它是终态，播完冻在最后一帧，不许被任何状态盖掉。
const COMMITTED: Array[int] = [State.ATTACK, State.SKILL, State.HIT]

const CANVAS := Vector2(215.0, 241.0)
const FOOT := Vector2(102.5, 129.0)
# 素材身体高 97 像素，现有 unit_player 高 78，缩到 0.8 正好同一量级、不会比 NPC 大一圈。
const DISPLAY_SCALE := 0.8
# 站立八向量出来的头顶行，与身体可见宽度（血条与接触阴影都按身体算，不能按 215 的画布算）。
const BODY_TOP := 32.0
const SHADOW_WIDTH := 34.0

signal state_changed(state: int)

## 期望移动方向，屏幕空间、长度 0..1（超过 1 会截成 1）。
## 输入不归角色管：谁驱动谁写这个值。试演台按键盘写，将来接别的驱动方也由外部喂。
var move_input := Vector2.ZERO
var facing: int = Enums.Direction.DOWN
var state: int = State.STAND

## 外部权威模式：位置由调用方摆（格子仿真还在当家），节点不自己积分位移，
## 只出朝向、状态机与动画计时。WorldView 现在就是这么用它的。
var externally_driven := false

@export_range(0.0, 1000.0, 1.0) var move_speed := 190.0

var _sprite: AnimatedSprite2D

static var _frames_cache: SpriteFrames


func _ready() -> void:
	_sprite = get_node("Sprite") as AnimatedSprite2D
	_sprite.frames = _load_frames()
	_sprite.centered = true
	# 画布中心到脚底那段向量取负，就把脚底挪到了节点原点。offset 在局部空间，跟着 scale 一起缩。
	_sprite.offset = CANVAS * 0.5 - FOOT
	_sprite.scale = Vector2.ONE * DISPLAY_SCALE
	_sprite.animation_finished.connect(_on_animation_finished)
	_sync_animation()


func _physics_process(_delta: float) -> void:
	if externally_driven:
		return
	if state == State.DEATH or COMMITTED.has(state):
		velocity = Vector2.ZERO
	else:
		var want := move_input
		if want.length() > 1.0:
			want = want.normalized()
		velocity = want * move_speed
		if want.length_squared() > 0.0001:
			facing = face_of(want)
			_set_state(State.RUN)
		else:
			_set_state(State.STAND)
	move_and_slide()
	_sync_animation()


## 出手。返回 false 表示没打成：已经死了，或正处在另一段不可打断的动作里。
func attack() -> bool:
	return _commit(State.ATTACK)


## 放技能。占用规则与出手相同。
func cast_skill() -> bool:
	return _commit(State.SKILL)


## 挨一下。受击可以盖掉出手与放招——被打断本来就是应该的，所以走 _set_state 不走 _commit。
func take_hit() -> bool:
	if state == State.DEATH:
		return false
	_set_state(State.HIT)
	return true


## 死亡。终态：钉住、冻在最后一帧。格子那套会原地把人拉起来，所以配了一条 revive。
func die() -> void:
	_set_state(State.DEATH)


## 撤销死亡。走的是直改 state，因为 _set_state 守的是"死着不许被任何动作盖掉"。
func revive() -> void:
	if state != State.DEATH:
		return
	velocity = Vector2.ZERO
	state = State.STAND
	_sync_animation()
	state_changed.emit(state)


## 外部权威模式下由调用方每帧喂进来：这一步在屏幕上走了多少。
## 出手/放招/受击期间不改状态——动作不能被走路顶掉，跟物理模式下的规矩一致。
func drive(screen_step: Vector2) -> void:
	if state == State.DEATH or COMMITTED.has(state):
		return
	if screen_step.length_squared() > 0.0000001:
		facing = face_of(screen_step)
		_set_state(State.RUN)
	else:
		_set_state(State.STAND)


## 身体从脚底到头顶有多高，血条与名字得按这个摆，不能按 241 的画布高摆。
static func body_height() -> float:
	return (FOOT.y - BODY_TOP) * DISPLAY_SCALE


## 屏幕方向向量 → 八向朝向序号。从"朝上"起顺时针数，一格 45°。
static func face_of(direction: Vector2) -> int:
	return posmod(int(round(atan2(direction.x, -direction.y) / (PI / 4.0))), 8)


func _commit(next: int) -> bool:
	if state == State.DEATH or COMMITTED.has(state):
		return false
	_set_state(next)
	return true


func _set_state(next: int) -> void:
	if state == State.DEATH or state == next:
		return
	state = next
	state_changed.emit(next)
	_sync_animation()


func _on_animation_finished() -> void:
	_set_state(State.STAND)


## 让正在播的动画始终等于"当前状态 + 当前朝向"。
## 每物理帧调一次，所以转向会自动换到那一套帧；play 同名会从头再来，故先比个名字。
func _sync_animation() -> void:
	if _sprite == null:
		return
	var key := "%s%d" % [STATE_NAMES[state], facing]
	if _sprite.animation != key:
		_sprite.play(key)


## 48 套动画（6 态 × 8 向）在代码里拼，不落 .tres——与工程"已经没有一个 .tres"的口径一致，
## 而且加一态只改上面那四张表，不用开编辑器点 264 下。整局共用一份，故走静态缓存。
static func _load_frames() -> SpriteFrames:
	if _frames_cache != null:
		return _frames_cache
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for s in range(STATE_NAMES.size()):
		var state_name: String = STATE_NAMES[s]
		for d in range(8):
			var key := "%s%d" % [state_name, d]
			frames.add_animation(key)
			frames.set_animation_loop(key, ANIM_LOOP[s])
			frames.set_animation_speed(key, ANIM_FPS[s])
			for k in range(FRAME_COUNT[s]):
				var path := "%s%d_%s_%d.png" % [ART_FOLDER, d, state_name, k]
				if not ResourceLoader.exists(path):
					push_error("缺帧：%s" % path)
					continue
				frames.add_frame(key, load(path) as Texture2D)
	_frames_cache = frames
	return frames
