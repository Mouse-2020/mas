class_name QuestDef
extends Resource

# 任务模板，来自 quest/quests.csv。链式关系只靠 requires_quest_id 一条边表达，够用了。

@export var id := ""
@export var display_name := ""

## 接任务时说的话。
@export_multiline var offer := ""

## 面板上"还差什么"的那句提示。
@export var hint := ""

## 完成后交付时说的话。
@export_multiline var turn_in_text := ""

@export_enum("猎杀", "收集") var kind: int = Enums.QuestKind.KILL

## 猎杀填怪物 id，收集填物品 id。
@export var target := ""

@export var count := 1
@export var npc_id := ""

## 留空表示在同一个 NPC 处交付。
@export var turn_in_npc_override := ""

## 前置任务必须已交付，用来控制推进节奏（别让 1 级就接到打白骨宗师的活）。
@export var requires_quest_id := ""

@export var reward_experience := 0
@export var reward_gold := 0
@export var rewards: Array[QuestReward] = []


var turn_in_npc_id: String:
	get:
		return turn_in_npc_override if turn_in_npc_override != "" else npc_id
