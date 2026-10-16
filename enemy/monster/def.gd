class_name MonsterDef
extends Resource

# 一只怪的模板，来自 enemy/monster/monsters.csv。经验由等级反推，血量与攻击区间决定难度。

@export var id := ""
@export var level := 1
@export var base_stats: StatBlock = null
@export var aggro_radius := 6
@export var attack_range := 1
@export var chase_range := 14.0
@export var drops: Array[DropRoll] = []
@export var gold_min := 0
@export var gold_max := 0


func _init() -> void:
	if base_stats == null:
		base_stats = StatBlock.new()


var experience: int:
	get:
		return 12 + level * level * 6
