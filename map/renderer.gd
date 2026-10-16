class_name WorldRenderer
extends RefCounted

# 整张地图渲染成一张图（无头核对用）：直接返回 Godot 的 Image，工具侧再 save_png。


static func render(session: GameSession, scale := 6, view_radius := 0) -> Image:
	var map: GameMap = session.map
	var tile := maxi(2, map.TILE_SIZE * scale / 8)

	var left := 0
	var top := 0
	var columns := map.width
	var rows := map.height
	if view_radius > 0:
		left = maxi(0, session.player.position.x - view_radius)
		top = maxi(0, session.player.position.y - view_radius)
		columns = mini(map.width - left, view_radius * 2 + 1)
		rows = mini(map.height - top, view_radius * 2 + 1)

	var image := Image.create(columns * tile, rows * tile, false, Image.FORMAT_RGBA8)
	image.fill(Palette.BACKDROP)

	for y in rows:
		for x in columns:
			var pos := Vector2i(left + x, top + y)
			var base := Palette.terrain_color(map.terrain_at(pos))
			# 棋盘式微差，让同色地形看出格子边界。
			var shade := 1.0 if ((left + x + top + y) & 1) == 0 else 0.93
			var px := x * tile
			var py := y * tile
			_fill_rect(image, px, py, tile, tile, Color8(
				int(base.r * 255.0 * shade), int(base.g * 255.0 * shade), int(base.b * 255.0 * shade)))
			if not map.is_walkable(pos):
				_hatch(image, px, py, tile)

	_marker(image, map.spawn, Palette.SPAWN, tile, left, top)
	for spawn in map.monster_spawns:
		_marker(image, spawn, Palette.MONSTER_SPAWN_MARK, tile, left, top)

	for entry in session.loot:
		var loot_item := entry as LootItem
		var center := _center(loot_item.position, tile, left, top)
		_fill_rect(image, center.x - tile / 6, center.y - tile / 6, tile / 3, tile / 3, Palette.LOOT)

	for entry in session.monsters:
		var monster := entry as MonsterUnit
		if not monster.alive:
			continue
		_draw_unit(image, monster.position, Palette.monster_color(monster.def.id), tile, left, top, monster.hp_percent)

	_draw_unit(image, session.player.position, Palette.PLAYER, tile, left, top, session.player.hp_percent)
	return image


static func _center(pos: Vector2i, tile: int, left: int, top: int) -> Vector2i:
	return Vector2i((pos.x - left) * tile + tile / 2, (pos.y - top) * tile + tile / 2)


static func _draw_unit(image: Image, pos: Vector2i, color: Color, tile: int, left: int, top: int, health: float) -> void:
	var center := _center(pos, tile, left, top)
	var size := tile * 3 / 4
	_fill_rect(image, center.x - size / 2, center.y - size / 2, size, size, Color8(
		int(color.r * 255.0 * 0.35), int(color.g * 255.0 * 0.35), int(color.b * 255.0 * 0.35)))
	_fill_rect(image, center.x - size / 2 + 1, center.y - size / 2 + 1, size - 2, size - 2, color)

	var bar_width := tile - 2
	_fill_rect(image, center.x - bar_width / 2, center.y - size / 2 - 4, bar_width, 3, Color8(30, 30, 30))
	var fill := int(float(bar_width) * clampf(health, 0.0, 1.0))
	var bar_color := Palette.HEALTH if health > 0.45 else Palette.HEALTH_LOW
	_fill_rect(image, center.x - bar_width / 2, center.y - size / 2 - 4, fill, 3, bar_color)


static func _marker(image: Image, pos: Vector2i, color: Color, tile: int, left: int, top: int) -> void:
	var px := (pos.x - left) * tile
	var py := (pos.y - top) * tile
	if px < 0 or py < 0:
		return
	_stroke_rect(image, px + 1, py + 1, tile - 2, tile - 2, color)


static func _hatch(image: Image, px: int, py: int, tile: int) -> void:
	var i := 0
	while i < tile:
		_line(image, px + i, py, px, py + i, Palette.HATCH)
		i += 3


static func _fill_rect(image: Image, x: int, y: int, rect_width: int, rect_height: int, color: Color) -> void:
	if rect_width <= 0 or rect_height <= 0:
		return
	for yy in range(y, y + rect_height):
		for xx in range(x, x + rect_width):
			_set_pixel(image, xx, yy, color)


static func _stroke_rect(image: Image, x: int, y: int, rect_width: int, rect_height: int, color: Color) -> void:
	if rect_width <= 0 or rect_height <= 0:
		return
	for xx in range(x, x + rect_width):
		_set_pixel(image, xx, y, color)
		_set_pixel(image, xx, y + rect_height - 1, color)
	for yy in range(y, y + rect_height):
		_set_pixel(image, x, yy, color)
		_set_pixel(image, x + rect_width - 1, yy, color)


static func _line(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var step_x := 1 if x0 < x1 else -1
	var step_y := 1 if y0 < y1 else -1
	var err := dx - dy
	while true:
		_set_pixel(image, x0, y0, color)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x0 += step_x
		if e2 < dx:
			err += dx
			y0 += step_y


static func _set_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, color)
