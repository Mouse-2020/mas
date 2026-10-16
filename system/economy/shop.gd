class_name ShopDef
extends Resource

# 一张货架，来自 system/economy/shops.csv。库存只写物品 id，价格沿用物品表，不再配一遍。

@export var id := ""
## 留空表示与 id 同名。
@export var title := ""
@export_multiline var greeting := "看看要什么。"
@export var stock: PackedStringArray = PackedStringArray()

## true 表示收材料与装备（药庐收货，铁匠也收货，按各自报价表）。
@export var buys_back := true


var display_name: String:
	get:
		return title if title != "" else id
