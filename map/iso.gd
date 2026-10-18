class_name Iso
extends RefCounted

# 等距投影的唯一算法，画面层（WorldView）与自检都从这里取，免得两处各算各的、然后悄悄歪掉半格。
# tool/render.gd 那张无头核对图仍是俯视图：它只用来肉眼核对"怪刷在哪儿、路通不通"，
# 要的是"一眼看全图"，等距反而挡住视线，所以没跟着走。
#
# 2:1 菱形：一格铺成 64x32，格 (x,y) 的中心落在 ((x-y)*32, (x+y)*16)。
# 线性变换所以逆投影、深度序、可见范围都能闭式算出来，不用试。

const HALF_W := ArtGen.TILE_W / 2.0
const HALF_H := ArtGen.TILE_H / 2.0


## 一格中心，也是站立物脚底该踩到的那个点。
static func center(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * HALF_W, (cell.x + cell.y) * HALF_H)


## 菱形四角：顶、右、底、左。顺时针，正好对上 ground_uv 给的四个 UV 角。
static func corners(cell: Vector2) -> PackedVector2Array:
	var at := center(cell)
	return PackedVector2Array([at + Vector2(0.0, -HALF_H), at + Vector2(HALF_W, 0.0),
		at + Vector2(0.0, HALF_H), at + Vector2(-HALF_W, 0.0)])


## 世界坐标 → 浮点格坐标。菱形在格空间里就是整数点周围那个 1x1 方框，所以取整用 round。
static func to_cell(world: Vector2) -> Vector2:
	return Vector2((world.x / HALF_W + world.y / HALF_H) * 0.5,
		(world.y / HALF_H - world.x / HALF_W) * 0.5)


static func to_grid(world: Vector2) -> Vector2i:
	var cell := to_cell(world)
	return Vector2i(roundi(cell.x), roundi(cell.y))


## 深度：值越大越靠近镜头，画得越晚。等于脚底的世界 y，所以不用另算一套。
static func depth(cell: Vector2) -> float:
	return (cell.x + cell.y) * HALF_H


## 整张地图在世界坐标里占的矩形（含最外圈菱形伸出去的四个尖）。
static func map_bounds(width: int, height: int) -> Rect2:
	if width <= 0 or height <= 0:
		return Rect2()
	var west := center(Vector2(0.0, float(height - 1))).x - HALF_W
	var east := center(Vector2(float(width - 1), 0.0)).x + HALF_W
	var north := center(Vector2.ZERO).y - HALF_H
	var south := center(Vector2(float(width - 1), float(height - 1))).y + HALF_H
	return Rect2(west, north, east - west, south - north)


## 视野覆盖到的格子范围。线性变换把屏幕矩形映成格空间的一个平行四边形，
## 极值一定落在四个角上，所以只需逆变换四个角取外接矩形。pad 是给立绘留的边。
static func visible_box(camera: Vector2, view: Vector2, pad := 1) -> Rect2i:
	var left := 1.0e18
	var top := 1.0e18
	var right := -1.0e18
	var bottom := -1.0e18
	for corner in [Vector2.ZERO, Vector2(view.x, 0.0), view, Vector2(0.0, view.y)]:
		var cell := to_cell(camera + corner)
		left = minf(left, cell.x)
		top = minf(top, cell.y)
		right = maxf(right, cell.x)
		bottom = maxf(bottom, cell.y)
	var x0 := int(floorf(left)) - pad
	var y0 := int(floorf(top)) - pad
	return Rect2i(x0, y0, int(ceili(right)) - x0 + 1 + pad, int(ceili(bottom)) - y0 + 1 + pad)
