extends SceneTree

# 武林风 · 等距画面取样台（开发期工具）。
#
# WorldView 画的是 CanvasItem，无头模式没有光栅化器，所以核对 2.5D 画面必须开一个真窗口：
# 这里把世界视图挂上去跑几帧，把视口纹理存成 PNG 再退出。
# 逻辑回归归 selftest，这里只管"长什么样"。
#
# 用法：godot --path . --script res://tool/preview.gd -- --seed 808 --map forest
# 加 --fish 则把人挪到城塘边下竿，等浮漂沉下去那一帧截（要连 HUD 的咬钩提示一起验）。

const DEFAULT_SEED := 20261016
const ARTIFACTS_FOLDER := ".artifacts"

var _seed := DEFAULT_SEED
var _map := ""
var _fish := false
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_seed = _parse_int(args, "--seed", DEFAULT_SEED)
	_map = _parse_str(args, "--map", "")
	_fish = args.has("--fish")
	var root_dir := ProjectSettings.globalize_path("res://").trim_suffix("/") + "/" + ARTIFACTS_FOLDER
	DirAccess.make_dir_recursive_absolute(root_dir)
	# --fish 会把人挪到塘边，产物得和默认那张分开存，不然互相盖掉。
	var tag := "fish" if _fish else (_map if _map != "" else "start")
	_out = "%s/iso-%s-%d.png" % [root_dir, tag, _seed]

	var session := GameSession.new_campaign(_seed)
	if _map != "":
		session.travel_to(_map)
	var host := _Host.new()
	host.session = session
	host.out = _out
	host.fish = _fish
	root.add_child(host)


func _parse_int(args: PackedStringArray, flag: String, fallback: int) -> int:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size() and args[index + 1].is_valid_int():
		return args[index + 1].to_int()
	return fallback


func _parse_str(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


class _Host extends Node:
	## 挂几帧再截：相机是指数平滑跟随的，头几帧还在出生点，画面会偏。
	const WARM_UP_FRAMES := 12
	## 等浮漂沉下去最多 2.6 秒，给到 6 秒还没动静就是站错了位，别死等。
	## 按会话时钟而不是帧数等：帧数跟刷新率走，120Hz 下能等出两倍时间。
	const FISH_DEADLINE_SECONDS := 6.0

	var session: GameSession
	var out := ""
	var fish := false
	var _view: Node
	var _hud: Node
	var _frames := 0


	func _ready() -> void:
		# 用 load 而不是直接写 WorldView：主循环脚本编译时自动加载单例还没注册，
		# 静态引用会把 view.gd 一起拖进那次编译，然后 Event 就"找不到标识符"。
		_view = load("res://map/view.gd").new()
		add_child(_view)
		_view.bind(session)
		if not fish:
			return
		# 咬钩提示是 HUD 正中的大字，只挂世界视图拍不到。
		_hud = load("res://ui/hud/hud.gd").new()
		add_child(_hud)
		_hud.bind(session)
		session.relocate_player(_find_bank())
		session.fish_toggle()


	func _process(_delta: float) -> void:
		_frames += 1
		if fish:
			# 平时截图不推世界：这里没有 Game 单例代跑，钓鱼这种要等时钟的得自己搬，
			# 事件也要手动喂给 HUD，否则咬钩提示永远刷不出来。
			session.tick(_delta)
			var batch := session.drain_events()
			if not batch.is_empty():
				_hud.append(batch)
				_hud.refresh()
			if not session.fish_biting() and session.elapsed < FISH_DEADLINE_SECONDS:
				return
		if _frames < WARM_UP_FRAMES:
			return
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(out)
		print("取样台：%s (%dx%d) %s" % [out, image.get_width(), image.get_height(),
			"写入失败" if error != OK else "已存盘"])
		if fish:
			# 报一下截的是哪一态：没咬钩就收工说明站错了位，别把白图当验收。
			print("取样台：第 %d 帧 下竿 %s 咬钩 %s 站位 %s" % [
				_frames, session.fishing, session.fish_biting(), session.player.position])
		get_tree().quit(0 if error == OK else 1)


	## 塘边第一格能下竿的地方；一格都没有就回出生点，这张图白截但不会卡住。
	func _find_bank() -> Vector2i:
		for entry in session.map.all_positions():
			var pos: Vector2i = entry
			if Fishing.spot(session.map, pos):
				return pos
		return session.map.spawn
