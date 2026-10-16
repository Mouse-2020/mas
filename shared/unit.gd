class_name Unit
extends RefCounted

# 一切能打、能被打的东西。静态格子由 GameMap 管，动态占位由 GameSession 管。

var name := ""
var position := Vector2i.ZERO
var facing := Enums.Direction.DOWN
var level := 1
var hp := 0


## 子类给出自己的属性口径（玩家＝基础+装备+增益，怪＝模板）。
func get_stats() -> StatBlock:
	return StatBlock.new()


## 能不能被砍。NPC 继承 Unit 只是为了占格，打人得拦住。
func is_attackable() -> bool:
	return true


var max_hp: int:
	get:
		return maxi(1, get_stats().max_hp)


var max_mp: int:
	get:
		return maxi(0, get_stats().max_mp)


var alive: bool:
	get:
		return hp > 0


var hp_percent: float:
	get:
		if max_hp <= 0:
			return 0.0
		return clampf(float(hp) / float(max_hp), 0.0, 1.0)


## 攻击间隔（秒）。速度属性越高越短。
var attack_delay: float:
	get:
		return clampf(1.25 - 0.045 * get_stats().attack_speed, 0.35, 2.5)


## 每秒走多少格。
var move_speed: float:
	get:
		return clampf(3.2 + 0.25 * get_stats().move_speed, 1.0, 8.0)
