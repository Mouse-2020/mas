class_name AttackResult
extends RefCounted

var hit := false
var damage := 0
var critical := false
var experience := 0
var killed := false


static func make(p_hit: bool, p_damage: int, p_critical: bool, p_experience: int, p_killed: bool) -> AttackResult:
	var result := AttackResult.new()
	result.hit = p_hit
	result.damage = p_damage
	result.critical = p_critical
	result.experience = p_experience
	result.killed = p_killed
	return result
