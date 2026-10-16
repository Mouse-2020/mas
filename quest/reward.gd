class_name QuestReward
extends Resource

@export var item_id := ""
@export var count := 1


static func make(p_item_id: String, p_count: int) -> QuestReward:
	var reward := QuestReward.new()
	reward.item_id = p_item_id
	reward.count = p_count
	return reward
