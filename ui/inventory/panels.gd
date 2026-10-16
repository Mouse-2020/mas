class_name Panels
extends CanvasLayer

# 背包 + 装备面板。点背包一下就是"穿上/喝掉"，右键丢掉；点身上装备脱下。

const SLOT_SIZE := 46.0

var _session: GameSession
var _changed: Callable
var _bag_panel: PanelContainer
var _gear_panel: PanelContainer
var _bag_grid: GridContainer
var _gear_grid: GridContainer
var _bag_title: Label
var _repair: Button
var _dirty := false


func bind(session: GameSession, changed: Callable) -> void:
	_session = session
	_changed = changed
	_dirty = true
	# 事件总线订阅一次即可，面板不再由场景根居中转发。
	if not Event.raised.is_connected(_on_event):
		Event.raised.connect(_on_event)


func mark_dirty() -> void:
	_dirty = true


var any_visible: bool:
	get:
		return _bag_panel.visible or _gear_panel.visible


func toggle_bag() -> void:
	_show(_bag_panel, not _bag_panel.visible)


func toggle_gear() -> void:
	_show(_gear_panel, not _gear_panel.visible)


func hide_all() -> void:
	_show(_bag_panel, false)
	_show(_gear_panel, false)


func _show(panel: PanelContainer, should_show: bool) -> void:
	panel.visible = should_show
	if should_show:
		_dirty = true


func _ready() -> void:
	layer = 2
	var view := get_viewport().get_visible_rect().size

	var bag_box: Array = []
	_bag_panel = _build_panel(Vector2(view.x - 12 - 512, view.y - 12 - 268), 512, 268, bag_box)
	_bag_title = _make_label("背包", 15)
	bag_box[0].add_child(_bag_title)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = Inventory.COLUMNS
	bag_box[0].add_child(_bag_grid)

	var gear_box: Array = []
	_gear_panel = _build_panel(Vector2(view.x - 12 - 400, 12), 400, 226, gear_box)
	gear_box[0].add_child(_make_label("身上装备（点一下脱下）", 15))
	_gear_grid = GridContainer.new()
	_gear_grid.columns = 4
	gear_box[0].add_child(_gear_grid)

	_repair = Button.new()
	_repair.text = "修理"
	_repair.focus_mode = Control.FOCUS_NONE
	_repair.add_theme_font_size_override("font_size", 15)
	_repair.pressed.connect(_on_repair)
	gear_box[0].add_child(_repair)

	_bag_panel.visible = false
	_gear_panel.visible = false


func _build_panel(at_pos: Vector2, panel_width: float, panel_height: float, out_box: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = at_pos
	panel.custom_minimum_size = Vector2(panel_width, panel_height)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.93)
	style.border_color = Color(1, 1, 1, 0.18)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	out_box.append(box)
	return panel


static func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _process(_delta: float) -> void:
	if _session == null:
		return
	if not _dirty or not any_visible:
		return
	if _bag_panel.visible:
		_rebuild_bag()
	if _gear_panel.visible:
		_rebuild_gear()
	_dirty = false


func _rebuild_bag() -> void:
	for child in _bag_grid.get_children():
		child.queue_free()
	_bag_title.text = "背包  %d/%d 格  负重 %d/%d  金币 %d" % [
		_session.bag.used_slots, Inventory.CAPACITY,
		_session.bag.total_weight, _session.bag.weight_limit,
		_session.player.gold]

	for index in Inventory.CAPACITY:
		var item := _session.bag.at(index)
		var button := _make_slot(ArtGen.item(item.def) if item != null else null,
			str(item.count) if item != null and item.count > 1 else "")
		if item != null:
			button.tooltip_text = _describe_with_text(item)
		button.pressed.connect(_use_slot.bind(index))
		button.gui_input.connect(_on_bag_slot_input.bind(index))
		_bag_grid.add_child(button)


