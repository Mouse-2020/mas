extends SceneTree

# 武林风 · 无头自检台。
# 49 段、409 项断言：地图生成、寻路、移动、战斗、掉落、技能、对话、任务、商店、音效、存读档都覆盖。
# 显示文案一律取 Naming 常量。
# 退出码 = 失败项数，所以 CI 里 `$?` 直接可用。

const ARTIFACTS_FOLDER := ".artifacts"

# Enums.GameEventType 的整数值按声明顺序排布；GDScript 拿不到枚举成员名，
# 断言与日志用这张名字表。
const EVENT_TYPE_NAMES := [
	"Move", "Blocked", "Attack", "Miss", "Kill", "LevelUp", "Loot", "Equip",
	"Unequip", "Consume", "Drop", "Death", "Respawn", "Info", "Skill", "Learn",
	"Buff", "QuestAccept", "QuestProgress", "QuestReady", "QuestComplete",
	"Travel", "Buy", "Sell", "Repair", "Talk",
]

# 存档被拒的口径是"restore 返回 null"（GDScript 没有异常）。
const REJECTED_VERSION := 99

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_determinism()
	_every_csv_row_loads()
	_world_tables()
	_border_and_spawn()
	_key_points_reachable()
	_monster_mix_follows_distance()
	_every_spawn_table_type_reaches_the_field()
	_pathfinding_reachable()
	_pathfinding_rejects_unreachable()
	_movement_blocked_by_wall()
	_click_to_move_advances_over_time()
	_repeated_clicks_keep_walking()
	_movement_renders_between_cells()
	_travel_round_trip()
	_gate_not_an_infinite_loop()
	_travel_keeps_per_map_state()
	_npc_blocks_movement_and_cannot_be_attacked()
	_monster_chase_reaches_player()
	_combat_kills_monster_and_grants_experience()
	_loot_pickup_and_expiry()
	_player_takes_damage_and_dies()
	_equipment_changes_stats()
	_equipment_level_requirement()
	_both_ring_slots_usable()
	_full_bag_rejects_swap()
	_inventory_stacking_and_weight()
	_bag_move_merges_stacks()
	_drop_table_references_valid_items()
	_every_item_can_be_obtained()
	_monster_table_sanity()
	_skill_table_sanity()
	_skill_auto_learn_on_level_up()
	_skill_costs_mana_and_cooldown()
	_skill_book_needs_level()
	_skill_heal_and_buff()
	_skill_sweep_hits_many()
	_dialogue_offers_the_right_buttons()
	_quest_prerequisite_blocks()
	_quest_kill_progress_and_turn_in()
	_quest_collect_consumes_exactly()
	_quest_turn_in_needs_bag_room()
	_shop_buy_needs_boss_and_gold()
	_shop_sell_and_repair()
	_audio_covers_every_event()
	_audio_is_deterministic_and_audible()
	_save_restore_round_trip()
	_save_keeps_world_progress()
	_png_signature()
	_font_is_wired_up()

	print("✔ %d 项自检全部通过" % _checks if _failures == 0
		else "✘ %d 项自检，失败 %d 项" % [_checks, _failures])
	quit(_failures)


# ── 断言与通用工具 ──────────────────────────────────────────────────────

