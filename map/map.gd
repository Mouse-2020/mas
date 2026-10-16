class_name GameMap
extends RefCounted

# 一张已生成的地图：整数网格 + 出生点 + 刷怪点 + 门 + NPC 站位。
# 内容由 MapGenerator 按 (地图定义, 种子) 决定，所以存档只需要记这两样。

const TILE_SIZE := 32

var id := ""
var display_name := ""
var theme := Enums.MapTheme.OUTDOOR
var safe := false
var seed := 0
var width := 96
var height := 72

var cells: Array = []
var spawn := Vector2i.ZERO
var monster_spawns: Array = []
var exits: Array = []

## { npc_id: Vector2i }
var npc_positions := {}


## 手工搭的小地图，自检里用来构造"被墙封死"这类极端场景。
func _init(p_name: String, p_width: int, p_height: int, p_theme: int = Enums.MapTheme.OUTDOOR,
		p_safe := false, p_seed := 0, p_id := "") -> void:
	assert(p_width > 0 and p_height > 0, "地图尺寸必须为正数")
	id = p_id if p_id != "" else p_name
	display_name = p_name
	theme = p_theme
	safe = p_safe
	seed = p_seed
	width = p_width
	height = p_height
	cells.clear()
	cells.resize(p_width * p_height)
	cells.fill(Enums.Terrain.FLOOR)


static func from_def(def: MapDef, p_seed: int) -> GameMap:
	return GameMap.new(def.display_name, def.width, def.height, def.theme, def.safe, p_seed, def.id)


func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


func terrain_at(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return Enums.Terrain.WALL
	return cells[pos.y * width + pos.x]


func set_terrain(pos: Vector2i, terrain: int) -> void:
	if not in_bounds(pos):
		return
	cells[pos.y * width + pos.x] = terrain


## 静态可走性由地形决定，动态占位由 GameSession 管。
static func terrain_is_walkable(terrain: int) -> bool:
	return terrain != Enums.Terrain.WATER and terrain != Enums.Terrain.WALL \
		and terrain != Enums.Terrain.ROCK and terrain != Enums.Terrain.TREE


func is_walkable(pos: Vector2i) -> bool:
	return in_bounds(pos) and terrain_is_walkable(terrain_at(pos))


func set_spawn(pos: Vector2i) -> void:
	spawn = walkable_near(pos)


func add_monster_spawn(pos: Vector2i) -> void:
	if not in_bounds(pos) or not is_walkable(pos):
		return
	monster_spawns.append(pos)


func add_exit(map_exit: MapExit) -> void:
	if not in_bounds(map_exit.at):
		return
	for existing in exits:
		if existing.at == map_exit.at or existing.to_map == map_exit.to_map:
			return
	exits.append(map_exit)


func put_npc(npc_id: String, pos: Vector2i) -> void:
	if not in_bounds(pos):
		return
	npc_positions[npc_id] = pos


func exit_at(pos: Vector2i) -> MapExit:
	for existing in exits:
		if existing.at == pos:
			return existing
	return null


## 从别的图进门后站哪儿：优先用"通回那张图"的门（进得去也找得回来），
## 没有对应门就退到任意一扇门，再没有就是出生点。
## 落点必须避开门格本身——踩在门上等于一落地就想再穿回去。
func arrival_for(from_map_id: String) -> Vector2i:
	var index := -1
	for i in exits.size():
		if exits[i].to_map == from_map_id:
			index = i
			break
	if index < 0 and not exits.is_empty():
		index = 0
	if index < 0:
		return spawn

	var gate: Vector2i = exits[index].at
	for ring in range(1, 5):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var candidate := gate + Vector2i(dx, dy)
				# 贴边那圈不算：落在边界上等于站在门槛外沿，下一步就又踩回门格。
				if candidate.x == 0 or candidate.y == 0 or candidate.x == width - 1 or candidate.y == height - 1:
					continue
				if not is_walkable(candidate) or exit_at(candidate) != null:
					continue
				return candidate
	return spawn


## 把任意点吸附到最近的可走格，保证生成脚本写歪一格就导致出生点在墙上。
func walkable_near(from: Vector2i) -> Vector2i:
	if is_walkable(from):
		return from
	var best := from
	var best_distance := 0x7FFFFFFF
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var candidate := from + Vector2i(dx, dy)
			if not is_walkable(candidate):
				continue
			var distance := Grid.manhattan(candidate, from)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


func all_positions() -> Array:
	var out: Array = []
	for y in height:
		for x in width:
			out.append(Vector2i(x, y))
	return out
