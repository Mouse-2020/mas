class_name ShopDatabase
extends RefCounted

# 商店表：读 system/economy/shops.csv，一行一间。

const CSV_PATH := "res://system/economy/shops.csv"

static var _defs := {}
static var _list: Array = []


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(shop_id: String) -> ShopDef:
	_ensure()
	if not _defs.has(shop_id):
		push_error("未知商店：" + shop_id)
		assert(false)
		return null
	return _defs[shop_id]


static func try_get(shop_id: String) -> ShopDef:
	_ensure()
	return _defs.get(shop_id)


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for entry in CsvTable.read(CSV_PATH):
		var row := entry as Dictionary
		var def := _make(row)
		if _defs.has(def.id):
			push_error("商店 id 重复：" + def.id)
			assert(false)
			continue
		for item_id in def.stock:
			if ItemDatabase.try_get(item_id) == null:
				push_error("商店 %s 卖了不存在的东西：%s" % [def.id, item_id])
				assert(false)
		_defs[def.id] = def
		_list.append(def)


static func _make(row: Dictionary) -> ShopDef:
	var def := ShopDef.new()
	def.id = CsvTable.text(row, "id")
	def.title = CsvTable.text(row, "title")
	def.greeting = CsvTable.text(row, "greeting", "看看要什么。")
	def.stock = CsvTable.words(row, "stock")
	def.buys_back = CsvTable.boolean(row, "buys_back", true)
	return def
