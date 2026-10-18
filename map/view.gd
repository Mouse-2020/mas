class_name WorldView
extends Node2D

# 把 GameSession 的格子世界画成 2.5D 等距画面：地面是 64x32 的菱形，
# 站立的物件脚底踩在菱形中心，谁的下边线更靠下谁就挡住谁。
# 仍然是一张即时模式画布（_draw 一把梭），单位没有拆成场景节点。

const TILE := ArtGen.TILE
const FLASH_SECONDS := 0.3
const NO_TARGET := Vector2i(-99999, -99999)

## 相机每秒收敛多少：用指数平滑而不是固定 lerp 系数，帧率变了跟随速度不该跟着变。
const CAMERA_SMOOTH := 9.0

## 走路时上下起伏的像素数。站定时两头都是 0，所以停下不会留半格抖动。
const STEP_BOB := 2.0

## 玩家真帧的节奏：四帧一轮、两帧一步（一轮正好两条腿各迈一次），所以一格走两帧。
const FRAMES_PER_CELL := 2.0

## 程序化步态的幅度：落脚压扁 5%、钟摆式前后倾 4°。给没有逐帧素材的怪用，
## 目的不是拟真，是去掉"贴着地面滑行"那种平移感。
const GAIT_SQUASH := 0.05
const GAIT_LEAN := 4.0

## 墙与岩石挤出的高度必须正好等于菱形高，否则前后两块墙之间会漏出一条缝。
const BLOCK_H := ArtGen.TILE_H
const BLOCK_LIGHT := Color(0.96, 0.96, 1.02)
const BLOCK_SHADE := Color(0.72, 0.72, 0.82)

## 地图边界以外不是"没有东西"，是一片压得很深的底色：等距画面里菱形铺到边缘就断，
## 留默认灰底看着像窗口没画完，压深才像镜头外还有世界。
const VOID := Color(0.045, 0.05, 0.062)

## 最高的一档素材是城里那栋大殿（315 像素）。这个数换算成"往下多留几排格子"，
## 屏幕外那排的屋顶伸进画面时才不会缺一块。
const TALL_ROWS := 12

## 横向剔除留的余量按最宽的那张立绘算：只留一格宽的话，半出画面的大殿会先被剔掉、
## 等相机再挪一点又整栋冒出来，边缘像有人在剪布。
const CULL_X := 260.0

## 同一深度里谁后画：贴地的事先画，房子再圈地，人最后踩进来。
enum Kind { PROP, BUILDING, EXIT, LOOT, NPC, MONSTER, PLAYER }

const FACE_UV: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
## 左上、右上、右下、左下四个角各自去取贴图的另一边，就是左右镜像。
const MIRRORED_UV: Array[Vector2] = [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
const OUTLINE_OFFSETS: Array[Vector2] = [
	Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 2)]
const EXIT_GLOW := 74.0

var _session: GameSession
var _camera := Vector2.ZERO
var _floaters: Array = []
var _flashes: Array = []
var _target := NO_TARGET
var _clock := 0.0
var _quarry := {}
## 玩家的走路状态：朝向与帧号。用累加"走过多少格"来定帧，速度变了节奏不会散。
var _player_face := ArtGen.FACE_FRONT
var _player_frame := 0
var _stride := 0.0
var _last_render := Vector2.ZERO


func bind(session: GameSession) -> void:
	_session = session
	_center_camera(true)
	_last_render = session.player_render_cell()
	_player_face = ArtGen.FACE_FRONT
	_player_frame = 0
	_stride = 0.0
	# 飘字是这个世界视图自己的事：直接订阅事件总线，不用场景根居中转发。
	if not Event.raised.is_connected(_on_event):
		Event.raised.connect(_on_event)
	queue_redraw()