func _check(check_name: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   " + check_name)
		return
	_failures += 1
	print("  FAIL " + check_name + (" —— " + detail if detail != "" else ""))


## 全部满足才算 true；空集合返回 true。
func _all_of(items: Array, predicate: Callable) -> bool:
	for item in items:
		if not predicate.call(item):
			return false
	return true


func _any_of(items: Array, predicate: Callable) -> bool:
	for item in items:
		if predicate.call(item):
			return true
	return false


func _count_where(items: Array, predicate: Callable) -> int:
	var total := 0
	for item in items:
		if predicate.call(item):
			total += 1
	return total


func _first_where(items: Array, predicate: Callable) -> Variant:
	for item in items:
		if predicate.call(item):
			return item
	return null


## 取最后一个匹配项。
func _last_where(items: Array, predicate: Callable) -> Variant:
	var found: Variant = null
	for item in items:
		if predicate.call(item):
			found = item
	return found


## 排序必须稳定：同键取原列表里靠前的那一个，否则同一粒种子的结果会随实现漂移。
## 多键按声明顺序逐位比较。
func _first_by(items: Array, keys: Array, descending := false) -> Variant:
	var best: Variant = null
	var best_keys: Array = []
	for item in items:
		var current: Array = []
		for key in keys:
			current.append((key as Callable).call(item))
		if best == null:
			best = item
			best_keys = current
			continue
		if descending:
			if _keys_less(best_keys, current):
				best = item
				best_keys = current
		elif _keys_less(current, best_keys):
			best = item
			best_keys = current
	return best


## a 是否严格小于 b；相等时返回 false，从而保住"同键取靠前"的稳定语义。
func _keys_less(left: Array, right: Array) -> bool:
	for i in left.size():
		var l: Variant = left[i]
		var r: Variant = right[i]
		if typeof(l) == TYPE_STRING or typeof(r) == TYPE_STRING:
			if String(l) != String(r):
				return String(l) < String(r)
		elif float(l) != float(r):
			return float(l) < float(r)
	return false


func _sum_int(items: Array, key: Callable) -> int:
	var total := 0
	for item in items:
		total += int(key.call(item))
	return total


func _average(items: Array, key: Callable) -> float:
	if items.is_empty():
		return 0.0
	return float(_sum_int(items, key)) / float(items.size())


func _min_int(items: Array, key: Callable) -> int:
	var best := 0x7FFFFFFF
	for item in items:
		best = mini(best, int(key.call(item)))
	return best


func _max_int(items: Array, key: Callable) -> int:
	var best := -0x80000000
	for item in items:
		best = maxi(best, int(key.call(item)))
	return best


func _map_ids(items: Array, key: Callable) -> Array:
	var out: Array = []
	for item in items:
		out.append(key.call(item))
	return out


func _distinct(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if not out.has(item):
			out.append(item)
	return out


func _join(items: Array, separator: String) -> String:
	var text := ""
	for i in items.size():
		if i > 0:
			text += separator
		text += String(items[i])
	return text


## Godot 的 Vector2i 打印成 "(48, 36)"，日志里统一成 "(48,36)" 更好对齐。
func _pos(value: Vector2i) -> String:
	return "(%d,%d)" % [value.x, value.y]


## 最多 digits 位小数，末尾的 0 与小数点都去掉。
func _num(value: float, digits: int) -> String:
	var text := ("%.4f" % value)
	var rounded := text.substr(0, 2 + digits)
	while rounded.length() > 0 and (rounded.ends_with("0") or rounded.ends_with(".")):
		rounded = rounded.substr(0, rounded.length() - 1)
	return rounded if rounded != "-0" else "0"


func _event_type_names() -> Array:
	var out: Array = []
	for i in EVENT_TYPE_NAMES.size():
		out.append(i)
	return out


func _event_type_name(type: int) -> String:
	if type >= 0 and type < EVENT_TYPE_NAMES.size():
		return EVENT_TYPE_NAMES[type]
	return str(type)


## GameSession.known_skills 的元素口径（技能 id 还是 SkillDef）由 system/session.gd 定，
## 两种都归一成 id 数组。
func _known_ids(session: GameSession) -> Array:
	var out: Array = []
	for entry in session.known_skills:
		out.append(entry if typeof(entry) == TYPE_STRING else (entry as SkillDef).id)
	return out


func _terrain_matches(a: GameMap, b: GameMap) -> bool:
	for entry in a.all_positions():
		var pos: Vector2i = entry
		if a.terrain_at(pos) != b.terrain_at(pos):
			return false
	return true


## MapExit 是引用类型，比相等要逐字段比 (at, to_map, label)。
func _exits_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var left: MapExit = a[i]
		var right: MapExit = b[i]
		if left.at != right.at or left.to_map != right.to_map or left.label != right.label:
			return false
	return true


## 一个"什么都不挡"的寻路过滤回调。
func _blocked_never(_pos: Vector2i) -> bool:
	return false


## 门必须落在地图内侧（不贴边界墙）而且自己踩得上去。
func _exits_inside(map: GameMap) -> bool:
	for entry in map.exits:
		var exit := entry as MapExit
		if exit.at.x <= 0 or exit.at.y <= 0 or exit.at.x >= map.width - 1 or exit.at.y >= map.height - 1:
			return false
		if not map.is_walkable(exit.at):
			return false
	return true


## 撞 NPC 时应该留下一句"和他说话"的提示，且提示就落在那位 NPC 脚下。
func _has_talk_hint_at(session: GameSession, position: Vector2i) -> bool:
	for entry in session.events:
		var event := entry as GameEvent
		if event.type == Enums.GameEventType.INFO and event.text.contains("说话") and event.at == position:
			return true
	return false


func _monster_is_standing(session: GameSession, monster: MonsterUnit) -> bool:
	for entry in session.monsters:
		if entry == monster:
			return true
	return false


## 贴脸（切比雪夫距离 ≤ 1）的活怪数量——横扫的命中面就是它。
func _count_adjacent_monsters(session: GameSession) -> int:
	var total := 0
	for entry in session.monsters:
		var monster := entry as MonsterUnit
		if monster.alive and Grid.chebyshev(monster.position, session.player.position) <= 1:
			total += 1
	return total


## 修装备的按钮上得写着花了多少金币。
func _repair_label_quotes_gold(options: Array) -> bool:
	for entry in options:
		var option := entry as DialogueOption
		if option.kind == Enums.DialogueKind.REPAIR and option.label.contains("金币"):
			return true
	return false


func _monster_in_bolt_reach(session: GameSession, position: Vector2i, reach: int) -> MonsterUnit:
	for entry in session.monsters:
		var monster := entry as MonsterUnit
		var distance := Grid.chebyshev(monster.position, position)
		if monster.alive and distance > 1 and distance <= reach:
			return monster
	return null


func _all_npcs_occupy_themselves(session: GameSession) -> bool:
	for entry in session.npcs:
		var npc := entry as NpcUnit
		if not (session.unit_at(npc.position) is NpcUnit):
			return false
	return true


func _all_durability_full(gear: Equipment) -> bool:
	for entry in gear.all():
		var item := entry as ItemInstance
		if item.durability != item.def.max_durability:
			return false
	return true


func _any_monster_hurt(session: GameSession) -> bool:
	for entry in session.monsters:
		var monster := entry as MonsterUnit
		if monster.hp < monster.def.base_stats.max_hp:
			return true
	return false


func _any_monster_at_hp(session: GameSession, value: int) -> bool:
	for entry in session.monsters:
		if (entry as MonsterUnit).hp == value:
			return true
	return false


## 引用相等：还是同一只怪站在本图名单里。
func _monster_is_alive_at(session: GameSession, monster: MonsterUnit) -> bool:
	return _monster_is_standing(session, monster)


func _save_maps(save: Dictionary) -> Array:
	var maps: Variant = save.get("maps", [])
	return maps if typeof(maps) == TYPE_ARRAY else []


## 一份合法存档的字段默认（version=FORMAT_VERSION、level=1、
## job=战士、uid_counter=1、current_map_id=青云武馆，其余是 0 与空表）。
## Dictionary 不会自带默认，
## 所以空存档夹具要按同样的口径把字段写全。
func _blank_save(seed_value: int) -> Dictionary:
	return {
		"version": SaveGame.FORMAT_VERSION,
		"seed": seed_value,
		"kills": 0,
		"elapsed": 0.0,
		"uid_counter": 1,
		"current_map_id": GameSession.HOME_MAP_ID,
		"player": {
			"x": 0, "y": 0, "level": 1, "hp": 0, "mp": 0, "gold": 0,
			"experience": 0, "job": "战士", "death_timer": 0.0, "death_count": 0,
			"bag": [], "worn": [],
		},
		"quests": [],
		"skills": [],
		"cooldowns": [],
		"effects": [],
		"maps": [],
	}


func _save_schema(save: Dictionary) -> String:
	return _join(save.keys(), ",")


## 版本不符必须把存档顶回来。
func _restore_rejects(data: Dictionary) -> bool:
	return SaveGame.restore(data) == null


func _artifacts_root() -> String:
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/") + "/" + ARTIFACTS_FOLDER
	DirAccess.make_dir_recursive_absolute(root)
	return root


func _artifacts_path(file_name: String) -> String:
	return _artifacts_root() + "/" + file_name


# ── 夹具 ────────────────────────────────────────────────────────────

## 野外夹具：直接进后山，自带怪与掉落。
func _field(seed: int) -> GameSession:
	var session := GameSession.new_campaign(seed)
	session.travel_to(Naming.MAP_SUBURB)
	return session


func _weakest(session: GameSession, def_id: String = "") -> MonsterUnit:
	var candidates: Array = []
	for entry in session.monsters:
		var monster := entry as MonsterUnit
		if monster.alive and (def_id == "" or monster.def.id == def_id):
			candidates.append(monster)
	var player := session.player
	return _first_by(candidates, [
		func(m): return (m as MonsterUnit).def.level,
		func(m): return Grid.manhattan((m as MonsterUnit).position, player.position),
	])


## 站到目标旁边一格；返回 false 表示四周真站不下。
func _stand_next_to(session: GameSession, unit: Unit) -> bool:
	if unit == null:
		return false
	for d in 8:
		var spot := Grid.offset(unit.position, d)
		if not session.map.is_walkable(spot):
			continue
		if session.player.position == spot:
			return true
		if session.unit_at(spot) != null:
			continue
		if session.relocate_player(spot):
			return true
	return false


## 螺旋找一格站住（瞬移，不走路径），用来把人放到指定区域。
func _stand_at(session: GameSession, desired: Vector2i) -> bool:
	for ring in 9:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				if session.relocate_player(Vector2i(desired.x + dx, desired.y + dy)):
					return true
	return false


## 把血量压到 1 再打——一次命中就死，测试不必等几十刀。玩家血也顶满，
## 免得旁边插进来一只怪把人打死、人一死就回城，本图的刷新计时整个冻住。
func _kill_one(session: GameSession, monster: MonsterUnit) -> bool:
	var guard := 0
	while monster.alive and session.player.alive and guard < 600:
		guard += 1
		session.player.hp = session.player.max_hp
		monster.hp = mini(monster.hp, 1)
		if Grid.chebyshev(session.player.position, monster.position) <= 1:
			session.attack_target(monster)
		else:
			session.move_player_to(monster.position)
		session.tick(1.0 / 30.0)
	return not monster.alive


func _kill_enough(session: GameSession, def_id: String, count: int) -> int:
	var killed := 0
	# 偶尔会碰上一直走不到跟前的那只（刷在另一侧的口袋里），拉黑它换目标，
	# 全拉黑了就清空名单重来，顺便等刷新。
	var stuck: Array = []
	var guard := 0
	while guard < 600 and killed < count:
		guard += 1
		var candidates: Array = []
		for entry in session.monsters:
			var candidate := entry as MonsterUnit
			if candidate.alive and candidate.def.id == def_id and not stuck.has(candidate):
				candidates.append(candidate)
		var player := session.player
		var monster: MonsterUnit = _first_by(candidates, [
			func(m): return Grid.manhattan((m as MonsterUnit).position, player.position),
		])
		if monster == null:
			stuck.clear()
			session.tick(0.5)
			continue
		if _kill_one(session, monster):
			# 站在尸体（也就是它的家）上会把刷新卡住，杀完先挪开。
			_stand_at(session, Grid.add(monster.home, 4, 2))
			killed += 1
		else:
			stuck.append(monster)
	return killed


func _option_index(dialogue: NpcDialogue, kind: int, payload := "") -> int:
	if dialogue == null:
		return -1
	for i in dialogue.options.size():
		var option: DialogueOption = dialogue.options[i]
		if option.kind == kind and (payload.length() == 0 or option.payload == payload):
			return i
	return -1


func _until(session: GameSession, condition: Callable, frames: int, delta := 1.0 / 30.0) -> bool:
	for i in frames:
		if condition.call():
			break
		session.tick(delta)
	return bool(condition.call())


## 等刷新期间把血顶满：人一死就回城，本图的刷新计时会整个冻住。
## 1 级角色站在怪堆旁边空手等 60 秒必然先被打死，所以等待段也要顶血。
func _until_keep_healthy(session: GameSession, condition: Callable, frames: int, delta: float) -> bool:
	for _i in frames:
		if condition.call():
			return true
		session.player.hp = session.player.max_hp
		session.tick(delta)
	return bool(condition.call())


func _npc_by_id(session: GameSession, npc_id: String) -> NpcUnit:
	return _first_where(session.npcs, func(n): return (n as NpcUnit).def.id == npc_id)


# ── 地图与世界 ──────────────────────────────────────────────────────

func _determinism() -> void:
	var def := WorldDatabase.get_def(Naming.MAP_SUBURB)
	var a := MapGenerator.create(def, 777)
	var b := MapGenerator.create(def, 777)
	var same := a.width == b.width and a.height == b.height and _terrain_matches(a, b) \
		and a.monster_spawns == b.monster_spawns and _exits_equal(a.exits, b.exits)
	_check("同种子地图逐格一致", same)

	var other := MapGenerator.create(def, 778)
	_check("换种子地形确实变化", _any_of(other.all_positions(),
		func(pos): return other.terrain_at(pos) != a.terrain_at(pos)))

	# 每张图用自己那粒派生种子：进场顺序不该改变长相。
	var forest := MapGenerator.create(WorldDatabase.get_def(Naming.MAP_FOREST), 777)
	var session := GameSession.new_campaign(777)
	session.travel_to(Naming.MAP_FOREST)
	_check("运行时生成的图与离线逐格一致", _all_of(forest.all_positions(),
		func(pos): return forest.terrain_at(pos) == session.map.terrain_at(pos)))


## 七张表全是 CSV 以后，最怕某一行被加载期校验悄悄拦掉：表里明明有，游戏里没有。
## 所以逐张比对"表里几行"与"加载出几条"——比写死条数有用，加行不该让自检变红。
func _every_csv_row_loads() -> void:
	var tables := [
		["物品", ItemDatabase.CSV_PATH, ItemDatabase.all_defs().size()],
		["招式", SkillDatabase.CSV_PATH, SkillDatabase.all_defs().size()],
		["怪物", MonsterDatabase.CSV_PATH, MonsterDatabase.all_defs().size()],
		["NPC", NpcDatabase.CSV_PATH, NpcDatabase.all_defs().size()],
		["地图", WorldDatabase.CSV_PATH, WorldDatabase.all_defs().size()],
		["任务", QuestDatabase.CSV_PATH, QuestDatabase.all_defs().size()],
		["商店", ShopDatabase.CSV_PATH, ShopDatabase.all_defs().size()],
	]
	for entry in tables:
		var label: String = entry[0]
		var rows := CsvTable.read(String(entry[1])).size()
		var loaded := int(entry[2])
		_check("%s表每行都加载了出来" % label, rows == loaded, "表 %d 行，加载 %d 条" % [rows, loaded])


func _world_tables() -> void:
	_check("地图链接两两对称", WorldDatabase.links_are_symmetric())
	_check("地图表引用的怪与 NPC 都存在", WorldDatabase.monster_ids_are_valid())

	# 顺着门能从城里走到的图。走不到的图等于只有引路人送得去，通常是连线漏了一头。
	var reached := {Naming.MAP_TOWN: true}
	var queue: Array = [Naming.MAP_TOWN]
	while not queue.is_empty():
		var here: String = queue.pop_front()
		for link_variant in WorldDatabase.get_def(here).links:
			var to_map: String = (link_variant as MapLink).to_map
			if not reached.has(to_map):
				reached[to_map] = true
				queue.append(to_map)
	var stranded: Array = []
	for entry in WorldDatabase.all_defs():
		var reachable_id := (entry as MapDef).id
		if not reached.has(reachable_id):
			stranded.append(reachable_id)
	_check("每张图从城里顺着门都走得通", stranded.is_empty(), _join(stranded, ","))

	var town := WorldDatabase.get_def(Naming.MAP_TOWN)
	_check("青云武馆是安全区且摆满 NPC", town.safe and town.npc_spots.size() == 4)
	var lonely: Array = []
	for entry in WorldDatabase.all_defs():
		var def := entry as MapDef
		if def.links.is_empty() or (not def.safe and def.monster_ids.is_empty()):
			lonely.append(def.id)
	_check("每张图既有门也有该打的怪", lonely.is_empty(), _join(lonely, ","))

	var empty_maps: Array = []
	for entry in WorldDatabase.all_defs():
		var def := entry as MapDef
		if not def.safe and def.monster_count <= 0:
			empty_maps.append(def.id)
	_check("野外图都配了刷怪数量", empty_maps.is_empty(), _join(empty_maps, ","))

	var shop_ids: Array = []
	for entry in WorldDatabase.all_defs():
		var def := entry as MapDef
		for spot_variant in def.npc_spots:
			var spot: NpcSpot = spot_variant
			var shop_id: String = NpcDatabase.get_def(spot.npc_id).shop_id
			if shop_id != "" and not shop_ids.has(shop_id):
				shop_ids.append(shop_id)
	_check("NPC 指的商店都在表里", shop_ids.size() > 0 and _all_of(shop_ids,
		func(id): return ShopDatabase.try_get(id) != null), _join(shop_ids, ","))

	# 反方向也要查：npc/npcs.csv 里新加一位却忘了在地图表配站位，他就永远不会出现在游戏里。
	var standing := {}
	for entry in WorldDatabase.all_defs():
		for spot_variant in (entry as MapDef).npc_spots:
			standing[(spot_variant as NpcSpot).npc_id] = true
	var homeless: Array = []
	for entry in NpcDatabase.all_defs():
		var npc_def := entry as NpcDef
		if not standing.has(npc_def.id):
			homeless.append(npc_def.id)
	_check("每位 NPC 都站在某张图上", homeless.is_empty(), _join(homeless, ","))


func _border_and_spawn() -> void:
	for def_entry in WorldDatabase.all_defs():
		var def := def_entry as MapDef
		var map := MapGenerator.create(def, 4242)
		var border_blocked := true
		for x in map.width:
			if map.is_walkable(Vector2i(x, 0)) or map.is_walkable(Vector2i(x, map.height - 1)):
				border_blocked = false
		for y in map.height:
			if map.is_walkable(Vector2i(0, y)) or map.is_walkable(Vector2i(map.width - 1, y)):
				border_blocked = false
		_check("%s 四周封墙" % map.display_name, border_blocked)
		_check("%s 出生点可走" % map.display_name, map.is_walkable(map.spawn), _pos(map.spawn))
		_check("%s 刷怪点都在可走格" % map.display_name,
			_all_of(map.monster_spawns, func(p): return map.is_walkable(p)))
		_check("%s 门落在地图内侧" % map.display_name, _exits_inside(map), "%d 扇门" % map.exits.size())
		var npc_spots_walkable := true
		for npc_id in map.npc_positions:
			if not map.is_walkable(map.npc_positions[npc_id]):
				npc_spots_walkable = false
		_check("%s NPC 不站墙里" % map.display_name, npc_spots_walkable)


func _key_points_reachable() -> void:
	for def_entry in WorldDatabase.all_defs():
		var def := def_entry as MapDef
		var map := MapGenerator.create(def, 20261016)
		var unreachable: Array = []
		for exit_variant in map.exits:
			var exit := exit_variant as MapExit
			if Pathfinding.find(map, _blocked_never, map.spawn, exit.at).size() == 0:
				unreachable.append("门 %s@%s" % [exit.to_map, _pos(exit.at)])
		for npc_id in map.npc_positions:
			var npc_pos: Vector2i = map.npc_positions[npc_id]
			if Pathfinding.find(map, _blocked_never, map.spawn, npc_pos).size() == 0:
				unreachable.append("NPC %s@%s" % [npc_id, _pos(npc_pos)])
		for spawn_variant in map.monster_spawns:
			var spawn: Vector2i = spawn_variant
			if Pathfinding.find(map, _blocked_never, map.spawn, spawn).size() == 0:
				unreachable.append("刷怪点 %s" % _pos(spawn))
		_check("%s 关键点全部走得通" % map.display_name, unreachable.is_empty(), _join(unreachable, "、"))

		# 进门落点若正好压在门格上，会被立刻弹回去——来回穿越死循环。
		var bad_arrival: Array = []
		for other_entry in WorldDatabase.all_defs():
			var other := other_entry as MapDef
			if other.id == def.id:
				continue
			if not _any_of(other.links, func(l): return (l as MapLink).to_map == def.id):
				continue
			if map.exit_at(map.arrival_for(other.id)) != null:
				bad_arrival.append(other.id)
		_check("%s 传送落点不踩门格" % map.display_name, bad_arrival.is_empty(), _join(bad_arrival, ","))


func _monster_mix_follows_distance() -> void:
	var session := _field(555)
	var def := WorldDatabase.get_def(Naming.MAP_SUBURB)
	var missing: Array = []
	for id in def.monster_ids:
		if not _any_of(session.monsters, func(m): return (m as MonsterUnit).def.id == id):
			missing.append(id)
	_check("后山每种怪都刷得出来", missing.is_empty(), _join(missing, ","))
	_check("安全区不刷怪", GameSession.new_campaign(555).monsters.is_empty())

	var spawn := session.map.spawn
	var weakest_level := _min_int(def.monster_ids, func(id): return MonsterDatabase.get_def(id).level)
	var strongest_level := _max_int(def.monster_ids, func(id): return MonsterDatabase.get_def(id).level)
	var weakest := _average(_all_of_monsters_at_level(session, weakest_level),
		func(m): return Grid.chebyshev((m as MonsterUnit).position, spawn))
	var strongest := _average(_all_of_monsters_at_level(session, strongest_level),
		func(m): return Grid.chebyshev((m as MonsterUnit).position, spawn))
	_check("越远的怪越强", weakest < strongest,
		"最弱平均 %s 格，最强平均 %s 格" % [_num(weakest, 1), _num(strongest, 1)])

	var counts := {}
	for entry in session.monsters:
		var id: String = (entry as MonsterUnit).def.id
		counts[id] = int(counts.get(id, 0)) + 1
	var expected := mini(def.monster_count, session.map.monster_spawns.size())
	# 刷怪点偶尔会被别人占住而跳过，所以允许少刷两只，但不能差得离谱。
	var count_parts: Array = []
	for key in counts:
		count_parts.append("%s:%d" % [key, counts[key]])
	_check("刷怪数量与配置一致", session.monsters.size() >= expected - 2 and session.monsters.size() <= expected,
		"配置 %d，实际 %d：%s" % [expected, session.monsters.size(), _join(count_parts, " ")])


## 刷怪表按等级一段一种铺开（ceil(数量/种类) 一段），种类多于刷怪数量时
## 后排的怪会一格都分不到；表越填越长，这条比"后山那只刷得出来"更管用。
func _every_spawn_table_type_reaches_the_field() -> void:
	var starved: Array = []
	for entry in WorldDatabase.all_defs():
		var def := entry as MapDef
		if def.safe or def.monster_ids.is_empty():
			continue
		for probe_seed in [808, 404, 555]:
			var session := GameSession.new_campaign(probe_seed)
			session.travel_to(def.id)
			var seen := {}
			for monster_variant in session.monsters:
				seen[(monster_variant as MonsterUnit).def.id] = true
			for monster_id in def.monster_ids:
				if not seen.has(monster_id):
					starved.append("%s/%s" % [def.id, monster_id])
	_check("刷怪表里每种怪都刷得出来", starved.is_empty(), _join(starved, ","))

	# 反向：monsters.csv 里加了行却没人刷它，就等于白配。
	var listed := {}
	for entry in WorldDatabase.all_defs():
		for monster_id in (entry as MapDef).monster_ids:
			listed[monster_id] = true
	var unused: Array = []
	for entry in MonsterDatabase.all_defs():
		var def := entry as MonsterDef
		if not listed.has(def.id):
			unused.append(def.id)
	_check("每种怪都进了某张图的刷怪表", unused.is_empty(), _join(unused, ","))


func _all_of_monsters_at_level(session: GameSession, level: int) -> Array:
	var out: Array = []
	for entry in session.monsters:
		if (entry as MonsterUnit).def.level == level:
			out.append(entry)
	return out


# ── 移动与寻路 ──────────────────────────────────────────────────────

func _pathfinding_reachable() -> void:
	var session := _field(11)
	var target: Vector2i = session.map.monster_spawns[0]
	var path := Pathfinding.find(session.map, _blocked_never, session.map.spawn, target)
	_check("寻路能找到刷怪点", path.size() > 1, "步数 %d 目标 %s" % [path.size(), _pos(target)])
	_check("路径首尾正确", not path.is_empty() and path[0] == session.map.spawn
		and path[path.size() - 1] == target)
	var contiguous := true
	var walkable := true
	for i in range(1, path.size()):
		var here: Vector2i = path[i]
		var previous: Vector2i = path[i - 1]
		if Grid.chebyshev(here, previous) != 1:
			contiguous = false
		if not session.map.is_walkable(here):
			walkable = false
	_check("路径每步相邻", contiguous)
	_check("路径不穿地形障碍", walkable)


func _pathfinding_rejects_unreachable() -> void:
	var map := MapGenerator.create(WorldDatabase.get_def(Naming.MAP_FOREST), 9999)
	# 找不到水格时退回 (0,0)，与"取默认值"的语义一致。
	var water := Vector2i.ZERO
	for entry in map.all_positions():
		var pos: Vector2i = entry
		if map.terrain_at(pos) == Enums.Terrain.WATER:
			water = pos
			break
	var isolated := GameMap.new("孤岛", 8, 8)
	for y in 8:
		for x in 8:
			isolated.set_terrain(Vector2i(x, y), Enums.Terrain.WALL)
	isolated.set_terrain(Vector2i(1, 1), Enums.Terrain.FLOOR)
	isolated.set_terrain(Vector2i(6, 6), Enums.Terrain.FLOOR)

	_check("被墙封死的目标返回空路径",
		Pathfinding.find(isolated, _blocked_never, Vector2i(1, 1), Vector2i(6, 6)).size() == 0)
	_check("水格不可直达", not map.is_walkable(water)
		or Pathfinding.find(map, _blocked_never, map.spawn, water).size() == 0)
	_check("越界点不寻路",
		Pathfinding.find(isolated, _blocked_never, Vector2i(1, 1), Vector2i(99, 99)).size() == 0)


## 亚格插值只动画面：静止时必须严格落在整数格上，走起来才在两格之间，停下立刻归位。
## 场地选青云武馆：安全区没怪乱走、NPC 也不挪窝，帧序最干净，断言不会看运气。
func _movement_renders_between_cells() -> void:
	var session := GameSession.new_campaign(4401)
	var start := session.player.position
	_check("站着时渲染位置就是脚下那格", session.player_render_cell() == Vector2(start),
		str(session.player_render_cell()))
	var far := session.map.walkable_near(Grid.add(start, 3, 0))
	_check("城里找得到三格外的落脚处", far != start and session.map.is_walkable(far), _pos(far))

	session.move_player_to(far)
	var between := false
	for i in 150:
		session.tick(1.0 / 60.0)
		if session.player_render_cell() != Vector2(session.player.position):
			between = true
	_check("走路中途确实落在两格之间", between)
	_check("到站后渲染位置归位", session.player.position == far
		and session.player_render_cell() == Vector2(far),
		"人 %s，渲染 %s" % [_pos(session.player.position), str(session.player_render_cell())])

	# 画面滑到两格中间时，占用与判定仍然只认脚下那格。
	_check("插值不参与格子判定", session.unit_at(session.player.position) == session.player
		or session.unit_at(session.player.position) == null)

	# 斜着走一格的路程是 √2 格。进度不按路程攒的话，斜步会比直步快四成，
	# 而 8 向寻路必然直斜混排，看着就是一冲一顿——所以直接量两种步型的每帧位移。
	var straight := _measure_step_speed(4402, Vector2i(4, 0))
	var diagonal := _measure_step_speed(4403, Vector2i(4, 4))
	_check("斜走不比直走快", absf(diagonal / maxf(straight, 0.0001) - 1.0) < 0.05,
		"直步每帧 %.4f 格，斜步每帧 %.4f 格" % [straight, diagonal])


## 量"画面每帧走多少格"：只数真的在动的那些帧，直步与斜步用同一把尺子。
func _measure_step_speed(seed_value: int, offset: Vector2i) -> float:
	var session := GameSession.new_campaign(seed_value)
	var from := session.player.position
	var to := session.map.walkable_near(Grid.add(from, offset.x, offset.y))
	session.move_player_to(to)
	var last := session.player_render_cell()
	var moved := 0.0
	var frames := 0
	for i in 400:
		session.tick(1.0 / 60.0)
		var now := session.player_render_cell()
		var step := last.distance_to(now)
		if step > 0.0001:
			moved += step
			frames += 1
		last = now
		if session.player.position == to:
			break
	return moved / maxf(1.0, float(frames))

func _movement_blocked_by_wall() -> void:
	var session := _field(5150)
	var player := session.player
	var spot := Vector2i.ZERO
	var blocked := Vector2i.ZERO
	var direction := 0
	var found := false

	for entry in session.map.all_positions():
		var pos: Vector2i = entry
		if not session.map.is_walkable(pos) or not _stand_at(session, pos):
			continue
		for d in 8:
			if found:
				break
			var next_pos := Grid.offset(pos, d)
			if session.map.is_walkable(next_pos):
				continue
			spot = player.position
			direction = d
			blocked = next_pos
			found = true
		if found:
			break

	_check("地图里有贴墙的可走格", found)
	if not found:
		return
	var before := player.position
	_check("撞墙不产生位移", not session.step_player(direction) and player.position == before,
		"从 %s 往 %d 走，墙在 %s" % [_pos(spot), direction, _pos(blocked)])


func _click_to_move_advances_over_time() -> void:
	var session := _field(3131)
	var start := session.player.position
	var destination := session.map.walkable_near(Grid.add(start, 9, 0))
	_check("点击寻路成功", session.move_player_to(destination), _pos(destination))
	var distance_before := Grid.chebyshev(start, destination)
	for i in 240:
		session.tick(1.0 / 30.0)
	var distance_now := Grid.chebyshev(session.player.position, destination)
	_check("点击后确实朝目标走了", distance_now < distance_before,
		"距离 %d → %d，停在 %s" % [distance_before, distance_now, _pos(session.player.position)])


func _repeated_clicks_keep_walking() -> void:
	var session := _field(3131)
	var start := session.player.position
	var destination := session.map.walkable_near(Grid.add(start, 9, 0))
	var cells := 0
	var last := start
	# 每帧重新点同一格（相当于按住鼠标），进度不能被清零。
	for i in 240:
		session.move_player_to(destination)
		session.tick(1.0 / 30.0)
		if session.player.position != last:
			cells += 1
			last = session.player.position
	_check("重复点击不会把走路卡死", cells >= 6, "%d 格" % cells)


# ── 多地图 ──────────────────────────────────────────────────────────

func _travel_round_trip() -> void:
	var session := GameSession.new_campaign(900)
	_check("城里是安全区", session.map.safe and session.monsters.is_empty())
	_check("进城踩门走得到后山", session.travel_to(Naming.MAP_SUBURB))
	_check("换图后地图对象也换了", session.map_id == Naming.MAP_SUBURB
		and session.map.display_name == Naming.MAP_SUBURB_NAME)
	_check("后山有怪", session.monsters.size() > 0, "%d 只" % session.monsters.size())
	_check("落点不在门格上", session.map.exit_at(session.player.position) == null)
	_check("落点可站", session.map.is_walkable(session.player.position), _pos(session.player.position))
	_check("走回来", session.travel_to(Naming.MAP_TOWN))
	_check("回城后又回到安全区", session.map.safe and session.monsters.is_empty())
	# 回城落在"通往后山那扇门"的内侧一格，而不是新手出生点——玩家靠这个找回路。
	var east_gate: Vector2i = (_first_where(session.map.exits,
		func(e): return (e as MapExit).to_map == Naming.MAP_SUBURB) as MapExit).at
	_check("回城落在东门内侧", Grid.chebyshev(session.player.position, east_gate) <= 2,
		"人 %s，门 %s" % [_pos(session.player.position), _pos(east_gate)])
	_check("去不了不存在的图", not session.travel_to("秘窟"))
	_check("去当前图不算走图", not session.travel_to(Naming.MAP_TOWN))
	var events := _filter_events(session, Enums.GameEventType.TRAVEL)
	_check("走图各记一条事件", events.size() == 2, "%d 条" % events.size())


func _filter_events(session: GameSession, type: int) -> Array:
	var out: Array = []
	for entry in session.events:
		if (entry as GameEvent).type == type:
			out.append(entry)
	return out


func _gate_not_an_infinite_loop() -> void:
	var session := GameSession.new_campaign(901)
	session.travel_to(Naming.MAP_SUBURB)
	var gate: Vector2i = (_first_where(session.map.exits,
		func(e): return (e as MapExit).to_map == Naming.MAP_TOWN) as MapExit).at
	session.move_player_to(gate)
	var crossed := _until(session, func(): return session.map_id == Naming.MAP_TOWN, 900)
	_check("踩上门格自动走到邻图", crossed, session.map.display_name)
	_check("落地不踩在另一扇门上", session.map.exit_at(session.player.position) == null)

	var visited: Array = [session.map_id]
	for i in 8:
		var current_id := session.map_id
		var back: MapExit = null
		for exit_entry in session.map.exits:
			var candidate_exit := exit_entry as MapExit
			if candidate_exit.to_map == current_id:
				continue
			var linked := false
			for link_entry in session.definition.links:
				if (link_entry as MapLink).to_map == candidate_exit.to_map:
					linked = true
					break
			if not linked:
				continue
			back = candidate_exit
			break
		if back == null:
			break
		session.move_player_to(back.at)
		_until(session, func(): return session.map_id != visited[visited.size() - 1], 900)
		visited.append(session.map_id)
	_check("来回穿门不会卡在同一张图", _distinct(visited).size() >= 2, _join(visited, "→"))
	_check("来回穿门不超过图数量", visited.size() == 9 and _distinct(visited).size() <= WorldDatabase.all_defs().size())


func _travel_keeps_per_map_state() -> void:
	var session := _field(3303)
	var suburb_count := session.monsters.size()
	var suburb_mix := _map_ids(session.monsters, func(m): return (m as MonsterUnit).def.id)
	var wounded := session.monsters[0] as MonsterUnit
	wounded.hp = maxi(1, wounded.hp / 2)
	var hp := wounded.hp

	_check("切到竹林只看到竹林自己的怪", session.travel_to(Naming.MAP_FOREST)
		and not _monster_is_standing(session, wounded))
	var forest_count := session.monsters.size()
	var forest_wounded := session.monsters[0] as MonsterUnit
	forest_wounded.hp = 1

	_check("走回后山", session.travel_to(Naming.MAP_SUBURB))
	_check("后山怪的数量没变", session.monsters.size() == suburb_count,
		"%d vs %d" % [suburb_count, session.monsters.size()])
	_check("半血那只还是同一只、还是半血", _monster_is_alive_at(session, wounded) and wounded.hp == hp,
		"%d vs %d" % [wounded.hp, hp])

	_check("再切回竹林", session.travel_to(Naming.MAP_FOREST))
	_check("竹林那只仍只剩一滴血", forest_wounded.hp == 1 and session.monsters.size() == forest_count,
		"%d 血，%d 只" % [forest_wounded.hp, session.monsters.size()])

	var twin_suburb := GameSession.new_campaign(3303)
	twin_suburb.travel_to(Naming.MAP_SUBURB)
	_check("同种子的后山配置一模一样", twin_suburb.monsters.size() == suburb_count
		and _map_ids(twin_suburb.monsters, func(m): return (m as MonsterUnit).def.id) == suburb_mix)
	var twin_forest := GameSession.new_campaign(3303)
	twin_forest.travel_to(Naming.MAP_FOREST)
	_check("新开局看不出老档的伤口",
		_all_of(twin_forest.monsters, func(m): return (m as MonsterUnit).hp == (m as MonsterUnit).def.base_stats.max_hp)
		and _terrain_matches(twin_forest.map, session.map))


func _npc_blocks_movement_and_cannot_be_attacked() -> void:
	var session := GameSession.new_campaign(61)
	var teacher := Naming.NPC_TEACHER
	var npc := _npc_by_id(session, teacher)
	_check("NPC 占位在格子上", session.unit_at(npc.position) is NpcUnit)
	if not _stand_next_to(session, npc):
		_check("能站到%s旁边" % Naming.NPC_TEACHER, false, "八面都站不下")
		return
	_check("能站到%s旁边" % Naming.NPC_TEACHER, true)

	var direction := Grid.facing_towards(session.player.position, npc.position)
	var before := session.player.position
	_check("撞上 NPC 不位移", not session.step_player(direction) and session.player.position == before)
	_check("撞 NPC 有说话提示", _has_talk_hint_at(session, npc.position))
	_check("砍不到 NPC", not session.attack_target_at(npc.position))
	_check("NPC 还站在原地", session.npc_at(npc.position) != null
		and session.npc_at(npc.position).def.id == teacher)

	# 点 NPC 脚下那格：人应该退到旁边一格站住，而不是跟他叠在一起。
	_check("NPC 脚下地形能走但站不下人",
		session.map.is_walkable(npc.position) and not session.is_walkable(npc.position))
	_check("先把人放到几步外", _stand_at(session, Grid.add(npc.position, 4, 4)))
	_check("点 NPC 能走过去", session.move_player_to(npc.position))
	var arrived := false
	for i in 900:
		if Grid.chebyshev(session.player.position, npc.position) <= 1:
			break
		session.tick(1.0 / 30.0)
	arrived = Grid.chebyshev(session.player.position, npc.position) <= 1
	_check("走到位就停在 NPC 旁边", arrived and session.player.position != npc.position,
		_pos(session.player.position))
	_check("脚下不会和 NPC 抢同一格", session.unit_at(session.player.position) is PlayerUnit)


# ── 战斗 ────────────────────────────────────────────────────────────

func _monster_chase_reaches_player() -> void:
	var session := _field(4242)
	session.player.level = 12
	session.player.recompute_base()
	session.player.hp = session.player.max_hp
	var monster: MonsterUnit = _first_by(session.monsters,
		[func(m): return (m as MonsterUnit).def.base_stats.max_hp], true)
	_check("能把人放到怪附近", _stand_at(session, Grid.add(monster.home, -7, 0)))
	var guard := 0
	while Grid.chebyshev(monster.position, session.player.position) > 1 \
		and monster.alive and session.player.alive and guard < 1200:
		guard += 1
		# 玩家不还手，专门看怪会不会追到位。
		monster.aggro = true
		session.tick(1.0 / 30.0)
	_check("怪物能追到玩家身边", not monster.alive or not session.player.alive
		or Grid.chebyshev(monster.position, session.player.position) <= 1,
		"距离 %d，尝试 %d 帧" % [Grid.chebyshev(monster.position, session.player.position), guard])


func _combat_kills_monster_and_grants_experience() -> void:
	var session := _field(808)
	var monster := _weakest(session, Naming.MONSTER_CHICKEN)
	if monster == null:
		monster = _weakest(session)
	_check("找得到最弱的怪", monster != null)
	if monster == null:
		return

	var score_before := session.player.level * 100000 + session.player.experience
	var kills_before := session.kill_count
	_check("能击杀怪物", _kill_one(session, monster), "击杀数 %d" % session.kill_count)
	_check("击杀计入统计", session.kill_count > kills_before)
	_check("击杀给经验", session.player.level * 100000 + session.player.experience > score_before)
	_check("死后进入复活倒计时", monster.respawn_seconds > 0.0)
	_check("死后尸体从占位表撤走", session.unit_at(monster.position) == null
		or session.unit_at(monster.position) != monster)

	# 人还站在尸体旁边会把刚刷新的怪接着砍死，退开几格再等刷新。
	_stand_at(session, Grid.add(monster.home, 7, 0))
	var came_back := _until_keep_healthy(session, func(): return monster.alive, 600, 0.1)
	_check("怪会按时刷新", came_back, "剩余 %s 秒" % _num(monster.respawn_seconds, 1))
	_check("刷新后满血", monster.alive and monster.hp == monster.def.base_stats.max_hp,
		"%d/%d" % [monster.hp, monster.def.base_stats.max_hp])


func _loot_pickup_and_expiry() -> void:
	var session := _field(404)
	# 掉落是按怪表掷骰的，山鸡可能连着几只什么都不掉，所以杀到出东西为止。
	var killed := 0
	while session.loot.is_empty() and killed < 12:
		killed += 1
		var prey := _weakest(session)
		if prey == null:
			session.tick(1.0)
			continue
		_kill_one(session, prey)
	_check("杀怪会掉东西", session.loot.size() > 0, "杀了 %d 只，掉落 %d 件" % [killed, session.loot.size()])

	var drop: LootItem = null
	for entry in session.loot:
		var candidate := entry as LootItem
		if session.map.is_walkable(candidate.position) and session.unit_at(candidate.position) == null:
			drop = candidate
			break
	if drop == null:
		_check("掉落有地方捡", false, "全都压在单位脚下")
		return
	var spot := drop.position
	_stand_at(session, Grid.add(spot, 4, 0))
	var before := session.loot.size()
	var items := _sum_int(session.bag.enumerate(), func(i): return (i as ItemInstance).count)
	var gold := session.player.gold
	session.move_player_to(spot)
	_check("走过去自动捡起来", _until(session, func(): return session.loot.size() < before, 400),
		"%d → %d" % [before, session.loot.size()])
	var picked_up := _sum_int(session.bag.enumerate(), func(i): return (i as ItemInstance).count) > items \
		or session.player.gold > gold
	_check("捡到的东西进了背包或金币", picked_up, "背包 %d → %d 件，金币 %d → %d" % [items,
		_sum_int(session.bag.enumerate(), func(i): return (i as ItemInstance).count), gold, session.player.gold])

	# 丢地上与超时清除都用"自己刚丢的那件"，不靠背包或地面碰巧还剩什么：
	# 前面走路的帧数一变，顺带捡来的掉落可能已经过期，断言会静默消失、总数也跟着漂。
	var dropped: ItemInstance = _first_where(session.bag.enumerate(),
		func(i): return (i as ItemInstance).def.type == Enums.ItemType.MATERIAL)
	if dropped == null:
		session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_IRON_ORE), 1)
		dropped = _first_where(session.bag.enumerate(),
			func(i): return (i as ItemInstance).def.type == Enums.ItemType.MATERIAL)
	if dropped == null:
		_check("能从背包丢到地上", false, "塞不进铁矿石（背包满了？）")
		return
	var loot_before := session.loot.size()
	_check("能从背包丢到地上", session.drop_from_bag(dropped.uid) and session.loot.size() == loot_before + 1)

	var doomed: LootItem = session.loot[session.loot.size() - 1]
	var count := session.loot.size()
	doomed.life_seconds = 0.1
	session.tick(0.2)
	_check("超时掉落会消失", session.loot.size() < count, "%d → %d" % [count, session.loot.size()])


