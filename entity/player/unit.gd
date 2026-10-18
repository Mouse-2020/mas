class_name PlayerUnit
extends Unit

# 玩家：背包、装备、金币、经验都挂在这。

var bag := Inventory.new()
var gear := Equipment.new()
var gold := 0
var mp := 0
var experience := 0
var job := "战士"

## 死亡后到复活之间的计时，由 GameSession.tick 推进。
var death_timer := 0.0

## 整局阵亡次数，用来判断难度是否合理。
var death_count := 0

var base_stats := StatBlock.new()

## 身上挂着的临时增益，按剩余秒数递减。
var effects: Array = []


func _init(start: Vector2i) -> void:
	position = start
	name = Naming.PLAYER_NAME
	level = 1
	recompute_base()
	hp = max_hp
	mp = max_mp


## 装备与增益属性直接叠在基础属性上，UI 和战斗都用这一个口径。
func get_stats() -> StatBlock:
	var total := base_stats.clone()
	total.add(gear.aggregate())
	for effect in effects:
		total.add((effect as SkillEffect).bonus)
	return total


var experience_to_next: int:
	get:
		return 60 + level * level * 45


func recompute_base() -> void:
	base_stats = StatBlock.make({
		"dc_min": 2 + level,
		"dc_max": 5 + level * 2,
		"mc_min": 2 + level if job == "法师" else 0,
		"mc_max": 4 + level * 2 if job == "法师" else 0,
		"ac_min": 1 + level / 2,
		"ac_max": 3 + level,
		"mac_min": 1 + level / 3,
		"mac_max": 2 + level / 2,
		"max_hp": 60 + level * 14,
		"max_mp": 30 + level * 8,
		"hit": 6 + level,
		"dodge": 2 + level / 2,
		"attack_speed": level / 4,
	})


## 返回升了几级；升级回满状态，单机节奏优先。
func gain_experience(amount: int) -> int:
	if amount <= 0:
		return 0
	experience += amount
	var levels := 0
	while experience >= experience_to_next and level < 50:
		experience -= experience_to_next
		level += 1
		levels += 1
		var previous_hp := base_stats.max_hp
		recompute_base()
		hp += maxi(0, max_hp - previous_hp)
		mp = max_mp
	hp = mini(hp, max_hp)
	return levels
