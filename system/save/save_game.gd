class_name SaveGame
extends RefCounted

# 整局状态快照。地形不进存档——每张图按 (地图定义, 种子) 重生成，
# 读档后不可能出现"地图漂移"，需要记的只有每张图里活着的动态内容。
# 存档用 Dictionary 对接 JSON，键名 snake_case。

const FORMAT_VERSION := 3


static func capture(session: GameSession) -> Dictionary:
	var player := session.player
	var save := {
		"version": FORMAT_VERSION,
		"seed": session.seed,
		"kills": session.kill_count,
		"elapsed": session.elapsed,
		"uid_counter": session.uid_counter,
		"current_map_id": session.map_id,
		"player": {
			"x": player.position.x,
			"y": player.position.y,
			"level": player.level,
			"hp": player.hp,
			"mp": player.mp,
			"gold": player.gold,
			"experience": player.experience,
			"job": player.job,
			"death_timer": player.death_timer,
			"death_count": player.death_count,
			"bag": [],
			"worn": [],
		},
		"quests": [],
		"skills": [],
		"cooldowns": [],
		"effects": [],
		"maps": [],
	}

	for entry in player.bag.enumerate():
		save["player"]["bag"].append(_save_item(entry as ItemInstance))

	for slot in player.gear.worn:
		save["player"]["worn"].append({
			"slot": slot,
			"item": _save_item(player.gear.worn[slot] as ItemInstance),
		})

	for entry in session.quests:
		var quest := entry as QuestState
		if quest.status != Enums.QuestStatus.NONE:
			save["quests"].append({"id": quest.id, "status": quest.status, "progress": quest.progress})

	for def in session.known_skills:
		save["skills"].append(def.id)

	for skill_id in session.cooldowns:
		var seconds: float = session.cooldowns[skill_id]
		if seconds > 0.0:
			save["cooldowns"].append({"skill_id": skill_id, "seconds": seconds})

	for entry in player.effects:
		var effect := entry as SkillEffect
		save["effects"].append({"skill_id": effect.skill_id, "remaining": effect.remaining})

	for entry in session.visited_maps:
		var runtime := entry as MapRuntime
		var map_save := {"id": runtime.def.id, "monsters": [], "loot": []}
		for monster in runtime.monsters:
			var unit := monster as MonsterUnit
			map_save["monsters"].append({
				"def_id": unit.def.id,
				"home_x": unit.home.x, "home_y": unit.home.y,
				"x": unit.position.x, "y": unit.position.y,
				"hp": unit.hp, "aggro": unit.aggro, "respawn_seconds": unit.respawn_seconds,
			})
		for stack in runtime.loot:
			var loot := stack as LootItem
			map_save["loot"].append({
				"x": loot.position.x, "y": loot.position.y,
				"life_seconds": loot.life_seconds, "item": _save_item(loot.item),
			})
		save["maps"].append(map_save)

	return save


