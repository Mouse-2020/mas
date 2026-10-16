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

	# 民居：固定网格排布，留出巷口，看上去像城而不是墙阵。
	for block in 12:
		var origin := Vector2i(6 + (block % 4) * 22, 8 + (block / 4) * 18)
		if absi(origin.x - center.x) < 15 and absi(origin.y - center.y) < 12:
			continue
		_house(map, origin, rng.next_inclusive(7, 11), rng.next_inclusive(5, 8))
	for y in range(2, map.height - 2, 3):
		for x in range(2, map.width - 2, 3):
			var pos := Vector2i(x, y)
			if map.terrain_at(pos) == Enums.Terrain.FLOOR and rng.chance(0.14):
				map.set_terrain(pos, Enums.Terrain.GRASS)


static func _house(map: GameMap, origin: Vector2i, house_width: int, house_height: int) -> void:
	for y in house_height:
		for x in house_width:
			var pos := origin + Vector2i(x, y)
			if not map.in_bounds(pos):
				continue
			var boundary := x == 0 or y == 0 or x == house_width - 1 or y == house_height - 1
			if not boundary:
				map.set_terrain(pos, Enums.Terrain.FLOOR)
				continue
			var doorway := (y == house_height / 2 and (x == 0 or x == house_width - 1)) \
				or (x == house_width / 2 and y == house_height - 1)
			map.set_terrain(pos, Enums.Terrain.ROAD if doorway else Enums.Terrain.WALL)


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
	var radius_x := maxi(3, int(rng.next_inclusive(7, 11) * scale))
	var radius_y := maxi(3, int(rng.next_inclusive(4, 7) * scale))
	for dy in range(-radius_y, radius_y + 1):
		for dx in range(-radius_x, radius_x + 1):
			if (dx * dx) / float(radius_x * radius_x) + (dy * dy) / float(radius_y * radius_y) > 1.0:
				continue
			var pos := center + Vector2i(dx, dy)
			if map.is_walkable(pos):
				map.set_terrain(pos, Enums.Terrain.WATER)
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
