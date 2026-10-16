class_name GameSession
extends RefCounted

# 一局游戏的运行时。表现层只调用这里，逻辑全部与引擎无关。

const HOME_MAP_ID := Naming.MAP_TOWN
const TALK_RADIUS := 3

## 斜着走一格的路程是 √2 格。进度要按路程攒，否则斜走比直走快四成，
## 而 8 向寻路的路径必然直斜混排，走起来就是一冲一顿。
const DIAGONAL_STEP := 1.4142135623730951

var player: PlayerUnit
var seed := 0
var elapsed := 0.0
var kill_count := 0

var _runtimes := {}
var _rng: Rng
var _events: Array = []
var _cooldowns := {}
var _learned := {}
var _quests: Array = []
var _current: MapRuntime
var _player_path: Array = []
var _move_progress := 0.0
var _player_attack_cooldown := 0.0
var _next_uid := 1


func _init(p_seed: int) -> void:
	seed = p_seed
	_rng = Rng.new(p_seed)

	var home := _runtime(WorldDatabase.get_def(HOME_MAP_ID))
	# 出生点可能正好被 NPC 占了（城里广场就是 NPC 站的地方）。
	var start: Variant = _find_free_spot_in(home, home.map.spawn)
	if start == null:
		start = home.map.spawn
	player = PlayerUnit.new(start)
	_current = home
	home.occupancy[start] = player

	_learn_auto_skills(true)
	_give_starting_kit()
	_raise(Enums.GameEventType.INFO, "进入 %s" % _current.map.display_name, player.position, 0)


static func new_campaign(p_seed: int) -> GameSession:
	return GameSession.new(p_seed)


# ── 查询 ──────────────────────────────────────────────────────────────

var map_id: String:
	get:
		return _current.def.id


var map: GameMap:
	get:
		return _current.map


var definition: MapDef:
	get:
		return _current.def


var monsters: Array:
	get:
		return _current.monsters


var loot: Array:
	get:
		return _current.loot


var npcs: Array:
	get:
		return _current.npcs


var events: Array:
	get:
		return _events


var quests: Array:
	get:
		return _quests


var bag: Inventory:
	get:
		return player.bag


var gear: Equipment:
	get:
		return player.gear


var player_alive: bool:
	get:
		return player.alive


var known_skills: Array:
	get:
		var out: Array = []
		for def in SkillDatabase.ordered():
			if _learned.has(def.id):
				out.append(def)
		return out


var cooldowns: Dictionary:
	get:
		return _cooldowns


var effects: Array:
	get:
		return player.effects


func unit_at(pos: Vector2i) -> Unit:
	return _current.occupancy.get(pos)


func loot_at(pos: Vector2i) -> LootItem:
	for entry in _current.loot:
		if (entry as LootItem).position == pos:
			return entry
	return null


func is_walkable(pos: Vector2i) -> bool:
	var blocker: Unit = _current.occupancy.get(pos)
	return map.is_walkable(pos) and (blocker == null or blocker == player)


## 供渲染层判断格子是否被单位占住。
func state_at(pos: Vector2i) -> int:
	if not map.is_walkable(pos):
		return Enums.CellState.BLOCKED
	return Enums.CellState.OCCUPIED if _current.occupancy.has(pos) else Enums.CellState.WALKABLE


func nearest_monster(from: Vector2i, max_distance: int) -> MonsterUnit:
	var candidates: Array = []
	for entry in _current.monsters:
		var monster := entry as MonsterUnit
		if monster.alive and Grid.chebyshev(from, monster.position) <= max_distance:
			candidates.append(monster)
	if candidates.is_empty():
		return null
	var sorted := order_by(candidates, [func(m) -> int: return Grid.manhattan(m.position, from)])
	return sorted[0]


func monsters_around(center: Vector2i, radius: int) -> Array:
	var candidates: Array = []
	for entry in _current.monsters:
		var monster := entry as MonsterUnit
		if monster.alive and Grid.chebyshev(center, monster.position) <= radius:
			candidates.append(monster)
	return order_by(candidates, [func(m) -> int: return Grid.manhattan(m.position, center)])


# ── 地图与传送 ────────────────────────────────────────────────────────

## 按需生成：不预铺四张图，进过哪张存哪张。
func _runtime(def: MapDef) -> MapRuntime:
	if _runtimes.has(def.id):
		return _runtimes[def.id]
	var generated := MapGenerator.create(def, seed)
	var runtime := MapRuntime.new()
	runtime.def = def
	runtime.map = generated
	runtime.rng = Rng.new((MapGenerator.seed_for(seed, def.id) ^ 0x5BD1E995) & 0xFFFFFFFF)
	_populate_npcs(runtime)
	_populate_monsters(runtime)
	_runtimes[def.id] = runtime
	return runtime


static func _populate_npcs(runtime: MapRuntime) -> void:
	for npc_id in runtime.map.npc_positions:
		var pos: Vector2i = runtime.map.npc_positions[npc_id]
		var def := NpcDatabase.try_get(npc_id)
		if def == null:
			continue
		var npc := NpcUnit.new(def, pos)
		runtime.npcs.append(npc)
		# 占位是为了"不能穿人而过"，而不是为了能被攻击。
		if not runtime.occupancy.has(pos):
			runtime.occupancy[pos] = npc


static func _populate_monsters(runtime: MapRuntime) -> void:
	if runtime.def.safe or runtime.def.monster_ids.is_empty():
		return

	var by_level: Array = []
	for monster_id in runtime.def.monster_ids:
		by_level.append(MonsterDatabase.get_def(monster_id))
	by_level = order_by(by_level, [func(d) -> int: return d.level])

	var spots: Array = []
	for pos in runtime.map.monster_spawns:
		spots.append(pos)
	spots = order_by(spots, [func(p) -> int: return Grid.chebyshev(p, runtime.map.spawn)])
	if spots.is_empty():
		return

	# 把"离出生点由近及远"的刷怪点等分成几段，一段一种怪：
	# 难度天然递增，而且每种怪保证刷得出来。用距离比例换算档位时，
	# 最近一段往往落不进第一档，武馆后山就会一只山鸡都见不到。
	var wanted := mini(runtime.def.monster_count, spots.size())
	var per_type := maxi(1, int(ceil(float(wanted) / float(by_level.size()))))
	var placed := 0
	for requested in spots:
		if placed >= wanted:
			break
		var spot: Variant = _find_free_spawn(runtime, requested)
		if spot == null:
			continue
		var index := mini(by_level.size() - 1, placed / per_type)
		# 偶尔错一档，让边界不那么整齐，但不改变"越远越凶"的大方向。
		if runtime.rng.chance(0.2):
			index = clampi(index + runtime.rng.next_range(-1, 2), 0, by_level.size() - 1)
		var monster := MonsterUnit.new(by_level[index], spot)
		runtime.monsters.append(monster)
		runtime.occupancy[spot] = monster
		placed += 1


