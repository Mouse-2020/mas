class_name Enums
extends RefCounted

# 全部共享枚举集中在这里，跨文件写法是 Enums.ItemType.WEAPON。
# 枚举顺序值会落进存档与统计，改顺序会读坏旧档。

enum Direction {
	UP = 0,
	UP_RIGHT = 1,
	RIGHT = 2,
	DOWN_RIGHT = 3,
	DOWN = 4,
	DOWN_LEFT = 5,
	LEFT = 6,
	UP_LEFT = 7,
}

enum CellState { WALKABLE, BLOCKED, OCCUPIED }

enum Terrain { FLOOR, GRASS, ROAD, SAND, WATER, WALL, ROCK, TREE }

enum MapTheme { TOWN, OUTDOOR, FOREST, CAVE }

enum MapSide { NORTH, EAST, SOUTH, WEST }

enum ItemType {
	GOLD,
	CONSUMABLE,
	WEAPON,
	ARMOR,
	HELMET,
	NECKLACE,
	RING,
	BOOTS,
	BELT,
	MATERIAL,
	BOOK,
}

enum EquipSlot { WEAPON, ARMOR, HELMET, NECKLACE, RING_LEFT, RING_RIGHT, BOOTS, BELT }

enum SkillKind { STRIKE, SWEEP, BOLT, HEAL, BUFF }

enum QuestStatus { NONE, ACTIVE, DONE }

enum QuestKind { KILL, COLLECT }

enum DialogueKind { TALK, ACCEPT_QUEST, TURN_IN_QUEST, OPEN_SHOP, REPAIR, TRAVEL, CLOSE }

enum Wave { SINE, SQUARE, SAW, NOISE }

enum GameEventType {
	MOVE,
	BLOCKED,
	ATTACK,
	MISS,
	KILL,
	LEVEL_UP,
	LOOT,
	EQUIP,
	UNEQUIP,
	CONSUME,
	DROP,
	DEATH,
	RESPAWN,
	INFO,
	SKILL,
	LEARN,
	BUFF,
	QUEST_ACCEPT,
	QUEST_PROGRESS,
	QUEST_READY,
	QUEST_COMPLETE,
	TRAVEL,
	BUY,
	SELL,
	REPAIR,
	TALK,
}


## 阻挡提示要用到地形名。
static func terrain_name(terrain: int) -> String:
	match terrain:
		Terrain.FLOOR:
			return "地面"
		Terrain.GRASS:
			return "草地"
		Terrain.ROAD:
			return "道路"
		Terrain.SAND:
			return "沙地"
		Terrain.WATER:
			return "水"
		Terrain.WALL:
			return "墙"
		Terrain.ROCK:
			return "岩石"
		Terrain.TREE:
			return "树"
		_:
			return "地面"