## 把事件翻译成头顶飘字。
func _on_event(event: GameEvent) -> void:
	var text := ""
	var color := Color(1, 1, 1)
	if event.type == Enums.GameEventType.ATTACK and event.at == _session.player.position:
		text = "-%d" % event.amount
		color = Color(1.0, 0.45, 0.4)
	elif event.type == Enums.GameEventType.ATTACK or event.type == Enums.GameEventType.SKILL:
		text = "-%d" % event.amount
		color = Color(1.0, 0.95, 0.8)
	elif event.type == Enums.GameEventType.MISS:
		text = "闪开"
		color = Color(0.75, 0.75, 0.75)
	elif event.type == Enums.GameEventType.KILL:
		text = "击杀"
		color = Color(1.0, 0.84, 0.35)
	elif event.type == Enums.GameEventType.LEVEL_UP:
		text = "升级"
		color = Color(0.48, 0.88, 1.0)
	elif event.type == Enums.GameEventType.LOOT:
		text = "拾取"
		color = Color(0.62, 0.9, 0.48)
	elif event.type == Enums.GameEventType.QUEST_READY:
		text = "可交付"
		color = Color(1.0, 0.82, 0.25)
	if text != "":
		add_floater(event.at, text, color)


## UI 点到的格子画个圈，让"我点了哪儿"看得见。
func mark_target(cell: Vector2i) -> void:
	_target = cell


## 一格中心在画面上的位置，也就是站立物脚底踩到的那一点。
func cell_to_screen(cell: Vector2) -> Vector2:
	return Iso.center(cell) - _camera


func screen_to_cell(screen: Vector2) -> Vector2i:
	return Iso.to_grid(screen + _camera)


## 用"离整数格多远"当步态相位：半格时最高，落回格子上正好归零。
static func _step_bob(cell: Vector2) -> Vector2:
	var phase := absf(cell.x - floorf(cell.x)) + absf(cell.y - floorf(cell.y))
	return Vector2(0.0, -STEP_BOB * sin(minf(phase, 1.0) * PI))


## 屏幕上的朝向由挪格子的方式决定：横向看 dx-dy，纵向看 dx+dy，谁大听谁的。
## 斜着走时屏幕位移更接近水平（一格斜走 = 横 32 竖 16），所以斜步归左右，符合直觉。
static func _face_of(step: Vector2) -> int:
	var across := step.x - step.y
	var down := step.x + step.y
	if absf(across) >= absf(down):
		return ArtGen.FACE_RIGHT if across >= 0.0 else ArtGen.FACE_LEFT
	return ArtGen.FACE_FRONT if down >= 0.0 else ArtGen.FACE_BACK


## 玩家的帧：累加"这一帧实际前进了多少格"来定帧号，而不是数秒。
## 于是按键走、点击寻路、被击退，节奏都自动跟得上，不会出现脚比人快的滑步。
func _update_player_walk() -> void:
	var at := _session.player_render_cell()
	var moved := absf(at.x - _last_render.x) + absf(at.y - _last_render.y)
	_last_render = at
	if moved <= 0.0001:
		return
	# 换图落点会瞬移，那一帧的"位移"是一大步，吃掉它，别把帧号甩到随机位置。
	_stride += minf(moved, 2.0)
	# 渲染位置是从"刚踩着的格子"往"下一步的格子"插出来的，所以 at - position 才是前进方向。
	# 落步那一帧两者重合，方向为零，此时保留上一个朝向，否则每步收尾都会闪一下正面。
	var player := _session.player
	var step := Vector2(at.x - player.position.x, at.y - player.position.y)
	if absf(step.x) + absf(step.y) > 0.0001:
		_player_face = _face_of(step)
	_player_frame = int(_stride * FRAMES_PER_CELL) % ArtGen.WALK_FRAMES


## 站定的时候渲染位置就等于脚下那格，所以这一点是"有没有在走"的判据。
func _is_walking() -> bool:
	var at := _session.player_render_cell()
	return absf(at.x - _session.player.position.x) + absf(at.y - _session.player.position.y) > 0.0001


## 怪的步态：没有逐帧素材，就用钟摆式的前后倾 + 落脚压扁 + 朝左时镜像。
## NPC 站在原地不动，所以不给它们套这套。
## 站定（脚下那格就是插值位置）时全部归零，免得停着还在轻微抽动。
static func _gait(at: Vector2, cell: Vector2i, clock: float) -> Dictionary:
	var drift := Vector2(at.x - float(cell.x), at.y - float(cell.y))
	if absf(drift.x) + absf(drift.y) <= 0.0001:
		return { "flip": false, "lean": 0.0, "squash": 0.0 }
	var beat := fmod(clock * 7.4 + float(cell.x * 5 + cell.y * 3) * 0.37, TAU)
	return {
		"flip": drift.x - drift.y < 0.0,
		"lean": deg_to_rad(GAIT_LEAN) * sin(beat),
		"squash": GAIT_SQUASH * -cos(beat),
	}


