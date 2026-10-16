class_name QuestPanel
extends CanvasLayer

# 任务：左上常驻的进行中提示 + J 键翻开的完整任务簿。
# 进度、能不能交、还差什么都问 system/session.gd，面板自己不算。

var _session: GameSession
var _tracker: VBoxContainer
var _log: PanelContainer
var _log_body: VBoxContainer
var _log_open := false
var _dirty := true


func bind(session: GameSession) -> void:
	_session = session
	_dirty = true
	# 事件总线订阅一次即可，面板不再由场景根居中转发。
	if not Event.raised.is_connected(_on_event):
		Event.raised.connect(_on_event)


func mark_dirty() -> void:
	_dirty = true


func _ready() -> void:
	layer = 2

	var box := VBoxContainer.new()
	box.position = Vector2(12, 158)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_tracker = box

	_log = PanelContainer.new()
	_log.position = Vector2(12, 158)
	_log.custom_minimum_size = Vector2(392, 384)
	_log.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	style.border_color = Color(1, 1, 1, 0.18)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_log.add_theme_stylebox_override("panel", style)
	add_child(_log)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(384, 368)
	_log.add_child(scroll)
	_log_body = VBoxContainer.new()
	_log_body.size_flags_horizontal = Control.SIZE_EXPAND
	_log_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_log_body)


func toggle_log() -> void:
	_log_open = not _log_open
	_log.visible = _log_open
	_tracker.visible = not _log_open
	_dirty = true


func _process(_delta: float) -> void:
	if _session == null or not _dirty:
		return
	_rebuild()
	_dirty = false


func _rebuild() -> void:
	for child in _tracker.get_children():
		child.queue_free()
	for child in _log_body.get_children():
		child.queue_free()

	_tracker.add_child(_header("任务"))
	var shown := 0
	for quest in QuestDatabase.all_defs():
		var state := _session.state_of(quest.id)
		if state.status != Enums.QuestStatus.ACTIVE:
			continue
		_tracker.add_child(_line(track(quest), _session.is_complete(quest)))
		shown += 1
		if shown >= 4:
			break
	if shown == 0:
		_tracker.add_child(_line("  没有任务  去武馆教头那儿聊聊", false))

	_log_body.add_child(_header("任务簿  （J 关闭）"))
	for quest in QuestDatabase.all_defs():
		var state := _session.state_of(quest.id)
		var status := ""
		match state.status:
			Enums.QuestStatus.DONE:
				status = "已完成"
			Enums.QuestStatus.ACTIVE:
				status = "可交付" if _session.is_complete(quest) else "进行中"
			_:
				status = "可接" if _session.quest_prerequisite_met(quest) else "未解锁"
		var color := Color(0.9, 0.93, 0.98)
		if state.status == Enums.QuestStatus.DONE:
			color = Color(0.55, 0.72, 0.5)
		elif status == "可交付":
			color = Color(1.0, 0.85, 0.4)
		elif status == "未解锁":
			color = Color(0.55, 0.55, 0.58)

		_log_body.add_child(_title("%s  %s  %s" % [quest.display_name, status, progress(quest)], color))
		_log_body.add_child(_line("  %s" % hint(quest), false))
		_log_body.add_child(_line("  酬劳：%d 经验、%d 金币、%s" % [
			quest.reward_experience, quest.reward_gold, rewards(quest)], false))


func track(quest: QuestDef) -> String:
	var tail := "  可交付：%s" % quest.turn_in_npc_id if _session.is_complete(quest) else "  %s" % _session.hint_of(quest)
	return "◦ %s  %s%s" % [quest.display_name, progress(quest), tail]


func progress(quest: QuestDef) -> String:
	if quest.kind == Enums.QuestKind.KILL:
		return "%d/%d" % [mini(_session.progress_of(quest), quest.count), quest.count]
	return "%d/%d" % [mini(_session.bag.count_of(quest.target), quest.count), quest.count]


static func hint(quest: QuestDef) -> String:
	if quest.kind == Enums.QuestKind.KILL:
		return "目标：%s ×%d" % [quest.target, quest.count]
	return "上交：%s ×%d" % [quest.target, quest.count]


func rewards(quest: QuestDef) -> String:
	if quest.rewards.is_empty():
		return "无实物"
	var parts: Array[String] = []
	for entry in quest.rewards:
		var reward: QuestReward = entry
		parts.append("%s x%d" % [reward.item_id, reward.count])
	return "、".join(parts)


static func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1.0, 0.88, 0.55)
	label.add_theme_font_size_override("font_size", 16)
	return label


static func _title(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", 16)
	return label


static func _line(text: String, ready: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1.0, 0.85, 0.4) if ready else Color(0.78, 0.8, 0.84)
	label.add_theme_font_size_override("font_size", 15)
	return label


func _on_event(_event: GameEvent) -> void:
	mark_dirty()
