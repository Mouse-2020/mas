class_name DialogueOutcome
extends RefCounted

# 选完一项以后 UI 要做的事：开哪家店、去哪张图、附带一句话。
# "没有"统一用空串表示。

var open_shop_id := ""
var travel_to_map := ""
var message := ""


static func make(p_message := "", p_open_shop_id := "", p_travel_to_map := "") -> DialogueOutcome:
	var outcome := DialogueOutcome.new()
	outcome.message = p_message
	outcome.open_shop_id = p_open_shop_id
	outcome.travel_to_map = p_travel_to_map
	return outcome
