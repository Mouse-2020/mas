class_name StatBlock
extends Resource

# 一组属性加成。装备、怪物模板、玩家基础属性共用同一口径。
# CSV 里写成 k=v;k=v（bonus/base/buff 三列）；改数值直接在表格里改。

@export var dc_min := 0
@export var dc_max := 0
@export var mc_min := 0
@export var mc_max := 0
@export var sc_min := 0
@export var sc_max := 0
@export var ac_min := 0
@export var ac_max := 0
@export var mac_min := 0
@export var mac_max := 0
@export var max_hp := 0
@export var max_mp := 0
@export var hit := 0
@export var dodge := 0
@export var attack_speed := 0
@export var move_speed := 0


func clone() -> StatBlock:
	var copy := StatBlock.new()
	copy.dc_min = dc_min
	copy.dc_max = dc_max
	copy.mc_min = mc_min
	copy.mc_max = mc_max
	copy.sc_min = sc_min
	copy.sc_max = sc_max
	copy.ac_min = ac_min
	copy.ac_max = ac_max
	copy.mac_min = mac_min
	copy.mac_max = mac_max
	copy.max_hp = max_hp
	copy.max_mp = max_mp
	copy.hit = hit
	copy.dodge = dodge
	copy.attack_speed = attack_speed
	copy.move_speed = move_speed
	return copy


func add(other: StatBlock) -> void:
	dc_min += other.dc_min
	dc_max += other.dc_max
	mc_min += other.mc_min
	mc_max += other.mc_max
	sc_min += other.sc_min
	sc_max += other.sc_max
	ac_min += other.ac_min
	ac_max += other.ac_max
	mac_min += other.mac_min
	mac_max += other.mac_max
	max_hp += other.max_hp
	max_mp += other.max_mp
	hit += other.hit
	dodge += other.dodge
	attack_speed += other.attack_speed
	move_speed += other.move_speed


## 配表自检：只写了一边的区间通常都是漏配。
var is_empty: bool:
	get:
		return dc_min == 0 and dc_max == 0 and mc_min == 0 and mc_max == 0 \
			and sc_min == 0 and sc_max == 0 and ac_min == 0 and ac_max == 0 \
			and mac_min == 0 and mac_max == 0 and max_hp == 0 and max_mp == 0 \
			and hit == 0 and dodge == 0 and attack_speed == 0 and move_speed == 0


## 用 { 属性名: 增量 } 造块，键名与上面的字段一致（导出工具与代码内构造用）。
static func make(values: Dictionary = {}) -> StatBlock:
	var block := StatBlock.new()
	for key in values:
		block[key] = values[key]
	return block
