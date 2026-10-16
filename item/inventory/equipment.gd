class_name Equipment
extends RefCounted

# 装备栏：8 个槽位，戒指左右各一。

const ALL_SLOTS := [
	Enums.EquipSlot.WEAPON,
	Enums.EquipSlot.ARMOR,
	Enums.EquipSlot.HELMET,
	Enums.EquipSlot.NECKLACE,
	Enums.EquipSlot.RING_LEFT,
	Enums.EquipSlot.RING_RIGHT,
	Enums.EquipSlot.BOOTS,
	Enums.EquipSlot.BELT,
]

var worn := {}


func at(slot: int) -> ItemInstance:
	return worn.get(slot)


func all() -> Array:
	return worn.values()


## 返回空串表示可以穿，否则是给人看的原因。
func can_wear(def: ItemDef, level: int) -> String:
	if not def.is_equipment:
		return "%s 不是装备" % def.display_name
	if level < def.required_level:
		return "%s 需要等级 %d" % [def.display_name, def.required_level]
	return ""


## 穿上并返回被换下来的那件。换装前先确认背包装得下旧装备，否则整笔操作不做。
## 返回 { "ok": bool, "replaced": ItemInstance 或 null, "reason": String }
func try_equip(instance: ItemInstance, bag: Inventory, level: int) -> Dictionary:
	var def: ItemDef = instance.def
	var reason := can_wear(def, level)
	if reason != "":
		return { "ok": false, "replaced": null, "reason": reason }

	var slot: Variant = _resolve_slot(def)
	if slot == null:
		return { "ok": false, "replaced": null, "reason": "%s 没有可用槽位" % def.display_name }

	var current: ItemInstance = worn.get(slot)
	if current != null and not bag.can_accept(current.def, current.count):
		return { "ok": false, "replaced": null, "reason": "背包已满，无法换下装备" }

	worn[slot] = instance
	if current != null:
		if not bag.try_place(current):
			# 预检和落位之间只可能因为重量上限失配，此时整笔操作作废。
			worn[slot] = current
			return { "ok": false, "replaced": null, "reason": "背包放不下旧装备" }
		return { "ok": true, "replaced": current, "reason": "" }

	return { "ok": true, "replaced": null, "reason": "" }


## 返回槽位整数，或 null 表示无位可放。
func _resolve_slot(def: ItemDef) -> Variant:
	if def.type != Enums.ItemType.RING:
		return def.slot
	if not worn.has(Enums.EquipSlot.RING_LEFT):
		return Enums.EquipSlot.RING_LEFT
	if not worn.has(Enums.EquipSlot.RING_RIGHT):
		return Enums.EquipSlot.RING_RIGHT
	return Enums.EquipSlot.RING_LEFT


## 返回 { "ok": bool, "removed": ItemInstance 或 null, "reason": String }
func try_unequip(slot: int, bag: Inventory) -> Dictionary:
	if not worn.has(slot):
		return { "ok": false, "removed": null, "reason": "该槽位没有装备" }
	var instance: ItemInstance = worn[slot]
	if not bag.try_place(instance):
		return { "ok": false, "removed": null, "reason": "背包已满" }
	worn.erase(slot)
	return { "ok": true, "removed": instance, "reason": "" }


## 耐久只掉装备本身这一件，读档时才用 force_wear 直接落位。
func force_wear(slot: int, instance: ItemInstance) -> void:
	worn[slot] = instance


func clear() -> void:
	worn.clear()


## 耐久归零的装备不再给属性，和"装备坏了要修"一致。
func aggregate() -> StatBlock:
	var total := StatBlock.new()
	for item in worn.values():
		var instance := item as ItemInstance
		if instance.def.max_durability > 0 and instance.durability <= 0:
			continue
		total.add(instance.def.bonus)
	return total


func wear_down(amount := 1) -> void:
	for item in worn.values():
		var instance := item as ItemInstance
		if instance.def.max_durability <= 0:
			continue
		instance.durability = maxi(0, instance.durability - amount)


func repair_all() -> void:
	for item in worn.values():
		var instance := item as ItemInstance
		instance.durability = instance.def.max_durability
