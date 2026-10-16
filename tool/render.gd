extends SceneTree

# 武林风 · 无头渲染台。
# 无头渲染台：每张图各出一张全图，
# --radius 为正时再补一张玩家视野特写。输出落在 <工程根>/.artifacts/。
# 用法：godot --headless --path . --script res://tool/render.gd -- --seed 808 --radius 14

const ARTIFACTS_FOLDER := ".artifacts"
const DEFAULT_SEED := 20261016

## radius 为 0 就只出全图；没给 --radius 时按下面的默认半径补一张特写，
## 没给 --radius 时用 sim 终局那张特写的同一档半径。
const DEFAULT_VIEW_RADIUS := 14

const FULL_MAP_SCALE := 4
const CLOSE_UP_SCALE := 8

var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := _parse_int(args, "--seed", DEFAULT_SEED)
	var radius := _parse_int(args, "--radius", 0)
	_out = _parse_str(args, "--out",
		ProjectSettings.globalize_path("res://").trim_suffix("/") + "/" + ARTIFACTS_FOLDER)
	DirAccess.make_dir_recursive_absolute(_out)
	quit(_render(seed_value, radius))


## 四张图都画一张全图；--radius 为正时再补一张玩家视野特写。
func _render(seed_value: int, radius: int) -> int:
	var session := GameSession.new_campaign(seed_value)
	for entry in WorldDatabase.all_defs():
		var def := entry as MapDef
		session.travel_to(def.id)
		var canvas := WorldRenderer.render(session, FULL_MAP_SCALE)
		var path := "%s/map-%s-%d.png" % [_out, def.id, seed_value]
		var error := canvas.save_png(path)
		if error != OK:
			print("写不出图片：%s（%s）" % [path, error_string(error)])
			return 1
		print("%s %dx%d 怪 %d 门 %d → %s" % [def.display_name, canvas.get_width(), canvas.get_height(),
			session.monsters.size(), session.map.exits.size(), path])

	# 与 Sim 的终局输出对齐：最后一张进过的图另存一份 world-<seed>.png。
	var world_path := "%s/world-%d.png" % [_out, seed_value]
	WorldRenderer.render(session, FULL_MAP_SCALE).save_png(world_path)

	var view_radius := radius if radius > 0 else DEFAULT_VIEW_RADIUS
	session.travel_to(Naming.MAP_SUBURB)
	var view := WorldRenderer.render(session, CLOSE_UP_SCALE, view_radius)
	var view_path := "%s/view-%d.png" % [_out, seed_value]
	var view_error := view.save_png(view_path)
	if view_error != OK:
		print("写不出图片：%s（%s）" % [view_path, error_string(view_error)])
		return 1
	print("玩家视野 %dx%d → %s" % [view.get_width(), view.get_height(), view_path])
	print("全图输出 %s" % world_path)
	return 0


# ── 命令行参数解析 ────────────────────────────────────────────────

func _parse_int(args: PackedStringArray, flag: String, fallback: int) -> int:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size() and _is_int(args[index + 1]):
		return args[index + 1].to_int()
	return fallback


func _parse_str(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


## 非整数（比如 "--seed abc"）用回退值，而不是当成 0。
func _is_int(text: String) -> bool:
	if text.is_empty():
		return false
	var body := text.substr(1) if text.begins_with("-") or text.begins_with("+") else text
	if body.is_empty():
		return false
	for i in body.length():
		if body[i] < "0" or body[i] > "9":
			return false
	return true
