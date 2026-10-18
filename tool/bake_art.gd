extends SceneTree

# 武林风 · 素材烘焙台（开发期工具，游戏运行时一行也不执行）。
#
# 吃的是 ImageGen 出的原图（.artifacts/raw/，不进仓库），吐的是运行时贴图（res://shared/art/）。
# 两件事：
#   1. 立绘：先在缩小的"判定图"上回答"这像不像品红背景"，用连通块认出到底有几个角色，
#      再回全分辨率按实测背景解出前景色。切片按连通块的外接框走，所以角色摆得均不均匀无所谓。
#   2. 地形：把"俯视无缝图"按 2:1 压扁成菱形贴图（为什么压扁就是逆变换，见 _bake_diamond），
#      这样不管生成模型理不理解等距投影，地面接缝都由数学保证，而不是祈祷它画得准。
#
# 用法：godot --headless --path . --script res://tool/bake_art.gd -- --raw .artifacts/raw
# 烘完必须再跑一遍 godot --headless --path . --import：引擎加载的是导入缓存，
# 不重导的话 PNG 已经换了，画面上却还是上一批贴图（改了半天看不出差别，就是这么来的）。

const ArtGen := preload("res://shared/art_gen.gd")

const OUT_DIR := "res://shared/art"
## 菱形贴图按画面尺寸烘（64x32），运行时 1:1 画，缩放质量在这里一次定死。
const DIAMOND := Vector2i(64, 32)
const GROUND_SAMPLE := 512
## 地形贴图的对比度系数：1 是原样，0 是一片纯色。见 _flatten。
const GROUND_CONTRAST := 0.52
const WATERMARK_BOX := Rect2(0.72, 0.92, 0.28, 0.08)

## 判背景和认角色都在判定图上做：原图的 JPEG 噪点会骗过色差，缩一遍把高频平均掉，
## 剩下的错就只有"整片判反"这种能被连通块数量抓出来的。
const MATTE_LONG_SIDE := 512
## 色差用归一化颜色算：像素和背景各除以自己的亮度再比，只问"像不像品红"、不问"亮不亮"。
## 生成图四周带暗角，按绝对色扣会在边上留一圈半透明品红；归一化之后暗角只是同一块品红调暗了。
const KEY_NEAR := 0.10
const KEY_FAR := 0.26
## 暗角是低频变化，32x32 一格足够描述，被角色挡住的格子靠邻格平均补。
const VIGNETTE_GRID := 32
## 块数多于角色数时允许把最近的一对并起来，但间距超过这个判定图像素就不并了——
## 隔这么远的两块是两个角色，不是一个人的腰带和剑穗。
const MAX_MERGE_GAP := 48
## 比这还小的碎块是噪点，不参与计数。
const MIN_PART := 0.0022

## 每张原图按从左到右顺序对应哪些素材名。名字必须能在 ArtGen.ART_SIZES 里找到，
## 找不到就直接失败——省得"烘焙台改了一个名，游戏里静悄悄用回占位图"。
const SHEETS := [
	{"raw": "sprite-player", "names": ["unit_player"]},
	{"raw": "sprite-player-front", "names": ["unit_player_f0", "unit_player_f1", "unit_player_f2", "unit_player_f3"]},
	{"raw": "sprite-player-back", "names": ["unit_player_b0", "unit_player_b1", "unit_player_b2", "unit_player_b3"]},
	{"raw": "sprite-player-side", "names": ["unit_player_r0", "unit_player_r1", "unit_player_r2", "unit_player_r3"]},
	{"raw": "sprites-monsters-a", "names": ["mon_shanji", "mon_yelu", "mon_murenzhuang", "mon_zhulinlang"]},
	{"raw": "sprites-monsters-b", "names": ["mon_mengmianfei", "mon_dongfu", "mon_kuguwunu", "mon_baiguzongshi"]},
	{"raw": "sprites-monsters-c", "names": ["mon_yehu", "mon_zhushu", "mon_dushe", "mon_shanzei"]},
	{"raw": "sprites-monsters-d", "names": ["mon_enu", "mon_duyanfei", "mon_tiemianke", "mon_yexiao"]},
	{"raw": "sprites-monsters-e", "names": ["mon_yaodao", "mon_shigandang", "mon_xuedaosen", "mon_shijietu"]},
	{"raw": "sprites-npcs-a", "names": ["npc_elder", "npc_vendor", "npc_healer", "npc_mage"]},
	{"raw": "sprites-npcs-b", "names": ["npc_guard", "npc_hunter", "npc_guide"]},
	{"raw": "sprites-props", "names": ["prop_bamboo", "prop_pine", "prop_deadtree", "prop_stalagmite"]},
	{"raw": "sprites-buildings-a", "names": ["house_hut", "house_shed", "house_tower", "house_pavilion"]},
	{"raw": "sprites-buildings-b", "names": ["house_hall", "house_forge"]},
	{"raw": "sprites-buildings-c", "names": ["house_shop", "house_gate"]},
]

