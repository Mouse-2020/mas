class_name Main
extends Node2D

# 场景根：只做两件事——把界面零件装配起来，把玩家输入翻译成单例调用。
# 世界推进在 autoload/game.gd，事件分发在各面板自己的订阅里，发声在 autoload/audio.gd，
# 存读档在 autoload/archive.gd，玩法数值与规则在 system/ 与各领域目录，这里一概不写。

var _view: WorldView
var _hud: Hud
var _panels: Panels
var _minimap: Minimap
var _quests: QuestPanel
var _skills: SkillBar
var _dialogue: DialoguePanel
var _shop: ShopPanel
var _key_step_cooldown := 0.0
var _shot_at_frame := 0
var _frame := 0
var _shot_path := ""
var _pending_talk := ""


func _ready() -> void:
	_shot_at_frame = _parse_int_from_args("--shot", 0)
	_shot_path = _parse_str_from_args("--png", ProjectSettings.globalize_path("res://shot.png"))

	_view = WorldView.new()
	_view.name = "World"
	add_child(_view)
	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	add_child(_minimap)
	_quests = QuestPanel.new()
	_quests.name = "Quests"
	add_child(_quests)
	_panels = Panels.new()
	_panels.name = "Panels"
	add_child(_panels)
	_skills = SkillBar.new()
	_skills.name = "Skills"
	add_child(_skills)
	_dialogue = DialoguePanel.new()
	_dialogue.name = "Dialogue"
	add_child(_dialogue)
	_shop = ShopPanel.new()
	_shop.name = "Shop"
	add_child(_shop)

	_skills.pressed = cast_hotkey
	_dialogue.shop_chosen = _open_shop
	_dialogue.say = _hud.say

	Event.session_ready.connect(_attach)
	var session := Game.start(_parse_int_from_args("--seed", Game.DEFAULT_SEED))
	var p := session.player.position
	print("[武林风] %s %dx%d，出生 (%d,%d)，怪物 %d 只，门 %d 处，NPC %d 位，种子 %d" % [
		session.map.display_name, session.map.width, session.map.height,
		p.x, p.y, session.monsters.size(), session.map.exits.size(),
		session.npcs.size(), Game.seed_in_use])


func _attach(session: GameSession) -> void:
	_pending_talk = ""
	_view.bind(session)
	_hud.bind(session)
	_minimap.bind(session)
	_quests.bind(session)
	_skills.bind(session)
	_dialogue.bind(session)
	_shop.bind(session, _panels.mark_dirty)
	_panels.bind(session, _panels.mark_dirty)
	_panels.mark_dirty()
	_hud.refresh()


func _open_shop(shop_id: String) -> void:
	_shop.open(shop_id)


func _process(delta: float) -> void:
	_handle_keyboard(delta)
	_walk_to_talk()
	if _shot_at_frame > 0:
		_step_shot_routine()


## 点了远处的人：先走过去，站到位再开口。
func _walk_to_talk() -> void:
	if _pending_talk.is_empty():
		return
	var session := Game.session
	var npc: NpcUnit = null
	for entry in session.npcs:
		var candidate := entry as NpcUnit
		if candidate.def.id == _pending_talk:
			npc = candidate
			break
	if npc == null or not session.player.alive:
		_pending_talk = ""
		return
	if Grid.chebyshev(session.player.position, npc.position) > GameSession.TALK_RADIUS:
		return
	_pending_talk = ""
	_dialogue.open(npc.def.id)


