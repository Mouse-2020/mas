class_name DialoguePanel
extends CanvasLayer

# 对话面板。说什么、能点什么全由 system/session.gd 的 talk_to 算出来，这里只把选项摆成按钮，
# 再按 choose 的返回值决定要不要开店、要不要收掉面板。

const WIDTH := 540.0
const HEIGHT := 300.0

var _session: GameSession
var _panel: PanelContainer
var _who: Label
var _speech: Label
var _options: VBoxContainer
var _npc_id := ""

var shop_chosen: Callable
var say: Callable

var is_open: bool:
	get:
		return _panel.visible


func bind(session: GameSession) -> void:
	_session = session
	close()
	# 事件总线订阅一次即可，面板不再由场景根居中转发。
	if not Event.raised.is_connected(_on_event):
		Event.raised.connect(_on_event)


func _ready() -> void:
	layer = 4
	var view := get_viewport().get_visible_rect().size

	_panel = PanelContainer.new()
	_panel.position = Vector2(view.x / 2.0 - WIDTH / 2.0, 150)
	_panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.1, 0.95)
	style.border_color = Color(1, 1, 1, 0.2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_panel.visible = false

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_who = _make_label("", 19, Color(1.0, 0.88, 0.55))
	box.add_child(_who)

	_speech = _make_label("", 16, Color(0.92, 0.92, 0.9))
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.custom_minimum_size = Vector2(WIDTH - 32, 74)
	box.add_child(_speech)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - 24, HEIGHT - 150)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)
	_options = VBoxContainer.new()
	_options.size_flags_horizontal = Control.SIZE_EXPAND
	_options.add_theme_constant_override("separation", 4)
	scroll.add_child(_options)


## 第一次打开会记一句"和某某说话"，之后重建只按当前状态摆按钮。
func open(npc_id: String) -> void:
	_show(_session.talk_to(npc_id), npc_id)


func rebuild() -> void:
	if not _panel.visible or _npc_id.is_empty():
		return
	_show(_session.talk_to(_npc_id, true), _npc_id)


func _show(dialogue: NpcDialogue, npc_id: String) -> void:
	if dialogue == null:
		close()
		return
	_npc_id = npc_id
	var def := NpcDatabase.try_get(npc_id)
	_who.text = def.display_name if def != null else npc_id
	_speech.text = dialogue.text

	for child in _options.get_children():
		child.queue_free()
	for i in dialogue.options.size():
		var option := dialogue.options[i] as DialogueOption
		var button := Button.new()
		button.text = option.label
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = option.kind == Enums.DialogueKind.TALK
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_pick.bind(i))
		_options.add_child(button)
	_panel.visible = true


func _pick(index: int) -> void:
	var outcome := _session.choose(_npc_id, index)
	if outcome.message != "":
		if say.is_valid():
			say.call(outcome.message)
	if outcome.travel_to_map != "":
		close()
		return
	if outcome.open_shop_id != "":
		close()
		if shop_chosen.is_valid():
			shop_chosen.call(outcome.open_shop_id)
		return
	rebuild()


func close() -> void:
	_panel.visible = false
	_npc_id = ""


static func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", size)
	return label


## 任务状态一变，对话里那排按钮就该跟着变（能交了就得冒出来）。
func _on_event(event: GameEvent) -> void:
	if event.type == Enums.GameEventType.QUEST_ACCEPT \
			or event.type == Enums.GameEventType.QUEST_READY \
			or event.type == Enums.GameEventType.QUEST_COMPLETE:
		rebuild()
