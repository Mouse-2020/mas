class_name WorldView
extends Node2D

# 把 GameSession 的格子世界画成画面：相机跟着人走，只画视野内的格子。

const TILE := ArtGen.TILE
const FLASH_SECONDS := 0.3
const NO_TARGET := Vector2i(-99999, -99999)

## 相机每秒收敛多少：用指数平滑而不是固定 lerp 系数，帧率变了跟随速度不该跟着变。
const CAMERA_SMOOTH := 9.0

## 走路时上下起伏的像素数。站定时两头都是 0，所以停下不会留半格抖动。
const STEP_BOB := 2.0

var _session: GameSession
var _camera := Vector2.ZERO
var _floaters: Array = []
var _flashes: Array = []
var _target := NO_TARGET


func bind(session: GameSession) -> void:
	_session = session
	_center_camera(true)
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


## 收 Vector2 是为了让"正在两格之间"的浮点位置也能直接进来（整数格调用方会自动升宽）。
func cell_to_screen(cell: Vector2) -> Vector2:
	return Vector2(cell.x * TILE - _camera.x, cell.y * TILE - _camera.y)


## 用"离整数格多远"当步态相位：半格时最高，落回格子上正好归零。
static func _step_bob(cell: Vector2) -> Vector2:
	var phase := absf(cell.x - floorf(cell.x)) + absf(cell.y - floorf(cell.y))
	return Vector2(0.0, -STEP_BOB * sin(minf(phase, 1.0) * PI))


func screen_to_cell(screen: Vector2) -> Vector2i:
	return Vector2i(floori((screen.x + _camera.x) / TILE), floori((screen.y + _camera.y) / TILE))


func add_floater(at: Vector2i, text: String, color: Color) -> void:
	var p := cell_to_screen(at) + Vector2(TILE / 2.0, 6)
	_floaters.append({ "at": p, "text": text, "color": color, "life": 1.1 })


## 技能落点闪一圈。半径用格数，画成方框比画圆省事也更贴合格子世界。
func add_flash(at: Vector2i, radius: int, color: Color) -> void:
	_flashes.append({ "at": at, "radius": maxi(1, radius), "color": color, "life": FLASH_SECONDS })


func _process(delta: float) -> void:
	if _session == null:
		return
	_center_camera(false, delta)
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
	# 跟着插值后的位置而不是脚下那格，否则相机仍在按整格追，人却滑着走。
	var p := _session.player_render_cell()
	var target := Vector2(p.x * TILE + TILE / 2.0 - view.x / 2.0, p.y * TILE + TILE / 2.0 - view.y / 2.0)
	target.x = clampf(target.x, 0.0, maxf(0.0, _session.map.width * TILE - view.x))
	target.y = clampf(target.y, 0.0, maxf(0.0, _session.map.height * TILE - view.y))
	if snap:
		_camera = target
	else:
		_camera = _camera.lerp(target, 1.0 - exp(-CAMERA_SMOOTH * delta))


