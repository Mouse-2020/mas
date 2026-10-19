extends Node2D

# 角色试演台（开发期工具，游戏不加载）。
#
# 用法：godot --path . res://tool/character_test.tscn
# 这条不能加 --headless——要看的是动画与遮挡，无头是 dummy 渲染器取不到视口。
#
# WASD / 方向键 走路，J 或左键 出手，K 放招，H 挨一下，X 死亡，R 重开一个。
# 这里只做三件事：把键盘翻成 move_input 喂给角色、摆几块能撞的墙、把状态打在角上。
# 动画与状态机一律不在本文件里，免得试演台长成第二个角色实现。

const PLAYER_SCENE := "res://entity/player/player.tscn"
const ARENA := Rect2(-520, -300, 1040, 620)
const WALL := 28.0

const FACE_LABELS: Array[String] = ["上", "右上", "右", "右下", "下", "左下", "左", "左上"]

var _player: PlayerCharacter
var _sorted: Node2D
var _label: Label
var _marker: FeetMarker

# 取样模式（照 tool/preview.gd 的路子）：--pose attack3 --frame 4 --shot 20 --png 路径
# 定在某套动画的某一帧上、不吃键盘也不走状态机，好让"脚底有没有踩在红线上"这件事可核对。
var _pose := ""
var _pose_frame := 0
var _shot_at := 0
var _shot_path := ""
var _frame := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_pose = _pick(args, "--pose")
	_pose_frame = int(_pick(args, "--frame"))
	_shot_at = int(_pick(args, "--shot"))
	_shot_path = _pick(args, "--png")

	RenderingServer.set_default_clear_color(Color(0.09, 0.09, 0.11))

	var ground := Ground.new()
	ground.arena = ARENA
	add_child(ground)

	# y_sort 开在容器上：子节点按各自原点的屏幕 Y 从远到近画。
	# 角色原点=脚底、砖块原点=底边中点，所以"谁站得靠前谁盖住谁"不用再手写画家算法。
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	add_child(_sorted)

	# 四块高度不一的墩子：为的是同时看到"人走到墩子后面被挡住"和"走到前面挡住墩子"。
	_add_block(Vector2(-260, -120), Vector2(150, 96), Color(0.42, 0.36, 0.30))
	_add_block(Vector2(180, 40), Vector2(190, 130), Color(0.40, 0.34, 0.29))
	_add_block(Vector2(-40, 230), Vector2(260, 74), Color(0.44, 0.38, 0.31))
	_add_block(Vector2(330, -210), Vector2(120, 150), Color(0.38, 0.33, 0.28))

	var mid_x := ARENA.position.x + ARENA.size.x * 0.5
	var dark := Color(0.30, 0.27, 0.24)
	_add_block(Vector2(mid_x, ARENA.position.y), Vector2(ARENA.size.x + WALL * 2, WALL), dark)
	_add_block(Vector2(mid_x, ARENA.end.y + WALL), Vector2(ARENA.size.x + WALL * 2, WALL), dark)
	_add_block(Vector2(ARENA.position.x - WALL * 0.5, ARENA.end.y), Vector2(WALL, ARENA.size.y), dark)
	_add_block(Vector2(ARENA.end.x + WALL * 0.5, ARENA.end.y), Vector2(WALL, ARENA.size.y), dark)

	_spawn()

	_label = Label.new()
	_label.position = Vector2(18, 14)
	_label.add_theme_font_size_override("font_size", 19)
	_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
	add_child(_label)


func _spawn() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	_player = packed.instantiate() as PlayerCharacter
	_player.position = Vector2(0, 60)
	_sorted.add_child(_player)

	var camera := Camera2D.new()
	_player.add_child(camera)
	camera.make_current()

	_marker = FeetMarker.new()
	add_child(_marker)

	if _pose != "":
		_apply_pose()


## 把角色钉在 "<状态><朝向>" 这套动画的某一帧上：关掉物理，状态机就不会把他拽回站立。
func _apply_pose() -> void:
	var dir := _pose.right(1).to_int()
	var state_name := _pose.substr(0, _pose.length() - 1)
	var index := PlayerCharacter.STATE_NAMES.find(state_name)
	if index < 0:
		push_error("认不出这套动画：%s（状态得是 %s 之一）" % [_pose, PlayerCharacter.STATE_NAMES])
		return
	_player.set_physics_process(false)
	_player.state = index
	_player.facing = dir
	var sprite := _player.get_node("Sprite") as AnimatedSprite2D
	sprite.play(_pose)
	# 必须在这儿停住：不 pause 的话出手/放招/死亡这些不循环的动画会在截到图之前播完，
	# animation_finished 又把角色拽回站立——截图看着就像 pose 模式根本没生效。
	sprite.pause()
	sprite.set_frame(clampi(_pose_frame, 0, sprite.sprite_frames.get_frame_count(_pose) - 1))
	_player.move_input = Vector2.ZERO


