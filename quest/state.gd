class_name QuestState
extends RefCounted

# 玩家在这条任务线上的进度。

var id := ""
var status := Enums.QuestStatus.NONE

## 击杀数。Collect 类任务不记在这儿，交付时直接按背包实数收。
var progress := 0
