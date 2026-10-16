class_name SkillBar
extends CanvasLayer

# 底部技能栏：十格对应 玩法层的 1..9 与 0 快捷键。
# 冷却用一块从顶往下压的暗罩表示，剩余秒数写在格子上，不额外算动画。

const SLOTS := 10
const CELL_SIZE := 50.0
const GAP := 4.0

var _session: GameSession
var _buttons: Array[Button] = []
var _shades: Array[ColorRect] = []
var _counts: Array[Label] = []

## 点第几格。玩法由 Main 去问 system/session.gd，这里不认识技能数值。
var pressed: Callable


func bind(session: GameSession) -> void:
	_session = session
	refresh()


func _ready() -> void:
	layer = 3
	var view := get_viewport().get_visible_rect().size

	var box := HBoxContainer.new()
	box.position = Vector2(view.x / 2.0 - (SLOTS * CELL_SIZE + (SLOTS - 1) * GAP) / 2.0, view.y - 88)
	box.add_theme_constant_override("separation", int(GAP))
	add_child(box)

	for i in SLOTS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		button.expand_icon = false
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", _cell(Color(0.11, 0.12, 0.16, 0.92)))
		button.add_theme_stylebox_override("hover", _cell(Color(0.2, 0.23, 0.3, 0.95)))
		box.add_child(button)
		_buttons.append(button)

		var hotkey := _make_label(_key_hint(i), 12, Color(1, 1, 1, 0.7))
		hotkey.position = Vector2(3, 2)
		button.add_child(hotkey)

		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.62)
		shade.size = Vector2(CELL_SIZE, 0)
		button.add_child(shade)
		_shades.append(shade)

		var count := _make_label("", 16, Color(1, 0.85, 0.4))
		count.position = Vector2(0, 16)
		count.size = Vector2(CELL_SIZE, 20)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(count)
		_counts.append(count)

		button.pressed.connect(_fire.bind(i + 1))


func _fire(index: int) -> void:
	if pressed.is_valid():
		pressed.call(index)


## 第十格写 0，和小腿上的快捷键一致；技能多于十招时得改成翻页，现在先不满屏。
static func _key_hint(slot_index: int) -> String:
	return "0" if slot_index == 9 else str(slot_index + 1)


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if _session == null:
		return

	for i in SLOTS:
		var button := _buttons[i]
		var skill_id := _session.skill_at_hotkey(i + 1)
		if skill_id == "":
			button.icon = null
			button.modulate = Color(1, 1, 1, 0.35)
			button.tooltip_text = "空格子  升等级或读技能书才会往后排一招"
			_shades[i].size = Vector2(CELL_SIZE, 0)
			_counts[i].text = ""
			continue

		var def := SkillDatabase.get_def(skill_id)
		var left := _session.cooldown_left(skill_id)
		button.icon = ArtGen.skill(def)
		button.modulate = _tint(_session, def)
		button.tooltip_text = _describe(def, left)

		var ratio := clampf(left / def.cooldown, 0.0, 1.0) if def.cooldown > 0.0 else 0.0
		_shades[i].size = Vector2(CELL_SIZE, CELL_SIZE * ratio)
		_counts[i].text = str(ceili(left)) if left > 0.05 else ""


## 学是学会了，但蓝不够或等级不够时格子要一眼看出"这会儿放不出"。
static func _tint(session: GameSession, def: SkillDef) -> Color:
	if session.can_cast(def.id) != "":
		return Color(0.58, 0.58, 0.68, 0.85)
	for entry in session.effects:
		var effect := entry as SkillEffect
		if effect.skill_id == def.id:
			return Color(1.0, 0.92, 0.6)
	return Color(1, 1, 1)


static func _describe(def: SkillDef, left: float) -> String:
	var head := "%s  %d 蓝  冷却 %s 秒" % [def.display_name, def.mp_cost, _num(def.cooldown, 1)]
	if def.kind == Enums.SkillKind.HEAL:
		head += "  回 %d%% 生命" % def.heal_percent
	if def.kind in [Enums.SkillKind.STRIKE, Enums.SkillKind.SWEEP, Enums.SkillKind.BOLT]:
		head += "  倍率 %s" % _num(def.factor, 2)
	if def.kind == Enums.SkillKind.BOLT:
		head += "  射程 %d 格" % def.reach
	if def.required_level > 1:
		head += "  需要 %d 级" % def.required_level
	if left > 0.05:
		head += "  还剩 %s 秒" % _num(left, 1)
	return head if def.description.is_empty() else "%s\n%s" % [head, def.description]


## 最多 N 位小数、尾零全削（"0.#" 那种观感）。
static func _num(value: float, decimals: int) -> String:
	var text := (("%%.%df" % decimals) % value)
	if "." in text:
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text


static func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", size)
	return label


static func _cell(background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = Color(1, 1, 1, 0.18)
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	box.set_border_width_all(1)
	box.set_content_margin_all(2)
	return box
