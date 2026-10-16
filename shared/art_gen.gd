class_name ArtGen
extends RefCounted

# 占位美术全部代码生成：不引用任何贴图素材，
# 只保证"看得出这是草地、那是树、这把是剑"。等正式素材到位时只需要换掉这里。

const TILE := 32

const FONT_PATH := "res://shared/font/puhuiti.ttf"

static var _cache := {}
static var _font: Font = null


static func ui_font() -> Font:
	if _font == null:
		var loaded: Font = load(FONT_PATH)
		if loaded != null:
			_font = loaded
		else:
			_font = ThemeDB.fallback_font
	return _font


static func ground(terrain: int) -> Texture2D:
	return _cached("t:%d" % terrain, _build_terrain.bind(terrain))


static func monster(monster_id: String) -> Texture2D:
	return _cached("m:" + monster_id, _build_monster.bind(monster_id))


static func player() -> Texture2D:
	return _cached("player", _build_player)


static func item(def: ItemDef) -> Texture2D:
	return _cached("i:" + def.id, _build_item.bind(def))


static func skill(def: SkillDef) -> Texture2D:
	return _cached("k:" + def.id, _build_skill.bind(def))


static func npc(palette: String) -> Texture2D:
	return _cached("n:" + palette, _build_npc.bind(palette))


static func _cached(key: String, build: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(build.call())
	return _cache[key]


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)


static func _blank(size: int = TILE) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for dy in h:
		for dx in w:
			var px := x + dx
			var py := y + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, color)


static func _disc(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var px := cx + dx
			var py := cy + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, color)