func _draw() -> void:
	if _session == null:
		return
	var map := _session.map
	var view := get_viewport().get_visible_rect().size
	var x0 := maxi(0, floori(_camera.x / TILE))
	var y0 := maxi(0, floori(_camera.y / TILE))
	var x1 := mini(map.width - 1, ceili((_camera.x + view.x) / TILE))
	var y1 := mini(map.height - 1, ceili((_camera.y + view.y) / TILE))

	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			var rect := Rect2(cell_to_screen(cell), Vector2(TILE, TILE))
			draw_texture_rect(ArtGen.ground(map.terrain_at(cell)), rect, false)
			if cell == map.spawn:
				draw_rect(rect.grow(-8), Color(Palette.SPAWN, 0.28))

	if _target != NO_TARGET:
		draw_rect(Rect2(cell_to_screen(_target), Vector2(TILE, TILE)).grow(-2), Color(1, 1, 1, 0.35), false, 2.0)

	for entry in map.exits:
		var exit := entry as MapExit
		var rect := Rect2(cell_to_screen(exit.at), Vector2(TILE, TILE))
		draw_rect(rect.grow(-3), Color(0.35, 0.78, 0.95, 0.28))
		draw_rect(rect.grow(-3), Color(0.75, 0.93, 1, 0.8), false, 2.0)
		draw_string(ArtGen.ui_font(), rect.position + Vector2(TILE / 2.0, -2), exit.label,
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, Color(0.75, 0.93, 1))

	for entry in _session.loot:
		var drop := entry as LootItem
		var pos := cell_to_screen(drop.position)
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(TILE - 8, TILE - 8)), Color(Palette.LOOT, 0.22))
		draw_texture_rect(ArtGen.item(drop.item.def), Rect2(pos + Vector2(6, 6), Vector2(20, 20)), false)

	# 任务怪的头顶标一下，否则"在迷雾竹林猎杀竹林狼"得靠翻怪物表。
	var quarry := {}
	for entry in _session.quests:
		var quest := entry as QuestState
		if quest.status != Enums.QuestStatus.ACTIVE:
			continue
		var def := QuestDatabase.get_def(quest.id)
		if def.kind == Enums.QuestKind.KILL:
			quarry[def.target] = true

	for entry in _session.monsters:
		var monster := entry as MonsterUnit
		if not monster.alive:
			continue
		var cell := _session.monster_render_cell(monster)
		var pos := cell_to_screen(cell) + _step_bob(cell)
		if pos.x < -TILE or pos.y < -TILE or pos.x > view.x or pos.y > view.y:
			continue
		draw_texture_rect(ArtGen.monster(monster.def.id), Rect2(pos, Vector2(TILE, TILE)), false)
		draw_bar(Rect2(pos + Vector2(3, -4), Vector2(TILE - 6, 3)), monster.hp_percent, Palette.HEALTH, Palette.HEALTH_LOW)
		draw_string(ArtGen.ui_font(), pos + Vector2(2, -8), "%s %d" % [monster.name, monster.level],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1, 0.85, 0.7))
		if quarry.has(monster.def.id):
			draw_string(ArtGen.ui_font(), pos + Vector2(TILE / 2.0, -22), "任务",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, Color(1.0, 0.82, 0.25))

	var player := _session.player
	var player_cell := _session.player_render_cell()
	var player_pos := cell_to_screen(player_cell) + _step_bob(player_cell)

	for entry in _session.npcs:
		var npc := entry as NpcUnit
		var pos := cell_to_screen(npc.position)
		if pos.x < -TILE or pos.y < -TILE or pos.x > view.x or pos.y > view.y:
			continue
		var rect := Rect2(pos, Vector2(TILE, TILE))
		var in_talk_range := Grid.chebyshev(player.position, npc.position) <= GameSession.TALK_RADIUS
		if in_talk_range:
			draw_rect(rect.grow(-2), Color(0.4, 0.8, 1, 0.35), false, 2.0)
		draw_texture_rect(ArtGen.npc(npc.def.palette), rect, false)
		draw_string(ArtGen.ui_font(), pos + Vector2(2, -8), npc.def.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.72, 0.9, 1))

	if player.alive:
		draw_texture_rect(ArtGen.player(), Rect2(player_pos, Vector2(TILE, TILE)), false)
	else:
		draw_rect(Rect2(player_pos + Vector2(6, 20), Vector2(20, 6)), Color(0.55, 0.2, 0.2, 0.8))
	draw_bar(Rect2(player_pos + Vector2(1, -8), Vector2(TILE - 2, 4)), player.hp_percent, Palette.HEALTH, Palette.HEALTH_LOW)
	if player.alive and not _session.effects.is_empty():
		draw_rect(Rect2(player_pos + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), Color(1.0, 0.85, 0.4, 0.5), false, 2.0)

	for f in _flashes:
		var flash: Dictionary = f
		var radius := int(flash["radius"])
		var side := radius * 2 + 1
		var origin := cell_to_screen(Grid.add(flash["at"], -radius, -radius))
		var alpha := clampf(float(flash["life"]) / FLASH_SECONDS, 0.0, 1.0) * 0.55
		var color: Color = flash["color"]
		draw_rect(Rect2(origin, Vector2(TILE * side, TILE * side)), Color(color.r, color.g, color.b, alpha), false, 2.0)

	for f in _floaters:
		var floater: Dictionary = f
		draw_string(ArtGen.ui_font(), floater["at"], floater["text"],
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16, floater["color"])


func draw_bar(rect: Rect2, ratio: float, full: Color, empty: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	draw_rect(rect, Color(0, 0, 0, 0.65))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), full if ratio > 0.3 else empty)
