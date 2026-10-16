class_name Pathfinding
extends RefCounted

# 8 向 A*；禁止穿墙角，和原作的走位手感一致。

const MAX_PATH_LENGTH := 4096


## is_blocked 是 Callable(pos) -> bool，由 GameSession 提供动态占位判断。
static func find(map: GameMap, is_blocked: Callable, from: Vector2i, to: Vector2i) -> Array:
	var empty: Array = []
	if not map.in_bounds(from) or not map.in_bounds(to):
		return empty
	if from == to:
		return [from]
	if not map.is_walkable(to) or is_blocked.call(to):
		return empty

	var frontier := _Heap.new()
	var came_from := {}
	var cost := {from: 0}
	frontier.push(_heuristic(from, to), from)

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop()
		if current == to:
			return _build_path(came_from, current)

		for step in _neighbours(map, current):
			if not map.is_walkable(step) or is_blocked.call(step):
				continue
			var step_cost := 14 if current.x != step.x and current.y != step.y else 10
			var next_cost: int = cost[current] + step_cost
			if cost.has(step) and cost[step] <= next_cost:
				continue
			cost[step] = next_cost
			came_from[step] = current
			if came_from.size() > MAX_PATH_LENGTH * 4:
				return empty
			frontier.push(next_cost + _heuristic(step, to), step)

	return empty


static func _neighbours(map: GameMap, from: Vector2i) -> Array:
	var out: Array = []
	for d in 8:
		var next_pos := Grid.offset(from, d)
		if not map.is_walkable(next_pos):
			continue
		# 斜走要求两侧直角格都可走，否则会从两块墙的夹缝穿过去。
		if d in [Enums.Direction.UP_RIGHT, Enums.Direction.DOWN_RIGHT, Enums.Direction.DOWN_LEFT, Enums.Direction.UP_LEFT]:
			if not map.is_walkable(from + Vector2i(signi(next_pos.x - from.x), 0)):
				continue
			if not map.is_walkable(from + Vector2i(0, signi(next_pos.y - from.y))):
				continue
		out.append(next_pos)
	return out


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return 10 * (dx + dy) - 6 * mini(dx, dy)


static func _build_path(came_from: Dictionary, goal: Vector2i) -> Array:
	var path: Array = [goal]
	var cursor := goal
	while came_from.has(cursor):
		cursor = came_from[cursor]
		path.append(cursor)
	path.reverse()
	return path


## 二叉最小堆，键是 (priority, 入队序号)：同分时按入队顺序出，路径才不会每次抖。
class _Heap:
	extends RefCounted

	var _prio: Array = []
	var _seq: Array = []
	var _values: Array = []
	var _counter := 0


	func push(priority: int, value: Vector2i) -> void:
		_counter += 1
		_prio.append(priority)
		_seq.append(_counter)
		_values.append(value)
		var i := _prio.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if not _less(i, parent):
				break
			_swap(i, parent)
			i = parent


	func is_empty() -> bool:
		return _prio.is_empty()


	func pop() -> Vector2i:
		var top: Vector2i = _values[0]
		var last_prio: int = _prio.pop_back()
		var last_seq: int = _seq.pop_back()
		var last_value: Vector2i = _values.pop_back()
		if not _prio.is_empty():
			_prio[0] = last_prio
			_seq[0] = last_seq
			_values[0] = last_value
			var i := 0
			while true:
				var left := i * 2 + 1
				var right := left + 1
				var smallest := i
				if left < _prio.size() and _less(left, smallest):
					smallest = left
				if right < _prio.size() and _less(right, smallest):
					smallest = right
				if smallest == i:
					break
				_swap(i, smallest)
				i = smallest
		return top


	func _less(a: int, b: int) -> bool:
		if _prio[a] != _prio[b]:
			return _prio[a] < _prio[b]
		return _seq[a] < _seq[b]


	func _swap(a: int, b: int) -> void:
		var p: int = _prio[a]
		_prio[a] = _prio[b]
		_prio[b] = p
		var s: int = _seq[a]
		_seq[a] = _seq[b]
		_seq[b] = s
		var v: Vector2i = _values[a]
		_values[a] = _values[b]
		_values[b] = v
