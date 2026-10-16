class_name NpcDatabase
extends RefCounted

# NPC 表：读 npc/npcs.csv，一行一位。

const CSV_PATH := "res://npc/npcs.csv"

static var _defs := {}
static var _list: Array = []


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(npc_id: String) -> NpcDef:
	_ensure()
	if not _defs.has(npc_id):
		push_error("未知 NPC：" + npc_id)
		assert(false)
		return null
	return _defs[npc_id]


static func try_get(npc_id: String) -> NpcDef:
	_ensure()
	return _defs.get(npc_id)


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for entry in CsvTable.read(CSV_PATH):
		var row := entry as Dictionary
		var def := _make(row)
		# 重复 id 会让地图定义里的站位指向错的那位。
		if _defs.has(def.id):
			push_error("NPC id 重复：" + def.id)
			assert(false)
			continue
		if def.shop_id != "" and ShopDatabase.try_get(def.shop_id) == null:
			push_error("NPC %s 指的是不存在的商店：%s" % [def.id, def.shop_id])
			assert(false)
		_defs[def.id] = def
		_list.append(def)


static func _make(row: Dictionary) -> NpcDef:
	var def := NpcDef.new()
	def.id = CsvTable.text(row, "id")
	def.title = CsvTable.text(row, "title")
	def.greeting = CsvTable.text(row, "greeting", "……")
	def.shop_id = CsvTable.text(row, "shop_id")
	def.can_repair = CsvTable.boolean(row, "can_repair")
	def.can_teleport = CsvTable.boolean(row, "can_teleport")
	def.palette = CsvTable.text(row, "palette", "guide")
	return def
