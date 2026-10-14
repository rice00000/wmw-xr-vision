class_name ItemDef
extends Resource
## Static data for one kind of item (coin, chair, butterfly...).
##
## Lives at res://content/items/<id>.tres. The file name IS the item id,
## so modules only ever pass ids around and look details up here.

const DIR := "res://content/items/"

@export var display_name := ""
@export var icon: Texture2D
## What appears in the world when the item is placed (furniture, creature...).
@export var scene: PackedScene
## Price paid from the inventory to place / buy it, e.g. {&"coin": 3}.
@export var cost: Dictionary[StringName, int] = {}

var id: StringName:
	get:
		return StringName(resource_path.get_file().get_basename())


static func find(item_id: StringName) -> ItemDef:
	var path := "%s%s.tres" % [DIR, item_id]
	return load(path) as ItemDef if ResourceLoader.exists(path) else null


## Human-readable name, even for ids that have no ItemDef file.
static func label(item_id: StringName) -> String:
	var def := find(item_id)
	if def and not def.display_name.is_empty():
		return def.display_name
	return String(item_id).capitalize()
