class_name QuestDatabase
extends RefCounted

# 任务表：读 quest/quests.csv，一行一条。链式关系只靠 requires 这一条边表达，够用了。

const CSV_PATH := "res://quest/quests.csv"

static var _defs := {}
static var _list: Array = []


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(quest_id: String) -> QuestDef:
	_ensure()
	if not _defs.has(quest_id):
		push_error("未知任务：" + quest_id)
		assert(false)
		return null
	return _defs[quest_id]


static func try_get(quest_id: String) -> QuestDef:
	_ensure()
	return _defs.get(quest_id)


## 由"武馆教头"这类 NPC 主动提供的任务，对话选项按表里的顺序排。
static func offered_by(npc_id: String) -> Array:
	var out: Array = []
	for def in all_defs():
		if def.npc_id == npc_id:
			out.append(def)
	return out


static func turned_in_at(npc_id: String) -> Array:
	var out: Array = []
	for def in all_defs():
		if def.turn_in_npc_id == npc_id:
			out.append(def)
	return out


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	var loaded: Array = []
	for entry in CsvTable.read(CSV_PATH):
		loaded.append(_make(entry as Dictionary))

	for def in loaded:
		if _defs.has(def.id):
			push_error("任务 id 重复：" + def.id)
			assert(false)
			continue
		# 配错一个 id 的后果是任务永远交不掉，所以在加载期就查干净。
		if NpcDatabase.try_get(def.npc_id) == null:
			push_error("任务 %s 引用了不存在的 NPC：%s" % [def.id, def.npc_id])
			assert(false)
		if NpcDatabase.try_get(def.turn_in_npc_id) == null:
			push_error("任务 %s 交付给不存在的 NPC：%s" % [def.id, def.turn_in_npc_id])
			assert(false)
		if def.kind == Enums.QuestKind.KILL and MonsterDatabase.try_get(def.target) == null:
			push_error("任务 %s 打的是不存在的怪：%s" % [def.id, def.target])
			assert(false)
		if def.kind == Enums.QuestKind.COLLECT and ItemDatabase.try_get(def.target) == null:
			push_error("任务 %s 收的是不存在的物品：%s" % [def.id, def.target])
			assert(false)
		if def.requires_quest_id != "" and _find_prerequisite(def.requires_quest_id, loaded) == null:
			push_error("任务 %s 的前置不存在：%s" % [def.id, def.requires_quest_id])
			assert(false)
		for reward in def.rewards:
			if ItemDatabase.try_get(reward.item_id) == null:
				push_error("任务 %s 奖励了不存在的物品：%s" % [def.id, reward.item_id])
				assert(false)
		_defs[def.id] = def
		_list.append(def)


static func _make(row: Dictionary) -> QuestDef:
	var def := QuestDef.new()
	def.id = CsvTable.text(row, "id")
	def.display_name = CsvTable.text(row, "title")
	def.offer = CsvTable.text(row, "offer")
	def.hint = CsvTable.text(row, "hint")
	def.turn_in_text = CsvTable.text(row, "turn_in_text")
	def.kind = CsvTable.choice(row, "kind", Enums.QuestKind, Enums.QuestKind.KILL)
	def.target = CsvTable.text(row, "target")
	def.count = CsvTable.integer(row, "count", 1)
	def.npc_id = CsvTable.text(row, "npc")
	def.turn_in_npc_override = CsvTable.text(row, "turn_in_npc")
	def.requires_quest_id = CsvTable.text(row, "requires")
	def.reward_experience = CsvTable.integer(row, "exp", 0)
	def.reward_gold = CsvTable.integer(row, "gold", 0)
	def.rewards = CsvTable.rewards(row, "rewards")
	return def


static func _find_prerequisite(quest_id: String, loaded: Array) -> QuestDef:
	if _defs.has(quest_id):
		return _defs[quest_id]
	for other in loaded:
		if other.id == quest_id:
			return other
	return null