func _rebuild_gear() -> void:
	for child in _gear_grid.get_children():
		child.queue_free()

	for slot in Equipment.ALL_SLOTS:
		var item := _session.gear.at(slot)
		var button := _make_slot(ArtGen.item(item.def) if item != null else null,
			"%d/%d" % [item.durability, item.def.max_durability]
				if item != null and item.def.max_durability > 0 else "")
		button.tooltip_text = _slot_name(slot) if item == null else "%s  %s" % [_slot_name(slot), _describe_with_text(item)]
		button.pressed.connect(_unequip_slot.bind(slot))
		_gear_grid.add_child(button)

	# 修装备是铁匠铺的活儿，站在城里别的角落按不动这个钮。
	var cost := Trade.repair_cost(_session.gear)
	var at_bench := _near_repairer()
	_repair.text = "装备没坏，不用修" if cost <= 0 else "修理全身装备（%d 金币）" % cost
	_repair.disabled = not at_bench or cost <= 0 or _session.player.gold < cost
	_repair.tooltip_text = "" if at_bench else "得站到能修的老板跟前"


func _near_repairer() -> bool:
	for entry in _session.npcs:
		var npc := entry as NpcUnit
		if npc.def.can_repair and Grid.chebyshev(_session.player.position, npc.position) <= GameSession.TALK_RADIUS:
			return true
	return false


func _make_slot(icon: Texture2D, text: String) -> Button:
	var button := Button.new()
	button.icon = icon
	button.text = text
	button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	button.expand_icon = false
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	# 空格子也得看得见，否则玩家不知道背包还剩几格。
	button.add_theme_stylebox_override("normal", _cell(Color(0.14, 0.15, 0.19, 0.95)))
	button.add_theme_stylebox_override("hover", _cell(Color(0.24, 0.27, 0.34, 0.95)))
	button.add_theme_stylebox_override("pressed", _cell(Color(0.1, 0.11, 0.14, 0.95)))
	return button


static func _cell(background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = Color(1, 1, 1, 0.14)
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	box.set_border_width_all(1)
	box.set_content_margin_all(2)
	return box


static func _describe_with_text(item: ItemInstance) -> String:
	var text := ArtGen.describe(item.def)
	if not item.def.description.is_empty():
		text += "  " + item.def.description
	if item.def.max_durability > 0:
		text += "  耐久 %d/%d" % [item.durability, item.def.max_durability]
	return text


static func _slot_name(slot: int) -> String:
	match slot:
		Enums.EquipSlot.WEAPON:
			return "武器"
		Enums.EquipSlot.ARMOR:
			return "铠甲"
		Enums.EquipSlot.HELMET:
			return "头盔"
		Enums.EquipSlot.NECKLACE:
			return "项链"
		Enums.EquipSlot.RING_LEFT:
			return "戒指（左）"
		Enums.EquipSlot.RING_RIGHT:
			return "戒指（右）"
		Enums.EquipSlot.BOOTS:
			return "鞋子"
		Enums.EquipSlot.BELT:
			return "腰带"
		_:
			return str(Enums.EquipSlot.keys()[slot])


func _use_slot(index: int) -> void:
	var item := _session.bag.at(index)
	if item == null:
		return
	if item.def.is_equipment:
		_session.equip_from_bag(item.uid)
	elif item.def.type == Enums.ItemType.CONSUMABLE:
		_session.consume_item(item.uid)
	_changed.call()
	_dirty = true


func _drop_slot(index: int) -> void:
	var item := _session.bag.at(index)
	if item == null:
		return
	_session.drop_from_bag(item.uid)
	_changed.call()
	_dirty = true


func _unequip_slot(slot: int) -> void:
	_session.unequip(slot)
	_changed.call()
	_dirty = true


func _on_repair() -> void:
	_session.repair_now()
	_changed.call()
	_dirty = true


func _on_bag_slot_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		_drop_slot(index)


func _on_event(_event: GameEvent) -> void:
	mark_dirty()
