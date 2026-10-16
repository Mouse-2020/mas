class_name DropRoll
extends Resource

# 一条掉落：杀这只怪时，按 chance 掷一次，命中就掉 min..max 个该物品。

@export var item_id := ""
@export_range(0.0, 1.0) var chance := 0.5
@export var min_count := 1
@export var max_count := 1


static func make(p_item_id: String, p_chance: float, p_min: int, p_max: int) -> DropRoll:
	var roll := DropRoll.new()
	roll.item_id = p_item_id
	roll.chance = p_chance
	roll.min_count = p_min
	roll.max_count = p_max
	return roll
