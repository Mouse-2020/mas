class_name DialogueOption
extends RefCounted

# 对话面板上的一枚按钮：语义 + 文案 + 载荷。

var kind := Enums.DialogueKind.TALK
var label := ""
var payload := ""


static func make(p_kind: int, p_label: String, p_payload := "") -> DialogueOption:
	var option := DialogueOption.new()
	option.kind = p_kind
	option.label = p_label
	option.payload = p_payload
	return option