## 飘字存世界坐标，画的时候才减相机——不然相机一动，字会跟着相机跑而不是跟着人跑。
func add_floater(at: Vector2i, text: String, color: Color) -> void:
	_floaters.append({ "at": Iso.center(Vector2(at.x, at.y)) + Vector2(0, -52),
		"text": text, "color": color, "life": 1.1 })


## 技能落点闪一圈。半径用格数，等距下这一圈正好摊成屏幕上的一个菱形。
func add_flash(at: Vector2i, radius: int, color: Color) -> void:
	_flashes.append({ "at": at, "radius": maxi(1, radius), "color": color, "life": FLASH_SECONDS })


func _process(delta: float) -> void:
	if _session == null:
		return
	_clock += delta
	_center_camera(false, delta)
	_update_player_walk()
	for i in range(_floaters.size() - 1, -1, -1):
		var f: Dictionary = _floaters[i]
		f["life"] = float(f["life"]) - delta
		f["at"] = (f["at"] as Vector2) + Vector2(0, -delta * 26.0)
		if float(f["life"]) <= 0.0:
			_floaters.remove_at(i)
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[i]
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			_flashes.remove_at(i)
	queue_redraw()


func _center_camera(snap: bool, delta := 0.0) -> void:
	var view := get_viewport().get_visible_rect().size
	var bounds := Iso.map_bounds(_session.map.width, _session.map.height)
	# 跟着插值后的位置而不是脚下那格，否则相机仍在按整格追，人却滑着走。
	# 焦点抬高半个身位：立绘是从脚往上长的，正中间会让人觉得人在往下陷。
	var focus := Iso.center(_session.player_render_cell()) - Vector2(0, 18)
	var target := focus - view * 0.5
	target.x = clampf(target.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - view.x))
	target.y = clampf(target.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - view.y))
	if snap:
		_camera = target
	else:
		_camera = _camera.lerp(target, 1.0 - exp(-CAMERA_SMOOTH * delta))


func _draw() -> void:
	if _session == null:
		return
	var map := _session.map
	var view := get_viewport().get_visible_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), VOID)
	_quarry = _quest_targets()
	_draw_floor(map, view)
	_draw_standing(map, view)
	_draw_flashes()
	_draw_floaters()


# ── 地面 ────────────────────────────────────────────────────────────

## 菱形贴图按四角仿射铺，UV 与烘焙时的逆变换严格互逆，所以接缝是数学上闭死的。
## 墙和岩石这里跳过：它们由 _draw_block 连顶面带侧墙整个盖住，先铺一份只会从边上漏出三角底。
func _draw_floor(map: GameMap, view: Vector2) -> void:
	var box := Iso.visible_box(_camera, view)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var cell := Vector2i(x, y)
			if not map.in_bounds(cell):
				continue
			var terrain := map.terrain_at(cell)
			if terrain == Enums.Terrain.WALL or terrain == Enums.Terrain.ROCK:
				continue
			var points := _to_screen(Iso.corners(Vector2(x, y)))
			draw_colored_polygon(points, ArtGen.ground_tint(terrain, map.theme, cell,
				_occlusion(map, cell), _shimmer(cell)), ArtGen.ground_uv(terrain, cell),
				ArtGen.ground_tile(terrain))
			if cell == map.spawn:
				_stroke(points, Color(Palette.SPAWN, 0.45), 2.0)
			elif cell == _target:
				_stroke(points, Color(1, 1, 1, 0.45 + 0.25 * sin(_clock * 7.0)), 2.5)


## 光从左上方来，所以只有左上方向（格空间 -x 与 -y）的墙、树、屋子会在这一格拖出一小片影。
static func _occlusion(map: GameMap, cell: Vector2i) -> float:
	var blocking := 0
	for step in [Vector2i(-1, 0), Vector2i(0, -1)]:
		var here := Grid.add(cell, step.x, step.y)
		if map.in_bounds(here) and _blocks(map.terrain_at(here)):
			blocking += 1
	return 0.09 * blocking