## 踩上门格就走图。回来时落在对面那扇门内侧，玩家永远找得回路。
func travel_to(to_map_id: String) -> bool:
	if to_map_id == map_id:
		return false
	var def := WorldDatabase.try_get(to_map_id)
	if def == null:
		_raise(Enums.GameEventType.INFO, "去不了那儿：%s" % to_map_id, player.position, 0)
		return false
	return _travel(def, false)


func _travel(def: MapDef, quiet: bool) -> bool:
	var from := map_id
	var target := _runtime(def)
	_current.occupancy.erase(player.position)
	_player_path.clear()
	_move_progress = 0.0
	_current = target

	var arrival := target.map.arrival_for(from)
	var spot: Variant = _find_free_spot_in(target, arrival)
	if spot == null:
		spot = arrival
	target.occupancy[spot] = player
	player.position = spot
	player.facing = Enums.Direction.DOWN
	if not quiet:
		_raise(Enums.GameEventType.TRAVEL, "到了 %s" % target.map.display_name, spot, 0)
	return true


func _try_use_exit(pos: Vector2i) -> void:
	var found := map.exit_at(pos)
	if found == null:
		return
	var def := WorldDatabase.try_get(found.to_map)
	if def == null:
		return
	_travel(def, false)


## 按 T：用脚下或身边的门。
func use_nearest_exit() -> bool:
	var nearby: Array = []
	for candidate in map.exits:
		if Grid.chebyshev(player.position, candidate.at) <= 1:
			nearby.append(candidate)
	if nearby.is_empty():
		_raise(Enums.GameEventType.INFO, "附近没有出口", player.position, 0)
		return false
	nearby = order_by(nearby, [func(e) -> int: return Grid.manhattan(e.at, player.position)])
	return travel_to(nearby[0].to_map)


# ── 移动 ──────────────────────────────────────────────────────────────

## 点击寻路。目标格被人或地形占住时，自动改成走到它旁边最近的空格——
## 否则"点怪物的格子"永远走不过去。返回 false 表示真的无路可走。
func move_player_to(target: Vector2i) -> bool:
	if not player.alive or not map.in_bounds(target):
		return false

	var destination: Variant = target if is_walkable(target) else _find_free_spot_near(target)
	if destination == null:
		_raise(Enums.GameEventType.BLOCKED, "走不过去", target, 0)
		return false

	var path := Pathfinding.find(map, _is_blocked_for_player, player.position, destination)
	if path.size() <= 1:
		_raise(Enums.GameEventType.BLOCKED, "走不过去", target, 0)
		return false

	var new_path := path.slice(1)
	# 按住鼠标/每帧重复点击时不能把进度清零，否则永远迈不完一格，角色看起来像卡住。
	if _player_path.is_empty() or new_path.is_empty() or _player_path[0] != new_path[0]:
		_move_progress = 0.0
	_player_path = new_path
	return true


