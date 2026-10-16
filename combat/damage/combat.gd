class_name Combat
extends RefCounted

# 命中与伤害的算法集中在这里，表现层和自检脚本共用同一套数。

## 区间下限被写大也能算，配表手滑时不至于掷出负数。
static func _roll(rng: Rng, min_value: int, max_value: int) -> int:
	return rng.next_inclusive(mini(min_value, max_value), maxi(min_value, max_value))


static func hit_chance(attacker: Unit, target: Unit) -> float:
	var difference := attacker.get_stats().hit - target.get_stats().dodge
	var level_advantage := float(attacker.level - target.level) * 0.015
	return clampf(0.74 + float(difference) * 0.02 + level_advantage, 0.15, 0.95)


static func resolve(rng: Rng, attacker: Unit, target: Unit, skill: SkillDef = null) -> AttackResult:
	var bonus := 0.1 if skill != null and skill.kind == Enums.SkillKind.BOLT else 0.0
	if not rng.chance(clampf(hit_chance(attacker, target) + bonus, 0.15, 0.97)):
		return AttackResult.make(false, 0, false, 0, false)

	var offense := _roll(rng, attacker.get_stats().dc_min, attacker.get_stats().dc_max) \
		+ _roll(rng, attacker.get_stats().mc_min, attacker.get_stats().mc_max) \
		+ _roll(rng, attacker.get_stats().sc_min, attacker.get_stats().sc_max)
	# 法术走内力防御，物理技能与平砍走物理防御。
	var defense := 0
	if skill != null and skill.kind == Enums.SkillKind.BOLT:
		defense = _roll(rng, target.get_stats().mac_min, target.get_stats().mac_max)
	else:
		defense = _roll(rng, target.get_stats().ac_min, target.get_stats().ac_max)

	# 倍率只乘在"出手"这一半上，防御照常扣，高倍率不会退化成固定伤害。
	var damage := 0
	if skill == null:
		damage = int(offense - defense)
	else:
		damage = int(float(offense) * skill.factor + skill.flat_damage - defense)
	damage = maxi(1, damage)
	var critical := rng.chance(0.08)
	if critical:
		damage = int(float(damage) * 1.6)

	damage = clampi(damage, 0, target.hp)
	target.hp -= damage

	# 武器每砍一下掉一点耐久，装备则挨打时掉，逼着玩家回武馆修装备。
	if attacker is PlayerUnit:
		(attacker as PlayerUnit).gear.wear_down()
	if target is PlayerUnit:
		(target as PlayerUnit).gear.wear_down()

	var killed := not target.alive
	var experience := 0
	if killed and target is MonsterUnit and attacker is PlayerUnit:
		experience = (target as MonsterUnit).def.experience

	return AttackResult.make(true, damage, critical, experience, killed)


## 按掉落表 roll 一次击杀奖励。uid_factory 是 Callable(def_id) -> String。
static func roll_drops(rng: Rng, def: MonsterDef, uid_factory: Callable) -> Array:
	var drops: Array = []
	for roll in def.drops:
		if not rng.chance(roll.chance):
			continue
		var item_def := ItemDatabase.try_get(roll.item_id)
		if item_def == null:
			continue
		var count := rng.next_inclusive(maxi(1, roll.min_count), maxi(roll.min_count, roll.max_count))
		drops.append(ItemInstance.new(uid_factory.call(roll.item_id), item_def.id, count, item_def.max_durability))
	return drops
