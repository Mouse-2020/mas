class_name Minimap
extends Control

# 小地图：地形只在换图时烘一张纹理，人和怪每帧叠几个点上去。

const PANEL_SIZE := 176.0

var _session: GameSession
var _map_id := ""
var _terrain: ImageTexture
var _scale := 1.0
var _offset := Vector2.ZERO


func bind(session: GameSession) -> void:
	_session = session
	_map_id = ""


func _ready() -> void:
	var view := get_viewport().get_visible_rect().size
	# 右上角装备面板（226 高）下面，背包面板左边，四块面板互不挡。
	position = Vector2(view.x - 12 - PANEL_SIZE, 12 + 226 + 12)
	size = Vector2(PANEL_SIZE, PANEL_SIZE)
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)


func _process(_delta: float) -> void:
	if _session == null:
		return
	if _session.map_id != _map_id:
		_bake()
	queue_redraw()


func _bake() -> void:
	_map_id = _session.map_id
	var map := _session.map
	_scale = PANEL_SIZE / maxf(1.0, float(maxi(map.width, map.height)))
	_offset = Vector2((PANEL_SIZE - map.width * _scale) / 2.0, (PANEL_SIZE - map.height * _scale) / 2.0)

	var img := Image.create_empty(map.width, map.height, false, Image.FORMAT_RGB8)
	for entry in map.all_positions():
		var pos: Vector2i = entry
		img.set_pixel(pos.x, pos.y, Palette.terrain_color(map.terrain_at(pos)))
	_terrain = ImageTexture.create_from_image(img)


func _draw() -> void:
	if _session == null or _terrain == null:
		return
	var map := _session.map

	draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_SIZE, PANEL_SIZE)), Color(0.03, 0.03, 0.05, 0.9))
	draw_texture_rect(_terrain, Rect2(_offset, Vector2(map.width * _scale, map.height * _scale)), false)

	for entry in map.exits:
		var exit := entry as MapExit
		_dot(exit.at, Color(1.0, 0.82, 0.2), 4)
	for entry in _session.loot:
		var drop := entry as LootItem
		_dot(drop.position, Palette.LOOT, 2)
	for entry in _session.monsters:
		var monster := entry as MonsterUnit
		if monster.alive:
			_dot(monster.position, Color(0.92, 0.3, 0.26), 2)
	for entry in _session.npcs:
		var npc := entry as NpcUnit
		_dot(npc.position, Color(0.42, 0.84, 1, 1), 3)
	_dot(map.spawn, Palette.SPAWN, 3)
	_dot(_session.player.position, Color(1, 1, 1), 4)

	draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_SIZE, PANEL_SIZE)), Color(1, 1, 1, 0.22), false, 1.0)
	draw_string(ArtGen.ui_font(), Vector2(6, PANEL_SIZE - 6),
		"%s%s" % [map.display_name, "  安全区" if map.safe else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1, 1, 1, 0.88))


func _dot(at: Vector2i, color: Color, pixels: int) -> void:
	var p := _offset + Vector2(at.x * _scale, at.y * _scale) - Vector2(pixels / 2.0, pixels / 2.0)
	draw_rect(Rect2(p, Vector2(pixels, pixels)), color)
