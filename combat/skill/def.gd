class_name SkillDef
extends Resource

# 一招技能，来自 combat/skill/skills.csv。表现层只按 kind 决定"要不要选目标"。

@export var id := ""
## 留空表示与 id 同名。
@export var title := ""
@export_enum("近身强化", "横扫", "远程单体", "回血", "增益") var kind: int = Enums.SkillKind.STRIKE
@export var mp_cost := 5
@export var cooldown := 1.5
@export var required_level := 1

## 横扫的半径 / 远程的射程 / 近身的要求距离，单位是格。
@export var reach := 1

## 打在"物攻 + 魔攻 + 道术"这次掷骰上的倍率。
@export var factor := 1.5

@export var flat_damage := 0

## 回复技用：回复最大生命的百分之几。
@export var heal_percent := 30

@export var buff: StatBlock = null
@export var buff_seconds := 10.0

## true 表示升到 required_level 自动掌握；false 需要武谱。
@export var auto_learn := false

@export var description := ""
@export var sound := "cast"


func _init() -> void:
	if kind == Enums.SkillKind.BUFF and buff == null:
		buff = StatBlock.new()


var display_name: String:
	get:
		return title if title != "" else id