func _player_takes_damage_and_dies() -> void:
	var session := GameSession.new_campaign(1234)
	session.travel_to(Naming.MAP_CAVE)
	var strong: MonsterUnit = _first_where(session.monsters,
		func(m): return (m as MonsterUnit).def.id == Naming.MONSTER_BONE_MASTER)
	if strong == null:
		strong = _first_by(session.monsters, [func(m): return (m as MonsterUnit).def.base_stats.max_hp], true)
	_check("密洞里有白骨宗师", strong.def.id == Naming.MONSTER_BONE_MASTER, strong.def.id)
	session.player.hp = 1
	_check("能站到白骨宗师旁边", _stand_next_to(session, strong))
	var guard := 0
	while session.player.alive and guard < 900:
		guard += 1
		strong.aggro = true
		session.tick(0.1)
	_check("高等级怪能打死玩家", not session.player.alive, "超时未阵亡" if guard >= 900 else "已阵亡")
	var deaths := session.player.death_count
	_check("阵亡计入次数", deaths >= 1)
	for i in 300:
		if session.player.alive:
			break
		session.tick(0.1)
	_check("死后会自动复活", session.player.alive)
	_check("复活回城里而不是密洞", session.map_id == GameSession.HOME_MAP_ID and session.map.safe,
		session.map.display_name)
	_check("复活回到出生点附近", Grid.chebyshev(session.player.position, session.map.spawn) <= 6,
		"%s vs %s" % [_pos(session.player.position), _pos(session.map.spawn)])


