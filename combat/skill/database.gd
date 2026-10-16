class_name SkillDatabase
extends RefCounted

# 技能表：读 combat/skill/skills.csv，一行一招。

const CSV_PATH := "res://combat/skill/skills.csv"

static var _defs := {}
static var _list: Array = []
static var _ordered: Array = []


## 快捷键顺序就是学习等级顺序（低等级在前），数字键与这个列表一一对应。
static func ordered() -> Array:
	_ensure()
	if _ordered.is_empty():
		_ordered = _list.duplicate()
		_ordered.sort_custom(_by_level_then_id)
	return _ordered


static func _by_level_then_id(a: SkillDef, b: SkillDef) -> bool:
	if a.required_level != b.required_level:
		return a.required_level < b.required_level
	return a.id < b.id


static func all_defs() -> Array:
	_ensure()
	return _list


static func get_def(skill_id: String) -> SkillDef:
	_ensure()
	if not _defs.has(skill_id):
		push_error("未知技能：" + skill_id)
		assert(false)
		return null
	return _defs[skill_id]


static func try_get(skill_id: String) -> SkillDef:
	_ensure()
	return _defs.get(skill_id)


## 这个等级该自动学会的招式。
static func auto_learned(level: int) -> Array:
	var out: Array = []
	for def in ordered():
		if def.auto_learn and def.required_level <= level:
			out.append(def)
	return out


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for entry in CsvTable.read(CSV_PATH):
		var row := entry as Dictionary
		var def := _make(row)
		if _defs.has(def.id):
			push_error("技能 id 重复：" + def.id)
			assert(false)
			continue
		if def.kind in [Enums.SkillKind.STRIKE, Enums.SkillKind.SWEEP, Enums.SkillKind.BOLT] and def.factor <= 0:
			push_error("技能 %s 没有伤害倍率" % def.id)
			assert(false)
		if def.kind == Enums.SkillKind.BUFF and (def.buff == null or def.buff.is_empty):
			push_error("技能 %s 是增益但没有属性" % def.id)
			assert(false)
		_defs[def.id] = def
		_list.append(def)


static func _make(row: Dictionary) -> SkillDef:
	var def := SkillDef.new()
	def.id = CsvTable.text(row, "id")
	def.title = CsvTable.text(row, "title")
	def.kind = CsvTable.choice(row, "kind", Enums.SkillKind, Enums.SkillKind.STRIKE)
	def.mp_cost = CsvTable.integer(row, "mp_cost", 0)
	def.cooldown = CsvTable.real(row, "cooldown", 1.0)
	def.required_level = CsvTable.integer(row, "required_level", 1)
	def.reach = CsvTable.integer(row, "reach", 1)
	def.factor = CsvTable.real(row, "factor", 1.0)
	def.flat_damage = CsvTable.integer(row, "flat_damage", 0)
	def.heal_percent = CsvTable.integer(row, "heal_percent", 30)
	def.buff_seconds = CsvTable.real(row, "buff_seconds", 10.0)
	def.auto_learn = CsvTable.boolean(row, "auto_learn")
	def.description = CsvTable.text(row, "description")
	def.sound = CsvTable.text(row, "sound", "cast")
	# 非增益招式留 null，别让"有没有属性块"变成第二种判定口径。
	var buff := CsvTable.stats(row, "buff")
	if def.kind == Enums.SkillKind.BUFF or not buff.is_empty:
		def.buff = buff
	return def
