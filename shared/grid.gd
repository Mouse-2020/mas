class_name Grid
extends RefCounted

# 网格坐标工具。地图是整数网格，单位对齐到格子中心。
# 网格坐标统一用 Godot 内建 Vector2i；这里只放运算函数。

static func delta(direction: int) -> Vector2i:
	match direction:
		Enums.Direction.UP:
			return Vector2i(0, -1)
		Enums.Direction.UP_RIGHT:
			return Vector2i(1, -1)
		Enums.Direction.RIGHT:
			return Vector2i(1, 0)
		Enums.Direction.DOWN_RIGHT:
			return Vector2i(1, 1)
		Enums.Direction.DOWN:
			return Vector2i(0, 1)
		Enums.Direction.DOWN_LEFT:
			return Vector2i(-1, 1)
		Enums.Direction.LEFT:
			return Vector2i(-1, 0)
		_:
			return Vector2i(-1, -1)


static func offset(pos: Vector2i, direction: int) -> Vector2i:
	return pos + delta(direction)


static func add(pos: Vector2i, dx: int, dy: int) -> Vector2i:
	return Vector2i(pos.x + dx, pos.y + dy)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func facing_towards(from: Vector2i, target: Vector2i) -> int:
	var dx := signi(target.x - from.x)
	var dy := signi(target.y - from.y)
	if dx == 0 and dy == 0:
		return Enums.Direction.DOWN
	if dx == 0:
		return Enums.Direction.UP if dy < 0 else Enums.Direction.DOWN
	if dx == 1:
		if dy < 0:
			return Enums.Direction.UP_RIGHT
		if dy > 0:
			return Enums.Direction.DOWN_RIGHT
		return Enums.Direction.RIGHT
	if dy < 0:
		return Enums.Direction.UP_LEFT
	if dy > 0:
		return Enums.Direction.DOWN_LEFT
	return Enums.Direction.LEFT
