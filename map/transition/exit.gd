class_name MapExit
extends RefCounted

# 生成后落地的门：踩上这一格就走图。

var at := Vector2i.ZERO
var to_map := ""
var label := ""


static func make(p_at: Vector2i, p_to_map: String, p_label: String) -> MapExit:
	var exit := MapExit.new()
	exit.at = p_at
	exit.to_map = p_to_map
	exit.label = p_label
	return exit