const GROUNDS := [
	{"raw": "tex-grass-seamless", "name": "gnd_grass"},
	{"raw": "tex-floor-seamless", "name": "gnd_floor"},
	{"raw": "tex-road-seamless", "name": "gnd_road"},
	{"raw": "tex-sand-seamless", "name": "gnd_sand"},
	{"raw": "tex-water-seamless", "name": "gnd_water"},
	{"raw": "tex-wall-seamless", "name": "gnd_wall"},
	{"raw": "tex-rock-seamless", "name": "gnd_rock"},
]

var _raw_dir := ""
var _baked := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_raw_dir = ProjectSettings.globalize_path("res://").trim_suffix("/") + "/" \
		+ _parse_str(args, "--raw", ".artifacts/raw")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	quit(_run())


func _run() -> int:
	var missing := _check_names()
	if not missing.is_empty():
		print("烘焙台：素材名对不上 ArtGen.ART_SIZES：%s" % ", ".join(missing))
		return 1

	var failures: Array[String] = []
	for entry in GROUNDS:
		var image := _load_raw(entry["raw"])
		if image == null:
			failures.append(entry["raw"])
			continue
		_heal_watermark(image)
		_save(entry["name"], _bake_diamond(image, DIAMOND.x, DIAMOND.y))
	for entry in SHEETS:
		var names: Array = entry["names"]
		var pieces := _bake_sheet(entry["raw"] as String, names)
		if pieces.is_empty():
			for name in names:
				failures.append(name as String)
			continue
		for i in names.size():
			_save(names[i] as String, pieces[i])

	_bake_helpers()
	_save_sheet()

	print("烘焙台：出图 %d 张 → %s" % [_baked.size(), OUT_DIR])
	if not failures.is_empty():
		print("烘焙台：不合格 %s" % ", ".join(failures))
		return 1
	return 0


# ── 原料 ────────────────────────────────────────────────────────────

func _load_raw(key: String) -> Image:
	var path := "%s/%s.png" % [_raw_dir, key]
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return image


func _save(name: String, image: Image) -> void:
	_baked[name] = image
	var error := image.save_png("%s/%s.png" % [OUT_DIR, name])
	if error != OK:
		print("烘焙台：写不出 %s（%s）" % [name, error_string(error)])


## 判定图摊平成一张黑白图（白=当成前景）并把认出的角色框画上去，留在 .artifacts/ 里。
## 切片对不上时先看这张：框多框少是"背景没扣净/角色真挨在一起"，一眼分清。
func _save_debug(key: String, fg: PackedByteArray, w: int, h: int, boxes: Array[Rect2i]) -> void:
	var out := ProjectSettings.globalize_path("res://").trim_suffix("/") + "/.artifacts/debug-" + key + ".png"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var view := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for i in fg.size():
		var on := fg[i] != 0
		view.set_pixel(i % w, i / w, Color8(236, 236, 240) if on else Color8(28, 28, 34))
	for index in boxes.size():
		var box := boxes[index]
		var tint := Color(1, 0.25, 0.25) if index % 3 == 0 else (Color(0.25, 1, 0.35) if index % 3 == 1 else Color(0.3, 0.6, 1))
		_draw_rect(view, box, tint)
	view.save_png(out)


