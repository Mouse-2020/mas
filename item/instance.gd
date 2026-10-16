class_name ItemInstance
extends RefCounted

# 一件具体物品：模板 id + 运行时状态。

static var _uid_counter := 0

var uid := ""
var def_id := ""
var count := 1
var durability := 0


func _init(p_uid := "", p_def_id := "", p_count := 1, p_durability := 0) -> void:
	uid = p_uid
	def_id = p_def_id
	count = p_count
	durability = p_durability


var def: ItemDef:
	get:
		return ItemDatabase.get_def(def_id)


static func from_def(item_def: ItemDef, p_count := 1, p_uid := "") -> ItemInstance:
	if p_uid == "":
		p_uid = next_uid()
	return ItemInstance.new(p_uid, item_def.id, p_count, item_def.max_durability)


## 自增号而不是 Guid：可读、可复现，也不会跟旧档里已有的 uid 撞。
static func next_uid() -> String:
	_uid_counter += 1
	return "item-%d" % _uid_counter


## 读档后把计数器抬过存档里已有的最大编号，避免新物品复用旧 uid。
static func note_uid(loaded_uid: String) -> void:
	if not loaded_uid.begins_with("item-"):
		return
	_uid_counter = maxi(_uid_counter, loaded_uid.substr(5).to_int())


static func reset_uid_counter() -> void:
	_uid_counter = 0
