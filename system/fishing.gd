class_name Fishing
extends RefCounted

# 钓鱼的规则表：哪儿能下竿、等多久咬钩、咬钩窗口多长、上的是什么鱼。
# 状态机本身挂在 GameSession 上（要跟着 tick 走），这里只放不碰状态的算法。
# 随机一律由调用方把 rng 递进来，同一粒种子因此永远钓到同一串鱼。

## 抛竿后等 0.9~2.6 秒浮漂下沉；沉下去以后只有 0.55 秒可收。
## 窗口再长就成了站着等，再短就变成反应测试而不是钓鱼。
const WAIT_MIN := 9
const WAIT_MAX := 26
const BITE_WINDOW := 6

## 城里的塘养不出山货：按图的 theme 换一签，水越深越阴，出的鱼越值钱。
const CATCH := {
	Enums.MapTheme.TOWN: [
		Naming.ITEM_FISH_CRUCIAN, Naming.ITEM_FISH_CRUCIAN, Naming.ITEM_FISH_CRUCIAN,
		Naming.ITEM_FISH_CARP, Naming.ITEM_FISH_CARP, Naming.ITEM_FISH_GRASS],
	Enums.MapTheme.OUTDOOR: [
		Naming.ITEM_FISH_CARP, Naming.ITEM_FISH_CARP, Naming.ITEM_FISH_CARP,
		Naming.ITEM_FISH_GRASS, Naming.ITEM_FISH_GRASS, Naming.ITEM_FISH_CRUCIAN,
		Naming.ITEM_FISH_BLACK],
	Enums.MapTheme.FOREST: [
		Naming.ITEM_FISH_GRASS, Naming.ITEM_FISH_GRASS, Naming.ITEM_FISH_GRASS,
		Naming.ITEM_FISH_CARP, Naming.ITEM_FISH_BLACK, Naming.ITEM_FISH_CRUCIAN],
	Enums.MapTheme.CAVE: [
		Naming.ITEM_FISH_BLACK, Naming.ITEM_FISH_BLACK, Naming.ITEM_FISH_BLACK,
		Naming.ITEM_FISH_GRASS, Naming.ITEM_FISH_CARP],
}


## 脚下这一格能不能下竿：自己站得住，且紧邻八格里有水。站在塘沿上就算。
static func spot(map: GameMap, at: Vector2i) -> bool:
	if not map.is_walkable(at):
		return false
	for d in 8:
		if map.terrain_at(Grid.offset(at, d)) == Enums.Terrain.WATER:
			return true
	return false


static func wait_seconds(rng: Rng) -> float:
	return float(rng.next_range(WAIT_MIN, WAIT_MAX + 1)) / 10.0


static func catch_of(theme: int, rng: Rng) -> String:
	var table: Array = CATCH[theme] if CATCH.has(theme) else CATCH[Enums.MapTheme.TOWN]
	return rng.pick(table) as String