static func _blocks(terrain: int) -> bool:
	return terrain == Enums.Terrain.WALL or terrain == Enums.Terrain.ROCK \
		or terrain == Enums.Terrain.TREE or terrain == Enums.Terrain.HOUSE


func _shimmer(cell: Vector2i) -> float:
	return sin(_clock * 1.6 + float(cell.x + cell.y) * 0.7)


func _to_screen(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p - _camera)
	return out


func _stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, color, width)


# ── 站着的东西：按深度排 ────────────────────────────────────────────

## 画家算法：按脚底所在的斜排 (x+y) 分桶，从远到近画，近处自然盖住远处。
## 桶里先塞地形再塞单位，所以站在同一斜排上的树永远在人后面。
## 建筑入桶用的是占地前角而不是格心：前角是这栋屋在斜排上最靠镜头的那一点，
## 拿它排序，站在屋前的怪才会盖住屋子，站在屋后的才会被屋挡住。
func _draw_standing(map: GameMap, view: Vector2) -> void:
	var box := Iso.visible_box(_camera, view, TALL_ROWS)
	var buckets := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var cell := Vector2i(x, y)
			if not map.in_bounds(cell):
				continue
			var terrain := map.terrain_at(cell)
			# 房子一格一画会被切成一排台阶，所以这里跳过，改由下面整栋入桶。
			if terrain != Enums.Terrain.HOUSE and _blocks(terrain):
				_push(buckets, Vector2(x, y), {"kind": Kind.PROP, "cell": cell, "terrain": terrain})
	for entry in map.buildings:
		var building := entry as Dictionary
		_push(buckets, GameMap.building_anchor(building["rect"] as Rect2i),
			{"kind": Kind.BUILDING, "art": building["art"] as String})
	for entry in map.exits:
		var exit := entry as MapExit
		_push(buckets, Vector2(exit.at.x, exit.at.y),
			{"kind": Kind.EXIT, "cell": exit.at, "exit": exit})
	for entry in _session.loot:
		var drop := entry as LootItem
		_push(buckets, Vector2(drop.position.x, drop.position.y),
			{"kind": Kind.LOOT, "cell": drop.position, "drop": drop})
	_push_units(buckets)

	var keys: Array = buckets.keys()
	keys.sort()
	for key in keys:
		for item in buckets[key]:
			_draw_item(item as Dictionary, map)


func _push(buckets: Dictionary, at: Vector2, item: Dictionary) -> void:
	item["at"] = at
	var key := int(floorf(Iso.depth(at)))
	if not buckets.has(key):
		buckets[key] = []
	(buckets[key] as Array).append(item)


## 任务怪的头顶要标一下，否则"在迷雾竹林猎杀竹林狼"得靠翻怪物表。
func _quest_targets() -> Dictionary:
	var ids := {}
	for entry in _session.quests:
		var quest := entry as QuestState
		if quest.status != Enums.QuestStatus.ACTIVE:
			continue
		var def := QuestDatabase.get_def(quest.id)
		if def.kind == Enums.QuestKind.KILL:
			ids[def.target] = true
	return ids


func _push_units(buckets: Dictionary) -> void:
	for entry in _session.npcs:
		var npc := entry as NpcUnit
		_push(buckets, Vector2(npc.position.x, npc.position.y),
			{"kind": Kind.NPC, "cell": npc.position, "npc": npc})
	for entry in _session.monsters:
		var monster := entry as MonsterUnit
		if not monster.alive:
			continue
		_push(buckets, _session.monster_render_cell(monster),
			{"kind": Kind.MONSTER, "cell": monster.position, "monster": monster})
	_push(buckets, _session.player_render_cell(), {"kind": Kind.PLAYER, "cell": _session.player.position})


