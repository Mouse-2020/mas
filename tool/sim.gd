extends SceneTree

# 武林风 · 无头跑台。
# 无头跑台：机器人 + 统计输出。
# 一个会找怪/喝药/穿装备/读书/接任务/走图/进店的机器人，把五条玩法线一起压一遍。
# 用法：godot --headless --path . --script res://tool/sim.gd -- --seed 808 --seconds 600

const ARTIFACTS_FOLDER := ".artifacts"
const DEFAULT_SEED := 20261016
const DEFAULT_SECONDS := 300

# Enums.GameEventType 的整数值按声明顺序排布；GDScript 拿不到枚举成员名，
# 事件分组表用这张名字表打印。
const EVENT_TYPE_NAMES := [
	"Move", "Blocked", "Attack", "Miss", "Kill", "LevelUp", "Loot", "Equip",
	"Unequip", "Consume", "Drop", "Death", "Respawn", "Info", "Skill", "Learn",
	"Buff", "QuestAccept", "QuestProgress", "QuestReady", "QuestComplete",
	"Travel", "Buy", "Sell", "Repair", "Talk",
]
const QUEST_STATUS_NAMES := ["None", "Active", "Done"]

var _artifacts := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := _parse_int(args, "--seed", DEFAULT_SEED)
	var seconds := _parse_int(args, "--seconds", DEFAULT_SECONDS)
	_artifacts = _parse_str(args, "--out",
		ProjectSettings.globalize_path("res://").trim_suffix("/") + "/" + ARTIFACTS_FOLDER)
	DirAccess.make_dir_recursive_absolute(_artifacts)
	quit(_run(seed_value, seconds))


# ── 命令行 ──────────────────────────────────────────────────────────

func _parse_int(args: PackedStringArray, flag: String, fallback: int) -> int:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size() and _is_int(args[index + 1]):
		return args[index + 1].to_int()
	return fallback


func _parse_str(args: PackedStringArray, flag: String, fallback: String) -> String:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


## 非整数（比如 "--seed abc"）用回退值，而不是当成 0。
func _is_int(text: String) -> bool:
	if text.is_empty():
		return false
	var body := text.substr(1) if text.begins_with("-") or text.begins_with("+") else text
	if body.is_empty():
		return false
	for i in body.length():
		if not _is_digit(body[i]):
			return false
	return true


func _is_digit(character: String) -> bool:
	return character >= "0" and character <= "9"


# ── 跑台 ────────────────────────────────────────────────────────────