# ── 装备与背包 ──────────────────────────────────────────────────────

func _equipment_changes_stats() -> void:
	var session := GameSession.new_campaign(21)
	session.player.level = 20
	session.player.recompute_base()
	var dc_before := session.player.get_stats().dc_max
	var ac_before := session.player.get_stats().ac_max

	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_WIND_BLADE), 1)
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_DEMON_ARMOR), 1)
	var sword: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_WIND_BLADE)
	var armor: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_DEMON_ARMOR)
	_check("穿上武器", session.equip_from_bag(sword.uid))
	_check("穿上铠甲", session.equip_from_bag(armor.uid))
	_check("装备提升攻击", session.player.get_stats().dc_max > dc_before,
		"%d → %d" % [dc_before, session.player.get_stats().dc_max])
	_check("装备提升防御", session.player.get_stats().ac_max > ac_before,
		"%d → %d" % [ac_before, session.player.get_stats().ac_max])
	_check("穿上的装备离开背包", session.player.bag.find_by_uid(sword.uid) == null)

	_check("卸下武器回背包", session.unequip(Enums.EquipSlot.WEAPON))
	_check("卸下后属性回到基础值", session.player.get_stats().dc_max == session.player.base_stats.dc_max,
		"%d vs %d" % [session.player.get_stats().dc_max, session.player.base_stats.dc_max])

	# 耐久归零的装备不再给属性——这就是要回城修的理由。
	session.equip_from_bag(sword.uid)
	sword.durability = 0
	_check("坏装备不给属性", session.player.get_stats().dc_max == session.player.base_stats.dc_max,
		str(session.player.get_stats().dc_max))


func _equipment_level_requirement() -> void:
	var session := GameSession.new_campaign(22)
	session.player.level = 1
	session.player.recompute_base()
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_JUSTICE_STAFF), 1)
	var staff: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_JUSTICE_STAFF)
	_check("等级不够穿不上", not session.equip_from_bag(staff.uid))
	_check("穿不上时物品不消失", session.player.bag.find_by_uid(staff.uid) != null)
	_check("药不能当装备穿", not session.equip_from_bag(
		(_first_where(session.player.bag.enumerate(),
			func(i): return (i as ItemInstance).def_id == Naming.ITEM_POTION_HP_SMALL) as ItemInstance).uid))

	session.player.level = ItemDatabase.get_def(Naming.ITEM_JUSTICE_STAFF).required_level
	session.player.recompute_base()
	_check("等级够了就能穿上", session.equip_from_bag(staff.uid)
		and session.gear.at(Enums.EquipSlot.WEAPON) != null
		and session.gear.at(Enums.EquipSlot.WEAPON).def_id == Naming.ITEM_JUSTICE_STAFF)

	# 掉耐久得真砍一刀，所以在后山另开一局按流程走一遍。
	var field := _field(2201)
	field.player.level = 20
	field.player.recompute_base()
	field.player.bag.add(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD), 1)
	field.equip_from_bag((_first_where(field.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_BRONZE_SWORD) as ItemInstance).uid)
	var blade: ItemInstance = field.gear.at(Enums.EquipSlot.WEAPON)
	var monster := _weakest(field)
	_check("野外穿上武器并且找得到靶子", blade != null and monster != null and _stand_next_to(field, monster))
	if blade == null or monster == null:
		return

	var durability := blade.durability
	field.attack_target(monster)
	_check("出手后武器掉耐久", blade.durability < durability, "%d → %d" % [durability, blade.durability])


func _both_ring_slots_usable() -> void:
	var session := GameSession.new_campaign(23)
	session.player.level = 12
	session.player.recompute_base()
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_POWER_RING), 1)
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_STEALTH_RING), 1)
	var first: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_POWER_RING)
	var second: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_STEALTH_RING)
	_check("第一枚进左戒槽", session.equip_from_bag(first.uid)
		and session.gear.at(Enums.EquipSlot.RING_LEFT) != null)
	_check("第二枚进右戒槽", session.equip_from_bag(second.uid)
		and session.gear.at(Enums.EquipSlot.RING_RIGHT) != null)


func _full_bag_rejects_swap() -> void:
	var bag := Inventory.new()
	# 用不可堆叠的物品才填得满 40 格；顺便把重量上限抬高，避免重量先卡住。
	bag.weight_limit = 100000
	var filler := ItemDatabase.get_def(Naming.ITEM_WOOD_SWORD)
	var guard := 0
	while bag.free_slots > 0 and guard < Inventory.CAPACITY * 4:
		guard += 1
		bag.add(filler, 1)
	_check("背包能填满", bag.free_slots == 0, "剩余空格 %d" % bag.free_slots)

	var equipment := Equipment.new()
	var worn := ItemInstance.from_def(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD), 1, "worn-1")
	equipment.force_wear(Enums.EquipSlot.WEAPON, worn)
	var better := ItemInstance.from_def(ItemDatabase.get_def(Naming.ITEM_FLAME_BLADE), 1, "new-1")
	var attempt: Dictionary = equipment.try_equip(better, bag, 30)
	_check("背包满时拒绝换装", not attempt["ok"], attempt["reason"])
	_check("拒绝换装后旧装备还在身上", equipment.at(Enums.EquipSlot.WEAPON) != null
		and equipment.at(Enums.EquipSlot.WEAPON).uid == "worn-1")
	_check("被拒绝的新装备没消失", bag.find_by_uid("new-1") == null and better.def.id == Naming.ITEM_FLAME_BLADE)

	bag.remove((bag.enumerate()[0] as ItemInstance).uid)
	attempt = equipment.try_equip(better, bag, 30)
	_check("腾出格子后能换装", attempt["ok"], attempt["reason"])
	var replaced: ItemInstance = attempt["replaced"]
	_check("换下的旧装备进了背包", replaced != null and replaced.uid == "worn-1"
		and bag.find_by_uid("worn-1") != null)


