class_name HomeLayout
extends Node3D
## Holds the furniture the player placed in one room and remembers it (via the Save module).
## Hand-placed children are left alone; only spawned items (meta "item_id") are saved.

## Give each room its own key if there's more than one layout.
@export var save_key := &"home_layout"


## Creates the item's scene (ItemDef.scene) at [param xform] (global).
func spawn(item_id: StringName, xform: Transform3D) -> Node3D:
	var def := ItemDef.find(item_id)
	if def == null or def.scene == null:
		push_warning("[HomeLayout] No scene for item: %s" % item_id)
		return null
	var node := def.scene.instantiate() as Node3D
	node.set_meta(&"item_id", item_id)
	add_child(node)
	node.global_transform = xform
	return node


func save_state() -> Dictionary:
	var items: Array = []
	for child in get_children():
		if child.has_meta(&"item_id"):
			items.append([child.get_meta(&"item_id"), (child as Node3D).transform])
	return {items = items}


func load_state(data: Dictionary) -> void:
	for child in get_children():
		if child.has_meta(&"item_id"):
			remove_child(child)
			child.queue_free()
	for entry: Array in data.get("items", []):
		var local: Transform3D = entry[1]
		spawn(entry[0], global_transform * local)
