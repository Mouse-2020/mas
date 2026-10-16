class_name Rng
extends RefCounted

# 可复现的随机源：同一粒种子永远得到同一局内容，方便存档校验与测试。
# uint32 xorshift：任何一处掩码改动都会改变同一粒种子的世界与战斗结果。

const U32 := 0xFFFFFFFF

var _a := 0
var _b := 0
var _c := 0
var _d := 0


func _init(seed_value: int = 0) -> void:
	_a = (seed_value & U32) | 1
	_b = ((seed_value * 2654435761) & U32) | 1
	_c = _b ^ 0x9E3779B9
	_d = _a ^ 0x85EBCA6B
	for _i in 8:
		next_uint()


func next_uint() -> int:
	var t := _d
	t = t ^ ((t << 11) & U32)
	t = t ^ (t >> 8)
	_d = _c
	_c = _b
	_b = _a
	_a = (t ^ _a ^ (_a >> 19)) & U32
	return _a


## [0, max_exclusive)
func next(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return next_uint() % max_exclusive


## [min_inclusive, max_exclusive)
func next_range(min_inclusive: int, max_exclusive: int) -> int:
	if max_exclusive <= min_inclusive:
		return min_inclusive
	return min_inclusive + next(max_exclusive - min_inclusive)


## [min_inclusive, max_inclusive]
func next_inclusive(min_inclusive: int, max_inclusive: int) -> int:
	if max_inclusive <= min_inclusive:
		return min_inclusive
	return min_inclusive + next(max_inclusive - min_inclusive + 1)


func next_double() -> float:
	return float(next_uint()) / (float(U32) + 1.0)


func chance(probability: float) -> bool:
	return next_double() < probability


## 正态抖动，用于让伤害不完全平均。
func gaussian(mean: float, deviation: float) -> float:
	var u1 := maxf(1e-9, next_double())
	var u2 := next_double()
	return mean + deviation * sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func pick(items: Array) -> Variant:
	return items[next(items.size())]
