class_name DecorBoard
extends Node3D
## Whitebox furniture menu: one button per item. Touching a button pays the item's
## cost (when the Inventory module is on; otherwise it's free) and places it at
## [member spawn_point] in [member layout].

const BUTTON := preload("res://components/touch_button.tscn")

@export var items: Array[StringName] = [&"chair", &"lamp", &"plant"]
@export var layout: HomeLayout
@export var spawn_point: Node3D
@export var spacing := 0.3


func _ready() -> void:
	for i in items.size():
		var def := ItemDef.find(items[i])
		var button := BUTTON.instantiate() as TouchButton
		button.id = items[i]
		button.text = "%s\n%s" % [ItemDef.label(items[i]), _price(def)]
		button.position.x = (i - (items.size() - 1) / 2.0) * spacing
		button.touched.connect(_on_button_touched.bind(items[i]))
		add_child(button)


func _on_button_touched(_hand: Node3D, item_id: StringName) -> void:
	var def := ItemDef.find(item_id)
	var inventory := Game.module(&"Inventory")
	if inventory and def and not inventory.spend(def.cost):
		Events.say("You need %s." % _price(def))
		return
	layout.spawn(item_id, spawn_point.global_transform)


func _price(def: ItemDef) -> String:
	if def == null or def.cost.is_empty():
		return "free"
	var parts: PackedStringArray = []
	for item_id in def.cost:
		parts.append("%d %s" % [def.cost[item_id], ItemDef.label(item_id)])
	return ", ".join(parts)