func _draw_item(item: Dictionary, map: GameMap) -> void:
	var at := item["at"] as Vector2
	var foot := cell_to_screen(at) + _step_bob(at)
	if not _on_screen(foot):
		return
	match int(item["kind"]):
		Kind.PROP:
			var terrain := int(item["terrain"])
			var cell: Vector2i = item["cell"]
			if terrain == Enums.Terrain.TREE:
				_billboard(ArtGen.prop_art(map.theme, cell), foot, null)
			else:
				_draw_block(cell, terrain, map.theme)
		Kind.BUILDING:
			_draw_building(foot, item["art"] as String, map.theme)
		Kind.EXIT:
			_draw_exit(foot, item["cell"] as Vector2i, item["exit"] as MapExit)
		Kind.LOOT:
			_draw_loot(foot, item["drop"] as LootItem)
		Kind.NPC:
			_draw_npc(foot, item["cell"] as Vector2i, item["npc"] as NpcUnit)
		Kind.MONSTER:
			_draw_monster(foot, at, item["monster"] as MonsterUnit)
		Kind.PLAYER:
			_draw_player(foot, item["cell"] as Vector2i)


func _on_screen(foot: Vector2) -> bool:
	var view := get_viewport().get_visible_rect().size
	return foot.x > -CULL_X and foot.x < view.x + CULL_X \
		and foot.y > -24.0 and foot.y < view.y + float(TALL_ROWS * TILE)


# ── 各种立着的东西 ──────────────────────────────────────────────────

## 一堵墙：顶面抬高 BLOCK_H，朝左下与朝右下的两面各贴同一张石纹（横向压扁一倍）。
## 三面一拼，厚度就出来了；一整面墙只会露出最前一排的侧墙，因为后面那些正好被前排顶面盖掉。
func _draw_block(cell: Vector2i, terrain: int, theme: int) -> void:
	var corners := Iso.corners(Vector2(cell.x, cell.y))
	var top := corners[0] - _camera - Vector2(0, BLOCK_H)
	var right := corners[1] - _camera - Vector2(0, BLOCK_H)
	var bottom := corners[2] - _camera - Vector2(0, BLOCK_H)
	var left := corners[3] - _camera - Vector2(0, BLOCK_H)
	var texture := ArtGen.ground_tile(terrain)
	var tint := ArtGen.ground_tint(terrain, theme, cell)
	var face_uv := PackedVector2Array(FACE_UV)
	draw_colored_polygon(PackedVector2Array([left, bottom,
		bottom + Vector2(0, BLOCK_H), left + Vector2(0, BLOCK_H)]), tint * BLOCK_LIGHT, face_uv, texture)
	draw_colored_polygon(PackedVector2Array([bottom, right,
		right + Vector2(0, BLOCK_H), bottom + Vector2(0, BLOCK_H)]), tint * BLOCK_SHADE, face_uv, texture)
	draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), tint,
		ArtGen.ground_uv(terrain, cell), texture)


## 立绘：脚底踩在菱形中心，往下多压 3 像素，让脚陷进格子里而不是戳在边线上。
## flip/lean/squash 是给步态用的：倾斜与压扁都绕脚底发生，所以头顶在晃、脚跟不动，
## 看着像踩在地上迈步，而不是整张图飘在半空缩放。左侧没有单独素材，借右侧镜像。
## 返回画面高度，血条和名字据此摆在头顶。
func _billboard(art_name: String, foot: Vector2, fallback: Texture2D,
		flip := false, lean := 0.0, squash := 0.0) -> float:
	var texture: Texture2D = ArtGen.billboard(art_name)
	var size := ArtGen.billboard_size(art_name)
	if texture == null:
		if fallback == null:
			_contact_shadow(foot, 26.0)
			draw_rect(Rect2(foot + Vector2(-4, -size.y), Vector2(8, size.y)), Color(0.3, 0.28, 0.24, 0.92))
			return size.y
		size = Vector2(TILE, TILE) * 1.6
		texture = fallback
	var drawn := Vector2(size.x * (1.0 + squash * 0.6), size.y * (1.0 - squash))
	_contact_shadow(foot, size.x)
	draw_set_transform(foot, lean, Vector2.ONE)
	# 引擎的 draw_texture_rect 不接受负尺寸，也没有翻转参数，所以镜像只能反过来喂 UV。
	var quad := PackedVector2Array([Vector2(-drawn.x * 0.5, 3.0 - drawn.y),
		Vector2(drawn.x * 0.5, 3.0 - drawn.y), Vector2(drawn.x * 0.5, 3.0),
		Vector2(-drawn.x * 0.5, 3.0)])
	draw_colored_polygon(quad, ArtGen.figure_tint(_session.map.theme),
		PackedVector2Array(MIRRORED_UV if flip else FACE_UV), texture)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return drawn.y


