class_name ItemDatabase
extends RefCounted

# 物品表：读 item/items.csv，一行一件。想调价格或加新装备，用表格软件改那一行即可。

const CSV_PATH := "res://item/items.csv"

static var _defs := {}
static var _list: Array = []


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(item_id: String) -> ItemDef:
	_ensure()
	if not _defs.has(item_id):
		push_error("未知物品模板：" + item_id)
		assert(false)
		return null
	return _defs[item_id]


## 找不到返回 null，调用方自行判空。
static func try_get(item_id: String) -> ItemDef:
	_ensure()
	return _defs.get(item_id)


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for entry in CsvTable.read(CSV_PATH):
		var row := entry as Dictionary
		var def := _make(row)
		# 重复 id 会让查表悄悄返回错的那一件，比报错更难查。
		if _defs.has(def.id):
			push_error("物品模板 id 重复：" + def.id)
			assert(false)
			continue
		# 武谱指向不存在的技能，点一下就是"书没了、招没学"，加载期直接拦掉。
		if def.learns_skill != "" and SkillDatabase.try_get(def.learns_skill) == null:
			push_error("物品 %s 指向不存在的技能：%s" % [def.id, def.learns_skill])
			assert(false)
		_defs[def.id] = def
		_list.append(def)


static func _make(row: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = CsvTable.text(row, "id")
	def.title = CsvTable.text(row, "title")
	def.type = CsvTable.choice(row, "type", Enums.ItemType, Enums.ItemType.CONSUMABLE)
	def.slot = CsvTable.choice(row, "slot", Enums.EquipSlot, Enums.EquipSlot.ARMOR)
	def.weight = CsvTable.integer(row, "weight", 1)
	def.price = CsvTable.integer(row, "price", 10)
	def.max_stack = CsvTable.integer(row, "max_stack", 1)
	def.max_durability = CsvTable.integer(row, "max_durability", 0)
	def.required_level = CsvTable.integer(row, "required_level", 1)
	def.heal_hp = CsvTable.integer(row, "heal_hp", 0)
	def.heal_mp = CsvTable.integer(row, "heal_mp", 0)
	def.description = CsvTable.text(row, "description")
	def.learns_skill = CsvTable.text(row, "learns_skill")
	def.shape = CsvTable.integer(row, "shape", 0)
	def.bonus = CsvTable.stats(row, "bonus")
	return def