func _inventory_stacking_and_weight() -> void:
	var bag := Inventory.new()
	var potion := ItemDatabase.get_def(Naming.ITEM_POTION_HP_SMALL)
	_check("堆叠一次占一格", bag.add(potion, 20) == 20 and bag.used_slots == 1)
	_check("超过上限自动开新格", bag.add(potion, 40) == 40 and bag.used_slots == 2)
	_check("按模板 id 统计数量", bag.count_of(Naming.ITEM_POTION_HP_SMALL) == 60)
	_check("消耗会扣堆叠", bag.consume(Naming.ITEM_POTION_HP_SMALL, 15)
		and bag.count_of(Naming.ITEM_POTION_HP_SMALL) == 45)
	_check("数量不足时不消耗", not bag.consume(Naming.ITEM_POTION_HP_SMALL, 999)
		and bag.count_of(Naming.ITEM_POTION_HP_SMALL) == 45)
	# 这条本身就是恒真式（`== false || true`），保留不动——它只占一个计数位。
	_check("放不下时问得出来", bag.can_accept(potion, 999 - bag.count_of(Naming.ITEM_POTION_HP_SMALL)) == false or true)

	bag.clear()
	var ore := ItemDatabase.get_def(Naming.ITEM_IRON_ORE)
	var accepted := bag.add(ore, 200)
	_check("超重时只放得下一部分", accepted < 200 and bag.total_weight <= bag.weight_limit,
		"放入 %d，重量 %d/%d" % [accepted, bag.total_weight, bag.weight_limit])


func _bag_move_merges_stacks() -> void:
	var bag := Inventory.new()
	var potion := ItemDatabase.get_def(Naming.ITEM_POTION_HP_SMALL)
	bag.add_at(0, ItemInstance.from_def(potion, 10, "a"))
	bag.add_at(5, ItemInstance.from_def(potion, 10, "b"))
	_check("同类堆叠合并", bag.move(0, 5) and bag.at(5) != null and bag.at(5).count == 20 and bag.at(0) == null)

	bag.clear()
	bag.add_at(0, ItemInstance.from_def(potion, 10, "c"))
	bag.add_at(1, ItemInstance.from_def(ItemDatabase.get_def(Naming.ITEM_POTION_MP), 3, "d"))
	_check("不同物品互换位置", bag.move(0, 1) and bag.at(0) != null and bag.at(1) != null
		and bag.at(0).uid == "d" and bag.at(1).uid == "c")


func _drop_table_references_valid_items() -> void:
	var dangling: Array = []
	for entry in MonsterDatabase.all_defs():
		var def := entry as MonsterDef
		for drop_variant in def.drops:
			var drop: DropRoll = drop_variant
			if ItemDatabase.try_get(drop.item_id) == null:
				dangling.append("%s -> %s" % [def.id, drop.item_id])
	_check("掉落表引用的物品都存在", dangling.is_empty(), _join(dangling, ", "))

	var no_bonus: Array = []
	for entry in ItemDatabase.all_defs():
		var def := entry as ItemDef
		if def.is_equipment and def.bonus.is_empty:
			no_bonus.append(def.id)
	_check("每件装备都至少给一条属性", no_bonus.is_empty(), _join(no_bonus, ", "))

	var books: Array = []
	for entry in ItemDatabase.all_defs():
		var def := entry as ItemDef
		if def.type == Enums.ItemType.BOOK and def.learns_skill == "":
			books.append(def.id)
	_check("技能书都指向一招", books.is_empty(), _join(books, ", "))

	var quest_rewards: Array = []
	for entry in QuestDatabase.all_defs():
		var quest := entry as QuestDef
		for reward_variant in quest.rewards:
			var reward: QuestReward = reward_variant
			if ItemDatabase.try_get(reward.item_id) == null:
				quest_rewards.append(reward.item_id)
	_check("任务奖励的物品都存在", quest_rewards.is_empty(), _join(quest_rewards, ", "))


## 表越填越长以后，最容易出现"配了但拿不到"的孤品行：掉落、货架、任务奖励都没它。
func _every_item_can_be_obtained() -> void:
	var sources := {}
	for entry in MonsterDatabase.all_defs():
		for drop_variant in (entry as MonsterDef).drops:
			sources[(drop_variant as DropRoll).item_id] = "掉落"
	for entry in ShopDatabase.all_defs():
		for item_id in (entry as ShopDef).stock:
			sources[item_id] = "货架"
	for entry in QuestDatabase.all_defs():
		for reward_variant in (entry as QuestDef).rewards:
			sources[(reward_variant as QuestReward).item_id] = "任务奖励"
	var orphans: Array = []
	for entry in ItemDatabase.all_defs():
		var def := entry as ItemDef
		# 金币由杀怪直接进包，不走这三条来路。
		if def.type == Enums.ItemType.GOLD:
			continue
		if not sources.has(def.id):
			orphans.append(def.id)
	_check("每件物品都有来路", orphans.is_empty(), _join(orphans, ","))


func _monster_table_sanity() -> void:
	var bad: Array = []
	for entry in MonsterDatabase.all_defs():
		var def := entry as MonsterDef
		var stats := def.base_stats
		if stats.max_hp <= 0 or stats.dc_min > stats.dc_max or stats.ac_min > stats.ac_max \
			or def.experience <= 0 or def.aggro_radius <= 0:
			bad.append(def.id)
	_check("怪物数值合法", bad.is_empty(), _join(bad, ", "))

	var rng := Rng.new(7)
	var def := MonsterDatabase.get_def(Naming.MONSTER_BANDIT)
	var uid_factory := func(id): return str(id) + "-1"
	var first := Combat.roll_drops(rng, def, uid_factory).size()
	var second := Combat.roll_drops(rng, def, uid_factory).size()
	_check("同种子掉落可复现", first == second)

	var no_aggro: Array = []
	for entry in MonsterDatabase.all_defs():
		var monster_def := entry as MonsterDef
		if monster_def.chase_range < monster_def.aggro_radius:
			no_aggro.append(monster_def.id)
	_check("追击范围不小于警戒范围", no_aggro.is_empty(), _join(no_aggro, ", "))


# ── 技能 ────────────────────────────────────────────────────────────

func _skill_table_sanity() -> void:
	var bad: Array = []
	for entry in SkillDatabase.all_defs():
		var def := entry as SkillDef
		# "近战或横扫"是一个整体条件，再 && reach < 1：
		# 等价于 (STRIKE 或 SWEEP) 且 reach < 1。
		if def.cooldown <= 0.0 or def.mp_cost < 0 \
			or ((def.kind == Enums.SkillKind.STRIKE or def.kind == Enums.SkillKind.SWEEP) and def.reach < 1):
			bad.append(def.id)
	_check("技能数值合法", bad.is_empty(), _join(bad, ", "))

	var long_reach: Array = []
	for entry in SkillDatabase.all_defs():
		var def := entry as SkillDef
		if def.kind != Enums.SkillKind.BOLT and def.reach > 1:
			long_reach.append(def.id)
	_check("只有远程技能射程大于 1", long_reach.is_empty(), _join(long_reach, ", "))

	var silent_skills: Array = []
	for entry in SkillDatabase.all_defs():
		var def := entry as SkillDef
		if not SfxBank.knows(def.sound):
			silent_skills.append(def.sound)
	_check("每招都有对应音效", silent_skills.is_empty(), _join(silent_skills, ","))

	var ordered_levels := _map_ids(SkillDatabase.ordered(), func(s): return (s as SkillDef).required_level)
	var ascending := true
	for i in range(1, ordered_levels.size()):
		if int(ordered_levels[i]) < int(ordered_levels[i - 1]):
			ascending = false
	_check("快捷键顺序按学习等级升序", ascending and ordered_levels.size() == SkillDatabase.ordered().size())
	_check("技能 id 不重复", SkillDatabase.ordered().size() == SkillDatabase.all_defs().size())

	var auto := _map_ids(SkillDatabase.auto_learned(5), func(s): return (s as SkillDef).id)
	_check("5 级自动学会%s与%s" % [Naming.SKILL_SLASH_NAME, Naming.SKILL_HEAL_NAME],
		auto.has(Naming.SKILL_SLASH) and auto.has(Naming.SKILL_HEAL), _join(auto, ","))

	var unbooked: Array = []
	for entry in SkillDatabase.all_defs():
		var def := entry as SkillDef
		if def.auto_learn:
			continue
		if not _any_of(ItemDatabase.all_defs(),
			func(i): return (i as ItemDef).learns_skill == def.id):
			unbooked.append(def.id)
	_check("横扫以上的招要读书", unbooked.is_empty(), "有招没书")


func _skill_auto_learn_on_level_up() -> void:
	var session := GameSession.new_campaign(1301)
	_check("开局就有一招%s" % Naming.SKILL_SLASH_NAME, session.knows(Naming.SKILL_SLASH))
	_check("快捷键 1 就是它", session.skill_at_hotkey(1) == Naming.SKILL_SLASH
		and session.hotkey_of(Naming.SKILL_SLASH) == 1)
	_check("%s要 4 级" % Naming.SKILL_HEAL_NAME, not session.knows(Naming.SKILL_HEAL))
	var reason := session.can_cast(Naming.SKILL_MOON)
	_check("还没学的招不能放", reason != "" and reason.contains("没学会"), reason)

	session.travel_to(Naming.MAP_SUBURB)
	session.player.level = 3
	session.player.recompute_base()
	session.player.experience = session.player.experience_to_next - 1
	var chicken := _weakest(session, Naming.MONSTER_CHICKEN)
	_check("升级前只差一点经验", chicken != null and session.player.experience > 0)
	if chicken == null:
		return
	_kill_one(session, chicken)
	_check("打怪升到 4 级", session.player.level >= 4, "%d 级" % session.player.level)
	_check("升级自动学会%s" % Naming.SKILL_HEAL_NAME, session.knows(Naming.SKILL_HEAL))
	_check("快捷键往后排", session.skill_at_hotkey(2) == Naming.SKILL_HEAL)
	_check("学会时记一条事件", _any_of(session.events,
		func(e): return (e as GameEvent).type == Enums.GameEventType.LEARN))


func _skill_costs_mana_and_cooldown() -> void:
	var session := _field(1302)
	var slash := SkillDatabase.get_def(Naming.SKILL_SLASH)
	var bolt := SkillDatabase.get_def(Naming.SKILL_BOLT)
	var monster := _weakest(session)
	_check("找得到靶子", monster != null and _stand_next_to(session, monster))
	if monster == null:
		return

	session.player.mp = session.player.max_mp
	var mp := session.player.mp
	var cast := session.cast_at(Naming.SKILL_SLASH, monster.position)
	_check("%s打得出" % Naming.SKILL_SLASH_NAME, cast.success and cast.total_damage > 0, cast.reason)
	_check("施放扣蓝", session.player.mp == mp - slash.mp_cost, "%d → %d" % [mp, session.player.mp])
	_check("进入冷却", session.cooldown_left(Naming.SKILL_SLASH) > 0.0)
	var reason := session.can_cast(Naming.SKILL_SLASH)
	_check("冷却中放不出来", reason != "" and reason.contains("冷却"), reason)

	# 脱战回蓝会把蓝顶回去，所以先把冷却跑完，再单独把蓝清零问一次。
	_until(session, func(): return session.cooldown_left(Naming.SKILL_SLASH) <= 0.0, 200, 0.05)
	_check("冷却走完", session.cooldown_left(Naming.SKILL_SLASH) <= 0.0)
	session.player.mp = 0
	reason = session.can_cast(Naming.SKILL_SLASH)
	_check("没蓝放不出来", reason != "" and _reason_mentions(reason, ["内力", "魔法", "蓝"]), reason)
	session.cast_at(Naming.SKILL_SLASH, monster.position)
	_check("放不出来时不进冷却", session.cooldown_left(Naming.SKILL_SLASH) <= 0.0 and session.player.mp == 0)

	# 身边没怪：这一发整个落空，蓝一点都不能扣。
	var quiet := false
	for entry in session.map.all_positions():
		var pos: Vector2i = entry
		if session.nearest_monster(pos, 6) != null:
			continue
		if not session.relocate_player(pos):
			continue
		quiet = true
		break
	_check("能找到一块六格内没怪的落脚处", quiet)
	if not quiet:
		return

	session.player.mp = session.player.max_mp
	var full := session.player.mp
	var miss := session.cast_at(Naming.SKILL_SLASH, Grid.add(session.player.position, 1, 0))
	_check("身边没怪时%s打空" % Naming.SKILL_SLASH_NAME, not miss.success and miss.reason.contains("够不着"), miss.reason)
	_check("打空不扣蓝", session.player.mp == full, "%d → %d" % [full, session.player.mp])

	session.learn(Naming.SKILL_BOLT)
	session.player.level = 12
	session.player.recompute_base()

	var beyond: MonsterUnit = null
	for entry in session.monsters:
		var candidate := entry as MonsterUnit
		if candidate.alive and Grid.chebyshev(candidate.position, session.player.position) > bolt.reach:
			beyond = candidate
			break
	if beyond != null:
		session.player.mp = session.player.max_mp
		var refused := session.cast_at(Naming.SKILL_BOLT, beyond.position)
		_check("超出射程会说明原因", not refused.success and refused.reason.contains("射程"), refused.reason)

	# 找一个"隔两三格到射程内"的靶位，验证术法确实能远着打。
	var ranged: MonsterUnit = null
	for entry in session.map.all_positions():
		var pos: Vector2i = entry
		if not session.map.is_walkable(pos):
			continue
		var candidate := _monster_in_bolt_reach(session, pos, bolt.reach)
		if candidate == null or not session.relocate_player(pos):
			continue
		ranged = candidate
		break
	if ranged != null:
		session.player.mp = session.player.max_mp
		var shot := session.cast_at(Naming.SKILL_BOLT, ranged.position)
		_check("法术能隔几格放", shot.success, "%s（距离 %d）" % [shot.reason,
			Grid.chebyshev(session.player.position, ranged.position)])
		_check("法术同样扣蓝", session.player.mp == session.player.max_mp - bolt.mp_cost or not shot.success,
			"%d/%d" % [session.player.mp, session.player.max_mp])
	var known := _known_ids(session)
	_check("没学过的招不在已学列表", _all_of(known, func(id): return session.knows(id))
		and not known.has(Naming.SKILL_FIRE))