## 接触阴影：椭圆一张压扁贴地。人一走动就有影子跟着，是"站在地上"最关键的一条线索。
func _contact_shadow(foot: Vector2, width: float) -> void:
	var texture := ArtGen.shadow()
	if texture == null:
		return
	var w := maxf(20.0, width * 0.78)
	draw_texture_rect(texture, Rect2(foot + Vector2(-w * 0.5, 2 - w * 0.25), Vector2(w, w * 0.5)),
		false, Color(1, 1, 1, 0.8 if _session.map.theme == Enums.MapTheme.CAVE else 0.55))


## 一栋房子：整张立绘按占地前角落地，底边中心对齐那一点。
## 不套步态、也不压接触阴影——石头台基本来就画在贴图里，再叠一圈影子反而像房子悬在半空。
func _draw_building(foot: Vector2, art_name: String, theme: int) -> void:
	var texture: Texture2D = ArtGen.billboard(art_name)
	if texture == null:
		_draw_house_mass(foot, ArtGen.house_side(art_name), theme)
		return
	var size := Vector2(float(texture.get_width()), float(texture.get_height()))
	var quad := PackedVector2Array([foot + Vector2(-size.x * 0.5, 2.0 - size.y),
		foot + Vector2(size.x * 0.5, 2.0 - size.y), foot + Vector2(size.x * 0.5, 2.0),
		foot + Vector2(-size.x * 0.5, 2.0)])
	draw_colored_polygon(quad, ArtGen.figure_tint(theme), PackedVector2Array(FACE_UV), texture)


## 贴图没导入时的房子：照占地挤出一个方块。位置、大小、遮挡都还是对的，只是难看——
## 省得"忘了重导素材"在画面里变成"城里凭空少了五十栋楼"。
func _draw_house_mass(foot: Vector2, side: int, theme: int) -> void:
	var across := float(side) * ArtGen.TILE_W * 0.5
	var down := float(side) * ArtGen.TILE_H * 0.5
	var lift := Vector2(0.0, -float(side) * TILE)
	var left := foot + Vector2(-across, -down)
	var right := foot + Vector2(across, -down)
	var back := foot + Vector2(0.0, -2.0 * down)
	var roof := Palette.terrain_color(Enums.Terrain.HOUSE) * ArtGen.figure_tint(theme)
	draw_colored_polygon(PackedVector2Array([left, foot, foot + lift, left + lift]), roof * BLOCK_LIGHT)
	draw_colored_polygon(PackedVector2Array([foot, right, right + lift, foot + lift]), roof * BLOCK_SHADE)
	draw_colored_polygon(PackedVector2Array([back + lift, right + lift, foot + lift, left + lift]), roof)


func _draw_exit(foot: Vector2, cell: Vector2i, exit: MapExit) -> void:
	var points := _to_screen(Iso.corners(Vector2(cell.x, cell.y)))
	draw_colored_polygon(points, Color(0.35, 0.78, 0.95, 0.26))
	_stroke(points, Color(0.75, 0.93, 1, 0.8), 2.0)
	var glow := ArtGen.glow()
	if glow != null:
		draw_texture_rect(glow, Rect2(foot + Vector2(-EXIT_GLOW * 0.5, 2 - EXIT_GLOW * 0.25),
			Vector2(EXIT_GLOW, EXIT_GLOW * 0.5)), false,
			Color(0.55, 0.88, 1, 0.45 + 0.25 * sin(_clock * 2.4)))
	_label(exit.label, foot + Vector2(0, -24), 13, Color(0.75, 0.93, 1))


func _draw_loot(foot: Vector2, drop: LootItem) -> void:
	var glow := ArtGen.glow()
	if glow != null:
		draw_texture_rect(glow, Rect2(foot + Vector2(-26, -11), Vector2(52, 26)), false,
			Color(Palette.LOOT.r, Palette.LOOT.g, Palette.LOOT.b, 0.5))
	var bob := sin(_clock * 2.2 + float(drop.position.x + drop.position.y)) * 2.0
	draw_texture_rect(ArtGen.item(drop.item.def),
		Rect2(foot + Vector2(-11, -30 + bob), Vector2(22, 22)), false)