func _run(seed_value: int, seconds: int) -> int:
	var session := GameSession.new_campaign(seed_value)
	print("起始：%s 出生 %s，城里 NPC %d 个" % [session.map.display_name, _pos(session.player.position),
		session.npcs.size()])
	_print_stats(session, "初始")

	var tick := 1.0 / 30.0
	var frames := int(float(seconds) / tick)
	var bot := SimBot.new(session)
	var events: Array = []
	var position_changes := 0
	var last_position := session.player.position

	for frame in frames:
		bot.step()
		session.tick(tick)
		for entry in session.drain_events():
			events.append(entry)

		if session.player.position != last_position:
			position_changes += 1
			last_position = session.player.position

		if frame % 900 == 0 and frame > 0:
			print("  %ds  %s 等级 %d  HP %d/%d MP %d  击杀 %d  金币 %d  任务 %d 已交  走图 %d 次" % [
				int(float(frame) * tick), session.map.display_name, session.player.level,
				session.player.hp, session.player.max_hp, session.player.mp, session.kill_count,
				session.player.gold, bot.quests_turned_in, bot.travels])

	_print_stats(session, "%d 秒后" % seconds)
	print("位置变化 %d 次；事件 %d 条" % [position_changes, events.size()])
	for row in _group_event_counts(events):
		print("  %s %d" % [_pad(row[0], 14), row[1]])

	print("技能出手 %d 次，接任务 %d 条、交差 %d 条，走图 %d 次，进店 %d 次，买东西 %d 件" % [
		bot.skill_casts, bot.quests_accepted, bot.quests_turned_in, bot.travels,
		bot.shop_visits, bot.purchases])
	print("等级 %d，击杀 %d，阵亡 %d 次，本图掉落 %d 件，金币 %d" % [session.player.level,
		session.kill_count, session.player.death_count, session.loot.size(), session.player.gold])
	print("到过：%s" % _join(bot.visited_maps, "、"))
	var quest_parts: Array = []
	for entry in session.quests:
		var state := entry as QuestState
		quest_parts.append("%s:%s/%d" % [QuestDatabase.get_def(state.id).display_name,
			_quest_status_name(state.status), state.progress])
	print("任务进度：" + ("一条没接" if quest_parts.is_empty() else _join(quest_parts, "、")))

	var save_path := _artifacts + "/wulin-%d.json" % seed_value
	SaveGame.write_to_file(SaveGame.capture(session), save_path)
	print("存档写入 " + save_path)

	var restored := SaveGame.restore(SaveGame.read_from_file(save_path))
	print("读档核对：所在图 %s，等级 %d，HP %d/%d，位置 %s，背包 %d 件，装备 %d 件，本图怪 %d 只，掉落 %d 件，击杀 %d，技能 %d 招，任务 %d 条" % [
		restored.map_id, restored.player.level, restored.player.hp, restored.player.max_hp,
		_pos(restored.player.position), restored.bag.used_slots, restored.gear.worn.size(),
		restored.monsters.size(), restored.loot.size(), restored.kill_count,
		_known_count(restored), restored.quests.size()])
	print("存档里存了 %d 张图的动态内容" % _save_map_count(SaveGame.read_from_file(save_path)))

	var world_path := _artifacts + "/world-%d.png" % seed_value
	WorldRenderer.render(session, 4).save_png(world_path)
	WorldRenderer.render(session, 8, 14).save_png(_artifacts + "/view-%d.png" % seed_value)
	print("渲染输出 " + world_path)
	return 0


func _print_stats(session: GameSession, label: String) -> void:
	var player := session.player
	var stats := player.get_stats()
	print("%s 等级 %d 经验 %d/%d HP %d/%d MP %d/%d DC %d-%d AC %d-%d 命中 %d 闪避 %d 装备 %d 件 技能 %d 招" % [
		_pad(label, 8), player.level, player.experience, player.experience_to_next,
		player.hp, stats.max_hp, player.mp, stats.max_mp,
		stats.dc_min, stats.dc_max, stats.ac_min, stats.ac_max,
		stats.hit, stats.dodge, player.gear.worn.size(), _known_count(session)])


## 按事件类型分组、再按次数降序：排序必须稳定，
## 计数相同的档位保持首次出现的顺序。
func _group_event_counts(events: Array) -> Array:
	var order: Array = []
	var counts := {}
	for entry in events:
		var type: int = (entry as GameEvent).type
		if not counts.has(type):
			counts[type] = 0
			order.append(type)
		counts[type] = int(counts[type]) + 1
	var rows: Array = []
	for i in order.size():
		rows.append([_event_type_name(order[i]), int(counts[order[i]]), i])
	# 计数降序、同计数按首次出现——显式带序号比较，不依赖排序算法的稳定性。
	for a in range(rows.size()):
		for b in range(a + 1, rows.size()):
			if int(rows[b][1]) > int(rows[a][1]) \
				or (int(rows[b][1]) == int(rows[a][1]) and int(rows[b][2]) < int(rows[a][2])):
				var swap: Variant = rows[a]
				rows[a] = rows[b]
				rows[b] = swap
	var out: Array = []
	for row in rows:
		out.append([row[0], row[1]])
	return out


func _save_map_count(save: Dictionary) -> int:
	var maps: Variant = save.get("maps", [])
	return maps.size() if typeof(maps) == TYPE_ARRAY else 0


## GameSession.known_skills 的元素口径（技能 id 或 SkillDef）由 system/session.gd 定，两种都算一招。
func _known_count(session: GameSession) -> int:
	return session.known_skills.size()


func _event_type_name(type: int) -> String:
	if type >= 0 and type < EVENT_TYPE_NAMES.size():
		return EVENT_TYPE_NAMES[type]
	return str(type)


