class_name Zone
extends Area3D
## A volume the player's head can walk into. Reports "entered:<id>" and,
## when [member target_level] is set, loads that level (door / portal).

@export var id: StringName = &"zone"
@export_file("*.tscn") var target_level := ""
## Shown on a child Label3D named "Label", if there is one.
@export var label := ""


func _ready() -> void:
	var label_node := get_node_or_null(^"Label") as Label3D
	if label_node and not label.is_empty():
		label_node.text = label


func player_entered(_player: Node3D) -> void:
	Events.report(&"entered", id)
	if not target_level.is_empty():
		Game.change_level(target_level)
