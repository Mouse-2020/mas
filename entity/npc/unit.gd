class_name NpcUnit
extends Unit

# 站在地图上的 NPC。它继承 Unit 是为了能进占位表——玩家不能穿过人，
# 但也不能砍人，所以 is_attackable 关掉。

var def: NpcDef
var _stats := StatBlock.new()


func _init(p_def: NpcDef, p_position: Vector2i) -> void:
	def = p_def
	name = p_def.display_name
	position = p_position
	hp = 1
	level = 1


func get_stats() -> StatBlock:
	return _stats


func is_attackable() -> bool:
	return false