func _pick(args: PackedStringArray, flag: String) -> String:
	var at := args.find(flag)
	if at < 0 or at + 1 >= args.size():
		return ""
	return args[at + 1]


func _add_block(at: Vector2, size: Vector2, color: Color) -> void:
	var block := Block.new()
	block.block_size = size
	block.color = color
	block.position = at
	_sorted.add_child(block)


func _process(_delta: float) -> void:
	_frame += 1
	if _player == null:
		return
	if _pose == "":
		var right := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
		var left := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
		var down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
		var up := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
		_player.move_input = Vector2(float(right) - float(left), float(down) - float(up))
	_marker.position = Vector2(0, _player.position.y)
	_refresh_hud()
	# 多挂几帧再截：相机与物理都要先收敛，第一帧截出来位置还没落定。
	if _shot_at > 0 and _frame >= _shot_at:
		if _shot_path != "":
			var image := get_viewport().get_texture().get_image()
			var err := image.save_png(_shot_path)
			print("截图 %s (%s)" % [_shot_path, "ok" if err == OK else str(err)])
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	# 取样模式下彻底不吃输入：窗口刚开那一下常有杂散左键，
	# 而 attack() 走的是 _commit，不看物理也不看状态机，会把钉好的姿势顶掉。
	if _pose != "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_J:
				_player.attack()
			KEY_K:
				_player.cast_skill()
			KEY_H:
				_player.take_hit()
			KEY_X:
				_player.die()
			KEY_R:
				_restart()
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_player.attack()


func _restart() -> void:
	_marker.queue_free()
	_player.queue_free()
	_player = null
	# 等一帧让上面两个真删掉再建新的：同一帧里新旧角色会同时占着碰撞世界。
	await get_tree().process_frame
	_spawn()


func _refresh_hud() -> void:
	var state_name: String = PlayerCharacter.STATE_NAMES[_player.state]
	var face_name: String = FACE_LABELS[_player.facing]
	_label.text = "武林风 · 角色试演台\n"
	_label.text += "状态 %s　朝向 %d(%s)　脚底 (%.0f, %.0f)　速度 %.0f\n" % [
		state_name, _player.facing, face_name, _player.position.x, _player.position.y,
		_player.velocity.length()]
	_label.text += "WASD 走　J/左键 出手　K 放招　H 挨打　X 死亡　R 重开"


# ---- 试演台自用节点。都不带 class_name，出了这个文件没人用。 ----

class Ground extends Node2D:
	var arena := Rect2()

	func _draw() -> void:
		draw_rect(arena, Color(0.16, 0.16, 0.19))
		var step := 64.0
		var x := arena.position.x
		while x <= arena.end.x:
			draw_line(Vector2(x, arena.position.y), Vector2(x, arena.end.y),
				Color(0.22, 0.22, 0.26), 1.0)
			x += step
		var y := arena.position.y
		while y <= arena.end.y:
			draw_line(Vector2(arena.position.x, y), Vector2(arena.end.x, y),
				Color(0.22, 0.22, 0.26), 1.0)
			y += step


class Block extends StaticBody2D:
	var block_size := Vector2(120, 90)
	var color := Color(0.42, 0.36, 0.30)

	func _ready() -> void:
		y_sort_enabled = true
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = block_size
		shape.shape = rect
		# 碰撞体摆在原点上方：原点那条线就是砖块底边，也是角色撞停的那条线。
		shape.position = Vector2(0, -block_size.y * 0.5)
		add_child(shape)

	func _draw() -> void:
		var top := -block_size.y
		draw_rect(Rect2(Vector2(-block_size.x * 0.5, top), block_size), color)
		draw_rect(Rect2(Vector2(-block_size.x * 0.5, top), Vector2(block_size.x, 8.0)),
			color.lightened(0.22))
		draw_rect(Rect2(Vector2(-block_size.x * 0.5, top), block_size),
			Color(0, 0, 0, 0.45), false, 2.0)


class FeetMarker extends Node2D:
	func _draw() -> void:
		var half := 1600.0
		draw_line(Vector2(-half, 0), Vector2(half, 0), Color(1.0, 0.18, 0.18, 0.8), 2.0)
		draw_line(Vector2(-6, -8), Vector2(6, -8), Color(1.0, 0.18, 0.18, 0.8), 2.0)
