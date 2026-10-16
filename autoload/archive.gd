extends Node

# 存档与读档：一局一个文件，文件名带种子，放在 Godot 的用户数据目录里。

const FILE_PREFIX := "wulin-"


func path_for(seed_value: int) -> String:
	return OS.get_user_data_dir() + "/%s%d.json" % [FILE_PREFIX, seed_value]


func exists(seed_value: int) -> bool:
	return FileAccess.file_exists(path_for(seed_value))


func save_session(session: GameSession) -> bool:
	var path := path_for(session.seed)
	var ok := SaveGame.write_to_file(SaveGame.capture(session), path)
	if ok:
		print("[武林风] 已存档 " + path)
	return ok


## 读不出来返回 null，调用方自己决定怎么提示。
func load_session(seed_value: int) -> GameSession:
	var path := path_for(seed_value)
	if not FileAccess.file_exists(path):
		print("[武林风] 还没有存档：" + path)
		return null
	return SaveGame.restore(SaveGame.read_from_file(path))
