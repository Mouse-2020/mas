class_name SkillCast
extends RefCounted

# 一次施放的结果，UI 用它决定飘字与冷却刷新。

var success := false
var reason := ""
var total_damage := 0
var hit_count := 0


static func make(p_success: bool, p_reason: String, p_total_damage: int, p_hit_count: int) -> SkillCast:
	var cast := SkillCast.new()
	cast.success = p_success
	cast.reason = p_reason
	cast.total_damage = p_total_damage
	cast.hit_count = p_hit_count
	return cast
