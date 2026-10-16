class_name Hud
extends CanvasLayer

# 左上角人物状态、下方战斗日志、死亡遮罩。只做展示，不改状态。

const MAX_LINES := 12

var _session: GameSession
var _hp: ProgressBar
var _mp: ProgressBar
var _xp: ProgressBar
var _headline: Label
var _attrs: Label
var _where: Label
var _log: RichTextLabel
var _death: Label
var _lines: Array[String] = []


func bind(session: GameSession) -> void:
	_session = session
	refresh()
	# 事件总线订阅一次即可，面板不再由场景根居中转发。
	if not Event.raised.is_connected(_on_event):
		Event.raised.connect(_on_event)


func _ready() -> void:
	layer = 1

	var left := PanelContainer.new()
	left.position = Vector2(12, 12)
	left.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.07, 0.09, 0.82)))
	add_child(left)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	left.add_child(box)

	_headline = _make_label("", 18)
	box.add_child(_headline)
	_hp = _bar(Color(0.78, 0.2, 0.22))
	_mp = _bar(Color(0.24, 0.46, 0.82))
	_xp = _bar(Color(0.86, 0.74, 0.3), 6)
	box.add_child(_hp)
	box.add_child(_mp)
	box.add_child(_xp)
	_attrs = _make_label("", 15)
	_where = _make_label("", 15)
	box.add_child(_attrs)
	box.add_child(_where)

	var view_height := get_viewport().get_visible_rect().size.y
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(12, view_height - 252)
	log_panel.custom_minimum_size = Vector2(470, 208)
	log_panel.add_theme_stylebox_override("panel", _flat(Color(0.05, 0.05, 0.07, 0.78)))
	add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	# FitContent 会让面板按行数无限长下去，把下面的操作提示盖住，所以固定高度滚动。
	_log.fit_content = false
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.custom_minimum_size = Vector2(462, 190)
	log_panel.add_child(_log)

	var help := _make_label(
		"左键 走/砍/说话  右键 拾取  空格 平砍  1-9 与 0 技能  Q 喝药  F 对话  T 传送门\n" +
		"B 背包  E 装备  J 任务簿  M 静音  F5 存档  F9 读档  F2 重开", 15)
	help.position = Vector2(12, view_height - 46)
	help.modulate = Color(1, 1, 1, 0.72)
	add_child(help)

	_death = _make_label("", 42)
	_death.visible = false
	add_child(_death)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func _flat(background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = Color(1, 1, 1, 0.12)
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_left = 6
	box.corner_radius_bottom_right = 6
	box.content_margin_left = 10.0
	box.content_margin_top = 8.0
	box.content_margin_right = 10.0
	box.content_margin_bottom = 8.0
	return box


static func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


static func _bar(fill: Color, height: int = 14) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(250, height)
	# 进度条用无边距的色块，否则 _flat() 那套 8px 内边距会把填充条挤成一个药丸。
	bar.add_theme_stylebox_override("background", _box(Color(0, 0, 0, 0.55), height))
	bar.add_theme_stylebox_override("fill", _box(fill, height))
	return bar


static func _box(color: Color, height: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(0)
	box.set_border_width_all(0)
	box.set_corner_radius_all(int(height / 2))
	return box


## 最多 N 位小数、尾零全削（"0.#" / "0.##" 那种观感）。
static func _num(value: float, decimals: int) -> String:
	var text := (("%%.%df" % decimals) % value)
	if "." in text:
		while text.ends_with("0"):
			text = text.substr(0, text.length() - 1)
		if text.ends_with("."):
			text = text.substr(0, text.length() - 1)
	return text


## UI 自己的一句话（放不出技能、钱不够之类），走同一条日志，不再多开一种提示。
func say(text: String) -> void:
	if text.is_empty():
		return
	var line := "[color=c9c9c9]%s[/color]" % text
	# 按住一个键不放就会把"魔法不够"刷满屏，同一句连着说两遍就没必要了。
	if not _lines.is_empty() and _lines[_lines.size() - 1] == line:
		return
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_log.text = "\n".join(_lines)


func append(events: Array) -> void:
	for entry in events:
		var event := entry as GameEvent
		var color := ""
		match event.type:
			Enums.GameEventType.KILL:
				color = "ffd35c"
			Enums.GameEventType.LEVEL_UP:
				color = "7be3ff"
			Enums.GameEventType.DEATH:
				color = "ff6a5a"
			Enums.GameEventType.LOOT, Enums.GameEventType.EQUIP, Enums.GameEventType.CONSUME:
				color = "9be67a"
			Enums.GameEventType.MISS, Enums.GameEventType.BLOCKED:
				color = "9a9a9a"
			Enums.GameEventType.ATTACK:
				color = "ffffff"
			_:
				color = "c9c9c9"
		_lines.append("[color=%s]%s[/color]" % [color, event.text])
		while _lines.size() > MAX_LINES:
			_lines.pop_front()
	_log.text = "\n".join(_lines)


func refresh() -> void:
	if _session == null:
		return
	var p := _session.player
	var s := p.get_stats()

	_headline.text = "%s  %s  %d 级  金币 %d" % [p.name, p.job, p.level, p.gold]
	_hp.max_value = maxi(1, p.max_hp)
	_hp.value = maxf(0, p.hp)
	_mp.max_value = maxi(1, s.max_mp)
	_mp.value = maxf(0, p.mp)
	_xp.max_value = maxi(1, p.experience_to_next)
	_xp.value = minf(p.experience, p.experience_to_next)
	_attrs.text = "攻 %d-%d  防 %d-%d  魔防 %d-%d  命中 %d  敏捷 %d" % [
		s.dc_min, s.dc_max, s.ac_min, s.ac_max, s.mac_min, s.mac_max, s.hit, s.dodge]
	_where.text = "%s%s  (%d,%d)  背包 %d/%d  负重 %d/%d  击杀 %d" % [
		_session.map.display_name,
		"（安全区）" if _session.map.safe else "",
		p.position.x, p.position.y,
		_session.bag.used_slots, Inventory.CAPACITY,
		_session.bag.total_weight, _session.bag.weight_limit,
		_session.kill_count]

	var buffs: Array[String] = []
	for entry in _session.effects:
		var effect := entry as SkillEffect
		buffs.append("%s %ss" % [effect.title, _num(effect.remaining, 1)])
	if not buffs.is_empty():
		_attrs.text += "  增益：" + "、".join(buffs)
	var doors := _session.map.exits.size()
	if doors > 0:
		_where.text += "  出口 %d（T 走门）" % doors

	_death.visible = not p.alive
	if not p.alive:
		var left := maxf(0.0, 2.5 - p.death_timer)
		_death.text = "你死了  %.1f 秒后在出生点苏醒" % left


func _on_event(event: GameEvent) -> void:
	append([event])
	refresh()
