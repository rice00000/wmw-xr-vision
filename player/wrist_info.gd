extends Label3D
## Whitebox wrist readout of the inventory. Removes itself when the Inventory module is off.


func _ready() -> void:
	var inventory := Game.module(&"Inventory")
	if inventory == null:
		queue_free()
		return
	inventory.changed.connect(func(_id: StringName, _count: int) -> void: _refresh(inventory))
	_refresh(inventory)


func _refresh(inventory: Node) -> void:
	var lines: PackedStringArray = []
	var items: Dictionary = inventory.all()
	for item_id: StringName in items:
		lines.append("%s x%d" % [ItemDef.label(item_id), items[item_id]])
	text = "\n".join(lines)
