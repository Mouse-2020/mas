class_name NpcDef
extends Resource

# 一个能说话、能开店、能传送的站桩角色，来自 npc/npcs.csv。

@export var id := ""
## 留空表示与 id 同名。
@export var title := ""

## 没任务可接没货可交时说的话。
@export_multiline var greeting := "……"

@export var shop_id := ""
@export var can_repair := false
@export var can_teleport := false

## 美术层按这个 key 取色，不关心玩法。
@export var palette := "guide"


var display_name: String:
	get:
		return title if title != "" else id