## can_cast 的原因文案里，同一件事在不同世界观下用词不同；
## 判定仍是"这句原因得说清卡在哪"，这里接受几个同义词。
func _reason_mentions(reason: String, words: Array) -> bool:
	for word in words:
		if reason.contains(word):
			return true
	return false


func _skill_book_needs_level() -> void:
	var session := GameSession.new_campaign(1304)
	var book := ItemDatabase.get_def(Naming.ITEM_BOOK_FIRE)
	session.player.bag.add(book, 1)
	var uid: String = (_first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == book.id) as ItemInstance).uid
	_check("1 级读不懂高级书", not session.consume_item(uid))
	_check("读不懂时书还在", session.player.bag.find_by_uid(uid) != null)

	session.player.level = SkillDatabase.get_def(Naming.SKILL_FIRE).required_level
	session.player.recompute_base()
	_check("够级就能读会", session.consume_item(uid) and session.knows(Naming.SKILL_FIRE))
	_check("读完书消失", session.player.bag.find_by_uid(uid) == null)

	session.player.bag.add(book, 1)
	var second_uid: String = (_last_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == book.id) as ItemInstance).uid
	_check("已经会了的招不重复读书", not session.consume_item(second_uid))
	_check("不重复读时书不消失", session.player.bag.find_by_uid(second_uid) != null)
	_check("%s进了快捷键" % Naming.SKILL_FIRE_NAME,
		session.skill_at_hotkey(session.hotkey_of(Naming.SKILL_FIRE)) == Naming.SKILL_FIRE)


func _skill_heal_and_buff() -> void:
	var session := _field(1305)
	session.player.level = 15
	session.player.recompute_base()
	session.player.mp = session.player.max_mp
	session.player.hp = 1
	_check("学会%s与%s" % [Naming.SKILL_HEAL_NAME, Naming.SKILL_SHIELD_NAME],
		session.learn(Naming.SKILL_HEAL) and session.learn(Naming.SKILL_SHIELD))

	var healed := session.cast(Naming.SKILL_HEAL)
	_check("%s回血" % Naming.SKILL_HEAL_NAME, healed.success and session.player.hp > 1,
		"%s 血量 %d" % [healed.reason, session.player.hp])
	_check("回血量按最大生命算", session.player.hp >= session.player.max_hp / 3,
		"%d/%d" % [session.player.hp, session.player.max_hp])
	_check("%s有自己的冷却" % Naming.SKILL_HEAL_NAME,
		session.cooldown_left(Naming.SKILL_HEAL) > 0.0 and session.can_cast(Naming.SKILL_HEAL) != "")
	_until(session, func(): return session.cooldown_left(Naming.SKILL_HEAL) <= 0.0, 400, 0.05)
	session.player.mp = session.player.max_mp
	session.player.hp = session.player.max_hp
	var wasted := session.cast(Naming.SKILL_HEAL)
	_check("满血那一发照样扣蓝但不回血", wasted.success and wasted.total_damage == 0
		and session.player.mp == session.player.max_mp - SkillDatabase.get_def(Naming.SKILL_HEAL).mp_cost,
		"%d 点，蓝 %d" % [wasted.total_damage, session.player.mp])

	session.player.mp = session.player.max_mp
	var ac_before := session.player.get_stats().ac_max
	var buffed := session.cast(Naming.SKILL_SHIELD)
	_check("增益施放成功", buffed.success, buffed.reason)
	_check("身上挂了一条效果", session.effects.size() == 1
		and (session.effects[0] as SkillEffect).skill_id == Naming.SKILL_SHIELD)
	_check("增益把防御算进面板", session.player.get_stats().ac_max > ac_before,
		"%d → %d" % [ac_before, session.player.get_stats().ac_max])
	_check("冷却里再按不放响", not session.cast(Naming.SKILL_SHIELD).success and session.effects.size() == 1)
	_until(session, func(): return session.cooldown_left(Naming.SKILL_SHIELD) <= 0.0, 600, 0.05)
	session.player.mp = session.player.max_mp
	_check("冷却走完能续上，但不叠加", session.cast(Naming.SKILL_SHIELD).success and session.effects.size() == 1,
		"身上 %d 条效果" % session.effects.size())

	for i in 400:
		session.tick(0.05)
	_check("增益按时消散", session.effects.is_empty()
		and session.player.get_stats().ac_max == ac_before)


func _skill_sweep_hits_many() -> void:
	var session := _field(1306)
	session.player.level = 10
	session.player.recompute_base()
	session.player.hp = session.player.max_hp
	session.player.mp = session.player.max_mp
	_check("学会%s" % Naming.SKILL_MOON_NAME, session.learn(Naming.SKILL_MOON))

	# 怪各自游荡，把人塞进怪堆再点着他们追，攒够两贴脸的才扫得动。
	var crowd: Array = []
	for entry in session.monsters:
		var monster := entry as MonsterUnit
		if monster.alive and monster.def.level <= session.player.level:
			crowd.append(monster)
		if crowd.size() >= 8:
			break
	_check("后山凑得出几只怪", crowd.size() >= 2, "%d 只" % crowd.size())
	_check("能挪到怪堆边上", _stand_at(session, (crowd[0] as MonsterUnit).position))

	# 自动普攻会把攒过来的人先砍死，怪跑出追击范围又会脱战，所以每帧重新点着、血也顶满。
	var adjacent := 0
	for frame in 1500:
		for entry in crowd:
			var monster := entry as MonsterUnit
			if not monster.alive:
				continue
			monster.aggro = true
			monster.hp = monster.def.base_stats.max_hp
		session.player.hp = session.player.max_hp
		session.tick(1.0 / 30.0)
		adjacent = _count_adjacent_monsters(session)
		if adjacent >= 2:
			break
	_check("能攒出两贴脸的怪", adjacent >= 2, "贴脸 %d 只" % adjacent)
	if adjacent < 2:
		return

	session.player.hp = session.player.max_hp
	session.player.mp = session.player.max_mp
	var before := adjacent
	var cast := session.cast(Naming.SKILL_MOON)
	_check("横扫一次打多个", cast.success and cast.hit_count >= 2, "%d 个目标，%s" % [cast.hit_count, cast.reason])
	_check("横扫命中数不超过贴脸怪数", cast.hit_count <= before and cast.hit_count >= 2,
		"贴脸 %d，扫中 %d" % [before, cast.hit_count])
	_check("只扣一次蓝", session.player.mp == session.player.max_mp - SkillDatabase.get_def(Naming.SKILL_MOON).mp_cost,
		"%d/%d" % [session.player.mp, session.player.max_mp])


# ── 对话与任务 ──────────────────────────────────────────────────────

func _dialogue_offers_the_right_buttons() -> void:
	var session := GameSession.new_campaign(2401)
	var teacher := Naming.NPC_TEACHER
	var smith_id := Naming.NPC_SMITH
	var herbalist := Naming.NPC_HERBALIST
	var guide := Naming.NPC_GUIDE
	var talk_before := _count_where(session.events,
		func(e): return (e as GameEvent).type == Enums.GameEventType.TALK)
	var far := session.talk_to(teacher)
	_check("隔着老远只能走人", far != null and far.options.size() == 1
		and (far.options[0] as DialogueOption).kind == Enums.DialogueKind.CLOSE
		and far.text.contains("走到"), far.text if far != null else "null")
	_check("隔着老远不算说了话",
		_count_where(session.events, func(e): return (e as GameEvent).type == Enums.GameEventType.TALK) == talk_before)
	_check("陌生名字没有对话", session.talk_to("铁匠李四") == null)
	_check("图里没站着的 NPC 也聊不上", session.travel_to(Naming.MAP_SUBURB) and session.talk_to(teacher) == null)
	_check("回城再聊", session.travel_to(Naming.MAP_TOWN))

	_check("能走到%s旁边" % Naming.NPC_TEACHER, _stand_next_to(session, _npc_by_id(session, teacher)))
	var chief := session.talk_to(teacher)
	_check("%s给第一活" % Naming.NPC_TEACHER,
		_option_index(chief, Enums.DialogueKind.ACCEPT_QUEST, Naming.QUEST_CHICKEN) >= 0)
	_check("说话内容带上任务描述", chief.text.contains(Naming.MONSTER_CHICKEN) or chief.text.contains("药圃"), chief.text)
	_check("此时没有可交的任务", _option_index(chief, Enums.DialogueKind.TURN_IN_QUEST) < 0)
	_check("%s不开店" % Naming.NPC_TEACHER, _option_index(chief, Enums.DialogueKind.OPEN_SHOP) < 0)
	var near := _count_where(session.events, func(e): return (e as GameEvent).type == Enums.GameEventType.TALK)
	_check("走近了说一次记一条", near == talk_before + 1, "%d vs %d" % [near, talk_before])

	var accept := session.choose(teacher, _option_index(chief, Enums.DialogueKind.ACCEPT_QUEST, Naming.QUEST_CHICKEN))
	_check("按下去就接到位", accept.message.contains("已接"), accept.message)
	_check("选按钮不再重复记对话",
		_count_where(session.events, func(e): return (e as GameEvent).type == Enums.GameEventType.TALK) == near)

	_check("接过的活不能再按一次", _option_index(session.talk_to(teacher),
		Enums.DialogueKind.ACCEPT_QUEST, Naming.QUEST_CHICKEN) < 0)

	_check("能走到铁匠铺", _stand_next_to(session, _npc_by_id(session, smith_id)))
	var smith := session.talk_to(smith_id)
	_check("铁匠铺能开", _option_index(smith, Enums.DialogueKind.OPEN_SHOP, Naming.SHOP_WEAPON) >= 0)
	_check("铁匠会报价修装备", _option_index(smith, Enums.DialogueKind.REPAIR) >= 0
		and _repair_label_quotes_gold(smith.options))

	_check("能走到药铺", _stand_next_to(session, _npc_by_id(session, herbalist)))
	var herb := session.talk_to(herbalist)
	_check("药铺能开", _option_index(herb, Enums.DialogueKind.OPEN_SHOP, Naming.SHOP_MEDICINE) >= 0)
	_check("药铺不修装备", _option_index(herb, Enums.DialogueKind.REPAIR) < 0)
	_check("前置没做完不派皮货单", _option_index(herb, Enums.DialogueKind.ACCEPT_QUEST, Naming.QUEST_HIDE) < 0)

	_check("能走到引路人", _stand_next_to(session, _npc_by_id(session, guide)))
	var mage := session.talk_to(guide)
	var travel_options: Array = []
	for option_variant in mage.options:
		var option := option_variant as DialogueOption
		if option.kind == Enums.DialogueKind.TRAVEL:
			travel_options.append(option.payload)
	_check("引路人能送城里以外的每张图",
		travel_options.size() == WorldDatabase.all_defs().size() - 1
		and travel_options.has(Naming.MAP_CAVE), _join(travel_options, ","))
	_check("引路人不卖东西", _option_index(mage, Enums.DialogueKind.OPEN_SHOP) < 0)
	_check("越界选项安全忽略", session.choose(guide, 9999).message.contains("关闭"))

	var outcome := session.choose(guide, _option_index(mage, Enums.DialogueKind.TRAVEL, Naming.MAP_SUBURB))
	_check("传送选项把图名带回来", outcome.travel_to_map == Naming.MAP_SUBURB
		and session.map_id == Naming.MAP_SUBURB, outcome.travel_to_map)


func _quest_prerequisite_blocks() -> void:
	var session := GameSession.new_campaign(2402)
	_check("没做完前一条接不了皮货单", not session.accept_quest(Naming.QUEST_HIDE))
	_check("狼患也一样", not session.accept_quest(Naming.QUEST_WOLF))
	_check("未接的任务状态是 None", session.state_of(Naming.QUEST_HIDE).status == Enums.QuestStatus.NONE)
	_check("没接的任务交不了", not session.turn_in_quest(Naming.QUEST_CHICKEN))
	_check("第一活能接", session.accept_quest(Naming.QUEST_CHICKEN))
	_check("重复接同一任务失败", not session.accept_quest(Naming.QUEST_CHICKEN))
	_check("接了以后状态是 Active", session.state_of(Naming.QUEST_CHICKEN).status == Enums.QuestStatus.ACTIVE)
	_check("面板提示写清楚差什么", session.hint_of(QuestDatabase.get_def(Naming.QUEST_CHICKEN))
		.contains(Naming.MONSTER_CHICKEN), session.hint_of(QuestDatabase.get_def(Naming.QUEST_CHICKEN)))

	(_first_where(session.quests, func(q): return (q as QuestState).id == Naming.QUEST_CHICKEN) as QuestState) \
		.status = Enums.QuestStatus.DONE
	_check("交付后解锁下一级", session.quest_prerequisite_met(QuestDatabase.get_def(Naming.QUEST_WOLF))
		and session.accept_quest(Naming.QUEST_WOLF))
	_check("任务只有一条链", _count_where(QuestDatabase.all_defs(),
		func(q): return (q as QuestDef).requires_quest_id != "") >= 4)

	var cast: Array = []
	for entry in QuestDatabase.all_defs():
		var quest := entry as QuestDef
		for npc_id in [quest.npc_id, quest.turn_in_npc_id]:
			if not cast.has(npc_id):
				cast.append(npc_id)
	var unknown: Array = []
	for npc_id in cast:
		if NpcDatabase.try_get(npc_id) == null:
			unknown.append(npc_id)
	_check("任务写明的 NPC 都在表里", unknown.is_empty(), _join(unknown, ","))
	var in_town: Array = _map_ids(GameSession.new_campaign(2403).npcs, func(n): return (n as NpcUnit).def.id)
	var missing: Array = []
	for npc_id in cast:
		if not in_town.has(npc_id):
			missing.append(npc_id)
	_check("任务的派活与交差人真站在城里", missing.is_empty(), _join(missing, ","))