static func _find_spot_near(requested: Vector2i, is_free: Callable, radius := 4) -> Variant:
	for ring in range(1, radius + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var candidate := requested + Vector2i(dx, dy)
				if is_free.call(candidate):
					return candidate
	return null


func _find_free_spot_near(requested: Vector2i) -> Variant:
	return _find_spot_near(requested, is_walkable)


static func _find_free_spot_in(runtime: MapRuntime, requested: Vector2i) -> Variant:
	var free := func(pos: Vector2i) -> bool:
		return runtime.map.is_walkable(pos) and not runtime.occupancy.has(pos)
	if free.call(requested):
		return requested
	return _find_spot_near(requested, free, 6)


func _is_blocked_for_player(pos: Vector2i) -> bool:
	var blocker: Unit = _current.occupancy.get(pos)
	return blocker != null and blocker != player


## 空格才算"能站"——追玩家时目标必须退到玩家旁边的空格，否则寻路直接返回空路径。
static func _is_free_for_monster(runtime: MapRuntime, pos: Vector2i) -> bool:
	return runtime.map.is_walkable(pos) and not runtime.occupancy.has(pos)


## 参数顺序是 (pos, monster)：Pathfinding 以 Callable(pos) 调用，bind(monster) 会把 monster 追加到末尾。
func _is_blocked_for_monster(pos: Vector2i, monster: MonsterUnit) -> bool:
	if not _current.map.is_walkable(pos):
		return true
	var blocker: Unit = _current.occupancy.get(pos)
	return blocker != null and blocker != monster


## 方向键单步移动，斜走同样不允许穿墙角。
func step_player(direction: int) -> bool:
	if not player.alive:
		return false
	var next := Grid.offset(player.position, direction)
	player.facing = direction
	if not map.is_walkable(next):
		_raise(Enums.GameEventType.BLOCKED, "%s 挡住去路" % Enums.terrain_name(map.terrain_at(next)), next, 0)
		return false
	var blocker: Unit = _current.occupancy.get(next)
	if blocker != null and blocker != player:
		# 撞到怪不算失败，改成攻击它更符合点击手感。
		if blocker is MonsterUnit and blocker.is_attackable():
			return attack_target(blocker as MonsterUnit)
		# 撞到 NPC 不能自动开对话：走路上撞到人就弹面板太吵，只提示一句。
		if blocker is NpcUnit:
			_raise(Enums.GameEventType.INFO, "%s 站在这儿，按 F 和他说话" % blocker.name, next, 0)
			return false
		_raise(Enums.GameEventType.BLOCKED, "%s 站在这里" % blocker.name, next, 0)
		return false
	_move_unit_to(player, next)
	_player_path.clear()
	_after_player_moved()
	return true


## 瞬移（读档、测试、任务演出都用它）。目标不可走或有人站着就失败。
func relocate_player(target: Vector2i) -> bool:
	var spot: Vector2i = map.walkable_near(target)
	var blocker: Unit = _current.occupancy.get(spot)
	if blocker != null and blocker != player:
		return false
	_player_path.clear()
	_move_unit_to(player, spot)
	return true


func _move_unit_to(unit: Unit, target: Vector2i) -> void:
	_current.occupancy.erase(unit.position)
	unit.position = target
	_occupy(unit)


func _occupy(unit: Unit) -> void:
	_current.occupancy[unit.position] = unit


## 走到新格之后该发生的事：捡东西、踩传送门。
func _after_player_moved() -> void:
	pick_up_at(player.position)
	_try_use_exit(player.position)


# ── 战斗 ──────────────────────────────────────────────────────────────

## 点击攻击：目标格上有怪就打它，没有则打范围内最近的。
func attack_target_at(target: Vector2i) -> bool:
	if not player.alive:
		return false
	var unit: Unit = _current.occupancy.get(target)
	if unit is MonsterUnit and (unit as MonsterUnit).is_attackable():
		return attack_target(unit as MonsterUnit)
	var nearest := nearest_monster(player.position, 2)
	return nearest != null and attack_target(nearest)


func attack_target(monster: MonsterUnit) -> bool:
	if not player.alive or not monster.alive or not monster.is_attackable():
		return false

	player.facing = Grid.facing_towards(player.position, monster.position)
	if Grid.chebyshev(player.position, monster.position) > 1:
		# 距离不够就先追过去，逻辑上等价于"点击怪物 = 走过去砍"。
		return _step_toward(monster.position)
	if _player_attack_cooldown > 0.0:
		return false

	_player_attack_cooldown = player.attack_delay
	var result := Combat.resolve(_rng, player, monster)
	if not result.hit:
		_raise(Enums.GameEventType.MISS, "%s 躲开了" % monster.name, monster.position, 0)
		return true

	var suffix := " 暴击" if result.critical else ""
	_raise(Enums.GameEventType.ATTACK, "%s -%d%s" % [monster.name, result.damage, suffix],
		monster.position, result.damage)
	if result.killed:
		_on_monster_killed(monster)
	return true


## 朝目标逼近一格；供"攻击但太远"和怪物追击共用。
func _step_toward(target: Vector2i) -> bool:
	var best := Vector2i.ZERO
	var best_distance := 0x7FFFFFFF
	var found := false
	for d in 8:
		var candidate := Grid.offset(player.position, d)
		if not is_walkable(candidate):
			continue
		var distance := Grid.chebyshev(candidate, target)
		if distance < best_distance:
			best_distance = distance
			best = candidate
			found = true
	if not found or best_distance >= Grid.chebyshev(player.position, target):
		return false
	player.facing = Grid.facing_towards(player.position, target)
	_move_unit_to(player, best)
	_after_player_moved()
	return true


func _on_monster_killed(monster: MonsterUnit) -> void:
	kill_count += 1
	_current.occupancy.erase(monster.position)
	_raise(Enums.GameEventType.KILL, "击杀 %s" % monster.name, monster.position, monster.def.experience)

	var levels := player.gain_experience(monster.def.experience)
	if levels > 0:
		_raise(Enums.GameEventType.LEVEL_UP, "升到 %d 级" % player.level, player.position, player.level)
		_learn_auto_skills(false)

	_advance_kill_quests(monster.def.id)
	_drop_loot(monster)
	monster.aggro = false
	monster.respawn_seconds = 12.0 + float(_current.rng.next(8))
	monster.position = monster.home


func _drop_loot(monster: MonsterUnit) -> void:
	var gold := _current.rng.next_inclusive(monster.def.gold_min,
		maxi(monster.def.gold_min, monster.def.gold_max))
	if gold > 0:
		_current.loot.append(LootItem.new(_new_instance(Naming.ITEM_GOLD, gold), monster.position))

	for item in Combat.roll_drops(_current.rng, monster.def, _take_uid):
		var spot: Variant = _free_spot_near(monster.position)
		_current.loot.append(LootItem.new(item, monster.position if spot == null else spot))


func _free_spot_near(center: Vector2i) -> Variant:
	for radius in range(0, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var candidate := center + Vector2i(dx, dy)
				if not map.is_walkable(candidate) or _current.occupancy.has(candidate):
					continue
				var occupied_by_loot := false
				for entry in _current.loot:
					if (entry as LootItem).position == candidate:
						occupied_by_loot = true
						break
				if not occupied_by_loot:
					return candidate
	return null


# ── 技能 ──────────────────────────────────────────────────────────────

func knows(skill_id: String) -> bool:
	return _learned.has(skill_id)


## 快捷键就是"已学列表里的第 N 个"，学新招会自动往后排。
func hotkey_of(skill_id: String) -> int:
	var ids: Array = []
	for def in known_skills:
		ids.append(def.id)
	var index := ids.find(skill_id)
	return 0 if index < 0 else index + 1


func skill_at_hotkey(hotkey: int) -> String:
	var skills := known_skills
	if hotkey >= 1 and hotkey <= skills.size():
		return skills[hotkey - 1].id
	return ""


func cooldown_left(skill_id: String) -> float:
	return _cooldowns.get(skill_id, 0.0)


func _learn_auto_skills(silent: bool) -> void:
	for skill in SkillDatabase.auto_learned(player.level):
		learn(skill.id, silent)


func learn(skill_id: String, silent := false) -> bool:
	var def := SkillDatabase.try_get(skill_id)
	if def == null:
		return false
	if _learned.has(def.id):
		return false
	_learned[def.id] = true
	_cooldowns[def.id] = 0.0
	if not silent:
		_raise(Enums.GameEventType.LEARN, "学会 %s" % def.display_name, player.position, 0)
	return true


## 返回空串表示可以施放。
func can_cast(skill_id: String) -> String:
	if not player.alive:
		return "已经倒下"
	if not knows(skill_id):
		return "还没学会这招"
	var def := SkillDatabase.get_def(skill_id)
	if player.level < def.required_level:
		return "%s 需要 %d 级" % [def.display_name, def.required_level]
	if cooldown_left(skill_id) > 0.0:
		return "%s 还在冷却" % def.display_name
	if player.mp < def.mp_cost:
		return "内力不够"
	return ""


## 不带坐标的施放（快捷键）：目标类技能自动打最近的怪。
func cast(skill_id: String) -> SkillCast:
	var nearest := nearest_monster(player.position, 999)
	return cast_at(skill_id, nearest.position if nearest != null else player.position)


func cast_at(skill_id: String, aim: Vector2i) -> SkillCast:
	var reason := can_cast(skill_id)
	if reason != "":
		return SkillCast.make(false, reason, 0, 0)
	var def := SkillDatabase.get_def(skill_id)

	match def.kind:
		Enums.SkillKind.HEAL:
			return _cast_heal(def)
		Enums.SkillKind.BUFF:
			return _cast_buff(def)
		Enums.SkillKind.SWEEP:
			return _cast_sweep(def)
		_:
			return _cast_single(def, aim)


func _cast_single(def: SkillDef, aim: Vector2i) -> SkillCast:
	# 先认"指点的那只怪"，落空了就退到射程内离准星最近的一只——快捷键没有坐标时也走这条路。
	var ranked := monsters_around(player.position, def.reach)
	ranked = order_by(ranked, [
		func(m) -> int: return 0 if m.position == aim else 1,
		func(m) -> int: return Grid.manhattan(m.position, aim),
	])
	if ranked.is_empty():
		return SkillCast.make(false, "射程内没有目标" if def.kind == Enums.SkillKind.BOLT else "够不着目标", 0, 0)
	var target: MonsterUnit = ranked[0]

	var result := Combat.resolve(_rng, player, target, def)
	_spend_mana(def)
	if not result.hit:
		_raise(Enums.GameEventType.MISS, "%s 被 %s 躲开" % [def.display_name, target.name], target.position, 0)
		return SkillCast.make(true, "", 0, 0)
	_raise(Enums.GameEventType.SKILL, "%s 命中 %s" % [def.display_name, target.name], target.position, result.damage)
	var suffix := " 暴击" if result.critical else ""
	_raise(Enums.GameEventType.ATTACK, "%s -%d%s" % [target.name, result.damage, suffix], target.position, result.damage)
	if result.killed:
		_on_monster_killed(target)
	return SkillCast.make(true, "", result.damage, 1)


func _cast_sweep(def: SkillDef) -> SkillCast:
	var targets := monsters_around(player.position, def.reach)
	if targets.is_empty():
		return SkillCast.make(false, "身边没有敌人", 0, 0)

	_spend_mana(def)
	var total := 0
	for entry in targets:
		var target := entry as MonsterUnit
		var result := Combat.resolve(_rng, player, target, def)
		if result.hit:
			total += result.damage
			_raise(Enums.GameEventType.ATTACK, "%s %s -%d" % [def.display_name, target.name, result.damage],
				target.position, result.damage)
		else:
			_raise(Enums.GameEventType.MISS, "%s 落空" % def.display_name, target.position, 0)
		if result.killed:
			_on_monster_killed(target)
	_raise(Enums.GameEventType.SKILL, "%s 扫中 %d 个目标" % [def.display_name, targets.size()], player.position, total)
	return SkillCast.make(true, "", total, targets.size())


func _cast_heal(def: SkillDef) -> SkillCast:
	_spend_mana(def)
	var missing := player.max_hp - player.hp
	var amount := mini(missing, maxi(1, player.max_hp * def.heal_percent / 100))
	player.hp += amount
	_raise(Enums.GameEventType.SKILL, "%s 回复 %d 生命" % [def.display_name, amount], player.position, amount)
	return SkillCast.make(true, "", amount, 0)


func _cast_buff(def: SkillDef) -> SkillCast:
	_spend_mana(def)
	for i in range(player.effects.size() - 1, -1, -1):
		if (player.effects[i] as SkillEffect).skill_id == def.id:
			player.effects.remove_at(i)
	var effect := SkillEffect.new()
	effect.skill_id = def.id
	effect.title = def.display_name
	effect.bonus = def.buff.clone()
	effect.remaining = def.buff_seconds
	player.effects.append(effect)
	_raise(Enums.GameEventType.BUFF, "%s：%d 秒内防御提升" % [def.display_name, int(def.buff_seconds)],
		player.position, 0)
	return SkillCast.make(true, "", 0, 0)


func _spend_mana(def: SkillDef) -> void:
	player.mp = maxi(0, player.mp - def.mp_cost)
	_cooldowns[def.id] = def.cooldown


# ── NPC、对话与任务 ───────────────────────────────────────────────────

func npc_at(pos: Vector2i) -> NpcUnit:
	for entry in _current.npcs:
		if (entry as NpcUnit).position == pos:
			return entry
	return null


## 能对话的距离。点人得站得近，隔一张图说话不叫角色扮演。
func nearest_npc(from: Vector2i, max_distance := TALK_RADIUS) -> NpcUnit:
	var candidates: Array = []
	for entry in _current.npcs:
		var npc := entry as NpcUnit
		if Grid.chebyshev(from, npc.position) <= max_distance:
			candidates.append(npc)
	if candidates.is_empty():
		return null
	var sorted := order_by(candidates, [func(n) -> int: return Grid.manhattan(n.position, from)])
	return sorted[0]


## 算出这一刻该对他说什么、能点什么。UI 拿这个直接摆按钮。
func talk_to(npc_id: String, quiet := false) -> NpcDialogue:
	var def := NpcDatabase.try_get(npc_id)
	if def == null:
		return null
	var unit := _npc_by_id(npc_id)
	if unit == null:
		return null

	var options: Array = []
	if Grid.chebyshev(player.position, unit.position) > TALK_RADIUS:
		var dialogue := NpcDialogue.new()
		dialogue.npc_id = npc_id
		dialogue.text = "先走到 %s 跟前再说话。" % def.display_name
		dialogue.options = [DialogueOption.make(Enums.DialogueKind.CLOSE, "知道了", "")]
		return dialogue

	# choose 会再算一次同一份对话，别把"和某某说话"记两遍。
	if not quiet:
		_raise(Enums.GameEventType.TALK, "和 %s 说话" % def.display_name, unit.position, 0)

	for quest in QuestDatabase.offered_by(npc_id):
		var state := state_of(quest.id)
		if state.status == Enums.QuestStatus.NONE and quest_prerequisite_met(quest):
			options.append(DialogueOption.make(Enums.DialogueKind.ACCEPT_QUEST, "接任务：%s" % quest.display_name, quest.id))

	for quest in QuestDatabase.turned_in_at(npc_id):
		if state_of(quest.id).status == Enums.QuestStatus.ACTIVE and is_complete(quest):
			options.append(DialogueOption.make(Enums.DialogueKind.TURN_IN_QUEST, "交付：%s" % quest.display_name, quest.id))

	# 挂在别处交付的任务也提一句进度，否则玩家会以为 NPC 忘了这回事。
	for quest in QuestDatabase.offered_by(npc_id):
		var state := state_of(quest.id)
		if state.status == Enums.QuestStatus.ACTIVE and quest.turn_in_npc_id != npc_id:
			options.append(DialogueOption.make(Enums.DialogueKind.TALK,
				"（%s：%s）" % [quest.display_name, hint_of(quest)], ""))

	var shop: ShopDef = ShopDatabase.try_get(def.shop_id) if def.shop_id != "" else null
	if shop != null:
		options.append(DialogueOption.make(Enums.DialogueKind.OPEN_SHOP, "看看%s" % shop.display_name, def.shop_id))
	if def.can_repair:
		options.append(DialogueOption.make(Enums.DialogueKind.REPAIR,
			"修理全身装备（%d 金币）" % Trade.repair_cost(gear), def.shop_id))
	if def.can_teleport:
		for other in WorldDatabase.all_defs():
			if other.id != HOME_MAP_ID:
				options.append(DialogueOption.make(Enums.DialogueKind.TRAVEL, "传送：%s" % other.display_name, other.id))

	options.append(DialogueOption.make(Enums.DialogueKind.CLOSE, "再见", ""))
	var result := NpcDialogue.new()
	result.npc_id = npc_id
	result.text = _speech(def)
	result.options = options
	return result


func _npc_by_id(npc_id: String) -> NpcUnit:
	for entry in _current.npcs:
		if (entry as NpcUnit).def.id == npc_id:
			return entry
	return null


func _speech(def: NpcDef) -> String:
	for quest in QuestDatabase.all_defs():
		if quest.turn_in_npc_id == def.id and state_of(quest.id).status == Enums.QuestStatus.ACTIVE \
				and is_complete(quest):
			return "事情办完了？%s" % quest.turn_in_text
	for quest in QuestDatabase.all_defs():
		if quest.npc_id == def.id and state_of(quest.id).status == Enums.QuestStatus.NONE \
				and quest_prerequisite_met(quest):
			return "%s\n%s" % [def.greeting, quest.offer]
	return def.greeting


## 执行对话里选中的那一项。返回给 UI 用来决定要不要开商店/切图。
func choose(npc_id: String, option_index: int) -> DialogueOutcome:
	var dialogue := talk_to(npc_id, true)
	if dialogue == null or option_index < 0 or option_index >= dialogue.options.size():
		return DialogueOutcome.make("对话已关闭")
	var option: DialogueOption = dialogue.options[option_index]
	match option.kind:
		Enums.DialogueKind.ACCEPT_QUEST:
			return DialogueOutcome.make("已接下任务" if accept_quest(option.payload) else "接不了这个任务")
		Enums.DialogueKind.TURN_IN_QUEST:
			return DialogueOutcome.make("任务完成" if turn_in_quest(option.payload) else "还差东西")
		Enums.DialogueKind.OPEN_SHOP:
			return DialogueOutcome.make("", option.payload)
		Enums.DialogueKind.REPAIR:
			return DialogueOutcome.make("装备修好了" if repair_now() else "钱不够")
		Enums.DialogueKind.TRAVEL:
			var message := "" if travel_to(option.payload) else "去不了那儿"
			return DialogueOutcome.make(message, "", option.payload)
		_:
			return DialogueOutcome.make("")


func state_of(quest_id: String) -> QuestState:
	for entry in _quests:
		if (entry as QuestState).id == quest_id:
			return entry
	var fresh := QuestState.new()
	fresh.id = quest_id
	fresh.status = Enums.QuestStatus.NONE
	return fresh


func quest_prerequisite_met(quest: QuestDef) -> bool:
	return quest.requires_quest_id == "" or state_of(quest.requires_quest_id).status == Enums.QuestStatus.DONE


func accept_quest(quest_id: String) -> bool:
	var quest := QuestDatabase.try_get(quest_id)
	if quest == null:
		return false
	var state := state_of(quest_id)
	if state.status != Enums.QuestStatus.NONE or not quest_prerequisite_met(quest):
		_raise(Enums.GameEventType.INFO, "现在不能接这个任务", player.position, 0)
		return false
	state.status = Enums.QuestStatus.ACTIVE
	state.progress = 0
	_quests.append(state)
	_raise(Enums.GameEventType.QUEST_ACCEPT, "任务：%s——%s" % [quest.display_name, quest.hint],
		player.position, quest.count)
	return true


func progress_of(quest: QuestDef) -> int:
	if quest.kind == Enums.QuestKind.COLLECT:
		return mini(quest.count, player.bag.count_of(quest.target))
	return mini(quest.count, state_of(quest.id).progress)


func is_complete(quest: QuestDef) -> bool:
	return progress_of(quest) >= quest.count


func hint_of(quest: QuestDef) -> String:
	return "%s %d/%d" % [quest.target, progress_of(quest), quest.count]


func _advance_kill_quests(monster_id: String) -> void:
	for quest in QuestDatabase.all_defs():
		if quest.kind != Enums.QuestKind.KILL or quest.target != monster_id:
			continue
		var state := state_of(quest.id)
		if state.status != Enums.QuestStatus.ACTIVE or state.progress >= quest.count:
			continue
		state.progress += 1
		_raise(Enums.GameEventType.QUEST_PROGRESS, "%s：%d/%d" % [quest.display_name, progress_of(quest), quest.count],
			player.position, state.progress)
		if state.progress == quest.count:
			_raise(Enums.GameEventType.QUEST_READY, "%s 办妥了，回去交差" % quest.display_name, player.position, 0)


func turn_in_quest(quest_id: String) -> bool:
	var quest := QuestDatabase.try_get(quest_id)
	if quest == null:
		return false
	var state := state_of(quest_id)
	if state.status != Enums.QuestStatus.ACTIVE:
		return false
	if not is_complete(quest):
		_raise(Enums.GameEventType.INFO, "%s 还没办完（%s）" % [quest.display_name, hint_of(quest)], player.position, 0)
		return false
	if quest.kind == Enums.QuestKind.COLLECT and player.bag.count_of(quest.target) < quest.count:
		_raise(Enums.GameEventType.INFO, "背包里的%s不够 %d 个" % [quest.target, quest.count], player.position, 0)
		return false

	# 奖励装不下就先别交付，否则东西就地消失。
	for reward in quest.rewards:
		var def := ItemDatabase.try_get(reward.item_id)
		if def == null:
			continue
		if not player.bag.can_accept(def, reward.count):
			_raise(Enums.GameEventType.BLOCKED, "背包满了，先腾点地方再来交", player.position, 0)
			return false

	if quest.kind == Enums.QuestKind.COLLECT:
		player.bag.consume(quest.target, quest.count)
	state.status = Enums.QuestStatus.DONE
	state.progress = quest.count

	var gold := quest.reward_gold
	player.gold += gold
	for reward in quest.rewards:
		var def := ItemDatabase.try_get(reward.item_id)
		if def == null:
			continue
		player.bag.add(def, reward.count)
	var levels := player.gain_experience(quest.reward_experience)
	if levels > 0:
		_raise(Enums.GameEventType.LEVEL_UP, "升到 %d 级" % player.level, player.position, player.level)
	_learn_auto_skills(false)

	_raise(Enums.GameEventType.QUEST_COMPLETE, "%s 完成：%d 金币、%d 经验" % [quest.display_name, gold, quest.reward_experience],
		player.position, gold)
	return true


# ── 商店 ──────────────────────────────────────────────────────────────

## 是不是站在卖这家东西的 NPC 旁边。UI 用它决定面板灰不灰。
func near_shop(shop_id: String) -> bool:
	for entry in _current.npcs:
		var npc := entry as NpcUnit
		if npc.def.shop_id == shop_id and Grid.chebyshev(player.position, npc.position) <= TALK_RADIUS:
			return true
	return false


func buy_from_shop(shop_id: String, def_id: String, count := 1) -> bool:
	var shop := ShopDatabase.try_get(shop_id)
	if shop == null:
		return false
	if not shop.stock.has(def_id):
		_raise(Enums.GameEventType.INFO, "货架上没有这个", player.position, 0)
		return false
	if not near_shop(shop_id):
		_raise(Enums.GameEventType.BLOCKED, "得站到老板跟前才买得到", player.position, 0)
		return false
	var def := ItemDatabase.try_get(def_id)
	if def == null:
		return false
	if count <= 0:
		return false

	var cost := Trade.buy_price(def) * count
	if player.gold < cost:
		_raise(Enums.GameEventType.INFO, "金币不够", player.position, cost)
		return false
	if not player.bag.can_accept(def, count):
		_raise(Enums.GameEventType.BLOCKED, "背包放不下", player.position, 0)
		return false

	var placed := player.bag.add(def, count)
	if placed <= 0:
		return false
	player.gold -= Trade.buy_price(def) * placed
	_raise(Enums.GameEventType.BUY, "买下 %s x%d（-%d 金币）" % [def.display_name, placed, Trade.buy_price(def) * placed],
		player.position, placed)
	return true


## 卖背包里的一件。站在哪个老板面前就按哪个老板的收价。
func sell_from_bag(uid: String, count := -1) -> bool:
	var item := player.bag.find_by_uid(uid)
	if item == null:
		return false
	if item.def.type == Enums.ItemType.GOLD:
		return false
	var shop_npc := _nearest_shop_npc()
	if shop_npc == null:
		_raise(Enums.GameEventType.BLOCKED, "走到商人跟前再卖", player.position, 0)
		return false

	var take := item.count if count < 0 else mini(count, item.count)
	var unit_price := Trade.sell_price(item)
	var total := unit_price * take
	var removed := player.bag.remove(uid, take)
	if removed == null:
		return false
	player.gold += total
	_raise(Enums.GameEventType.SELL, "卖出 %s x%d（+%d 金币）" % [removed.def.display_name, take, total],
		player.position, total)
	return true


func _nearest_shop_npc() -> NpcUnit:
	for entry in _current.npcs:
		var npc := entry as NpcUnit
		if npc.def.shop_id != "" and Grid.chebyshev(player.position, npc.position) <= TALK_RADIUS:
			return npc
	return null


func repair_now() -> bool:
	var cost := Trade.repair_cost(gear)
	if cost <= 0:
		_raise(Enums.GameEventType.INFO, "装备没坏，不用修", player.position, 0)
		return false
	if player.gold < cost:
		_raise(Enums.GameEventType.INFO, "修理要 %d 金币，钱不够" % cost, player.position, cost)
		return false
	player.gold -= cost
	gear.repair_all()
	_raise(Enums.GameEventType.REPAIR, "花 %d 金币修好全身装备" % cost, player.position, cost)
	return true


# ── 拾取与物品 ────────────────────────────────────────────────────────

## 走到位子上自动捡同格的东西；手动捡也走这里。
func pick_up_at(pos: Vector2i) -> bool:
	var on_spot: Array = []
	for entry in _current.loot:
		if (entry as LootItem).position == pos:
			on_spot.append(entry)
	if on_spot.is_empty():
		return false

	var took := false
	for entry in on_spot:
		var stack := entry as LootItem
		if stack.item.def.type == Enums.ItemType.GOLD:
			player.gold += stack.item.count
			_raise(Enums.GameEventType.LOOT, "拾取 %s x%d" % [stack.item.def.display_name, stack.item.count],
				pos, stack.item.count)
			_current.loot.erase(stack)
			took = true
			continue
		if player.bag.free_slots == 0:
			_raise(Enums.GameEventType.BLOCKED, "背包满了", pos, 0)
			break
		var placed := player.bag.add(stack.item.def, stack.item.count, stack.item.uid)
		if placed <= 0:
			break
		_current.loot.erase(stack)
		_raise(Enums.GameEventType.LOOT, "拾取 %s x%d" % [stack.item.def.display_name, placed], pos, placed)
		took = true
	return took


func _new_uid() -> String:
	_next_uid += 1
	return "u%d" % (_next_uid - 1)


func _take_uid(_def_id: String) -> String:
	return _new_uid()


func _new_instance(def_id: String, count: int) -> ItemInstance:
	var def := ItemDatabase.get_def(def_id)
	return ItemInstance.new(_new_uid(), def.id, count, def.max_durability)


func equip_from_bag(uid: String) -> bool:
	var item := player.bag.find_by_uid(uid)
	if item == null:
		return false
	var removed_from_bag := player.bag.remove(uid, 1)
	if removed_from_bag == null:
		return false
	var outcome := player.gear.try_equip(removed_from_bag, player.bag, player.level)
	if outcome.ok:
		_raise(Enums.GameEventType.EQUIP, "穿上 %s" % removed_from_bag.def.display_name, player.position, 0)
		return true
	# 装备失败必须原样放回背包（连耐久一起），否则点错一次就少一件东西。
	player.bag.try_place(removed_from_bag)
	_raise(Enums.GameEventType.INFO, outcome.reason, player.position, 0)
	return false


func unequip(slot: int) -> bool:
	var outcome := player.gear.try_unequip(slot, player.bag)
	if not outcome.ok:
		_raise(Enums.GameEventType.INFO, outcome.reason, player.position, 0)
		return false
	_raise(Enums.GameEventType.UNEQUIP, "卸下 %s" % (outcome.removed as ItemInstance).def.display_name,
		player.position, 0)
	return true


## 吃掉/读掉。武谱是唯一"用了就学会"的那类物品。
func consume_item(uid: String) -> bool:
	var item := player.bag.find_by_uid(uid)
	if item == null:
		return false
	var def := item.def
	if def.type == Enums.ItemType.BOOK:
		var skill := SkillDatabase.get_def(def.learns_skill)
		if player.level < skill.required_level:
			_raise(Enums.GameEventType.INFO, "%s 要 %d 级才读得懂" % [def.display_name, skill.required_level],
				player.position, 0)
			return false
		if knows(def.learns_skill):
			_raise(Enums.GameEventType.INFO, "这招已经会了", player.position, 0)
			return false
		player.bag.remove(uid, 1)
		learn(def.learns_skill)
		return true
	if def.type != Enums.ItemType.CONSUMABLE:
		return false

	player.bag.remove(uid, 1)
	var healed := mini(def.heal_hp, player.max_hp - player.hp)
	var mana := mini(def.heal_mp, player.max_mp - player.mp)
	player.hp += healed
	player.mp += mana
	_raise(Enums.GameEventType.CONSUME, "%s 回复 %d 生命 / %d 内力" % [def.display_name, healed, mana],
		player.position, healed + mana)
	return true


func drop_from_bag(uid: String) -> bool:
	var item := player.bag.find_by_uid(uid)
	if item == null:
		return false
	var spot: Variant = _free_spot_near(player.position)
	var removed := player.bag.remove(uid, item.count)
	if removed == null:
		return false
	_current.loot.append(LootItem.new(removed, player.position if spot == null else spot))
	_raise(Enums.GameEventType.DROP, "丢下 %s" % removed.def.display_name,
		player.position if spot == null else spot, removed.count)
	return true


func move_bag_item(from: int, to: int) -> void:
	player.bag.move(from, to)


# ── 每帧驱动 ──────────────────────────────────────────────────────────

func tick(delta_seconds: float) -> void:
	var delta := clampf(delta_seconds, 0.0, 0.25)
	elapsed += delta
	_player_attack_cooldown = maxf(0.0, _player_attack_cooldown - delta)

	for skill_id in _cooldowns.keys():
		_cooldowns[skill_id] = maxf(0.0, _cooldowns[skill_id] - delta)

	if player.alive:
		_advance_player_path(delta)
		_auto_attack_nearby()
		_regenerate(delta)
	else:
		player.death_timer += delta
		if player.death_timer > 2.5:
			_revive_player()

	_tick_effects(delta)
	for entry in _current.monsters:
		_update_monster(entry as MonsterUnit, delta)
	_update_loot(delta)


## 城里站着回血回蓝，野外只有脱战以后慢慢回——给玩家一个"回城"的理由。
func _regenerate(delta: float) -> void:
	var threatened := nearest_monster(player.position, 6) != null
	if map.safe:
		player.mp = mini(player.max_mp, player.mp + int(ceil(delta * 6.0)))
		player.hp = mini(player.max_hp, player.hp + int(ceil(delta * 8.0)))
		return
	player.mp = mini(player.max_mp, player.mp + int(ceil(delta * 1.1)))
	if not threatened:
		player.hp = mini(player.max_hp, player.hp + int(ceil(delta * 0.6)))


func _tick_effects(delta: float) -> void:
	for i in range(player.effects.size() - 1, -1, -1):
		var effect := player.effects[i] as SkillEffect
		effect.remaining -= delta
		if effect.remaining > 0.0:
			continue
		player.effects.remove_at(i)
		_raise(Enums.GameEventType.BUFF, "%s 的效果消散了" % effect.title, player.position, 0)


## 当前这一步该按几格的路程计时：斜格 √2，直格 1。
static func _step_scale(from: Vector2i, path: Array) -> float:
	if path.is_empty():
		return 1.0
	var next: Vector2i = path[0]
	if next == from:
		return 1.0
	if absi(next.x - from.x) == 1 and absi(next.y - from.y) == 1:
		return DIAGONAL_STEP
	return 1.0


func _advance_player_path(delta: float) -> void:
	if _player_path.is_empty():
		return
	_move_progress += delta * player.move_speed / _step_scale(player.position, _player_path)
	while _move_progress >= 1.0 and not _player_path.is_empty():
		var next: Vector2i = _player_path[0]
		if next == player.position:
			_player_path.remove_at(0)
			_move_progress = 0.0
			continue
		var blocker: Unit = _current.occupancy.get(next)
		if blocker != null and blocker != player:
			if blocker is MonsterUnit and blocker.is_attackable() \
					and Grid.chebyshev(player.position, next) == 1:
				_player_path.clear()
				attack_target(blocker as MonsterUnit)
				break
			# 有人（或 NPC）挡住：重新寻路，寻不到就停下。
			_player_path.clear()
			_move_progress = 0.0
			break
		player.facing = Grid.facing_towards(player.position, next)
		_move_unit_to(player, next)
		_player_path.remove_at(0)
		_move_progress -= 1.0
		pick_up_at(player.position)
		if map.exit_at(player.position) != null:
			_player_path.clear()
			_try_use_exit(player.position)
			break
	if _player_path.is_empty():
		_move_progress = 0.0


## 贴脸有怪就自动出手，省掉"狂点鼠标"的伪需求。
func _auto_attack_nearby() -> void:
	if _player_attack_cooldown > 0.0 or map.safe:
		return
	var target := nearest_monster(player.position, 1)
	if target != null:
		attack_target(target)


func _update_monster(monster: MonsterUnit, delta: float) -> void:
	if not monster.alive:
		monster.respawn_seconds -= delta
		if monster.respawn_seconds > 0.0:
			return
		_respawn(monster)
		return

	monster.attack_cooldown = maxf(0.0, monster.attack_cooldown - delta)
	monster.wander_cooldown = maxf(0.0, monster.wander_cooldown - delta)
	monster.repath_seconds -= delta

	if not player.alive:
		if monster.aggro:
			monster.aggro = false
			monster.path.clear()
		return

	var distance := Grid.chebyshev(monster.position, player.position)
	if not monster.aggro and distance <= monster.def.aggro_radius:
		monster.aggro = true
		monster.path.clear()
	elif monster.aggro and distance > monster.def.chase_range:
		monster.aggro = false
		monster.path.clear()
		return

	if monster.aggro:
		if distance == 1:
			if monster.attack_cooldown <= 0.0:
				monster.attack_cooldown = monster.attack_delay
				monster.facing = Grid.facing_towards(monster.position, player.position)
				var result := Combat.resolve(_rng, monster, player)
				if result.hit:
					_raise(Enums.GameEventType.ATTACK, "%s 命中 -%d" % [monster.name, result.damage],
						player.position, result.damage)
				else:
					_raise(Enums.GameEventType.MISS, "%s 砍空" % monster.name, player.position, 0)

				if not player.alive:
					_on_player_death()
			return

		# 玩家所在格对怪是"占住"的，寻路目标要退到旁边，否则永远追不上人。
		if monster.path.is_empty() or monster.repath_seconds <= 0.0:
			monster.repath_seconds = 0.6
			var keep_progress := monster.path.size() > 0
			var first_step: Variant = monster.path[0] if keep_progress else null
			monster.path.clear()
			var path := _chase_path(monster)
			if path.size() > 1:
				for step in path.slice(1, mini(13, path.size())):
					monster.path.append(step)
			# 还是往同一格迈腿就保留进度，否则每次重寻路都要从零攒一步，怪永远走不动。
			if not keep_progress or monster.path.is_empty() or monster.path[0] != first_step:
				monster.move_progress = 0.0
		_advance_monster(monster, delta)
		return

	if monster.wander_cooldown > 0.0:
		return
	monster.wander_cooldown = 0.8 + float(_current.rng.next(12)) / 10.0
	var direction := _current.rng.next(8)
	var candidate := Grid.offset(monster.position, direction)
	if map.is_walkable(candidate) and not _current.occupancy.has(candidate) \
			and Grid.chebyshev(candidate, monster.home) <= 4:
		monster.facing = direction
		_move_unit_to(monster, candidate)


## 追击寻路：玩家那格站着人，怪只能走他旁边的空格。
## 候选按"离这只怪由近及远"试，第一个走得通的就用——固定取扫描顺序的第一个，
## 一群怪挤在一起时会反复绕到人背后、被人墙堵死在三步外。
func _chase_path(monster: MonsterUnit) -> Array:
	var candidates: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var pos := player.position + Vector2i(dx, dy)
			if _is_free_for_monster(_current, pos):
				candidates.append(pos)

	var ranked := order_by(candidates, [
		func(p) -> int: return Grid.chebyshev(monster.position, p),
		func(p) -> int: return Grid.manhattan(p, monster.position),
	])
	for target in ranked:
		var path := Pathfinding.find(map, _is_blocked_for_monster.bind(monster), monster.position, target)
		if path.size() > 1:
			return path
	return []


func _advance_monster(monster: MonsterUnit, delta: float) -> void:
	if monster.path.is_empty():
		monster.move_progress = 0.0
		return
	# 一帧走不满一格很常见，进度必须攒在怪物身上，否则 30fps 下谁都挪不动腿。
	monster.move_progress += delta * monster.move_speed / _step_scale(monster.position, monster.path)
	while monster.move_progress >= 1.0 and not monster.path.is_empty():
		var next: Vector2i = monster.path[0]
		monster.path.remove_at(0)
		if next == monster.position:
			continue
		if _current.occupancy.has(next) or not map.is_walkable(next):
			monster.path.clear()
			monster.move_progress = 0.0
			break
		monster.facing = Grid.facing_towards(monster.position, next)
		_move_unit_to(monster, next)
		monster.move_progress -= 1.0


# ── 画面用的亚格位置 ──────────────────────────────────────────────────

## 格子世界只有整数格，但走路是连续的：把"已经站定的那格"和"正在走进去的那格"
## 按攒下的进度插出来给画面用。占用、判定、存档一律还是整数格，玩法不受影响。
func player_render_cell() -> Vector2:
	return _render_cell(player, _player_path, _move_progress)


func monster_render_cell(monster: MonsterUnit) -> Vector2:
	return _render_cell(monster, monster.path, monster.move_progress)


static func _render_cell(unit: Unit, path: Array, progress: float) -> Vector2:
	if path.is_empty() or progress <= 0.0:
		return Vector2(unit.position)
	var next: Vector2i = path[0]
	return Vector2(unit.position).lerp(Vector2(next), minf(progress, 1.0))


func _update_loot(delta: float) -> void:
	for i in range(_current.loot.size() - 1, -1, -1):
		var stack := _current.loot[i] as LootItem
		stack.life_seconds -= delta
		if stack.life_seconds > 0.0:
			continue
		_current.loot.remove_at(i)


func _respawn(monster: MonsterUnit) -> void:
	# 家里被别的怪或玩家长期占着时就近找一格落下去，
	# 只认 Home 那一格的话，这只怪就永远刷不出来了。
	var spot: Variant = _find_free_spot_in(_current, monster.home)
	if spot == null:
		return
	monster.hp = monster.def.base_stats.max_hp
	monster.position = spot
	monster.aggro = false
	monster.path.clear()
	_occupy(monster)


static func _find_free_spawn(runtime: MapRuntime, requested: Vector2i) -> Variant:
	var free := func(pos: Vector2i) -> bool:
		return runtime.map.is_walkable(pos) and not runtime.occupancy.has(pos)
	if free.call(requested):
		return requested
	return _find_spot_near(requested, free)


func _give_starting_kit() -> void:
	player.bag.add(ItemDatabase.get_def(Naming.ITEM_POTION_HP_SMALL), 5)
	player.bag.add(ItemDatabase.get_def(Naming.ITEM_WOOD_SWORD), 1)
	player.bag.add(ItemDatabase.get_def(Naming.ITEM_CLOTH), 1)
	player.gold = 200
	for wanted_id in [Naming.ITEM_WOOD_SWORD, Naming.ITEM_CLOTH]:
		for entry in player.bag.enumerate():
			var instance := entry as ItemInstance
			if instance.def_id == wanted_id:
				equip_from_bag(instance.uid)
				break


func _on_player_death() -> void:
	player.death_timer = 0.0
	player.death_count += 1
	var lost := player.gold / 10
	player.gold -= lost
	_raise(Enums.GameEventType.DEATH, "你被撂倒了，掉落 %d 金币" % lost, player.position, lost)


## 死了回城复活，比"在原地爬起来"更符合单机的惩罚节奏。
func _revive_player() -> void:
	_current.occupancy.erase(player.position)
	var home := _runtime(WorldDatabase.get_def(HOME_MAP_ID))
	_current = home
	var spot: Variant = _find_free_spot_in(home, home.map.spawn)
	if spot == null:
		spot = home.map.spawn
	player.position = spot
	home.occupancy[spot] = player
	player.hp = player.max_hp
	player.mp = player.max_mp
	player.death_timer = 0.0
	_player_path.clear()
	for entry in _current.monsters:
		var monster := entry as MonsterUnit
		monster.aggro = false
		monster.path.clear()
	_raise(Enums.GameEventType.RESPAWN, "在 %s 苏醒" % home.map.display_name, spot, 0)


## 取走并清空事件队列，UI 每帧只消费新增项。
func drain_events() -> Array:
	if _events.is_empty():
		return []
	var batch := _events.duplicate()
	_events.clear()
	return batch


func _raise(event_type: int, text: String, at: Vector2i, amount: int) -> void:
	_events.append(GameEvent.make(event_type, text, at, amount))


# ── 排序工具 ──────────────────────────────────────────────────────────

## 稳定排序：Array.sort_custom 不保证同键次序，
## 所以按 (键..., 原始下标) 排；刷怪分档、追击候选与技能选目标都靠它保持可复现。
static func order_by(source: Array, keys: Array) -> Array:
	var decorated: Array = []
	for i in source.size():
		var tuple: Array = [i]
		for key in keys:
			tuple.append(key.call(source[i]))
		decorated.append([tuple, source[i]])
	decorated.sort_custom(func(a, b):
		var size_a: Array = a[0]
		var size_b: Array = b[0]
		for j in range(1, size_a.size()):
			if size_a[j] != size_b[j]:
				return size_a[j] < size_b[j]
		return size_a[0] < size_b[0])
	var out: Array = []
	for entry in decorated:
		out.append(entry[1])
	return out


# ── 存档口（外部不该用） ──────────────────────────────────────────────

var visited_maps: Array:
	get:
		return _runtimes.values()


var monster_list: Array:
	get:
		return _current.monsters


var loot_list: Array:
	get:
		return _current.loot


var occupancy_map: Dictionary:
	get:
		return _current.occupancy


var quest_list: Array:
	get:
		return _quests


var learned: Dictionary:
	get:
		return _learned


var cooldown_map: Dictionary:
	get:
		return _cooldowns


var uid_counter: int:
	get:
		return _next_uid
	set(value):
		_next_uid = value


## 读档专用：按地图 id 生成（或复用）运行时并清掉它自己刷出来的怪与掉落。
## NPC 站位属于地图定义，清完要立刻还回去，否则读档后能穿过商人走。
func open_for_restore(map_id_to_open: String) -> MapRuntime:
	var runtime := _runtime(WorldDatabase.get_def(map_id_to_open))
	_current = runtime
	runtime.monsters.clear()
	runtime.loot.clear()
	runtime.occupancy.clear()
	for entry in runtime.npcs:
		var npc := entry as NpcUnit
		runtime.occupancy[npc.position] = npc
	return runtime


func occupy_restored_player() -> void:
	_occupy(player)
	_player_path.clear()
	_move_progress = 0.0
