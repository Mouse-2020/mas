class_name Palette
extends RefCounted

# 配色表是唯一来源：离线 PNG 和运行时画面都读这里，
# 这样"我看到的那张图"和"引擎里跑出来的画面"不会各画各的。


static func terrain_color(terrain: int) -> Color:
	match terrain:
		Enums.Terrain.FLOOR:
			return Color8(122, 104, 78)
		Enums.Terrain.GRASS:
			return Color8(74, 118, 62)
		Enums.Terrain.ROAD:
			return Color8(158, 150, 134)
		Enums.Terrain.SAND:
			return Color8(196, 176, 122)
		Enums.Terrain.WATER:
			return Color8(48, 96, 158)
		Enums.Terrain.WALL:
			return Color8(60, 56, 54)
		Enums.Terrain.ROCK:
			return Color8(92, 88, 86)
		Enums.Terrain.TREE:
			return Color8(38, 82, 48)
		_:
			return Color8(122, 104, 78)


static func monster_color(monster_id: String) -> Color:
	match monster_id:
		Naming.MONSTER_CHICKEN:
			return Color8(226, 202, 138)
		Naming.MONSTER_DEER:
			return Color8(186, 138, 88)
		Naming.MONSTER_DUMMY:
			return Color8(206, 176, 96)
		Naming.MONSTER_BANDIT:
			return Color8(150, 92, 74)
		Naming.MONSTER_BONE_SLAVE:
			return Color8(204, 204, 210)
		Naming.MONSTER_BONE_MASTER:
			return Color8(126, 74, 120)
		_:
			return Color8(180, 120, 120)


const PLAYER := Color8(238, 240, 244)
const LOOT := Color8(240, 208, 72)
const PATH := Color8(250, 250, 250)
const SPAWN := Color8(120, 200, 255)
const HEALTH := Color8(72, 210, 96)
const HEALTH_LOW := Color8(222, 74, 62)
const MONSTER_SPAWN_MARK := Color8(120, 90, 90)
const BACKDROP := Color8(16, 16, 20)
const HATCH := Color8(24, 22, 22)
const HEALTH_BAR_TRACK := Color8(30, 30, 30)
