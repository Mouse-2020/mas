class_name MapGenerator
extends RefCounted

# 程序化地形：同一粒种子 + 同一张地图定义永远得到同一张图，所以存档只记种子和地图 id。
# 次序是硬性的：先画满装饰，再把关键点强制开路，最后用 L 形走廊把它们串起来。
# 反过来（先留走廊再放障碍）会因为装饰步骤在关键点之前而把门埋掉。

const U32 := 0xFFFFFFFF


static func create(def: MapDef, campaign_seed: int) -> GameMap:
	# 每张图独立的随机源：换了进场顺序也不会导致同一张图长得不一样。
	var rng := Rng.new(seed_for(campaign_seed, def.id))
	var map := GameMap.from_def(def, campaign_seed)

	match def.theme:
		Enums.MapTheme.TOWN:
			_paint_town(map, rng)
		Enums.MapTheme.CAVE:
			_paint_cave(map, rng)
		Enums.MapTheme.FOREST:
			_paint_forest(map, rng)
		_:
			_paint_outdoor(map, rng)
	_border_walls(map)

	map.set_spawn(_anchor(map))
	_place_npcs(map, def)
	_place_gates(map, def)

	# 关键点必须先站得住，再谈连通。
	_force_open(map, map.spawn)
	for map_exit in map.exits:
		_force_open(map, map_exit.at)
	for pos in map.npc_positions.values():
		_force_open(map, pos)

	_carve_trunk(map)
	for map_exit in map.exits:
		_carve_corridor(map, map.spawn, map_exit.at)
	for pos in map.npc_positions.values():
		_carve_corridor(map, map.spawn, pos)

	_scatter_spawns(map, def, rng)
	# 房子排在最后：它要拿"最终地形"来判这块地能不能站屋，见 _place_buildings。
	if def.theme == Enums.MapTheme.TOWN:
		_place_buildings(map, rng)
	return map


## 把地图 id 混进种子，避免四张图因为同种子而纹理雷同。
static func seed_for(campaign_seed: int, map_id: String) -> int:
	var h := campaign_seed & U32
	for i in map_id.length():
		h = ((h ^ map_id.unicode_at(i)) * 16777619) & U32
	var as_int32 := h - 0x100000000 if h >= 0x80000000 else h
	return as_int32 | 1


## 地图中心：出生点、广场、传送落点都往这儿靠。
static func _anchor(map: GameMap) -> Vector2i:
	return Vector2i(map.width / 2, map.height / 2)


## 把这一格和周围 8 格全清开——门和 NPC 绝不能站进墙里。
static func _force_open(map: GameMap, center: Vector2i, terrain := Enums.Terrain.ROAD) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var pos := center + Vector2i(dx, dy)
			if not map.in_bounds(pos) or _is_border(map, pos):
				continue
			map.set_terrain(pos, terrain)


static func _is_border(map: GameMap, pos: Vector2i) -> bool:
	return pos.x == 0 or pos.y == 0 or pos.x == map.width - 1 or pos.y == map.height - 1


## 沿地图中线拉一条主干道，各条支线从这里分叉，视觉上像路而不像隧道。
static func _carve_trunk(map: GameMap) -> void:
	var y := map.height / 2
	for x in range(1, map.width - 1):
		for dy in range(-1, 2):
			var pos := Vector2i(x, y + dy)
			if not _is_border(map, pos):
				map.set_terrain(pos, Enums.Terrain.ROAD)


static func _carve_corridor(map: GameMap, from: Vector2i, to: Vector2i) -> void:
	var cursor := from
	while cursor.x != to.x:
		_clear_band(map, cursor)
		cursor = cursor + Vector2i(signi(to.x - cursor.x), 0)
	while cursor.y != to.y:
		_clear_band(map, cursor)
		cursor = cursor + Vector2i(0, signi(to.y - cursor.y))
	_clear_band(map, to)


