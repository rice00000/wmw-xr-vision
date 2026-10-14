extends Node
## Inventory module (autoload "Inventory"): item id -> count.
## Item details (name, icon, scene, cost) live in ItemDef resources.
## Fills itself from Events.reward_granted; saved by the Save module.

signal changed(item_id: StringName, count: int)

var _items: Dictionary[StringName, int] = {}


func _ready() -> void:
	Events.reward_granted.connect(add)


func count(item_id: StringName) -> int:
	return _items.get(item_id, 0)


func all() -> Dictionary[StringName, int]:
	return _items.duplicate()


func add(item_id: StringName, amount := 1) -> void:
	_put(item_id, count(item_id) + amount)


func can_afford(cost: Dictionary) -> bool:
	for item_id: StringName in cost:
		if count(item_id) < cost[item_id]:
			return false
	return true


## Takes everything in [param cost], or nothing at all. Returns true on success.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for item_id: StringName in cost:
		_put(item_id, count(item_id) - cost[item_id])
	return true


func _put(item_id: StringName, value: int) -> void:
	if value > 0:
		_items[item_id] = value
	else:
		_items.erase(item_id)
	changed.emit(item_id, maxi(value, 0))


func save_state() -> Dictionary:
	return {items = _items.duplicate()}


func load_state(data: Dictionary) -> void:
	_items.assign(data.get("items", {}))
	changed.emit(&"", 0)
