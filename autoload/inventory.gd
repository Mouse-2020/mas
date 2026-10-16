extends Node

# 背包与装备管理。单例取名 Kit（行囊）而不是 Inventory，因为 Inventory 已经是
# item/inventory/inventory.gd 的类名，两者重名会让全局标识符打架。

func bag() -> Inventory:
	return Game.session.bag


func gear() -> Equipment:
	return Game.session.gear


func equip(uid: String) -> bool:
	return Game.session.equip_from_bag(uid)


func unequip(slot: int) -> bool:
	return Game.session.unequip(slot)


func consume(uid: String) -> bool:
	return Game.session.consume_item(uid)


func drop(uid: String) -> bool:
	return Game.session.drop_from_bag(uid)


func move(from: int, to: int) -> void:
	Game.session.move_bag_item(from, to)


func pick_up(pos: Vector2i) -> bool:
	return Game.session.pick_up_at(pos)


func count_of(def_id: String) -> int:
	return Game.session.bag.count_of(def_id)


## Q 键那口药：挑背包里回血最多的那瓶。
func best_health_potion() -> ItemInstance:
	var best: ItemInstance = null
	for entry in Game.session.bag.enumerate():
		var item := entry as ItemInstance
		if item.def.type == Enums.ItemType.CONSUMABLE and item.def.heal_hp > 0:
			if best == null or item.def.heal_hp > best.def.heal_hp:
				best = item
	return best


func drink_best_potion() -> bool:
	var potion := best_health_potion()
	if potion == null:
		return false
	return consume(potion.uid)


func buy(shop_id: String, item_id: String, count := 1) -> bool:
	return Game.session.buy_from_shop(shop_id, item_id, count)


func sell(uid: String, count := -1) -> bool:
	return Game.session.sell_from_bag(uid, count)


func repair() -> bool:
	return Game.session.repair_now()


func repair_quote() -> int:
	return Trade.repair_cost(Game.session.gear)
