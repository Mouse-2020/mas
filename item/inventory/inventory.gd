class_name Inventory
extends RefCounted

# 背包：10 x 4 = 40 格，可堆叠物品合并到同一格。

const COLUMNS := 10
const ROWS := 4
const CAPACITY := COLUMNS * ROWS

var slots: Array = []
var weight_limit := 120


func _init() -> void:
	slots.resize(CAPACITY)


var used_slots: int:
	get:
		var n := 0
		for s in slots:
			if s != null:
				n += 1
		return n


var free_slots: int:
	get:
		return CAPACITY - used_slots


var total_weight: int:
	get:
		var w := 0
		for s in slots:
			if s != null:
				w += (s as ItemInstance).def.weight * (s as ItemInstance).count
		return w


func at(index: int) -> ItemInstance:
	if index >= 0 and index < CAPACITY:
		return slots[index]
	return null


func find_by_uid(item_uid: String) -> ItemInstance:
	for s in slots:
		if s != null and (s as ItemInstance).uid == item_uid:
			return s
	return null


## 找不到返回 -1。
func index_of(item_uid: String) -> int:
	for i in CAPACITY:
		var s: ItemInstance = slots[i]
		if s != null and s.uid == item_uid:
			return i
	return -1


func contains(def_id: String) -> bool:
	for s in slots:
		if s != null and (s as ItemInstance).def_id == def_id:
			return true
	return false


## 先问能不能放下，再真放进去；换装这类操作靠它避免"吞掉旧装备"。
func can_accept(def: ItemDef, count: int) -> bool:
	if count <= 0:
		return true
	var room := 0
	if def.max_stack > 1:
		for s in slots:
			if s != null and (s as ItemInstance).def_id == def.id and (s as ItemInstance).count < def.max_stack:
				room += def.max_stack - (s as ItemInstance).count
	room += free_slots * (def.max_stack if def.max_stack > 1 else 1)
	return room >= count and total_weight + def.weight * count <= weight_limit


func count_of(def_id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and (s as ItemInstance).def_id == def_id:
			n += (s as ItemInstance).count
	return n


## 能放多少放多少，返回实际放下的数量（0 表示背包满或超重）。
func add(def: ItemDef, count: int, item_uid := "") -> int:
	if count <= 0:
		return 0

	var placed := 0
	if def.max_stack > 1:
		for i in CAPACITY:
			if placed >= count:
				break
			var slot: ItemInstance = slots[i]
			if slot == null or slot.def_id != def.id or slot.count >= def.max_stack:
				continue
			var room := def.max_stack - slot.count
			var take := mini(room, count - placed)
			slot.count += take
			placed += take

	while placed < count:
		var index := slots.find(null)
		if index < 0:
			break
		var take := mini(def.max_stack, count - placed) if def.max_stack > 1 else 1
		if total_weight + def.weight * take > weight_limit:
			break
		slots[index] = ItemInstance.from_def(def, take, item_uid if item_uid != "" else ItemInstance.next_uid())
		placed += take

	return placed


func add_at(index: int, instance: ItemInstance) -> void:
	slots[index] = instance


## 把这一件原样塞进空格。装备换下来必须走这条路：add 是按模板新建一件，
## 耐久会被重置成满值，等于"脱一次装备就免费修好"。放不下时什么都不动。
func try_place(instance: ItemInstance) -> bool:
	var index := slots.find(null)
	if index < 0:
		return false
	if total_weight + instance.def.weight * instance.count > weight_limit:
		return false
	slots[index] = instance
	return true


## 扣掉指定数量；不足则返回 false 且不动背包。
func consume(def_id: String, count: int) -> bool:
	if count_of(def_id) < count:
		return false
	var remaining := count
	for i in CAPACITY:
		if remaining <= 0:
			break
		var slot: ItemInstance = slots[i]
		if slot == null or slot.def_id != def_id:
			continue
		var take := mini(slot.count, remaining)
		slot.count -= take
		remaining -= take
		if slot.count == 0:
			slots[i] = null
	return true


func remove(item_uid: String, count := -1) -> ItemInstance:
	var index := index_of(item_uid)
	if index < 0:
		return null
	var slot: ItemInstance = slots[index]
	if count < 0 or slot.count <= count:
		slots[index] = null
		return slot
	slot.count -= count
	# 拆出来的那一小份按模板重新起耐久，不继承原格状态。
	return ItemInstance.from_def(slot.def, count, item_uid)


func move(from: int, to: int) -> bool:
	if from == to or from < 0 or to < 0 or from >= CAPACITY or to >= CAPACITY:
		return false
	var source: ItemInstance = slots[from]
	var destination: ItemInstance = slots[to]

	# 同类可堆叠物品合并，剩下的留在原位，符合点一下叠成一堆的手感。
	if source != null and destination != null and source.def_id == destination.def_id and source.def.max_stack > 1:
		var room := source.def.max_stack - destination.count
		if room <= 0:
			return true
		var take := mini(room, source.count)
		destination.count += take
		source.count -= take
		if source.count == 0:
			slots[from] = null
		return true

	slots[from] = destination
	slots[to] = source
	return true


func enumerate() -> Array:
	var out: Array = []
	for s in slots:
		if s != null:
			out.append(s)
	return out


## 读档前清空，避免和默认的新手礼包混在一起。
func clear() -> void:
	for i in CAPACITY:
		slots[i] = null