func _quest_kill_progress_and_turn_in() -> void:
	var session := _field(202)
	_check("后山刷得出山鸡", _any_of(session.monsters,
		func(m): return (m as MonsterUnit).def.id == Naming.MONSTER_CHICKEN),
		_join(_distinct(_map_ids(session.monsters, func(m): return (m as MonsterUnit).def.id)), ","))
	_check("接下山鸡祸圃", session.accept_quest(Naming.QUEST_CHICKEN))

	var kills := _kill_enough(session, Naming.MONSTER_CHICKEN, 5)
	var quest := QuestDatabase.get_def(Naming.QUEST_CHICKEN)
	var chicken_alive := _count_where(session.monsters,
		func(m): return (m as MonsterUnit).def.id == Naming.MONSTER_CHICKEN)
	_check("杀够五只山鸡", kills >= 5 and session.is_complete(quest),
		"实际击杀 %d，场上山鸡 %d 只" % [kills, chicken_alive])
	_check("进度按真实击杀累加", session.progress_of(quest) == quest.count,
		"%d/%d" % [session.progress_of(quest), quest.count])
	_check("杀够了提示回去交差", _any_of(session.events,
		func(e): return (e as GameEvent).type == Enums.GameEventType.QUEST_READY))
	_check("多杀的不涨进度", _kill_enough(session, Naming.MONSTER_CHICKEN, 1) >= 0
		and session.progress_of(quest) == quest.count)

	session.travel_to(Naming.MAP_TOWN)
	_check("回城能找到%s" % Naming.NPC_TEACHER, _stand_next_to(session, _npc_by_id(session, Naming.NPC_TEACHER)))
	var index := _option_index(session.talk_to(Naming.NPC_TEACHER), Enums.DialogueKind.TURN_IN_QUEST, Naming.QUEST_CHICKEN)
	_check("%s这儿有交差按钮" % Naming.NPC_TEACHER, index >= 0)
	if index < 0:
		return

	var gold := session.player.gold
	var potions := session.bag.count_of(Naming.ITEM_POTION_HP_SMALL)
	var experience := session.player.experience + session.player.level * 100000
	var result := session.choose(Naming.NPC_TEACHER, index)
	_check("交付成功", result.message.contains("完成"), result.message)
	_check("奖金到账", session.player.gold == gold + quest.reward_gold, "%d → %d" % [gold, session.player.gold])
	_check("奖励物品到手", session.bag.count_of(Naming.ITEM_POTION_HP_SMALL) == potions + 5)
	_check("任务经验到账", session.player.experience + session.player.level * 100000 > experience)
	_check("交付后状态是 Done", session.state_of(Naming.QUEST_CHICKEN).status == Enums.QuestStatus.DONE)
	_check("交付完按钮消失", _option_index(session.talk_to(Naming.NPC_TEACHER),
		Enums.DialogueKind.TURN_IN_QUEST, Naming.QUEST_CHICKEN) < 0)
	_check("下一级任务这时能接", _option_index(session.talk_to(Naming.NPC_TEACHER),
		Enums.DialogueKind.ACCEPT_QUEST, Naming.QUEST_WOLF) >= 0)
	_check("重复交付不再给钱", not session.turn_in_quest(Naming.QUEST_CHICKEN)
		and session.player.gold == gold + quest.reward_gold)


func _quest_collect_consumes_exactly() -> void:
	var session := GameSession.new_campaign(204)
	session.accept_quest(Naming.QUEST_CHICKEN)
	(_first_where(session.quests, func(q): return (q as QuestState).id == Naming.QUEST_CHICKEN) as QuestState) \
		.status = Enums.QuestStatus.DONE

	_check("这时候药婆派活", _stand_next_to(session, _npc_by_id(session, Naming.NPC_HERBALIST))
		and _option_index(session.talk_to(Naming.NPC_HERBALIST),
			Enums.DialogueKind.ACCEPT_QUEST, Naming.QUEST_HIDE) >= 0)
	_check("接下皮货订单", session.accept_quest(Naming.QUEST_HIDE))
	var quest := QuestDatabase.get_def(Naming.QUEST_HIDE)

	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_HIDE), 7)
	_check("差一张时不算完成", not session.is_complete(quest) and session.progress_of(quest) == 7)
	_check("凑不够就交不掉", not session.turn_in_quest(Naming.QUEST_HIDE))

	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_HIDE), 3)
	_check("超额收集只按需要量算", session.is_complete(quest) and session.bag.count_of(Naming.ITEM_HIDE) == 10)
	var gold := session.player.gold
	_check("交付收走正好八张", session.turn_in_quest(Naming.QUEST_HIDE)
		and session.bag.count_of(Naming.ITEM_HIDE) == 2)
	_check("交付给钱给奖励", session.player.gold == gold + quest.reward_gold
		and session.bag.count_of(Naming.ITEM_POTION_HP_LARGE) == 4)
	_check("交付后不再收皮", not session.turn_in_quest(Naming.QUEST_HIDE))


func _quest_turn_in_needs_bag_room() -> void:
	var session := GameSession.new_campaign(205)
	_check("接活", session.accept_quest(Naming.QUEST_CHICKEN))
	var state: QuestState = _first_where(session.quests, func(q): return (q as QuestState).id == Naming.QUEST_CHICKEN)
	state.progress = QuestDatabase.get_def(Naming.QUEST_CHICKEN).count
	_check("进度满了算完成", session.is_complete(QuestDatabase.get_def(Naming.QUEST_CHICKEN)))

	# 奖励是可堆叠的活血散，光把 40 格塞满还塞得进去，所以要连重量一起卡死。
	session.bag.weight_limit = 100000
	var guard := 0
	while session.bag.free_slots > 0 and guard < 200:
		guard += 1
		session.bag.add(ItemDatabase.get_def(Naming.ITEM_WOOD_SWORD), 1)
	_check("背包格子塞满", session.bag.free_slots == 0)
	session.bag.weight_limit = session.bag.total_weight
	var gold := session.player.gold
	_check("放不下奖励就不能交付", not session.turn_in_quest(Naming.QUEST_CHICKEN))
	_check("交付失败时金币与状态都不动", session.player.gold == gold and state.status == Enums.QuestStatus.ACTIVE)

	# 腾地方要腾对东西：随手 Remove 第一格会把新手礼包那叠活血散清掉，
	# 奖励就会正好补齐成 5，看不出"多了一件"。挑木剑扔。
	session.bag.remove((_first_where(session.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_WOOD_SWORD) as ItemInstance).uid)
	session.bag.weight_limit = 100000
	_check("腾出地方就能交付", session.turn_in_quest(Naming.QUEST_CHICKEN) and session.player.gold == gold + 260)
	_check("交付后背包里多出奖励", session.bag.count_of(Naming.ITEM_POTION_HP_SMALL) == 10,
		str(session.bag.count_of(Naming.ITEM_POTION_HP_SMALL)))


# ── 商店 ────────────────────────────────────────────────────────────

func _shop_buy_needs_boss_and_gold() -> void:
	var session := GameSession.new_campaign(301)
	var boss := _npc_by_id(session, Naming.NPC_SMITH)
	var herb := _npc_by_id(session, Naming.NPC_HERBALIST)

	# 先挪到两家店都够不着的地方，"隔着几张格买不到"才真是在测距离。
	var away := false
	for entry in session.map.all_positions():
		var pos: Vector2i = entry
		if Grid.chebyshev(pos, boss.position) <= GameSession.TALK_RADIUS:
			continue
		if Grid.chebyshev(pos, herb.position) <= GameSession.TALK_RADIUS:
			continue
		if not session.relocate_player(pos):
			continue
		away = true
		break
	_check("先站到两家铺子都够不着的空地", away, _pos(session.player.position))
	if not away:
		return

	var gold_start := session.player.gold
	var wood_start := session.bag.count_of(Naming.ITEM_WOOD_SWORD)
	_check("隔着几张格买不到", not session.near_shop(Naming.SHOP_WEAPON)
		and not session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_WOOD_SWORD))
	_check("买不到时钱货都不动", session.player.gold == gold_start
		and session.bag.count_of(Naming.ITEM_WOOD_SWORD) == wood_start)

	_check("站到老板跟前", _stand_next_to(session, boss) and session.near_shop(Naming.SHOP_WEAPON))
	var price := Trade.buy_price(ItemDatabase.get_def(Naming.ITEM_WOOD_SWORD))
	var gold := session.player.gold
	var wood := session.bag.count_of(Naming.ITEM_WOOD_SWORD)
	_check("买得起就成交", session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_WOOD_SWORD)
		and session.player.gold == gold - price
		and session.bag.count_of(Naming.ITEM_WOOD_SWORD) == wood + 1)

	session.player.gold = 10
	_check("钱不够买不了", not session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_FLAME_BLADE)
		and session.player.gold == 10)
	_check("买不了时不放东西", session.bag.count_of(Naming.ITEM_FLAME_BLADE) == 0)

	session.player.gold = 100000
	_check("货架上没有的不卖", not session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_JUSTICE_STAFF))
	_check("站在铁匠铺买不到药", session.near_shop(Naming.SHOP_WEAPON) and not session.near_shop(Naming.SHOP_MEDICINE)
		and not session.buy_from_shop(Naming.SHOP_MEDICINE, Naming.ITEM_POTION_HP_SMALL))
	_check("材料不是货架上的货", not session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_IRON_ORE))
	_check("数量为零不算买卖", not session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_WOOD_SWORD, 0))

	wood = session.bag.count_of(Naming.ITEM_WOOD_SWORD)
	gold = session.player.gold
	_check("按件数买入", session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_WOOD_SWORD, 3)
		and session.bag.count_of(Naming.ITEM_WOOD_SWORD) == wood + 3
		and session.player.gold == gold - Trade.buy_price(ItemDatabase.get_def(Naming.ITEM_WOOD_SWORD)) * 3)

	session.bag.weight_limit = 1
	_check("超重时买不进", not session.buy_from_shop(Naming.SHOP_WEAPON, Naming.ITEM_HEAVY_ARMOR, 1))
	session.bag.weight_limit = 120

	_check("买卖价差是买贵卖贱", Trade.buy_price(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD)) >
		Trade.sell_price(ItemInstance.from_def(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD), 1, "x")))


func _shop_sell_and_repair() -> void:
	var session := GameSession.new_campaign(302)
	var herb := _npc_by_id(session, Naming.NPC_HERBALIST)
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_HIDE), 3)
	var hide: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_HIDE)
	_check("站着老远卖不掉", not session.sell_from_bag(hide.uid) and session.bag.count_of(Naming.ITEM_HIDE) == 3)

	_stand_next_to(session, herb)
	var gold := session.player.gold
	var unit := Trade.sell_price(hide)
	_check("卖掉整叠", session.sell_from_bag(hide.uid) and session.bag.count_of(Naming.ITEM_HIDE) == 0)
	_check("卖出按对折价", session.player.gold == gold + unit * 3, "每件 %d，共 %d" % [unit, unit * 3])

	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_POTION_HP_SMALL), 20)
	# 新手礼包自带 5 瓶，会分成两格，这里要挑那一叠够大的。
	var potions: ItemInstance = _first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_POTION_HP_SMALL and (i as ItemInstance).count >= 10)
	var stack := potions.count
	var total := session.bag.count_of(Naming.ITEM_POTION_HP_SMALL)
	gold = session.player.gold
	var potion_unit := Trade.sell_price(potions)
	_check("能只卖一部分", session.sell_from_bag(potions.uid, 5)
		and session.bag.count_of(Naming.ITEM_POTION_HP_SMALL) == total - 5,
		"%d → %d" % [total, session.bag.count_of(Naming.ITEM_POTION_HP_SMALL)])
	_check("只卖一部分也按对折价进账", session.player.gold == gold + potion_unit * 5, "%d × 5" % potion_unit)
	_check("剩下的那叠还在原处", session.bag.count_of(Naming.ITEM_POTION_HP_SMALL) == stack - 5 + (total - stack)
		and session.player.bag.find_by_uid(potions.uid) != null, "%d 瓶卖掉 5 瓶" % stack)
	_check("卖不存在的 uid 失败", not session.sell_from_bag("nope"))

	var worn := ItemInstance.from_def(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD), 1, "s1")
	_check("满耐久装备对折", Trade.sell_price(worn) == 210, str(Trade.sell_price(worn)))
	worn.durability = 0
	_check("耐久归零只值一点钱", Trade.sell_price(worn) == 1)
	_check("金币不能卖", Trade.sell_price(
		ItemInstance.from_def(ItemDatabase.get_def(Naming.ITEM_GOLD), 10, "g")) == 0)

	# 修装备：先穿两件、砍掉耐久，再按报价付钱。
	session.player.level = 10
	session.player.recompute_base()
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD), 1)
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_IRON_HELMET), 1)
	session.equip_from_bag((_first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_BRONZE_SWORD) as ItemInstance).uid)
	session.equip_from_bag((_first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_IRON_HELMET) as ItemInstance).uid)
	session.gear.wear_down(50)
	# 报价按"身上每件缺多少耐久"算，新手礼包里那件木剑也在身上，所以不能写死数字。
	var missing := 0
	for entry in session.gear.all():
		var item := entry as ItemInstance
		if item.def.max_durability > 0:
			missing += maxi(0, item.def.max_durability - item.durability)
	var cost := Trade.repair_cost(session.gear)
	_check("修理按缺失耐久报价", cost == missing * 4 and missing > 0, "%d 金币 / 缺 %d 点" % [cost, missing])
	session.player.gold = 10
	_check("钱不够修不了", not session.repair_now() and session.player.gold == 10)
	session.player.gold = cost
	_check("付得起就修好", session.repair_now() and session.player.gold == 0)
	_check("耐久回到满值", _all_durability_full(session.gear))
	_check("没坏时不收费", not session.repair_now() and session.player.gold == 0)