static func _ring(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for a in 64:
		var t := a * TAU / 64.0
		var px := cx + roundi(cos(t) * r)
		var py := cy + roundi(sin(t) * r)
		if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
			img.set_pixel(px, py, color)


# ── 地形 ────────────────────────────────────────────────────────────

static func _build_terrain(terrain: int) -> Image:
	var base_color := Palette.terrain_color(terrain)
	var img := _blank()
	var rng := Rng.new(terrain * 7717 + 13)

	# 每格独立的明暗噪声，让大面积同色地形不至于像一张纯色纸。
	for y in TILE:
		for x in TILE:
			var k := 0.86 + rng.next_range(0, 28) / 100.0
			img.set_pixel(x, y, _shade(base_color, k))

	match terrain:
		Enums.Terrain.FLOOR:
			for y in range(0, TILE, 8):
				_rect(img, 0, y, TILE, 1, _shade(base_color, 0.62))
			for x in range(0, TILE, 16):
				_rect(img, x, 0, 1, TILE, _shade(base_color, 0.68))
		Enums.Terrain.GRASS:
			for i in 26:
				_rect(img, rng.next_range(0, TILE), rng.next_range(0, TILE), 1, rng.next_range(2, 5), _shade(base_color, 0.7))
		Enums.Terrain.ROAD:
			for i in 9:
				_rect(img, rng.next_range(2, TILE - 6), rng.next_range(2, TILE - 4), 4, 1, _shade(base_color, 0.78))
		Enums.Terrain.SAND:
			for i in 40:
				img.set_pixel(rng.next_range(0, TILE), rng.next_range(0, TILE), _shade(base_color, 1.14))
		Enums.Terrain.WATER:
			for y in range(3, TILE, 7):
				_rect(img, 0, y, TILE, 2, _shade(base_color, 1.3))
			_rect(img, 0, TILE - 3, TILE, 3, _shade(base_color, 0.7))
		Enums.Terrain.WALL:
			for y in range(0, TILE, 8):
				_rect(img, 0, y, TILE, 1, _shade(base_color, 0.45))
				var offset := 0 if int(y / 8) % 2 == 0 else 8
				for x in range(offset, TILE, 16):
					_rect(img, x, y, 1, 8, _shade(base_color, 0.5))
			_rect(img, 0, 0, TILE, 2, _shade(base_color, 1.25))
		Enums.Terrain.ROCK:
			_rect(img, 0, 0, TILE, TILE, _shade(Palette.terrain_color(Enums.Terrain.GRASS), 1.0))
			_disc(img, 16, 19, 11, _shade(base_color, 1.0))
			_disc(img, 12, 14, 6, _shade(base_color, 1.25))
			_ring(img, 16, 19, 11, _shade(base_color, 0.6))
		Enums.Terrain.TREE:
			_rect(img, 0, 0, TILE, TILE, _shade(Palette.terrain_color(Enums.Terrain.GRASS), 0.92))
			_rect(img, 14, 20, 4, 10, Color(0.36, 0.24, 0.14))
			_disc(img, 16, 14, 10, _shade(base_color, 1.05))
			_disc(img, 12, 10, 4, _shade(base_color, 1.35))
	return img


# ── 单位 ────────────────────────────────────────────────────────────

static func _build_monster(monster_id: String) -> Image:
	var body := Palette.monster_color(monster_id)
	var img := _blank()
	# 身子 + 头 + 两只眼，够区分"这是一只怪"，形状差异靠配色。
	_disc(img, 16, 21, 9, _shade(body, 1.0))
	_disc(img, 16, 11, 7, _shade(body, 1.08))
	_rect(img, 7, 28, 6, 3, _shade(body, 0.7))
	_rect(img, 19, 28, 6, 3, _shade(body, 0.7))
	_ring(img, 16, 21, 9, _shade(body, 0.55))
	_ring(img, 16, 11, 7, _shade(body, 0.55))
	img.set_pixel(13, 10, Color(0.1, 0.1, 0.12))
	img.set_pixel(14, 10, Color(0.1, 0.1, 0.12))
	img.set_pixel(18, 10, Color(0.1, 0.1, 0.12))
	img.set_pixel(19, 10, Color(0.1, 0.1, 0.12))
	return img


static func _build_player() -> Image:
	var body := Palette.PLAYER
	var img := _blank()
	_disc(img, 16, 21, 9, _shade(body, 0.82))
	_disc(img, 16, 10, 7, _shade(body, 1.0))
	_rect(img, 6, 28, 6, 3, _shade(body, 0.6))
	_rect(img, 20, 28, 6, 3, _shade(body, 0.6))
	_ring(img, 16, 21, 9, Color(0.2, 0.3, 0.55))
	_ring(img, 16, 10, 7, Color(0.2, 0.3, 0.55))
	# 右手一道剑光，一眼能和怪物区分开。
	_rect(img, 25, 6, 2, 16, Color(0.86, 0.9, 0.96))
	_rect(img, 24, 20, 4, 2, Color(0.45, 0.3, 0.16))
	img.set_pixel(13, 9, Color(0.1, 0.1, 0.12))
	img.set_pixel(19, 9, Color(0.1, 0.1, 0.12))
	return img


# ── NPC ─────────────────────────────────────────────────────────────

# key 与 npc/base.gd 里 NpcDef.palette 的取值约定一致，不要改。
static func _npc_color(palette: String) -> Color:
	match palette:
		"elder":
			return Color(0.66, 0.7, 0.78)
		"vendor":
			return Color(0.86, 0.62, 0.28)
		"healer":
			return Color(0.42, 0.76, 0.5)
		"mage":
			return Color(0.6, 0.46, 0.88)
		"guard":
			return Color(0.44, 0.56, 0.72)
		"hunter":
			return Color(0.72, 0.6, 0.34)
		_:
			return Color(0.7, 0.7, 0.72)


static func _build_npc(palette: String) -> Image:
	var body := _npc_color(palette)
	var img := _blank()
	# 长袍 + 尖帽，轮廓刻意和怪物的圆滚滚分开，站桩的也一样能一眼认出是人。
	for y in 14:
		_rect(img, 10 - int(y / 3), 16 + y, 12 + int(y * 2 / 3), 1, _shade(body, 0.95 + y * 0.01))
	_disc(img, 16, 12, 6, Color(0.92, 0.82, 0.72))
	for y in 9:
		_rect(img, 16 - y, 3 + y, y * 2 + 1, 1, _shade(body, 0.8))
	_ring(img, 16, 24, 10, _shade(body, 0.55))
	img.set_pixel(14, 12, Color(0.1, 0.1, 0.12))
	img.set_pixel(18, 12, Color(0.1, 0.1, 0.12))
	return img


# ── 技能图标 ────────────────────────────────────────────────────────

static func _build_skill(def: SkillDef) -> Image:
	var img := _blank()
	var hue := absi(_hash(def.id)) % 360
	var accent := Color.from_hsv(hue / 360.0, 0.62, 0.95)
	var steel := Color(0.85, 0.88, 0.94)

	match def.kind:
		Enums.SkillKind.STRIKE:
			_rect(img, 22, 4, 3, 18, steel)
			_rect(img, 8, 22, 16, 3, accent)
			_rect(img, 6, 25, 4, 4, _shade(accent, 0.6))
		Enums.SkillKind.SWEEP:
			for r in range(8, 15, 3):
				for a in range(20, 161, 4):
					var t := deg_to_rad(a)
					var px := 16 + roundi(cos(t) * r)
					var py := 20 + roundi(sin(t) * r)
					# 大半径扫到画布外时显式跳过，不靠引擎吞越界写。
					if px < 0 or py < 0 or px >= TILE or py >= TILE:
						continue
					img.set_pixel(px, py, accent)
			_rect(img, 15, 6, 2, 10, steel)
		Enums.SkillKind.BOLT:
			for i in 5:
				var x := 14 if i % 2 == 0 else 18
				_rect(img, x, 4 + i * 5, 5, 4, accent)
			_rect(img, 12, 27, 9, 3, _shade(accent, 0.7))
		Enums.SkillKind.HEAL:
			_rect(img, 14, 6, 5, 22, accent)
			_rect(img, 6, 15, 21, 5, accent)
		Enums.SkillKind.BUFF:
			_disc(img, 16, 16, 11, _shade(accent, 0.9))
			_ring(img, 16, 16, 11, _shade(accent, 0.5))
			_rect(img, 12, 10, 9, 12, steel)
	return img


# ── 物品图标 ────────────────────────────────────────────────────────

static func _build_item(def: ItemDef) -> Image:
	var img := _blank()
	var hue := absi(_hash(def.id)) % 360
	var accent := Color.from_hsv(hue / 360.0, 0.35 if def.type == Enums.ItemType.GOLD else 0.55, 0.95)
	var steel := Color(0.8, 0.84, 0.9)
	var wood := Color(0.45, 0.3, 0.16)

	match def.type:
		Enums.ItemType.WEAPON:
			_rect(img, 15, 3, 3, 20, steel)
			_rect(img, 12, 22, 9, 3, accent)
			_rect(img, 15, 25, 3, 5, wood)
		Enums.ItemType.ARMOR:
			_disc(img, 16, 15, 10, accent)
			_rect(img, 10, 6, 12, 6, accent)
			_rect(img, 14, 2, 5, 6, _shade(accent, 0.6))
			_ring(img, 16, 16, 10, _shade(accent, 0.55))
		Enums.ItemType.HELMET:
			_disc(img, 16, 18, 10, accent)
			_rect(img, 6, 16, 20, 4, _shade(accent, 1.2))
			_ring(img, 16, 18, 10, _shade(accent, 0.55))
		Enums.ItemType.BOOTS:
			_rect(img, 8, 8, 7, 16, accent)
			_rect(img, 8, 22, 13, 5, _shade(accent, 0.75))
			_rect(img, 18, 12, 6, 12, _shade(accent, 0.9))
		Enums.ItemType.BELT:
			_rect(img, 4, 13, 24, 7, accent)
			_rect(img, 13, 11, 7, 11, steel)
		Enums.ItemType.NECKLACE:
			_ring(img, 16, 14, 9, accent)
			_disc(img, 16, 24, 5, _shade(accent, 1.25))
		Enums.ItemType.RING:
			_ring(img, 16, 17, 9, accent)
			_disc(img, 16, 8, 4, steel)
		Enums.ItemType.CONSUMABLE:
			_rect(img, 13, 4, 6, 4, Color(0.5, 0.35, 0.2))
			var juice := Color(0.3, 0.5, 0.9)
			if def.heal_hp > 0 and def.heal_mp > 0:
				juice = Color(0.9, 0.8, 0.35)
			elif def.heal_hp > 0:
				juice = Color(0.85, 0.28, 0.3)
			_rect(img, 10, 8, 12, 20, juice)
			_rect(img, 12, 10, 3, 15, Color(1, 1, 1, 0.35))
		Enums.ItemType.GOLD:
			_disc(img, 12, 20, 7, Color(0.92, 0.78, 0.28))
			_disc(img, 20, 14, 7, Color(0.98, 0.86, 0.4))
			_ring(img, 20, 14, 7, Color(0.6, 0.48, 0.12))
		_:
			_disc(img, 16, 18, 9, accent)
			_disc(img, 12, 14, 4, _shade(accent, 1.3))
			_ring(img, 16, 18, 9, _shade(accent, 0.55))
	return img


static func _hash(text: String) -> int:
	# FNV-1a 逐字符哈希：同一 id 永远得到同一配色。
	var h := 2166136261
	for i in text.length():
		h ^= text.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h & 0x7FFFFFFF


## 把物品属性拼成一行鼠标提示，装备面板和背包共用。
static func describe(def: ItemDef) -> String:
	var parts: Array[String] = [def.display_name]
	var b := def.bonus
	if b.dc_max > 0:
		parts.append("攻击 %d-%d" % [b.dc_min, b.dc_max])
	if b.mc_max > 0:
		parts.append("魔法 %d-%d" % [b.mc_min, b.mc_max])
	if b.sc_max > 0:
		parts.append("道术 %d-%d" % [b.sc_min, b.sc_max])
	if b.ac_max > 0:
		parts.append("防御 %d-%d" % [b.ac_min, b.ac_max])
	if b.mac_max > 0:
		parts.append("魔防 %d-%d" % [b.mac_min, b.mac_max])
	if b.max_hp > 0:
		parts.append("生命 +%d" % b.max_hp)
	if b.max_mp > 0:
		parts.append("魔法 +%d" % b.max_mp)
	if b.hit != 0:
		parts.append("命中 +%d" % b.hit)
	if b.dodge != 0:
		parts.append("敏捷 +%d" % b.dodge)
	if b.attack_speed != 0:
		parts.append("攻击速度 +%d" % b.attack_speed)
	if b.move_speed != 0:
		parts.append("移动速度 +%d" % b.move_speed)
	if def.type == Enums.ItemType.CONSUMABLE:
		var heal_text := "回复 %d 生命" % def.heal_hp if def.heal_hp > 0 else "回复 %d 魔法" % def.heal_mp
		parts.append(heal_text)
	if def.required_level > 1:
		parts.append("需要 %d 级" % def.required_level)
	if def.price > 0:
		parts.append("价格 %d" % def.price)
	return "  ".join(parts)
