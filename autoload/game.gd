extends Node

# 游戏总管理：持有唯一一局 GameSession、驱动每帧推进、开新局与换世界。
# 玩法数值与规则都在 system/session.gd 那边，这里只管生命周期。

const DEFAULT_SEED := 20261016

var session: GameSession
var seed_in_use := DEFAULT_SEED


func _init() -> void:
	# 让输入先处理、再推进世界：与拆单例前 main 里"先读键再 tick"的顺序一致。
	process_priority = 100


func _process(delta: float) -> void:
	if session == null:
		return
	session.tick(delta)
	for entry in session.drain_events():
		Event.raised.emit(entry as GameEvent)


func start(p_seed: int) -> GameSession:
	seed_in_use = p_seed
	session = GameSession.new_campaign(p_seed)
	Event.session_ready.emit(session)
	return session


## 读档后用外部造好的会话接管当前局。
func adopt(p_session: GameSession) -> GameSession:
	session = p_session
	seed_in_use = p_session.seed
	Event.session_ready.emit(session)
	return session


func new_world(p_seed: int) -> GameSession:
	return start(p_seed)