func _draw_npc(foot: Vector2, cell: Vector2i, npc: NpcUnit) -> void:
	var height := _billboard(ArtGen.npc_art(npc.def.palette), foot, ArtGen.npc(npc.def.palette))
	if Grid.chebyshev(_session.player.position, npc.position) <= GameSession.TALK_RADIUS:
		_stroke(_to_screen(Iso.corners(Vector2(cell.x, cell.y))), Color(0.4, 0.8, 1, 0.8), 2.0)
	_label(npc.def.display_name, foot + Vector2(0, -height - 6), 13, Color(0.72, 0.9, 1))


func _draw_monster(foot: Vector2, at: Vector2, monster: MonsterUnit) -> void:
	var gait := _gait(at, monster.position, _clock)
	var height := _billboard(ArtGen.monster_art(monster.def.id), foot, ArtGen.monster(monster.def.id),
		bool(gait["flip"]), float(gait["lean"]), float(gait["squash"]))
	var top := foot + Vector2(0, -height - 2)
	draw_bar(Rect2(top + Vector2(-15, 0), Vector2(30, 3)), monster.hp_percent,
		Palette.HEALTH, Palette.HEALTH_LOW)
	_label("%s %d" % [monster.name, monster.level], top + Vector2(0, -6), 13, Color(1, 0.85, 0.7))
	if _quarry.has(monster.def.id):
		_label("任务", top + Vector2(0, -20), 13, Color(1.0, 0.82, 0.25))


func _draw_player(foot: Vector2, cell: Vector2i) -> void:
	var player := _session.player
	var points := _to_screen(Iso.corners(Vector2(cell.x, cell.y)))
	if not player.alive:
		_stroke(points, Color(0.42, 0.12, 0.12, 0.9), 3.0)
		draw_bar(Rect2(foot + Vector2(-16, -20), Vector2(32, 4)), player.hp_percent,
			Palette.HEALTH, Palette.HEALTH_LOW)
		return
	# 站着不动时也画走路帧的第 0 帧：素材表里没单独登记"立正"，
	# 用起步那一帧当待机，比让身体僵在跨步中间看着自然。
	var frame := _player_frame if _is_walking() else 0
	var height := _billboard(ArtGen.walk_art(_player_face, frame), foot,
		ArtGen.player(), ArtGen.walk_flips(_player_face))
	draw_bar(Rect2(foot + Vector2(-16, -height - 8), Vector2(32, 4)), player.hp_percent,
		Palette.HEALTH, Palette.HEALTH_LOW)
	if not _session.effects.is_empty():
		_stroke(points, Color(1.0, 0.85, 0.4, 0.85), 2.5)


func draw_bar(rect: Rect2, ratio: float, full: Color, empty: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	draw_rect(rect, Color(0, 0, 0, 0.65))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)),
		full if ratio > 0.3 else empty)


## 居中的描边字：地面花纹一花，没描边的白字就糊了。
func _label(text: String, at: Vector2, size: int, color: Color) -> void:
	var font := ArtGen.ui_font()
	var left := at + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x * 0.5, 0)
	for off in OUTLINE_OFFSETS:
		draw_string(font, left + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Color(0, 0, 0, 0.7))
	draw_string(font, left, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


# ── 特效 ────────────────────────────────────────────────────────────

func _draw_flashes() -> void:
	for f in _flashes:
		var flash: Dictionary = f
		var radius := int(flash["radius"])
		var color: Color = flash["color"]
		var alpha := clampf(float(flash["life"]) / FLASH_SECONDS, 0.0, 1.0)
		var center := flash["at"] as Vector2i
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := Grid.add(center, dx, dy)
				var points := _to_screen(Iso.corners(Vector2(cell.x, cell.y)))
				draw_colored_polygon(points, Color(color.r, color.g, color.b, alpha * 0.13))
				if absi(dx) == radius or absi(dy) == radius:
					_stroke(points, Color(color.r, color.g, color.b, alpha * 0.75), 2.0)


func _draw_floaters() -> void:
	for f in _floaters:
		var floater: Dictionary = f
		var color: Color = floater["color"]
		var alpha := clampf(float(floater["life"]) / 1.1, 0.0, 1.0)
		_label(floater["text"], (floater["at"] as Vector2) - _camera, 16,
			Color(color.r, color.g, color.b, alpha))
