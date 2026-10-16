class_name GameEvent
extends RefCounted

# 给 UI 用的事件流：战斗飘字、日志面板、音效都从这里取。

var type := Enums.GameEventType.MOVE
var text := ""
var at := Vector2i.ZERO
var amount := 0


static func make(p_type: int, p_text: String, p_at: Vector2i, p_amount := 0) -> GameEvent:
	var event := GameEvent.new()
	event.type = p_type
	event.text = p_text
	event.at = p_at
	event.amount = p_amount
	return event