static func restore(save_data: Dictionary) -> GameSession:
	var version: int = int(save_data.get("version", 0))
	if version != FORMAT_VERSION:
		push_error("存档版本 %d 与当前 %d 不兼容" % [version, FORMAT_VERSION])
		return null

	# 构造函数会在新手村刷一批怪，读档前得把它的动态内容让位给存档。
	var session := GameSession.new_campaign(int(save_data["seed"]))
	session.kill_count = int(save_data["kills"])
	session.elapsed = float(save_data["elapsed"])
	session.uid_counter = maxi(1, int(save_data["uid_counter"]))
	session.open_for_restore(GameSession.HOME_MAP_ID)

	var saved_player: Dictionary = save_data["player"]
	var player := session.player
	player.job = saved_player["job"]
	player.level = maxi(1, int(saved_player["level"]))
	player.recompute_base()
	player.experience = int(saved_player["experience"])
	player.gold = int(saved_player["gold"])
	player.death_count = int(saved_player["death_count"])
	player.death_timer = float(saved_player["death_timer"])
	player.bag.clear()
	player.gear.clear()
	player.effects.clear()

	var index := 0
	for entry in saved_player["bag"]:
		if index >= Inventory.CAPACITY:
			break
		var item := _from_save(entry)
		if item == null:
			continue
		player.bag.add_at(index, item)
		index += 1

	for entry in saved_player["worn"]:
		var item := _from_save(entry["item"])
		if item == null:
			continue
		player.gear.force_wear(entry["slot"], item)

	player.hp = clampi(int(saved_player["hp"]), 0, player.max_hp)
	player.mp = clampi(int(saved_player["mp"]), 0, player.max_mp)

	session.learned.clear()
	for skill_id in save_data["skills"]:
		if SkillDatabase.try_get(skill_id) != null:
			session.learned[skill_id] = true
	for entry in save_data["cooldowns"]:
		var skill_id: String = entry["skill_id"]
		if session.learned.has(skill_id):
			session.cooldown_map[skill_id] = maxf(0.0, float(entry["seconds"]))

	for entry in save_data["effects"]:
		var skill := SkillDatabase.try_get(entry["skill_id"])
		if skill == null or skill.buff == null:
			continue
		var effect := SkillEffect.new()
		effect.skill_id = skill.id
		effect.title = skill.display_name
		effect.bonus = skill.buff.clone()
		effect.remaining = maxf(0.0, float(entry["remaining"]))
		player.effects.append(effect)

	session.quest_list.clear()
	for entry in save_data["quests"]:
		if QuestDatabase.try_get(entry["id"]) == null:
			continue
		var state := QuestState.new()
		state.id = entry["id"]
		state.status = entry["status"]
		state.progress = int(entry["progress"])
		session.quest_list.append(state)

	# 当前那张图最后开：玩家落位要用 _current，先开就会被后面的图覆盖掉。
	var current_map_id: String = save_data["current_map_id"]
	var order: Array = []
	for entry in save_data["maps"]:
		if entry["id"] != current_map_id and WorldDatabase.try_get(entry["id"]) != null:
			order.append(entry)
	for entry in save_data["maps"]:
		if entry["id"] == current_map_id and WorldDatabase.try_get(entry["id"]) != null:
			order.append(entry)

	for map_save in order:
		session.open_for_restore(map_save["id"])
		for monster in map_save["monsters"]:
			var def := MonsterDatabase.try_get(monster["def_id"])
			if def == null:
				continue
			var position := session.map.walkable_near(Vector2i(int(monster["x"]), int(monster["y"])))
			if session.occupancy_map.has(position):
				continue

			var unit := MonsterUnit.new(def, position)
			unit.home = session.map.walkable_near(Vector2i(int(monster["home_x"]), int(monster["home_y"])))
			unit.aggro = false
			unit.respawn_seconds = float(monster["respawn_seconds"])
			unit.hp = clampi(int(monster["hp"]), 0, unit.max_hp)
			session.monster_list.append(unit)
			# 死掉的怪占着家里那格会让重生一直失败，所以只给活着的登记占位。
			if unit.alive:
				session.occupancy_map[position] = unit

		for loot in map_save["loot"]:
			if ItemDatabase.try_get(loot["item"]["def_id"]) == null:
				continue
			var item := _from_save(loot["item"])
			if item == null:
				continue
			var stack := LootItem.new(item, session.map.walkable_near(Vector2i(int(loot["x"]), int(loot["y"]))))
			stack.life_seconds = float(loot["life_seconds"])
			session.loot_list.append(stack)

	if WorldDatabase.try_get(current_map_id) == null:
		session.open_for_restore(GameSession.HOME_MAP_ID)
	player.position = session.map.walkable_near(Vector2i(int(saved_player["x"]), int(saved_player["y"])))
	session.occupy_restored_player()
	return session


static func to_json(save_data: Dictionary) -> String:
	return JSON.stringify(save_data, "  ")


static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("存档内容为空或不是 JSON 对象")
		return {}
	return parsed


static func write_to_file(save_data: Dictionary, path: String) -> bool:
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("写不开存档文件：" + path)
		return false
	file.store_string(to_json(save_data))
	file.close()
	return true


static func read_from_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("读不开存档文件：" + path)
		return {}
	var text := file.get_as_text()
	file.close()
	return from_json(text)


static func _save_item(item: ItemInstance) -> Dictionary:
	return {
		"uid": item.uid,
		"def_id": item.def_id,
		"count": item.count,
		"durability": item.durability,
	}


## 遇到不存在的物品记一条错误后跳过那一件，其余照常还原（不中断整份读档）。
static func _from_save(entry: Dictionary) -> ItemInstance:
	var def := ItemDatabase.try_get(entry["def_id"])
	if def == null:
		push_error("存档里有不存在的物品：" + str(entry["def_id"]))
		return null
	ItemInstance.note_uid(entry["uid"])
	return ItemInstance.new(entry["uid"], def.id, maxi(1, int(entry["count"])), int(entry["durability"]))
