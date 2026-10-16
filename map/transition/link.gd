class_name MapLink
extends Resource

# 两个地图之间的连线，写在 map/maps.csv 的 links 列里。只记"哪一侧的门 + 去哪张图"，绝对坐标交给生成器。

@export var to_map := ""
@export_enum("北", "东", "南", "西") var side: int = Enums.MapSide.NORTH
@export var label := ""
