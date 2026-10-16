class_name ItemDef
extends Resource

# 物品模板：item/items.csv 里的一行，读进来就是这个 Resource。

@export var id := ""
## 留空表示与 id 同名。
@export var title := ""
@export_enum("金币", "消耗品", "武器", "护甲", "头盔", "项链", "戒指", "鞋", "腰带", "材料", "武谱") var type: int = Enums.ItemType.GOLD
@export_enum("武器", "护甲", "头盔", "项链", "左戒指", "右戒指", "鞋", "腰带") var slot: int = Enums.EquipSlot.ARMOR
@export var weight := 1
@export var price := 10
@export var max_stack := 1
@export var max_durability := 0
@export var required_level := 1
@export var bonus: StatBlock = null
@export var heal_hp := 0
@export var heal_mp := 0
@export var description := ""
## 武谱指向的那招；非武谱留空。
@export var learns_skill := ""

const _EQUIPMENT_TYPES := [
	Enums.ItemType.WEAPON,
	Enums.ItemType.ARMOR,
	Enums.ItemType.HELMET,
	Enums.ItemType.NECKLACE,
	Enums.ItemType.RING,
	Enums.ItemType.BOOTS,
	Enums.ItemType.BELT,
]


func _init() -> void:
	if bonus == null:
		bonus = StatBlock.new()


## 不单独写名字时直接用 id，省掉成倍的配表重复。
var display_name: String:
	get:
		return title if title != "" else id


var is_equipment: bool:
	get:
		return type in _EQUIPMENT_TYPES


static func create(item_id: String, item_type: int, props: Dictionary = {}) -> ItemDef:
	var def := ItemDef.new()
	def.id = item_id
	def.type = item_type
	for key in props:
		if key == "bonus":
			def.bonus = props[key] as StatBlock
		elif key in def:
			def[key] = props[key]
		else:
			push_error("物品 %s 写了不认识的配表项：%s" % [item_id, key])
			assert(false)
	return def
