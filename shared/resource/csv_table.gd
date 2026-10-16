class_name CsvTable
extends RefCounted

# 批量数值表的读取与取值：一行一条记录，表头就是字段名。
# 之所以让 CSV 直接喂出 Resource 模板，是为了让你能用表格软件一行一行改数值，
# 而玩法代码拿到的仍然是带类型的 ItemDef/MonsterDef……不用改任何调用方。

const SPLIT_ROWS := "|"
const SPLIT_KV := ";"


## 读一张 CSV。首行是表头；以 # 开头的行与空行忽略（方便你在表里留备注）。
static func read(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("打不开数值表：" + path)
		return []
	var rows: Array = []
	var headers: PackedStringArray = PackedStringArray()
	var line_no := 0
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() == 0 or (cells.size() == 1 and cells[0].strip_edges() == ""):
			continue
		line_no += 1
		if cells[0].strip_edges().begins_with("#"):
			continue
		if headers.is_empty():
			for cell in cells:
				headers.append(cell.strip_edges())
			continue
		var row := {}
		for i in headers.size():
			row[headers[i]] = (cells[i] as String).strip_edges() if i < cells.size() else ""
		rows.append(row)
	file.close()
	return rows


static func has_column(rows: Array, column: String) -> bool:
	if rows.is_empty():
		return false
	return (rows[0] as Dictionary).has(column)


static func text(row: Dictionary, column: String, fallback := "") -> String:
	if not row.has(column):
		return fallback
	var value := String(row[column])
	return value if value != "" else fallback


static func integer(row: Dictionary, column: String, fallback := 0) -> int:
	var value := text(row, column)
	return value.to_int() if value.is_valid_int() else fallback


static func real(row: Dictionary, column: String, fallback := 0.0) -> float:
	var value := text(row, column)
	return value.to_float() if value.is_valid_float() else fallback


static func boolean(row: Dictionary, column: String, fallback := false) -> bool:
	var value := text(row, column).to_lower()
	match value:
		"1", "true", "yes", "y", "on", "是":
			return true
		"0", "false", "no", "n", "off", "否":
			return false
		_:
			return fallback


## 枚举列：写名字（WEAPON / RING_LEFT）或写序号都认，名字大小写不敏感。
static func choice(row: Dictionary, column: String, enum_dict: Dictionary, fallback: int) -> int:
	var value := text(row, column)
	if value == "":
		return fallback
	var upper := value.to_upper()
	if enum_dict.has(upper):
		return enum_dict[upper]
	if value.is_valid_int():
		return value.to_int()
	push_error("数值表里 %s 不是认识的取值：%s" % [column, value])
	return fallback


## "max_hp=28;dc_min=3;dc_max=6" → StatBlock
static func stats(row: Dictionary, column: String) -> StatBlock:
	var block := StatBlock.new()
	for pair in text(row, column).split(SPLIT_KV):
		var kv := String(pair).split("=")
		if kv.size() != 2:
			continue
		var key := kv[0].strip_edges()
		if key in block:
			block[key] = kv[1].strip_edges().to_int()
		else:
			push_error("属性块没有这个字段：%s（列 %s）" % [key, column])
	return block


## 复合列的统一拆法：竖线分组、冒号分字段，"a:1:2|b:3:4" → [[a,1,2],[b,3,4]]。
static func groups(row: Dictionary, column: String) -> Array:
	var out: Array = []
	for entry in text(row, column).split(SPLIT_ROWS):
		var group := PackedStringArray()
		for part in String(entry).split(":"):
			var value := String(part).strip_edges()
			if value != "":
				group.append(value)
		if not group.is_empty():
			out.append(group)
	return out


## "兽皮:0.45:1:1|铁矿石:0.15:1:1" → Array[DropRoll]
## 返回类型必须写成带元素的数组：MonsterDef.drops 是 Array[DropRoll]，
## 喂普通 Array 进去会在赋值时报 "Invalid assignment of property 'drops'"。
static func drops(row: Dictionary, column: String) -> Array[DropRoll]:
	var out: Array[DropRoll] = []
	for parts in groups(row, column):
		var group: PackedStringArray = parts
		if group.size() < 2:
			continue
		var chance := float(group[1]) if group[1].is_valid_float() else 1.0
		var min_count := group[2].to_int() if group.size() > 2 and group[2].is_valid_int() else 1
		var max_count := group[3].to_int() if group.size() > 3 and group[3].is_valid_int() else min_count
		out.append(DropRoll.make(group[0], chance, min_count, max_count))
	return out


## "suburb:EAST:竹林入口|cave:NORTH:洞口" → Array[MapLink]
static func links(row: Dictionary, column: String) -> Array[MapLink]:
	var out: Array[MapLink] = []
	for parts in groups(row, column):
		var group: PackedStringArray = parts
		if group.size() < 1:
			continue
		var link := MapLink.new()
		link.to_map = group[0]
		link.side = _enum_value(Enums.MapSide, group[1], Enums.MapSide.NORTH) if group.size() > 1 else Enums.MapSide.NORTH
		link.label = group[2] if group.size() > 2 else ""
		out.append(link)
	return out


## "武馆教头:-6:-5|铁匠王二:6:-5" → Array[NpcSpot]
static func npc_spots(row: Dictionary, column: String) -> Array[NpcSpot]:
	var out: Array[NpcSpot] = []
	for parts in groups(row, column):
		var group: PackedStringArray = parts
		if group.size() < 3:
			continue
		var spot := NpcSpot.new()
		spot.npc_id = group[0]
		spot.dx = group[1].to_int()
		spot.dy = group[2].to_int()
		out.append(spot)
	return out


## "活血散:5|两仪丹:3" → Array[QuestReward]
static func rewards(row: Dictionary, column: String) -> Array[QuestReward]:
	var out: Array[QuestReward] = []
	for parts in groups(row, column):
		var group: PackedStringArray = parts
		var count := group[1].to_int() if group.size() > 1 and group[1].is_valid_int() else 1
		out.append(QuestReward.make(group[0], count))
	return out


## "山鸡;野鹿;木人桩" → PackedStringArray
static func words(row: Dictionary, column: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in text(row, column).split(SPLIT_KV):
		var value := String(entry).strip_edges()
		if value != "":
			out.append(value)
	return out


static func _enum_value(enum_dict: Dictionary, value: String, fallback: int) -> int:
	var upper := value.to_upper()
	if enum_dict.has(upper):
		return enum_dict[upper]
	return value.to_int() if value.is_valid_int() else fallback
