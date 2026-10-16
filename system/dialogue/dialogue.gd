class_name NpcDialogue
extends RefCounted

# 一轮对话：一句话 + 若干可选项。选项由 system/session.gd 算出来，表现层只负责画。

var npc_id := ""
var text := ""
var options: Array = []