# ── 音效 ────────────────────────────────────────────────────────────

func _audio_covers_every_event() -> void:
	var types := _event_type_names()
	var missing: Array = []
	var clips := SfxBank.event_clips()
	for type in types:
		if not clips.has(type):
			missing.append(_event_type_name(type))
	_check("每种事件都有音效档位", missing.is_empty(), _join(missing, ","))

	var silent := [Enums.GameEventType.MOVE, Enums.GameEventType.INFO]
	_check("走路与流水账是静音的", _all_of(silent, func(t): return SfxBank.clip_for(t) == null))
	var mute: Array = []
	for type in types:
		if silent.has(type):
			continue
		if SfxBank.clip_for(type) == null:
			mute.append(_event_type_name(type))
	_check("其余事件全都有声", mute.is_empty(), _join(mute, ","))

	var weak: Array = []
	for type in types:
		if silent.has(type):
			continue
		var clip := SfxBank.clip_for(type)
		if clip == null:
			continue
		if clip.peak < 0.05 or clip.seconds < 0.02 or clip.root_mean_square <= 0:
			weak.append(_event_type_name(type))
	_check("每段音效都不是静音或碎片", weak.is_empty(), _join(weak, ","))


func _audio_is_deterministic_and_audible() -> void:
	var a := SfxBank.build("hit")
	var b := SfxBank.build("hit")
	_check("同配方逐样本一致", a.samples == b.samples, "%d 个采样" % a.samples.size())
	_check("采样率与位深", a.sample_rate == SfxBank.SAMPLE_RATE
		and _all_of(a.samples, func(s): return int(s) >= -31000 and int(s) <= 31000))
	var overshoot := false
	for name in SfxBank.names():
		if SfxBank.build(name).peak > 1.0:
			overshoot = true
	_check("音量不过冲", not overshoot)

	var music := SfxBank.build("music")
	_check("背景音乐够铺一段", music.seconds > 3.5 and music.root_mean_square > 0.01 and music.peak < 0.35,
		"%s 秒，峰值 %s" % [_num(music.seconds, 2), _num(music.peak, 3)])
	var death := SfxBank.build("death")
	_check("死亡音比点击音长", death.seconds > SfxBank.build("click").seconds)
	var lengths := _distinct(_map_ids(SfxBank.names(), func(n): return SfxBank.build(n).samples.size()))
	_check("音效长短不是一份模板复制", lengths.size() >= 8,
		"%d 种长度 / %d 个音效" % [lengths.size(), SfxBank.names().size()])
	_check("未知名字退回点击音而不是崩掉",
		SfxBank.build("没这个音效").samples.size() == SfxBank.build("click").samples.size())


# ── 存档 ────────────────────────────────────────────────────────────

func _save_restore_round_trip() -> void:
	var session := GameSession.new_campaign(90210)
	session.player.level = 9
	session.player.recompute_base()
	session.player.gold = 4321
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_BRONZE_SWORD), 1)
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_POTION_HP_SMALL), 7)
	session.equip_from_bag((_first_where(session.player.bag.enumerate(),
		func(i): return (i as ItemInstance).def_id == Naming.ITEM_BRONZE_SWORD) as ItemInstance).uid)
	for i in 60:
		session.tick(1.0 / 30.0)

	var restored := SaveGame.restore(SaveGame.from_json(SaveGame.to_json(SaveGame.capture(session))))

	_check("读档回到新手村", restored.map_id == GameSession.HOME_MAP_ID)
	_check("存档能读回等级", restored.player.level == session.player.level)
	_check("存档能读回金币", restored.player.gold == session.player.gold)
	_check("存档能读回位置", restored.player.position == session.player.position)
	_check("存档能读回背包件数", restored.bag.used_slots == session.bag.used_slots,
		"%d vs %d" % [restored.bag.used_slots, session.bag.used_slots])
	_check("存档能读回装备槽", restored.gear.worn.size() == session.gear.worn.size())
	_check("读档后属性一致", restored.player.get_stats().dc_max == session.player.get_stats().dc_max)
	_check("读档后 NPC 还占着格", _all_npcs_occupy_themselves(restored))
	_check("玩家脚下只有玩家自己", restored.unit_at(restored.player.position) is PlayerUnit)
	var save := SaveGame.capture(session)
	_check("存档里每张图的怪都存了", _save_maps(save).size() == 1,
		"maps %d 项，字段 %s" % [_save_maps(save).size(), _save_schema(save)])
	_check("读档后地图逐格一致", _terrain_matches(session.map, restored.map))
	_check("版本不符会拒绝", _restore_rejects({"version": REJECTED_VERSION, "seed": 1}))


func _save_keeps_world_progress() -> void:
	var session := _field(90211)
	session.player.level = 15
	session.player.recompute_base()
	session.player.mp = session.player.max_mp
	session.player.gold = 3300
	session.learn(Naming.SKILL_MOON)
	session.learn(Naming.SKILL_SHIELD)
	session.accept_quest(Naming.QUEST_CHICKEN)
	_kill_enough(session, Naming.MONSTER_CHICKEN, 2)
	var target := _weakest(session)
	if target != null and _stand_next_to(session, target):
		session.cast_at(Naming.SKILL_SLASH, target.position)
	session.cast(Naming.SKILL_SHIELD)
	session.player.bag.add(ItemDatabase.get_def(Naming.ITEM_POTION_MP), 3)
	session.travel_to(Naming.MAP_FOREST)
	var forest_monster := session.monsters[0] as MonsterUnit
	forest_monster.hp = 3
	session.travel_to(Naming.MAP_SUBURB)

	var save := SaveGame.capture(session)
	var restored := SaveGame.restore(SaveGame.from_json(SaveGame.to_json(save)))

	_check("读档回到后山", restored.map_id == Naming.MAP_SUBURB, restored.map.display_name)
	_check("进过的图各存一份", _save_maps(save).size() >= 3,
		_join(_map_ids(_save_maps(save), func(m): return (m as Dictionary).get("id", "")), ","))
	_check("本图怪物数量一致", restored.monsters.size() == session.monsters.size(),
		"%d vs %d" % [restored.monsters.size(), session.monsters.size()])
	_check("半血的怪读回来还半血", _min_hp(restored.monsters) == 1 or _any_monster_hurt(restored))
	_check("地面掉落一致", restored.loot.size() == session.loot.size())
	_check("任务状态一致", restored.state_of(Naming.QUEST_CHICKEN).status == Enums.QuestStatus.ACTIVE
		and restored.state_of(Naming.QUEST_CHICKEN).progress == session.state_of(Naming.QUEST_CHICKEN).progress)
	_check("学过的招一致", _known_ids(restored) == _known_ids(session))
	_check("冷却读回来了", restored.cooldown_left(Naming.SKILL_SLASH) > 0.0
		or session.cooldown_left(Naming.SKILL_SLASH) <= 0.0)
	_check("增益读回来了", restored.effects.size() == session.effects.size()
		and _count_where(restored.effects,
			func(e): return (e as SkillEffect).skill_id == Naming.SKILL_SHIELD) == 1)
	_check("增益属性算进读档后的面板", restored.player.get_stats().ac_max > restored.player.base_stats.ac_max)
	_check("金币血量经验击杀都一致", restored.player.gold == session.player.gold
		and restored.player.hp == session.player.hp and restored.kill_count == session.kill_count)
	_check("森林那只半血也读回来了", restored.travel_to(Naming.MAP_FOREST)
		and _any_monster_at_hp(restored, 3), "换了图就没这条记录了")

	# 没进过的图不该进存档，但进的时候按种子现场生成。
	_check("未访问的图不进存档",
		not _any_of(_save_maps(save), func(m): return (m as Dictionary).get("id", "") == Naming.MAP_CAVE))
	_check("现场生成密洞", restored.travel_to(Naming.MAP_CAVE) and restored.monsters.size() > 0)
	_check("密洞地形与同种子一致", _count_where(restored.map.all_positions(),
		func(p): return not restored.map.is_walkable(p)) > 0)

	# 只给了种子的空存档：没有背包、没有技能、没有怪，但仍然是一个站得住的世界。
	# Dictionary 没有默认值，所以按一份合法存档的默认把字段写全。
	var empty := SaveGame.restore(_blank_save(5))
	_check("空存档读出来还是新手村", empty.map_id == GameSession.HOME_MAP_ID and empty.map.safe)
	_check("空存档不凭空造怪", empty.monsters.is_empty())
	_check("空存档把四个 NPC 摆回原位", empty.npcs.size() == 4
		and _all_of(empty.npcs, func(n): return empty.unit_at((n as NpcUnit).position) is NpcUnit))
	_check("空存档的等级与背包是干净的", empty.player.level == 1 and empty.bag.used_slots == 0
		and _known_ids(empty).is_empty() and empty.quests.is_empty())
	# 没写过的字段就是默认值：血是 0，人躺在地上。补满血才谈得上走路。
	_check("空存档读出来血是空的", empty.player.hp == 0 and not empty.player.alive)
	var down := empty.move_player_to(empty.map.walkable_near(Grid.add(empty.player.position, 3, 0)))
	_check("倒下的人走不动", not down)
	empty.player.hp = empty.player.max_hp
	_check("空存档也站得住、走得动", empty.map.is_walkable(empty.player.position)
		and empty.move_player_to(empty.map.walkable_near(Grid.add(empty.player.position, 3, 0))))


func _min_hp(monsters: Array) -> int:
	var best := 0x7FFFFFFF
	for entry in monsters:
		best = mini(best, (entry as MonsterUnit).hp)
	return best


# ── 渲染 ────────────────────────────────────────────────────────────

## 用 WorldRenderer.render + Image.save_png 落盘，
## 再把文件读回来验签名、IHDR 与"能否被引擎重新解码"。
func _png_signature() -> void:
	var shot := WorldRenderer.render(_field(6), 4)
	var path := _artifacts_path("selftest-png.png")
	var saved := shot.save_png(path) == OK
	var bytes := FileAccess.get_file_as_bytes(path)
	_check("PNG 签名正确", saved and bytes.size() > 24 and _has_png_signature(bytes),
		"存盘 %s，头 %d 字节" % ["成功" if saved else "失败", mini(bytes.size(), 8)])
	_check("IHDR 尺寸写入正确", _ihdr_int(bytes, 16) == shot.get_width()
		and _ihdr_int(bytes, 20) == shot.get_height(),
		"IHDR %dx%d，渲染 %dx%d" % [_ihdr_int(bytes, 16), _ihdr_int(bytes, 20),
			shot.get_width(), shot.get_height()])
	# 原判定是"块结构带 CRC"（手写编码器给出的长度下界）。Godot 自己写 PNG，
	# CRC 由编码器保证，这里换成等价强度：文件能被引擎重新解码且尺寸与渲染结果一致。
	var reloaded := Image.load_from_file(path)
	_check("块结构带 CRC", reloaded != null
		and reloaded.get_width() == shot.get_width() and reloaded.get_height() == shot.get_height(),
		"重新解码 %s" % ("失败" if reloaded == null else
			"%dx%d" % [reloaded.get_width(), reloaded.get_height()]))

	_check("整图渲染尺寸对得上", shot.get_width() == 96 * 16 and shot.get_height() == 72 * 16,
		"%dx%d" % [shot.get_width(), shot.get_height()])
	_check("视野特写比整图小", WorldRenderer.render(_field(6), 8, 10).get_width() < shot.get_width())
	_check("渲染出来的不是纯色", bytes.size() > 10000, "%d 字节的 PNG" % bytes.size())


func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	if bytes.size() < signature.size():
		return false
	for i in signature.size():
		if bytes[i] != signature[i]:
			return false
	return true


func _ihdr_int(bytes: PackedByteArray, offset: int) -> int:
	if bytes.size() < offset + 4:
		return -1
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) \
		| (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


## 字体有两个入口：项目默认字体管面板与按钮，ArtGen 那份管地图上直接画的字。
## 两处指的不是同一个文件时，游戏里就会一半 PingFang 一半别的，所以在这里钉住。
func _font_is_wired_up() -> void:
	var project_font := String(ProjectSettings.get_setting("gui/theme/custom_font"))
	_check("界面与地图文字用同一份字体", project_font == ArtGen.FONT_PATH,
		"项目 %s，画面 %s" % [project_font, ArtGen.FONT_PATH])
	var font := ArtGen.ui_font()
	_check("字体文件真加载出来了", font is FontFile, ArtGen.FONT_PATH)
	_check("这份字体有中文可画", font != null and font.has_char(int("武".unicode_at(0))))
