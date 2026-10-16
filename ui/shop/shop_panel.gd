class_name ShopPanel
extends CanvasLayer

# 商店面板：左边货架、右边背包。买不动和卖不动都直接灰掉，
# 原因由玩法层的事件与 near_shop 判定给，这里不自己算价。

const WIDTH := 610.0
const HEIGHT := 400.0

var _session: GameSession
var _changed: Callable
var _panel: PanelContainer
var _title: Label
var _foot: Label
var _buy: VBoxContainer
var _sell: VBoxContainer
var _repair: Button
var _shop_id := ""
var _dirty := false

var is_open: bool:
	get:
		return _panel.visible


func bind(session: GameSession, changed: Callable) -> void:
	_session = session
	_changed = changed
	_dirty = true
	# 事件总线订阅一次即可，面板不再由场景根居中转发。
	if not Event.raised.is_connected(_on_event):
		Event.raised.connect(_on_event)


func mark_dirty() -> void:
	_dirty = true


func open(shop_id: String) -> void:
	_shop_id = shop_id
	_dirty = true
	_panel.visible = true


func close() -> void:
	_panel.visible = false


func _ready() -> void:
	layer = 5
	var view := get_viewport().get_visible_rect().size

	_panel = PanelContainer.new()
	_panel.position = Vector2(view.x / 2.0 - WIDTH / 2.0, 120)
	_panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.96)
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

	_title = _make_label("", 19, Color(1.0, 0.88, 0.55))
	box.add_child(_title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND
	columns.add_theme_constant_override("separation", 10)
	box.add_child(columns)
	var buy_parts := _column("买（左键 1 件，右键 5 件）")
	columns.add_child(buy_parts[0])
	_buy = buy_parts[1]
	var sell_parts := _column("卖（左键 1 件，右键整叠）")
	columns.add_child(sell_parts[0])
	_sell = sell_parts[1]

	_repair = Button.new()
	_repair.focus_mode = Control.FOCUS_NONE
	_repair.add_theme_font_size_override("font_size", 16)
	_repair.pressed.connect(_on_repair)
	box.add_child(_repair)

	_foot = _make_label("", 15, Color(0.8, 0.8, 0.8))
	box.add_child(_foot)

	var close_button := Button.new()
	close_button.text = "关门（Esc）"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", 15)
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _column(header: String) -> Array:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND
	wrap.add_theme_constant_override("separation", 4)
	wrap.add_child(_make_label(header, 15, Color(0.7, 0.8, 0.95)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND
	scroll.custom_minimum_size = Vector2(285, HEIGHT - 200)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND
	body.add_theme_constant_override("separation", 3)
	scroll.add_child(body)
	wrap.add_child(scroll)
	return [wrap, body]


func _process(_delta: float) -> void:
	if _session == null or not _panel.visible or not _dirty:
		return
	_rebuild()
	_dirty = false


func _rebuild() -> void:
	var shop := ShopDatabase.try_get(_shop_id)
	if shop == null:
		close()
		return

	var here := _session.near_shop(_shop_id)
	var cost := Trade.repair_cost(_session.gear)
	_title.text = "%s  金币 %d%s" % [shop.display_name, _session.player.gold, "" if here else "  （得站到老板跟前）"]
	_repair.text = "装备没坏，不用修" if cost <= 0 else "修理全身装备（%d 金币）" % cost
	_repair.disabled = not here or cost <= 0 or _session.player.gold < cost
	_foot.text = "卖价对折，装备按剩余耐久折算。" if shop.buys_back else "这家只卖不收。"

	_fill(shop, here)


func _fill(shop: ShopDef, here: bool) -> void:
	for child in _buy.get_children():
		child.queue_free()
	for child in _sell.get_children():
		child.queue_free()
	_buy_rows(shop, here)
	if shop.buys_back:
		_sell_rows(shop, here)
	else:
		_sell.add_child(_make_label("这家不收东西。", 15, Color(0.7, 0.7, 0.7)))


func _buy_rows(shop: ShopDef, here: bool) -> void:
	for entry in shop.stock:
		var def_id: String = entry
		var def := ItemDatabase.try_get(def_id)
		if def == null:
			continue
		var price := Trade.buy_price(def)
		var tip := "右键一次买 5 件，共 %d" % (price * 5) if def.type == Enums.ItemType.CONSUMABLE else ArtGen.describe(def)
		var button := _row(ArtGen.item(def), "%s  %d" % [def.display_name, price], tip)
		button.disabled = not here or _session.player.gold < price
		button.pressed.connect(_buy_one.bind(shop.id, def.id))
		button.gui_input.connect(_on_buy_input.bind(shop.id, def.id))
		_buy.add_child(button)


func _sell_rows(shop: ShopDef, here: bool) -> void:
	var rows := 0
	for entry in _session.bag.enumerate():
		var item := entry as ItemInstance
		if item.def.type == Enums.ItemType.GOLD:
			continue
		rows += 1
		var button := _row(ArtGen.item(item.def),
			"%s x%d  %d" % [item.def.display_name, item.count, Trade.sell_price(item)],
			ArtGen.describe(item.def))
		button.disabled = not here
		button.pressed.connect(_sell_one.bind(item.uid))
		button.gui_input.connect(_on_sell_input.bind(item.uid))
		_sell.add_child(button)
	if rows == 0:
		_sell.add_child(_make_label("背包里没有能卖的东西。", 15, Color(0.7, 0.7, 0.7)))


func _row(icon: Texture2D, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.icon = icon
	button.text = text
	button.expand_icon = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(285, 40)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _row_style(Color(0.12, 0.13, 0.17, 0.95)))
	button.add_theme_stylebox_override("hover", _row_style(Color(0.2, 0.23, 0.3, 0.95)))
	return button


static func _row_style(background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = Color(1, 1, 1, 0.14)
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	box.set_border_width_all(1)
	box.set_content_margin_all(4)
	return box


static func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.add_theme_font_size_override("font_size", size)
	return label


func _buy_one(shop_id: String, def_id: String, count: int) -> void:
	_session.buy_from_shop(shop_id, def_id, count)
	_changed.call()
	_dirty = true


func _sell_one(uid: String, count: int) -> void:
	_session.sell_from_bag(uid, count)
	_changed.call()
	_dirty = true


func _on_repair() -> void:
	_session.repair_now()
	_changed.call()
	_dirty = true


func _on_buy_input(event: InputEvent, shop_id: String, def_id: String) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		_buy_one(shop_id, def_id, 5)


func _on_sell_input(event: InputEvent, uid: String) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		# 右键整叠：count 传 -1 表示"有多少卖多少"。
		_sell_one(uid, -1)


func _on_event(_event: GameEvent) -> void:
	mark_dirty()