static func _draw_rect(image: Image, box: Rect2i, tint: Color) -> void:
	var right := box.position.x + box.size.x - 1
	var bottom := box.position.y + box.size.y - 1
	for x in range(box.position.x, right + 1):
		_put(image, x, box.position.y, tint)
		_put(image, x, bottom, tint)
	for y in range(box.position.y, bottom + 1):
		_put(image, box.position.x, y, tint)
		_put(image, right, y, tint)


static func _put(image: Image, x: int, y: int, tint: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, tint)


func _check_names() -> Array[String]:
	var missing: Array[String] = []
	for entry in SHEETS:
		for name in entry["names"] as Array:
			if not ArtGen.ART_SIZES.has(name):
				missing.append(name)
	for entry in GROUNDS:
		if not ArtGen.GROUND_ART.values().has(entry["name"]):
			missing.append(entry["name"])
	return missing


# ── 立绘：判定图 → 连通块 → 全分辨率抠色 → 按块裁切 ──────────────────

## 整张 sheet 走一遍。返回空数组表示这张不合格（原因已打印）——
## 宁可少出几张，也不要把两个角色合成一个，或者把一个人拦腰切开。
func _bake_sheet(key: String, names: Array) -> Array[Image]:
	var empty: Array[Image] = []
	var image := _load_raw(key)
	if image == null:
		print("烘焙台：缺原料 %s.png" % key)
		return empty

	_clear_watermark(image)
	var small := _shrink(image, MATTE_LONG_SIDE)
	var bg := _background_color(small)
	var fg := _foreground(small, bg)
	var found := _shapes(fg, small.get_width(), small.get_height(), names.size())
	var boxes: Array[Rect2i] = found["boxes"]
	if boxes.size() != names.size():
		print("烘焙台：%s 认出 %d 个角色，想要 %d 个（%s）→ 重画这张" % [
			key, boxes.size(), names.size(), _shape_note(boxes)])
		_save_debug(key, fg, small.get_width(), small.get_height(), boxes)
		return empty

	_key_at(image, bg, _vignette(small, bg, fg), _silhouette(
		found["labels"], found["count"], small.get_width(), small.get_height(), found["groups"]))
	_despill(image)

	var ratio := Vector2(float(image.get_width()) / float(small.get_width()),
		float(image.get_height()) / float(small.get_height()))
	var pieces: Array[Image] = []
	for i in names.size():
		var piece := _piece(image, _scale_box(boxes[i], ratio), ArtGen.ART_SIZES[names[i]] as int)
		if piece == null:
			print("烘焙台：%s 第 %d 块裁不出内容" % [key, i + 1])
			return empty
		pieces.append(piece)
	return pieces


func _shape_note(boxes: Array[Rect2i]) -> String:
	var parts: Array[String] = []
	for box in boxes:
		parts.append("%dx%d@%d" % [box.size.x, box.size.y, box.position.x])
	return ", ".join(parts)


## 水印是半透明白字，压在纯品红底上；立绘右下角那一块一定是背景，直接刷成背景色最省事。
## 不刷的话，白字在判定图里是一大块"不像品红"，会被当成多出来的角色。
func _clear_watermark(image: Image) -> void:
	image.fill_rect(_watermark_rect(image), _background_color(image))