static func _clear_band(map: GameMap, center: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var pos := center + Vector2i(dx, dy)
			if not map.in_bounds(pos) or _is_border(map, pos):
				continue
			if map.is_walkable(pos):
				continue
			map.set_terrain(pos, Enums.Terrain.FLOOR)


# ── 主题画法 ──────────────────────────────────────────────────────────

static func _paint_outdoor(map: GameMap, rng: Rng) -> void:
	for y in map.height:
		for x in map.width:
			var noise := sin(x * 0.21 + map.seed % 7) + cos(y * 0.17 - map.seed % 5)
			map.set_terrain(Vector2i(x, y), Enums.Terrain.GRASS if noise > 0.35 else Enums.Terrain.FLOOR)
	_carve_lake(map, rng)
	_scatter_rocks(map, rng, 26)
	_plant_grove(map, rng, 5)
	_build_ruins(map, rng)


static func _paint_forest(map: GameMap, rng: Rng) -> void:
	for y in map.height:
		for x in map.width:
			map.set_terrain(Vector2i(x, y), Enums.Terrain.GRASS if rng.chance(0.72) else Enums.Terrain.FLOOR)

	# 密林：一簇一簇的树，中间留几块空地当猎场。
	for _cluster in 16:
		var center := Vector2i(rng.next_inclusive(4, map.width - 5), rng.next_inclusive(4, map.height - 5))
		var count := rng.next_inclusive(20, 46)
		for _i in count:
			var pos := center + Vector2i(rng.next_inclusive(-5, 5), rng.next_inclusive(-4, 4))
			if map.is_walkable(pos):
				map.set_terrain(pos, Enums.Terrain.TREE)
	for _clearing in 5:
		var center := Vector2i(rng.next_inclusive(8, map.width - 9), rng.next_inclusive(8, map.height - 9))
		var radius := rng.next_inclusive(4, 7)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius:
					continue
				var pos := center + Vector2i(dx, dy)
				if map.terrain_at(pos) == Enums.Terrain.TREE:
					map.set_terrain(pos, Enums.Terrain.GRASS)
	_carve_pond(map, rng)
	_scatter_rocks(map, rng, 14)


static func _paint_cave(map: GameMap, rng: Rng) -> void:
	for y in map.height:
		for x in map.width:
			map.set_terrain(Vector2i(x, y), Enums.Terrain.WALL)

	# 随机游走挖隧道，再从几个点扩出石室；剩下的连通性交给走廊。
	for _tunnel in 8:
		var cursor := Vector2i(rng.next_inclusive(6, map.width - 7), rng.next_inclusive(6, map.height - 7))
		var steps := rng.next_inclusive(110, 220)
		for _i in steps:
			cursor = Grid.offset(cursor, rng.next(8))
			if not map.in_bounds(cursor):
				cursor = _anchor(map)
				continue
			map.set_terrain(cursor, Enums.Terrain.FLOOR)
			if rng.chance(0.14):
				_room(map, cursor, rng.next_inclusive(3, 6), rng.next_inclusive(3, 5))
	_room(map, _anchor(map), 9, 7)

	for _pool in 4:
		var center := Vector2i(rng.next_inclusive(6, map.width - 7), rng.next_inclusive(6, map.height - 7))
		var radius := rng.next_inclusive(2, 4)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy > radius * radius:
					continue
				var pos := center + Vector2i(dx, dy)
				if map.terrain_at(pos) == Enums.Terrain.FLOOR:
					map.set_terrain(pos, Enums.Terrain.WATER)
	_scatter_rocks(map, rng, 24)


static func _room(map: GameMap, center: Vector2i, half_width: int, half_height: int) -> void:
	for dy in range(-half_height, half_height + 1):
		for dx in range(-half_width, half_width + 1):
			var pos := center + Vector2i(dx, dy)
			if map.in_bounds(pos):
				map.set_terrain(pos, Enums.Terrain.FLOOR)


## 城里那口塘。位置与半径都钉死，不进随机：渔夫 老姜 的站位是按广场中心算的固定偏移，
## 塘一漂他就站进水里；半径漂一寸，塘边可钓的那几格也跟着漂。
const POND_OFFSET := Vector2i(-27, 8)
const POND_RADIUS := Vector2i(5, 4)


static func _paint_town(map: GameMap, rng: Rng) -> void:
	for y in map.height:
		for x in map.width:
			map.set_terrain(Vector2i(x, y), Enums.Terrain.FLOOR)

	var center := _anchor(map)
	# 广场：城中心一片铺装，NPC 都摆在广场四周。
	for dy in range(-8, 9):
		for dx in range(-10, 11):
			map.set_terrain(center + Vector2i(dx, dy), Enums.Terrain.ROAD)

	for y in range(1, map.height - 1):
		for w in range(-1, 2):
			map.set_terrain(Vector2i(center.x + w, y), Enums.Terrain.ROAD)

	# 空地上的几处院落：整片刷成草皮。按格点撒、或者一半一半地撒，
	# 泥地上出来的就不是院子而是一张污渍网。
	for _patch in 8:
		var patch := Vector2i(rng.next_range(5, map.width - 6), rng.next_range(5, map.height - 6))
		var radius := rng.next_inclusive(2, 3)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				# 齐边的方块在斜视图里是一块铺好的地毯，最外圈随机啃掉几口才像自己长出来的草。
				if maxi(absi(dx), absi(dy)) == radius and rng.next(100) < 45:
					continue
				var pos := patch + Vector2i(dx, dy)
				if map.terrain_at(pos) == Enums.Terrain.FLOOR:
					map.set_terrain(pos, Enums.Terrain.GRASS)

	# 城里那口塘：水不可走，所以钉死在广场西南角外——既躲开穿城的南北大街，
	# 也躲开沿中线拉的东西主干道，否则后面的开路步骤会把塘从中劈开。
	# 半径同样钉死：渔夫 老姜 的站位按 npc_spots 的偏移算，塘一漂他就站进水里。
	_carve_ellipse(map, center + POND_OFFSET, POND_RADIUS.x, POND_RADIUS.y)
	_ring_sand(map)


# ── 建筑 ──────────────────────────────────────────────────────────────

## 街区网格：一格地块、四周留巷。地块原点再随机错开几格，
## 于是街墙有进有退，而不是在斜排上排出一条笔直的队列。
const LOT_PITCH := Vector2i(9, 8)
const LOT_EDGE := 4
const LOT_JITTER := Vector2i(3, 2)
## 一块地试几种素材就收手：试不中说明这块地本来就被路占着，换一间屋子也不会突然合适。
const LOT_TRIES := 5

## 抽房用摊平的权重表而不是字典等概率：城里绝大多数该是民居与柴房，
## 望楼、门楼要稀罕。等概率撒八十几间下来，县城会看着像一座兵器库。
const HOUSE_LOTTERY := [
	"house_hut", "house_hut", "house_hut", "house_shed", "house_shed", "house_shed",
	"house_pavilion", "house_pavilion", "house_forge", "house_forge",
	"house_shop", "house_shop", "house_tower", "house_gate",
]

## 大殿的候选位置：广场四角外侧，都躲开那条穿城而过的南北大街。
## 抽签到它头上几乎不可能（四格见方、外圈还得整圈能走），所以这座城的主屋得点名。
const HALL_LOTS: Array[Vector2i] = [Vector2i(2, -13), Vector2i(6, -13),
	Vector2i(2, 10), Vector2i(6, 10)]


## 城里盖房。一条硬规矩撑起整段逻辑：占地和它的外圈在落笔前必须整圈可走。
## 有了它，"绕着房子走一圈"就正好是原来那条路，连通性由规矩本身保证，不用回溯搜索；
## 顺带还保证了任意两栋房子之间至少隔一格——不会出现走不通的夹缝。
static func _place_buildings(map: GameMap, rng: Rng) -> void:
	_place_hall(map)
	for row in range((map.height - LOT_EDGE * 2) / LOT_PITCH.y):
		for col in range((map.width - LOT_EDGE * 2) / LOT_PITCH.x):
			var lot := Vector2i(LOT_EDGE + col * LOT_PITCH.x, LOT_EDGE + row * LOT_PITCH.y) \
				+ Vector2i(rng.next(LOT_JITTER.x + 1), rng.next(LOT_JITTER.y + 1))
			for _try in LOT_TRIES:
				var art := HOUSE_LOTTERY[rng.next(HOUSE_LOTTERY.size())] as String
				if not _lot_clear(map, lot, ArtGen.house_side(art)):
					continue
				_stamp(map, lot, art)
				break


## 武馆大殿点名盖，不抽签：四格见方、外圈还得整圈能走，签到它头上的概率低到整座城
## 常常一栋都不剩。四个候选都堵了就算了——少一栋大殿只是不好看，硬塞一栋会埋掉广场。
static func _place_hall(map: GameMap) -> void:
	var side := ArtGen.house_side("house_hall")
	var center := _anchor(map)
	for offset in HALL_LOTS:
		var lot := center + offset
		if _lot_clear(map, lot, side):
			_stamp(map, lot, "house_hall")
			return


static func _stamp(map: GameMap, origin: Vector2i, art: String) -> void:
	var side := ArtGen.house_side(art)
	for dy in side:
		for dx in side:
			map.set_terrain(origin + Vector2i(dx, dy), Enums.Terrain.HOUSE)
	map.add_building(Rect2i(origin.x, origin.y, side, side), art)


## 圈要能走，块得是块裸地：压在路上等于把巷子埋了，挨着别人则两条巷挤成一条。
static func _lot_clear(map: GameMap, origin: Vector2i, side: int) -> bool:
	var rect := Rect2i(origin.x, origin.y, side, side)
	for pos in GameMap.building_ring(rect):
		if not map.is_walkable(pos):
			return false
	for dy in side:
		for dx in side:
			var terrain := map.terrain_at(origin + Vector2i(dx, dy))
			if terrain != Enums.Terrain.FLOOR and terrain != Enums.Terrain.GRASS:
				return false
	return true


# ── 公共装饰件 ────────────────────────────────────────────────────────

static func _border_walls(map: GameMap) -> void:
	for x in map.width:
		map.set_terrain(Vector2i(x, 0), Enums.Terrain.WALL)
		map.set_terrain(Vector2i(x, map.height - 1), Enums.Terrain.WALL)
	for y in map.height:
		map.set_terrain(Vector2i(0, y), Enums.Terrain.WALL)
		map.set_terrain(Vector2i(map.width - 1, y), Enums.Terrain.WALL)


static func _carve_lake(map: GameMap, rng: Rng) -> void:
	_carve_water(map, rng, 1.0)


static func _carve_pond(map: GameMap, rng: Rng) -> void:
	_carve_water(map, rng, 0.6)


static func _carve_water(map: GameMap, rng: Rng, scale: float) -> void:
	var center := Vector2i(rng.next_inclusive(12, map.width - 20), rng.next_inclusive(8, 22))
	_carve_ellipse(map, center, maxi(3, int(rng.next_inclusive(7, 11) * scale)),
		maxi(3, int(rng.next_inclusive(4, 7) * scale)))
	_ring_sand(map)


static func _carve_ellipse(map: GameMap, center: Vector2i, radius_x: int, radius_y: int) -> void:
	for dy in range(-radius_y, radius_y + 1):
		for dx in range(-radius_x, radius_x + 1):
			if (dx * dx) / float(radius_x * radius_x) + (dy * dy) / float(radius_y * radius_y) > 1.0:
				continue
			var pos := center + Vector2i(dx, dy)
			if map.is_walkable(pos):
				map.set_terrain(pos, Enums.Terrain.WATER)


static func _ring_sand(map: GameMap) -> void:
	# 水陆交界刷一圈沙，边界不像地形切出来的。
	for pos in map.all_positions():
		var terrain := map.terrain_at(pos)
		if terrain != Enums.Terrain.FLOOR and terrain != Enums.Terrain.GRASS:
			continue
		for d in 8:
			if map.terrain_at(Grid.offset(pos, d)) != Enums.Terrain.WATER:
				continue
			map.set_terrain(pos, Enums.Terrain.SAND)
			break


static func _scatter_rocks(map: GameMap, rng: Rng, count: int) -> void:
	for _i in count:
		var pos := Vector2i(rng.next_range(2, map.width - 2), rng.next_range(2, map.height - 2))
		if not map.is_walkable(pos) or Grid.chebyshev(pos, map.spawn) < 4:
			continue
		map.set_terrain(pos, Enums.Terrain.ROCK)
		if not rng.chance(0.4):
			continue
		var extra := Grid.offset(pos, rng.next(8))
		if map.is_walkable(extra):
			map.set_terrain(extra, Enums.Terrain.ROCK)


static func _plant_grove(map: GameMap, rng: Rng, clusters: int) -> void:
	for _cluster in clusters:
		var center := Vector2i(rng.next_inclusive(6, map.width - 7), rng.next_inclusive(6, map.height - 7))
		var count := rng.next_inclusive(8, 18)
		for _i in count:
			var pos := center + Vector2i(rng.next_inclusive(-4, 4), rng.next_inclusive(-4, 4))
			if not map.is_walkable(pos) or Grid.chebyshev(pos, map.spawn) < 5:
				continue
			map.set_terrain(pos, Enums.Terrain.TREE)


static func _build_ruins(map: GameMap, rng: Rng) -> void:
	var origin := Vector2i(rng.next_inclusive(10, maxi(11, map.width - 26)),
			rng.next_inclusive(28, maxi(29, map.height - 20)))
	var ruins_width := rng.next_inclusive(9, 15)
	var ruins_height := rng.next_inclusive(7, 11)
	for y in ruins_height:
		for x in ruins_width:
			var pos := origin + Vector2i(x, y)
			if not map.in_bounds(pos):
				continue
			var boundary := x == 0 or y == 0 or x == ruins_width - 1 or y == ruins_height - 1
			if not boundary:
				map.set_terrain(pos, Enums.Terrain.FLOOR)
				continue
			var doorway := (y == ruins_height / 2 and (x == 0 or x == ruins_width - 1)) \
				or (x == ruins_width / 2 and y == ruins_height - 1)
			map.set_terrain(pos, Enums.Terrain.FLOOR if doorway else Enums.Terrain.WALL)
	map.add_monster_spawn(origin + Vector2i(ruins_width / 2, ruins_height / 2))


static func _place_npcs(map: GameMap, def: MapDef) -> void:
	var center := _anchor(map)
	for spot in def.npc_spots:
		var pos := center + Vector2i(spot.dx, spot.dy)
		if not map.in_bounds(pos):
			continue
		map.put_npc(spot.npc_id, pos)


static func _place_gates(map: GameMap, def: MapDef) -> void:
	for link in def.links:
		var at := Vector2i.ZERO
		match link.side:
			Enums.MapSide.NORTH:
				at = Vector2i(map.width / 2, 1)
			Enums.MapSide.SOUTH:
				at = Vector2i(map.width / 2, map.height - 2)
			Enums.MapSide.WEST:
				at = Vector2i(1, map.height / 2)
			_:
				at = Vector2i(map.width - 2, map.height / 2)
		map.add_exit(MapExit.make(at, link.to_map, link.label))


static func _scatter_spawns(map: GameMap, def: MapDef, rng: Rng) -> void:
	if def.monster_ids.is_empty():
		return
	var placed := map.monster_spawns.size()
	var attempts := 0
	# 拒绝采样必须带上限，否则换个种子就可能永远凑不满要求数量。
	while placed < def.monster_count and attempts < 3000:
		attempts += 1
		var pos := Vector2i(rng.next_range(2, map.width - 2), rng.next_range(2, map.height - 2))
		if not map.is_walkable(pos) or Grid.chebyshev(pos, map.spawn) < 8:
			continue
		var too_close := false
		for other in map.monster_spawns:
			if Grid.chebyshev(other, pos) < 3:
				too_close = true
				break
		if too_close:
			continue
		map.add_monster_spawn(pos)
		placed += 1
	# 刷怪点也得走得到，不然玩家为了完成击杀任务得等到地老天荒。
	for pos in map.monster_spawns.duplicate():
		_force_open(map, pos, Enums.Terrain.FLOOR)
		_carve_corridor(map, map.spawn, pos)