## 无人值守的取证模式：--shot N 让第 3 帧自己走路、开面板，第 N 帧截屏退出。
## 没有它我只能证明逻辑对，没法证明画面画得对。
func _step_shot_routine() -> void:
	var session := Game.session
	_frame += 1
	if _frame == 3:
		_panels.toggle_bag()
		_panels.toggle_gear()
		# 先走到教头边上，这样 150 帧的对话截图里是真选项，不是"走近点再说"。
		var talker := session.nearest_npc(session.player.position, 999)
		if talker != null:
			session.move_player_to(talker.position)
	if _frame > 40 and session.player.alive:
		var prey := session.nearest_monster(session.player.position, 1)
		# 够得着才出手，而且直接瞄那只怪：截图时没人动鼠标，按鼠标位置会一直"够不着目标"。
		if prey != null:
			_cast(Naming.SKILL_SLASH, prey.position)
		if session.player.hp * 2 < session.player.max_hp:
			_drink_potion()
		if _frame % 45 == 0:
			var far := session.nearest_monster(session.player.position, 999)
			if far != null:
				session.move_player_to(far.position)
			# 城里没怪就往门走，顺便把跨图和小地图换图一起验了。
			elif not session.map.exits.is_empty():
				var gate: MapExit = session.map.exits[0]
				session.move_player_to(gate.at)
	if _frame == 150:
		_quests.toggle_log()
		var npc := session.nearest_npc(session.player.position, GameSession.TALK_RADIUS)
		if npc != null:
			_dialogue.open(npc.def.id)
	if _frame == 200:
		_dialogue.close()
		_quests.toggle_log()
		_shop.open(Naming.SHOP_WEAPON)
		# 走传送这条路进后山：截图要拍到怪、掉落和技能闪光。
		if session.nearest_monster(session.player.position, 999) == null:
			session.travel_to(Naming.MAP_SUBURB)
	if _frame < _shot_at_frame:
		return

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_shot_path)
	if error == OK:
		print("[武林风] 截图 %dx%d → %s" % [image.get_width(), image.get_height(), _shot_path])
	else:
		print("[武林风] 截图失败：%s" % error)
	# 顺手把 Godot 这边的存档路径也验一遍：存完立刻读回来。
	_save()
	_load()
	print("[武林风] 读档后 等级 %d 位置 (%d,%d) 击杀 %d" % [
		Game.session.player.level, Game.session.player.position.x,
		Game.session.player.position.y, Game.session.kill_count])
	get_tree().quit()


# ── 输入 ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_handle_click(click)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		_handle_key(key)


func _handle_click(click: InputEventMouseButton) -> void:
	var session := Game.session
	var cell := _view.screen_to_cell(click.position)
	if not session.map.in_bounds(cell):
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			_view.mark_target(cell)
			var npc := session.npc_at(cell)
			if npc != null:
				_talk_to(npc)
				_hud.refresh()
				return
			# 点怪（或点人堆旁边）优先打，其余一律走过去。
			if not session.attack_target_at(cell):
				session.move_player_to(cell)
		MOUSE_BUTTON_RIGHT:
			Kit.pick_up(cell)
	_hud.refresh()


func _talk_to(npc: NpcUnit) -> void:
	var session := Game.session
	if Grid.chebyshev(session.player.position, npc.position) <= GameSession.TALK_RADIUS:
		_dialogue.open(npc.def.id)
		return
	session.move_player_to(npc.position)
	_pending_talk = npc.def.id


func _handle_keyboard(delta: float) -> void:
	_key_step_cooldown -= delta
	if _key_step_cooldown > 0.0:
		return

	var up := _held(KEY_W) or _held(KEY_UP)
	var down := _held(KEY_S) or _held(KEY_DOWN)
	var left := _held(KEY_A) or _held(KEY_LEFT)
	var right := _held(KEY_D) or _held(KEY_RIGHT)
	if not (up or down or left or right):
		return

	_key_step_cooldown = 0.26
	var step := _screen_step(up, down, left, right)
	Game.session.step_player(_of(step.x, step.y))
	_hud.refresh()


## 等距画面里"屏幕正上方"是格子的 (-1,-1)，所以按键方向要先转 45° 再交给格子世界，
## 否则按 W 会斜着往右上跑。两个键一起按时取屏幕上的合方向。
static func _screen_step(up: bool, down: bool, left: bool, right: bool) -> Vector2i:
	var dx := int(down) + int(right) - int(up) - int(left)
	var dy := int(down) + int(left) - int(up) - int(right)
	return Vector2i(clampi(dx, -1, 1), clampi(dy, -1, 1))


static func _held(key: int) -> bool:
	return Input.is_key_pressed(key)


static func _of(dx: int, dy: int) -> int:
	if dx == 0 and dy == -1:
		return Enums.Direction.UP
	if dx == 1 and dy == -1:
		return Enums.Direction.UP_RIGHT
	if dx == 1 and dy == 0:
		return Enums.Direction.RIGHT
	if dx == 1 and dy == 1:
		return Enums.Direction.DOWN_RIGHT
	if dx == 0 and dy == 1:
		return Enums.Direction.DOWN
	if dx == -1 and dy == 1:
		return Enums.Direction.DOWN_LEFT
	if dx == -1 and dy == 0:
		return Enums.Direction.LEFT
	if dx == -1 and dy == -1:
		return Enums.Direction.UP_LEFT
	return Enums.Direction.DOWN


