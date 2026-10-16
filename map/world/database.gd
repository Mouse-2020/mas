class_name WorldDatabase
extends RefCounted

# 世界地图表：读 map/maps.csv，一行一张图。
# 双向对称是硬约定：A 链到 B，B 必须有链回 A 的门，
# 否则玩家进去就出不来（自检会逐条查）。

const CSV_PATH := "res://map/maps.csv"

static var _list: Array = []


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(map_id: String) -> MapDef:
	var def := try_get(map_id)
	if def == null:
		push_error("未知地图：" + map_id)
		assert(false)
	return def


static func try_get(map_id: String) -> MapDef:
	_ensure()
	for def in _list:
		if def.id == map_id:
			return def
	return null


## 每条链接都必须有回程，否则玩家会被困在图里。
static func links_are_symmetric() -> bool:
	for map_def in all_defs():
		for link in map_def.links:
			var target := try_get(link.to_map)
			if target == null:
				return false
			var has_back := false
			for back in target.links:
				if back.to_map == map_def.id:
					has_back = true
					break
			if not has_back:
				return false
	return true


## 掉落表与怪物表引用的 id 是否都存在（配表自检用）。
static func monster_ids_are_valid() -> bool:
	for def in all_defs():
		for id in def.monster_ids:
			if MonsterDatabase.try_get(id) == null:
				return false
		for spot in def.npc_spots:
			if NpcDatabase.try_get(spot.npc_id) == null:
				return false
	return true


static func _ensure() -> void:
	if not _list.is_empty():
		return
	var seen := {}
	for entry in CsvTable.read(CSV_PATH):
		var row := entry as Dictionary
		var def := _make(row)
		if seen.has(def.id):
			push_error("地图 id 重复：" + def.id)
			assert(false)
			continue
		if def.width <= 0 or def.height <= 0:
			push_error("地图尺寸必须为正数：" + def.id)
			assert(false)
			continue
		seen[def.id] = true
		_list.append(def)


static func _make(row: Dictionary) -> MapDef:
	var def := MapDef.new()
	def.id = CsvTable.text(row, "id")
	def.display_name = CsvTable.text(row, "title")
	def.theme = CsvTable.choice(row, "theme", Enums.MapTheme, Enums.MapTheme.OUTDOOR)
	def.width = CsvTable.integer(row, "width", 96)
	def.height = CsvTable.integer(row, "height", 72)
	def.safe = CsvTable.boolean(row, "safe")
	def.monster_ids = CsvTable.words(row, "monsters")
	def.monster_count = CsvTable.integer(row, "monster_count", 16)
	def.links = CsvTable.links(row, "links")
	def.npc_spots = CsvTable.npc_spots(row, "npc_spots")
	return def
