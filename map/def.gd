class_name MapDef
extends Resource

# 一张地图的静态定义，来自 map/maps.csv。想加新图就在表里加一行，不用碰生成逻辑。

@export var id := ""
@export var display_name := ""
@export_enum("城镇", "野外", "树林", "洞窟") var theme: int = Enums.MapTheme.OUTDOOR
@export var width := 96
@export var height := 72

## 安全区：不刷怪、不会被攻击、站着回血回蓝。
@export var safe := false

## 按由弱到强排列，越远离出生点越往后取。
@export var monster_ids: PackedStringArray = PackedStringArray()

@export var monster_count := 16
@export var links: Array[MapLink] = []

## NPC 相对广场中心的偏移，城外的图一般不放 NPC。
@export var npc_spots: Array[NpcSpot] = []
