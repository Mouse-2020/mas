class_name Trade
extends RefCounted

# 买卖价差就是游戏里的"来回武馆一趟"成本：买价照表，卖价对折，
# 装备再按剩余耐久折算，所以砍到快碎的刀不值钱。


static func buy_price(def: ItemDef) -> int:
	return maxi(1, def.price)


static func sell_price(item: ItemInstance) -> int:
	var def: ItemDef = item.def
	if def.type == Enums.ItemType.GOLD:
		return 0
	var half := maxi(1, buy_price(def) / 2)
	if not def.is_equipment or def.max_durability <= 0:
		return half
	var ratio := clampf(float(item.durability) / float(def.max_durability), 0.0, 1.0)
	return maxi(1, int(float(half) * ratio))


## 修好全身装备的报价，按缺的耐久条数算，空手来不收费。
static func repair_cost(gear: Equipment, gold_per_point := 4) -> int:
	var missing := 0
	for item in gear.all():
		var instance := item as ItemInstance
		if instance.def.max_durability <= 0:
			continue
		missing += maxi(0, instance.def.max_durability - instance.durability)
	return missing * gold_per_point