func _handle_key(e: InputEventKey) -> void:
	var hotkey := _number_hotkey(e.keycode)
	if hotkey > 0:
		cast_hotkey(hotkey)
		return

	match e.keycode:
		KEY_B:
			_panels.toggle_bag()
		KEY_E:
			_panels.toggle_gear()
		KEY_J:
			_quests.toggle_log()
		KEY_M:
			Audio.toggle_mute()
			_hud.say("静音了" if Audio.muted else "有声音了")
		KEY_F:
			_talk_nearest()
		KEY_T:
			Game.session.use_nearest_exit()
		KEY_Q:
			_drink_potion()
		KEY_G:
			Game.session.fish_toggle()
		KEY_SPACE:
			_attack_nearest()
		KEY_ESCAPE:
			if _shop.is_open:
				_shop.close()
			elif _dialogue.is_open:
				_dialogue.close()
			elif _panels.any_visible:
				_panels.hide_all()
			else:
				get_tree().quit()
		KEY_F5:
			_save()
		KEY_F9:
			_load()
		KEY_F2:
			Game.new_world(int(Time.get_ticks_msec()))
	_hud.refresh()


## 数字 1..9 与 0 就是技能栏十格的快捷键，小键盘同样有效。
static func _number_hotkey(key: int) -> int:
	if key == KEY_0 or key == KEY_KP_0:
		return 10
	if key >= KEY_1 and key <= KEY_9:
		return key - KEY_1 + 1
	if key >= KEY_KP_1 and key <= KEY_KP_9:
		return key - KEY_KP_1 + 1
	return 0


func cast_hotkey(hotkey: int) -> void:
	var skill_id := Skill.hotkey_slot(hotkey)
	if skill_id == "":
		_hud.say("第 %d 格还没招式" % hotkey)
		return
	_cast(skill_id, _aim_of_mouse())


## 鼠标指哪打哪；回血与护体不挑目标，落点收在自己身上。
func _aim_of_mouse() -> Vector2i:
	var session := Game.session
	var cell := _view.screen_to_cell(get_viewport().get_mouse_position())
	return cell if session.map.in_bounds(cell) else session.player.position


func _cast(skill_id: String, aim: Vector2i) -> void:
	var def := SkillDatabase.get_def(skill_id)
	var landing := aim
	if def.kind == Enums.SkillKind.HEAL or def.kind == Enums.SkillKind.BUFF:
		landing = Game.session.player.position

	var result := Skill.cast(skill_id, landing)
	if not result.success:
		_hud.say(result.reason)
		return
	Audio.play(def.sound)
	_view.add_flash(landing, def.reach, _flash_color(def.kind))


static func _flash_color(kind: int) -> Color:
	match kind:
		Enums.SkillKind.HEAL:
			return Color(0.55, 0.95, 0.6)
		Enums.SkillKind.BUFF:
			return Color(1.0, 0.85, 0.4)
		Enums.SkillKind.BOLT:
			return Color(0.6, 0.78, 1.0)
		Enums.SkillKind.SWEEP:
			return Color(1.0, 0.7, 0.45)
		_:
			return Color(1.0, 0.95, 0.85)


func _talk_nearest() -> void:
	var session := Game.session
	var npc := session.nearest_npc(session.player.position, 999)
	if npc == null:
		_hud.say("这一带没有人可说话")
		return
	_talk_to(npc)


func _attack_nearest() -> void:
	var session := Game.session
	var near := session.nearest_monster(session.player.position, 1)
	if near != null:
		session.attack_target(near)


func _drink_potion() -> void:
	if not Kit.drink_best_potion():
		_hud.say("背包里没有回血的药")


# ── 存读档 ──────────────────────────────────────────────────────────

func _save() -> void:
	Archive.save_session(Game.session)


func _load() -> void:
	var loaded := Archive.load_session(Game.seed_in_use)
	if loaded == null:
		return
	Game.adopt(loaded)
	print("[武林风] 读档完成，等级 %d，击杀 %d" % [loaded.player.level, loaded.kill_count])


static func _parse_int_from_args(flag: String, fallback: int) -> int:
	var previous := ""
	# Godot 只把 "--" 之后的参数交给我们，命令行形如：Godot --path . -- --seed 808
	for arg in OS.get_cmdline_user_args():
		if previous == flag and arg.is_valid_int():
			return arg.to_int()
		previous = arg
	return fallback


static func _parse_str_from_args(flag: String, fallback: String) -> String:
	var previous := ""
	for arg in OS.get_cmdline_user_args():
		if previous == flag:
			return arg
		previous = arg
	return fallback
