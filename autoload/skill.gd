extends Node

# 技能学习、冷却、释放管理。招式数值在 combat/skill/skills.csv 里，这里只管"会不会、能不能放、放出去怎样"。

func known() -> Array:
	return Game.session.known_skills


func knows(skill_id: String) -> bool:
	return Game.session.knows(skill_id)


func hotkey_slot(hotkey: int) -> String:
	return Game.session.skill_at_hotkey(hotkey)


func hotkey_of(skill_id: String) -> int:
	return Game.session.hotkey_of(skill_id)


func cooldown_left(skill_id: String) -> float:
	return Game.session.cooldown_left(skill_id)


## 返回空串表示可以施放。
func can_cast(skill_id: String) -> String:
	return Game.session.can_cast(skill_id)


func learn(skill_id: String) -> bool:
	return Game.session.learn(skill_id)


## 指哪打哪；回血与护体不挑目标，落点自动收到自己身上。
func cast(skill_id: String, aim: Vector2i) -> SkillCast:
	var def := SkillDatabase.get_def(skill_id)
	var target := aim
	if def.kind == Enums.SkillKind.HEAL or def.kind == Enums.SkillKind.BUFF:
		target = Game.session.player.position
	return Game.session.cast_at(skill_id, target)


## 快捷键不带坐标时：目标类招式自动打最近的怪。
func cast_by_hotkey(hotkey: int) -> SkillCast:
	var skill_id := hotkey_slot(hotkey)
	if skill_id == "":
		return SkillCast.make(false, "这一格还没招式", 0, 0)
	return Game.session.cast(skill_id)