## 地形是不透明的，不能刷透明，只能从对角取一块补上（无缝噪声纹理里看不出来）。
func _heal_watermark(image: Image) -> void:
	var box := _watermark_rect(image)
	var width := image.get_width()
	var height := image.get_height()
	var patch := Image.create_empty(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
	for y in box.size.y:
		for x in box.size.x:
			patch.set_pixel(x, y, image.get_pixel(
				width - 1 - int(box.position.x) - x, height - 1 - int(box.position.y) - y))
	image.blit_rect(patch, Rect2i(0, 0, patch.get_width(), patch.get_height()), Vector2i(box.position))


func _watermark_rect(image: Image) -> Rect2i:
	return Rect2i(int(image.get_width() * WATERMARK_BOX.position.x),
		int(image.get_height() * WATERMARK_BOX.position.y),
		int(image.get_width() * WATERMARK_BOX.size.x),
		int(image.get_height() * WATERMARK_BOX.size.y))


## 背景色实测出来，别写死：生成模型给的"品红"其实是偏粉的 #F0179E 一档。
## 只采边框（角色站在中间），并且绕开水印那块——白字混进来会把实测背景带向发白，
## 后面解前景色用的"本地背景"就跟着偏了。
func _background_color(image: Image) -> Color:
	var box := _watermark_rect(image)
	var sum := Color(0, 0, 0, 0)
	var samples := 0
	var step_x := maxi(1, image.get_width() / 48)
	var step_y := maxi(1, image.get_height() / 48)
	var edge_x := step_x * 3
	var edge_y := step_y * 3
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			if box.has_point(Vector2i(x, y)):
				continue
			var on_border := x < edge_x or y < edge_y \
				or x >= image.get_width() - edge_x or y >= image.get_height() - edge_y
			if on_border:
				sum += image.get_pixel(x, y)
				samples += 1
	return sum / maxf(1.0, float(samples))


static func _shrink(image: Image, long_side: int) -> Image:
	var small := image.duplicate()
	var width := image.get_width()
	var height := image.get_height()
	var ratio := float(height) / float(width)
	if ratio >= 1.0:
		small.resize(maxi(1, roundi(float(long_side) / ratio)), long_side, Image.INTERPOLATE_LANCZOS)
	else:
		small.resize(long_side, maxi(1, roundi(long_side * ratio)), Image.INTERPOLATE_LANCZOS)
	return small


## 判定图逐像素回答"这算前景吗"，返回 1 字节/像素的 0/1。
static func _foreground(small: Image, bg: Color) -> PackedByteArray:
	var width := small.get_width()
	var height := small.get_height()
	var fg := PackedByteArray()
	fg.resize(width * height)
	var reference := _normalize(bg)
	for y in height:
		for x in width:
			var d := _chroma_distance(_normalize(small.get_pixel(x, y)), reference)
			fg[y * width + x] = 1 if d > (KEY_NEAR + KEY_FAR) * 0.5 else 0
	return fg


## 连通块标号 → 碎块扔掉 → 块数超了就并最近的一对 → 取最大的 want 个按 x 排。
## 块数对不上想要的角色数就原样返回，由调用方判这张图不合格。
func _shapes(fg: PackedByteArray, width: int, height: int, want: int) -> Dictionary:
	var ids := PackedInt32Array()
	ids.resize(fg.size())
	ids.fill(-1)
	var raw: Array[Dictionary] = []
	var queue := PackedInt32Array()
	var label := 0
	for seed in fg.size():
		if fg[seed] == 0 or ids[seed] >= 0:
			continue
		queue.clear()
		queue.append(seed)
		ids[seed] = label
		var head := 0
		var left := seed % width
		var top := int(seed / width)
		var right := left
		var bottom := top
		var area := 0
		while head < queue.size():
			var at: int = queue[head]
			head += 1
			area += 1
			var x := at % width
			var y := int(at / width)
			left = mini(left, x)
			top = mini(top, y)
			right = maxi(right, x)
			bottom = maxi(bottom, y)
			# 八邻域：斜着搭上的头发丝、剑尖该算同一个人。
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					var next := ny * width + nx
					if fg[next] == 0 or ids[next] >= 0:
						continue
					ids[next] = label
					queue.append(next)
		raw.append({"area": area, "box": Rect2i(left, top, right - left + 1, bottom - top + 1),
			"ids": [label]})
		label += 1

	var min_area := int(float(fg.size()) * MIN_PART)
	var kept: Array[Dictionary] = []
	for part in raw:
		if (part["area"] as int) >= min_area:
			kept.append(part)
	# 块数比角色多，就把"挨得最近的一对"并起来（剑穗、飘带断成两截不该算两个人），
	# 一直并到刚好；还是多就得并到很远的位置才够，说明这张图真画了多余的东西。
	kept.sort_custom(_by_left)
	while kept.size() > want:
		var pair := _closest_pair(kept)
		if pair < 0:
			break
		var a: Dictionary = kept[pair]
		var b: Dictionary = kept[pair + 1]
		var box_a: Rect2i = a["box"]
		var box_b: Rect2i = b["box"]
		if _gap(box_a, box_b) > MAX_MERGE_GAP:
			break
		a["box"] = box_a.merge(box_b)
		a["area"] = (a["area"] as int) + (b["area"] as int)
		a["ids"] = (a["ids"] as Array) + (b["ids"] as Array)
		kept.remove_at(pair + 1)
	kept.sort_custom(_by_area)
	var picked: Array[Dictionary] = []
	for i in mini(want, kept.size()):
		picked.append(kept[i])
	picked.sort_custom(_by_left)

	var boxes: Array[Rect2i] = []
	var groups: Array = []
	for part in picked:
		boxes.append(part["box"] as Rect2i)
		groups.append(part["ids"] as Array)
	return {"boxes": boxes, "groups": groups, "labels": ids, "count": label}


## 返回相邻一对（排过序后按 x 挨着）之间间距最小的下标；并查非相邻对没意义。
static func _closest_pair(parts: Array[Dictionary]) -> int:
	var best := -1
	var best_gap := 1.0e9
	for i in parts.size() - 1:
		var gap := _gap(parts[i]["box"] as Rect2i, parts[i + 1]["box"] as Rect2i)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


## 两个外接框之间的真空隙（框在另一维上重叠时就是横向间距），重叠则为 0。
static func _gap(a: Rect2i, b: Rect2i) -> float:
	var dx := maxf(0.0, maxf(float(a.position.x) - float(b.position.x + b.size.x),
		float(b.position.x) - float(a.position.x + a.size.x)))
	var dy := maxf(0.0, maxf(float(a.position.y) - float(b.position.y + b.size.y),
		float(b.position.y) - float(a.position.y + a.size.y)))
	return sqrt(dx * dx + dy * dy)


static func _by_area(a: Dictionary, b: Dictionary) -> bool:
	return (a["area"] as int) > (b["area"] as int)


static func _by_left(a: Dictionary, b: Dictionary) -> bool:
	return (a["box"] as Rect2i).position.x < (b["box"] as Rect2i).position.x


## 只放行"被选中那些连通块自己的像素"，再糊两遍 3x3：糊出来的软边就是"这块允许有像素"的闸门，
## 顺手把角色身上误判成背景的洞填平（见 _key_at）。
## 按块而不是按外接框放行：框里常常还躺着别人甩过来的一缕头发、或自己掉的一点碎影，
## 按框取会把它们一起印进立绘，运行时就成了飘在角色身边的斑点。
func _silhouette(labels: PackedInt32Array, count: int, width: int, height: int,
		groups: Array) -> Image:
	var owner := PackedInt32Array()
	owner.resize(count)
	owner.fill(-1)
	for i in groups.size():
		for id in groups[i] as Array:
			owner[id as int] = i
	var raw := PackedByteArray()
	raw.resize(width * height)
	for p in raw.size():
		var id: int = labels[p]
		if id >= 0 and owner[id] >= 0:
			raw[p] = 255
	var mask := Image.create_empty(width, height, false, Image.FORMAT_R8)
	mask.set_data(width, height, false, Image.FORMAT_R8, raw)
	_blur(mask)
	_blur(mask)
	return mask


static func _blur(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var copy := image.duplicate()
	for y in height:
		for x in width:
			var sum := 0.0
			var n := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					sum += copy.get_pixel(nx, ny).r
					n += 1
			image.set_pixel(x, y, Color(sum / maxf(1.0, float(n)), 0, 0, 1))


## 背景色在场子里并不均匀（暗角），解前景色得知道"这一带暗了多少"。
## 只统计判定为背景的像素的亮度比，被角色挡住的格子交给邻格平均迭代补平。
func _vignette(small: Image, bg: Color, fg: PackedByteArray) -> PackedFloat32Array:
	var width := small.get_width()
	var height := small.get_height()
	var grid := PackedFloat32Array()
	grid.resize(VIGNETTE_GRID * VIGNETTE_GRID)
	var hits := PackedInt32Array()
	hits.resize(grid.size())
	var base := maxf(0.02, (bg.r + bg.g + bg.b) / 3.0)
	for y in height:
		for x in width:
			if fg[y * width + x] != 0:
				continue
			var c := small.get_pixel(x, y)
			var cell := int(y * VIGNETTE_GRID / height) * VIGNETTE_GRID + int(x * VIGNETTE_GRID / width)
			grid[cell] = grid[cell] + clampf((c.r + c.g + c.b) / 3.0 / base, 0.2, 2.5)
			hits[cell] = hits[cell] + 1
	var known := PackedByteArray()
	known.resize(grid.size())
	for i in grid.size():
		if hits[i] > 0:
			grid[i] = grid[i] / float(hits[i])
			known[i] = 1
	_fill_gaps(grid, known)
	return grid


static func _fill_gaps(grid: PackedFloat32Array, known: PackedByteArray) -> void:
	var side := VIGNETTE_GRID
	for step in 64:
		var pending := false
		for i in known.size():
			if known[i] == 1:
				continue
			var sum := 0.0
			var n := 0
			var x := i % side
			var y := int(i / side)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= side or ny >= side:
						continue
					var at := ny * side + nx
					if known[at] == 0:
						continue
					sum += grid[at]
					n += 1
			if n == 0:
				pending = true
				continue
			grid[i] = sum / float(n)
			known[i] = 1
		if not pending:
			break


## 全分辨率抠色：alpha 由归一化色差给（软边靠它），判定图的糊边只当闸门——
## 闸门外的噪点一律透明，闸门里的洞一律不透明，于是 Matte 上那些横条和麻点都翻不了案。
func _key_at(image: Image, bg: Color, grid: PackedFloat32Array, silhouette: Image) -> void:
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var reference := _normalize(bg)
	for y in height:
		for x in width:
			var u := float(x) / float(width)
			var v := float(y) / float(height)
			var gate := _sample_scalar(silhouette, u, v)
			if gate <= 0.02:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := image.get_pixel(x, y)
			var d := _chroma_distance(_normalize(c), reference)
			var a := clampf((d - KEY_NEAR) / (KEY_FAR - KEY_NEAR), 0.0, 1.0)
			a *= clampf((gate - 0.12) / 0.22, 0.0, 1.0)
			a = maxf(a, clampf((gate - 0.5) * 3.0, 0.0, 1.0))
			if a <= 0.004:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var scale := _sample_grid(grid, u, v)
			var local := Color(clampf(bg.r * scale, 0.0, 1.0), clampf(bg.g * scale, 0.0, 1.0),
				clampf(bg.b * scale, 0.0, 1.0))
			var k := 1.0 / maxf(a, 0.08)
			image.set_pixel(x, y, Color(
				clampf((c.r - local.r * (1.0 - a)) * k, 0.0, 1.0),
				clampf((c.g - local.g * (1.0 - a)) * k, 0.0, 1.0),
				clampf((c.b - local.b * (1.0 - a)) * k, 0.0, 1.0), a))


static func _sample_scalar(image: Image, u: float, v: float) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var x := clampf(u * float(width) - 0.5, 0.0, float(width - 1))
	var y := clampf(v * float(height) - 0.5, 0.0, float(height - 1))
	var x0 := int(floorf(x))
	var y0 := int(floorf(y))
	var x1 := mini(x0 + 1, width - 1)
	var y1 := mini(y0 + 1, height - 1)
	var fx := x - float(x0)
	var fy := y - float(y0)
	var left := image.get_pixel(x0, y0).r
	var right := image.get_pixel(x1, y0).r
	var below := image.get_pixel(x1, y1).r
	var above := image.get_pixel(x0, y1).r
	return (left + (right - left) * fx) * (1.0 - fy) + (above + (below - above) * fx) * fy


static func _sample_grid(grid: PackedFloat32Array, u: float, v: float) -> float:
	var side := VIGNETTE_GRID
	var x := clampf(u * float(side) - 0.5, 0.0, float(side - 1))
	var y := clampf(v * float(side) - 0.5, 0.0, float(side - 1))
	var x0 := int(floorf(x))
	var y0 := int(floorf(y))
	var x1 := mini(x0 + 1, side - 1)
	var y1 := mini(y0 + 1, side - 1)
	var fx := x - float(x0)
	var fy := y - float(y0)
	var left := grid[y0 * side + x0]
	var right := grid[y0 * side + x1]
	var below := grid[y1 * side + x1]
	var above := grid[y1 * side + x0]
	return (left + (right - left) * fx) * (1.0 - fy) + (above + (below - above) * fx) * fy


static func _normalize(c: Color) -> Color:
	var luminance := maxf(0.02, (c.r + c.g + c.b) / 3.0)
	return Color(c.r / luminance, c.g / luminance, c.b / luminance)


static func _chroma_distance(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


## 取一块：按该块自己的外接框裁出来，再按目标高度缩放。框留 2 像素余量，
## 免得 Lanczos 的振铃把描边削掉。
func _piece(image: Image, box: Rect2i, draw_height: int) -> Image:
	var bounds := Rect2i(0, 0, image.get_width(), image.get_height())
	var used := box.grow(2).intersection(bounds)
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var piece := image.get_region(used)
	var target := maxi(8, draw_height)
	var scale := float(target) / float(piece.get_height())
	var width := maxi(8, roundi(piece.get_width() * scale))
	_premultiply(piece)
	piece.resize(width, target, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(piece)
	return piece


static func _scale_box(box: Rect2i, ratio: Vector2) -> Rect2i:
	return Rect2i(int(float(box.position.x) * ratio.x), int(float(box.position.y) * ratio.y),
		maxi(1, int(roundf(float(box.size.x) * ratio.x))),
		maxi(1, int(roundf(float(box.size.y) * ratio.y))))


## 去溢色：品红底会在亮边和浅色衣物上留下一层粉，特征是 r 与 b 同时高出 g。
## 真红（r 高 b 低）与真蓝（b 高 r 低）都不满足这个特征，所以袍子的颜色不会被误伤。
func _despill(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var spill := maxf(0.0, minf(c.r, c.b) - c.g)
			if spill <= 0.0:
				continue
			image.set_pixel(x, y, Color(clampf(c.r - spill * 0.8, 0.0, 1.0), c.g,
				clampf(c.b - spill * 0.8, 0.0, 1.0), c.a))


static func _premultiply(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))


static func _unpremultiply(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.001:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			image.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))


# ── 地形：俯视无缝图 → 等距菱形 ─────────────────────────────────────

## 菱形贴图就是"把俯视正方图压扁一半"，不用转 45°，也不用管菱形画在哪儿。
## 推导：格 (i,j) 的菱形是方格子 [i-½,i+½]×[j-½,j+½] 在 P(gx,gy)=((gx-gy)·½TILE_W,(gx+gy)·½TILE_H)
## 下的像，四角正好是顶/右/底/左；画的时候又把贴图矩形的 (0,0)(1,0)(1,1)(0,1) 依次钉到这四个角。
## 两条仿射合成下来恰好是 uv 直映射 —— 菱形的面积只有矩形的一半，所以一屏像素要吃 √2 个贴图像素，
## 用 lanczos 一次收下这层过采样，接缝则由无缝原图自己保证。
static func _bake_diamond(source: Image, w: int, h: int) -> Image:
	var out := source.duplicate()
	# 分两步缩：原图上千像素宽，一步跳到 64 会把 lanczos 的振核拉得太长，先归到判定尺寸再落到画面尺寸。
	out.resize(GROUND_SAMPLE, GROUND_SAMPLE, Image.INTERPOLATE_LANCZOS)
	out.resize(w, h, Image.INTERPOLATE_LANCZOS)
	_flatten(out)
	return out


## 把一张贴图按"离均值的偏差"整体压扁：色相、颗粒、明暗层次都还在，但对比度减半。
## 生成模型给的铺石图带很重的规则花纹，压到 64x32 之后每格花纹正好和菱形网格咬上，
## 整片地面于是变成一张抢戏的大棋盘。运行时那层每格随机明暗只能再打散一点，救不回来。
static func _flatten(image: Image) -> void:
	var mean := Color(0, 0, 0, 0)
	for y in image.get_height():
		for x in image.get_width():
			mean += image.get_pixel(x, y)
	mean /= float(image.get_width() * image.get_height())
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, mean + (c - mean) * GROUND_CONTRAST)


## 阴影与光晕：运行时画接触阴影、掉落微光和门的呼吸全靠这两张，省掉一堆画多边形。
## 这两张是唯一按缩放画的，所以烘得比用到大一倍，配合 LINEAR 过滤才不会有硬边。
func _bake_helpers() -> void:
	var size := 128
	var shadow := Image.create_empty(size, size / 2, false, Image.FORMAT_RGBA8)
	var glow := Image.create_empty(size, size / 2, false, Image.FORMAT_RGBA8)
	for y in shadow.get_height():
		for x in shadow.get_width():
			var dx := (x + 0.5) / shadow.get_width() * 2.0 - 1.0
			var dy := (y + 0.5) / shadow.get_height() * 2.0 - 1.0
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			shadow.set_pixel(x, y, Color(0, 0, 0, 0.62 * a * a))
			glow.set_pixel(x, y, Color(1, 1, 1, a * a * a))
	_save("shadow", shadow)
	_save("glow", glow)


## 一张校样图：所有立绘铺在棋盘格上，透明边有没有扣干净一眼看出来。
func _save_sheet() -> void:
	var names := _sheet_order()
	var cell := 200
	var columns := 6
	var rows := ceili(float(names.size()) / columns)
	var sheet := Image.create_empty(columns * cell, rows * cell, false, Image.FORMAT_RGBA8)
	for y in sheet.get_height():
		for x in sheet.get_width():
			var on := ((x / 16) + (y / 16)) % 2 == 0
			sheet.set_pixel(x, y, Color8(52, 50, 58) if on else Color8(74, 72, 82))
	for i in names.size():
		var image: Image = _baked.get(names[i])
		if image == null:
			continue
		var at := Vector2i((i % columns) * cell, (i / columns) * cell)
		var blit := image
		var fit_scale := minf(float(cell - 8) / image.get_width(), float(cell - 8) / image.get_height())
		if fit_scale < 1.0:
			blit = image.duplicate()
			_premultiply(blit)
			blit.resize(maxi(1, int(image.get_width() * fit_scale)),
				maxi(1, int(image.get_height() * fit_scale)), Image.INTERPOLATE_LANCZOS)
			_unpremultiply(blit)
		_composite(sheet, blit, at + Vector2i((cell - blit.get_width()) / 2,
			(cell - blit.get_height()) / 2 + 4))
	var out := ProjectSettings.globalize_path("res://").trim_suffix("/") + "/.artifacts/baked-sheet.png"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("烘焙台：校样 %s" % out)


func _sheet_order() -> Array[String]:
	var names: Array[String] = []
	for entry in SHEETS:
		for name in entry["names"] as Array:
			names.append(name)
	for entry in GROUNDS:
		names.append(entry["name"])
	return names


static func _composite(dst: Image, src: Image, at: Vector2i) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a <= 0.001:
				continue
			var px := at.x + x
			var py := at.y + y
			if px < 0 or py < 0 or px >= dst.get_width() or py >= dst.get_height():
				continue
			var old := dst.get_pixel(px, py)
			dst.set_pixel(px, py, Color(
				old.r + (c.r - old.r) * c.a, old.g + (c.g - old.g) * c.a,
				old.b + (c.b - old.b) * c.a, clampf(old.a + c.a, 0.0, 1.0)))


# ── 命令行 ──────────────────────────────────────────────────────────

func _parse_str(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback
