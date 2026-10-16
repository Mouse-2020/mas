class_name MapRuntime
extends RefCounted

# 一张图的全部动态状态。切图就是换一个运行时，静态地形不重来。

var def: MapDef
var map: GameMap

## 本图专用的随机源：进场顺序不该影响 wandering 与刷新计时。
var rng: Rng

var monsters: Array = []
var loot: Array = []
var npcs: Array = []

## { Vector2i: Unit }
var occupancy := {}