func _quest_status_name(status: int) -> String:
	if status >= 0 and status < QUEST_STATUS_NAMES.size():
		return QUEST_STATUS_NAMES[status]
	return str(status)


## 左对齐补空格。手动实现，避免 % 宽度按字节算还是按字符算的歧义。
func _pad(text: String, width: int) -> String:
	var out_text := text
	while out_text.length() < width:
		out_text += " "
	return out_text


func _pos(value: Vector2i) -> String:
	return "(%d,%d)" % [value.x, value.y]


func _join(items: Array, separator: String) -> String:
	var text := ""
	for i in items.size():
		if i > 0:
			text += separator
		text += String(items[i])
	return text


# ── 机器人 ──────────────────────────────────────────────────────────

## 优先级从上往下：活着 > 有蓝有药 > 穿装备 > 读书 > 城里做买卖 > 打不过就回城 > 找怪打。
## 每步只做一件事，所以一帧一步不会把逻辑搅在一起。
class SimBot:
	const HUNTING_GROUNDS := [Naming.MAP_SUBURB, Naming.MAP_FOREST, Naming.MAP_CAVE]

	var skill_casts := 0
	var quests_accepted := 0
	var quests_turned_in := 0
	var travels := 0
	var shop_visits := 0
	var purchases := 0
	## 只记第一次进图的顺序（去重保序）。
	var visited_maps: Array = []

	var _session: GameSession
	var _cooldown := 0
	var _travel_cooldown := 0
	var _walk_frames := 0


	func _init(session: GameSession) -> void:
		_session = session
		_mark_visited(session.map_id)


	func step() -> void:
		var player := _session.player
		if not player.alive:
			return
		if _cooldown > 0:
			_cooldown -= 1
		if _travel_cooldown > 0:
			_travel_cooldown -= 1
		_mark_visited(_session.map_id)

		if player.hp_percent < 0.45 and _try_restore_health():
			return
		if _try_equip_best():
			return
		if _try_read_book():
			return
		if _session.map.safe:
			if _try_talk():
				return
		elif _should_go_home():
			_head_toward(GameSession.HOME_MAP_ID)
			return
		_hunt()


	func _mark_visited(map_id: String) -> void:
		if not visited_maps.has(map_id):
			visited_maps.append(map_id)


	# ── 自理 ────────────────────────────────────────────────────────

	func _try_restore_health() -> bool:
		var player := _session.player
		if player.hp_percent < 0.85 and _session.knows(Naming.SKILL_HEAL) \
			and _session.cooldown_left(Naming.SKILL_HEAL) <= 0.0 \
			and _session.cast(Naming.SKILL_HEAL).success:
			return true

		var potion: ItemInstance = null
		for entry in player.bag.enumerate():
			var item := entry as ItemInstance
			if item.def.type == Enums.ItemType.CONSUMABLE and item.def.heal_hp > 0:
				potion = item
				break
		if potion != null:
			return _session.consume_item(potion.uid)

		# 空手没药就先去药铺买，别硬顶。
		return false


	func _try_equip_best() -> bool:
		var player := _session.player
		var best: ItemInstance = null
		var best_score := -1
		for entry in player.bag.enumerate():
			var item := entry as ItemInstance
			if not item.def.is_equipment or player.level < item.def.required_level:
				continue
			var bonus := item.def.bonus
			# OrderByDescending 是稳定排序，同分取背包里靠前的那件。
			var score := bonus.dc_min + bonus.dc_max + bonus.ac_min + bonus.ac_max
			if score > best_score:
				best_score = score
				best = item
		return best != null and _session.equip_from_bag(best.uid)


	func _try_read_book() -> bool:
		var book: ItemInstance = null
		for entry in _session.player.bag.enumerate():
			var item := entry as ItemInstance
			if item.def.type == Enums.ItemType.BOOK and item.def.learns_skill != "" \
				and not _session.knows(item.def.learns_skill):
				book = item
				break
		return book != null and _session.consume_item(book.uid)


	# ── 城里：说话、接交任务、补药修装备 ──────────────────────────────

	## 站在真有生意的 NPC 跟前把事办掉；没事可做就返回 false，让调用方去打猎。
	func _try_talk() -> bool:
		if _cooldown > 0:
			return true
		var npc := _business_npc()
		if npc == null:
			return false

		if Grid.chebyshev(_session.player.position, npc.position) > GameSession.TALK_RADIUS:
			# nearest_npc 隔着半张图也返回人，所以这里必须自己走位；
			# 光"说话"只会拿到一句"先走到跟前"，然后原地转圈。
			_session.move_player_to(npc.position)
			_walk_frames += 1
			if _walk_frames > 420:
				_walk_frames = 0
				return false
			return true
		_walk_frames = 0

		var dialogue := _session.talk_to(npc.def.id)
		if dialogue == null:
			return false
		_cooldown = 30

		for i in dialogue.options.size():
			var option: DialogueOption = dialogue.options[i]
			match option.kind:
				Enums.DialogueKind.ACCEPT_QUEST:
					if _session.choose(npc.def.id, i).message.contains("已接"):
						quests_accepted += 1
					return true
				Enums.DialogueKind.TURN_IN_QUEST:
					if _session.choose(npc.def.id, i).message.contains("完成"):
						quests_turned_in += 1
					return true
				Enums.DialogueKind.OPEN_SHOP:
					if _restock(option.payload):
						return true
				Enums.DialogueKind.REPAIR:
					if Trade.repair_cost(_session.gear) > 0:
						_session.choose(npc.def.id, i)
						return true
		# 走到了跟前却发现没什么可办，别杵在城里。
		return false


	## 挑一个"此刻真有活要办"的 NPC 走过去；没事可做就返回 null。
	func _business_npc() -> NpcUnit:
		var best: NpcUnit = null
		var best_distance := 0
		for entry in _session.npcs:
			var npc := entry as NpcUnit
			if _pending_business(npc.def.id) <= 0:
				continue
			var distance := Grid.manhattan(npc.position, _session.player.position)
			# OrderBy 稳定：同距离取 NPC 列表里靠前的那位。
			if best == null or distance < best_distance:
				best = npc
				best_distance = distance
		return best


	func _pending_business(npc_id: String) -> int:
		var offers := 0
		for entry in QuestDatabase.offered_by(npc_id):
			var quest := entry as QuestDef
			if _session.state_of(quest.id).status == Enums.QuestStatus.NONE \
				and _session.quest_prerequisite_met(quest):
				offers += 1
		var ready := 0
		for entry in QuestDatabase.turned_in_at(npc_id):
			var quest := entry as QuestDef
			if _session.state_of(quest.id).status == Enums.QuestStatus.ACTIVE \
				and _session.is_complete(quest):
				ready += 1
		var needs_potions := _session.player.bag.count_of(Naming.ITEM_POTION_HP_SMALL) < 20 \
			and _session.player.gold >= 300
		var shopping := 0
		if NpcDatabase.get_def(npc_id).shop_id == Naming.SHOP_MEDICINE and needs_potions:
			shopping = 1
		var cost := Trade.repair_cost(_session.gear)
		var fixing := 0
		if NpcDatabase.get_def(npc_id).can_repair and cost > 0 and _session.player.gold >= cost:
			fixing = 1
		return offers + ready + shopping + fixing


	## 站在药铺就把随身药补到 20 瓶。
	func _restock(shop_id: String) -> bool:
		var player := _session.player
		var wanted := 20 - player.bag.count_of(Naming.ITEM_POTION_HP_SMALL)
		if wanted <= 0:
			return false
		shop_visits += 1
		var before := player.bag.count_of(Naming.ITEM_POTION_HP_SMALL)
		if not _session.buy_from_shop(shop_id, Naming.ITEM_POTION_HP_SMALL, mini(wanted, 10)):
			return false
		purchases += player.bag.count_of(Naming.ITEM_POTION_HP_SMALL) - before
		return true


	# ── 回城与走图 ────────────────────────────────────────────────────

	func _should_go_home() -> bool:
		for entry in _session.quests:
			var state := entry as QuestState
			if state.status == Enums.QuestStatus.ACTIVE \
				and _session.is_complete(QuestDatabase.get_def(state.id)):
				return true
		var out_of_potions := _session.player.bag.count_of(Naming.ITEM_POTION_HP_SMALL) == 0 \
			and _session.player.gold >= 60
		return out_of_potions or _session.player.hp_percent < 0.3


	## 沿世界表往目标图挪一步：找"那一侧的门"，走到门口踩上去。
	func _head_toward(destination: String) -> void:
		var next_map := _next_hop_toward(destination)
		if next_map == "":
			return

		var index := -1
		for i in _session.map.exits.size():
			if (_session.map.exits[i] as MapExit).to_map == next_map:
				index = i
				break
		if index < 0:
			return
		var gate: Vector2i = (_session.map.exits[index] as MapExit).at
		if Grid.chebyshev(_session.player.position, gate) <= 1:
			if _travel_cooldown > 0:
				return
			_travel_cooldown = 240
			if _session.travel_to(next_map):
				travels += 1
			return
		_session.move_player_to(gate)


	## 世界表就四张图，直接看一层邻居够用了，犯不上上 Dijkstra。
	## 玩法层用空串表示"不用走"。
	func _next_hop_toward(destination: String) -> String:
		if destination == _session.map_id:
			return ""
		var links := _session.definition.links
		for entry in links:
			if (entry as MapLink).to_map == destination:
				return destination
		for entry in links:
			var hop: String = (entry as MapLink).to_map
			var def := WorldDatabase.try_get(hop)
			if def == null:
				continue
			for inner in def.links:
				if (inner as MapLink).to_map == destination:
					return hop
		return "" if links.is_empty() else (links[0] as MapLink).to_map


	# ── 打猎 ──────────────────────────────────────────────────────────

	func _hunt() -> void:
		var player := _session.player
		var wanted_ground := Naming.MAP_SUBURB
		if player.level >= 15:
			wanted_ground = Naming.MAP_CAVE
		elif player.level >= 8:
			wanted_ground = Naming.MAP_FOREST
		if _session.map_id != wanted_ground:
			_head_toward(wanted_ground)
			return

		# OrderBy(等级超标记 1).ThenBy(曼哈顿距离)：先挑没超标的，再挑最近的。
		var target: MonsterUnit = null
		var target_flag := 2
		var target_distance := 0
		for entry in _session.monsters:
			var monster := entry as MonsterUnit
			if not monster.alive:
				continue
			var flag := 1 if monster.def.level > player.level + 2 else 0
			var distance := Grid.manhattan(monster.position, player.position)
			if target == null or flag < target_flag \
				or (flag == target_flag and distance < target_distance):
				target = monster
				target_flag = flag
				target_distance = distance

		if target == null or target.def.level > player.level + 2:
			# 本图清空了或只剩打不过的，就走图换场，而不是站在原地等刷新。
			var index := HUNTING_GROUNDS.find(_session.map_id)
			var rotation: String = HUNTING_GROUNDS[(maxi(0, index) + 1) % HUNTING_GROUNDS.size()]
			if _is_adjacent_to_any_exit() and _travel_cooldown <= 0:
				_travel_cooldown = 240
				if _session.use_nearest_exit():
					travels += 1
				return
			_head_toward(rotation if rotation != _session.map_id else wanted_ground)
			return

		if player.hp_percent < 0.3 and player.bag.count_of(Naming.ITEM_POTION_HP_SMALL) == 0:
			_head_toward(GameSession.HOME_MAP_ID)
			return

		if Grid.chebyshev(player.position, target.position) > 1:
			if _cast(Naming.SKILL_BOLT, target.position):
				return
			_session.move_player_to(target.position)
			return

		if _cast(Naming.SKILL_MOON, target.position):
			return
		if _cast(Naming.SKILL_SLASH, target.position):
			return
		_session.attack_target(target)


	func _is_adjacent_to_any_exit() -> bool:
		for entry in _session.map.exits:
			if Grid.chebyshev(_session.player.position, (entry as MapExit).at) <= 1:
				return true
		return false


	func _cast(skill_id: String, aim: Vector2i) -> bool:
		if not _session.knows(skill_id) or _session.cooldown_left(skill_id) > 0.0:
			return false
		if not _session.cast_at(skill_id, aim).success:
			return false
		skill_casts += 1
		return true
