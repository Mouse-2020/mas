class_name MonsterUnit
extends Unit

# 场上的一只怪：模板 + 运行时状态（归位点、仇恨、复活倒计时、寻路缓存）。

var def: MonsterDef
var home := Vector2i.ZERO
var aggro := false
var respawn_seconds := 0.0
var path: Array = []
var attack_cooldown := 0.0
var wander_cooldown := 0.0

## 追击时不必每帧重算 A*，用这个倒计时限制重寻路频率。
var repath_seconds := 0.0

## 走格子的分数进度：单帧位移不足一格时靠它攒够一步。
var move_progress := 0.0


func _init(p_def: MonsterDef, p_position: Vector2i) -> void:
	def = p_def
	home = p_position
	position = p_position
	name = p_def.id
	level = p_def.level
	hp = p_def.base_stats.max_hp


func get_stats() -> StatBlock:
	return def.base_stats
