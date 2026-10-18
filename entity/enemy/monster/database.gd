class_name MonsterDatabase
extends RefCounted

# 怪物表：读 entity/enemy/monster/monsters.csv，一行一只。

const CSV_PATH := "res://entity/enemy/monster/monsters.csv"

static var _defs := {}
static var _list: Array = []


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(monster_id: String) -> MonsterDef:
	var def := try_get(monster_id)
	if def == null:
		push_error("未知怪物：" + monster_id)
		assert(false)
	return def


static func try_get(monster_id: String) -> MonsterDef:
	_ensure()
	return _defs.get(monster_id)


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for entry in CsvTable.read(CSV_PATH):
		var row := entry as Dictionary
		var def := _make(row)
		if _defs.has(def.id):
			push_error("怪物 id 重复：" + def.id)
			assert(false)
			continue
		if def.base_stats == null or def.base_stats.max_hp <= 0:
			push_error("怪物 %s 没有配血量" % def.id)
			assert(false)
		for roll in def.drops:
			if ItemDatabase.try_get(roll.item_id) == null:
				push_error("怪物 %s 掉的是不存在的物品：%s" % [def.id, roll.item_id])
				assert(false)
		_defs[def.id] = def
		_list.append(def)


static func _make(row: Dictionary) -> MonsterDef:
	var def := MonsterDef.new()
	def.id = CsvTable.text(row, "id")
	def.level = CsvTable.integer(row, "level", 1)
	def.base_stats = CsvTable.stats(row, "base")
	def.aggro_radius = CsvTable.integer(row, "aggro_radius", 6)
	def.attack_range = CsvTable.integer(row, "attack_range", 1)
	def.chase_range = CsvTable.real(row, "chase_range", 14.0)
	def.gold_min = CsvTable.integer(row, "gold_min", 0)
	def.gold_max = CsvTable.integer(row, "gold_max", 0)
	def.drops = CsvTable.drops(row, "drops")
	return def
