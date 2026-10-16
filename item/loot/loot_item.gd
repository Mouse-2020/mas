class_name LootItem
extends RefCounted

# 掉在地上的东西，等玩家走过去捡。

var item: ItemInstance
var position := Vector2i.ZERO
var life_seconds := 90.0


func _init(p_item: ItemInstance, p_position: Vector2i) -> void:
	item = p_item
	position = p_position
