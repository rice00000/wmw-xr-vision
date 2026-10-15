extends Node3D
## Boot scene: creates the persistent player once, then swaps levels under $Level.

@export_file("*.tscn") var first_level := "res://levels/island/island.tscn"


func _ready() -> void:
	add_child(load(Game.PLAYER_SCENE).instantiate())
	Game.level_root = $Level
	Game.home_level = first_level
	Game.change_level(_first())


## "-- --level=testbed" (or a full res:// path) boots straight into one level, so
## a level can be opened without walking the game to it — including on the
## headset, where there is no F6: tools\quest.cmd run passes it through.
func _first() -> String:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--level="):
			continue
		var name := arg.trim_prefix("--level=")
		var path := name if name.begins_with("res://") else "res://levels/%s/%s.tscn" % [name, name]
		if ResourceLoader.exists(path):
			return path
		push_warning("[Main] No level called '%s' (%s)" % [name, path])
	return first_level
