class_name Level
extends Node3D
## Root script for every level scene (the island).
##
## On ready it registers with Game, puts the player on the child Marker3D
## named "Spawn" and reports "entered:<level_id>".
## Any level can also be run on its own (F6): a player is created for it.

## Empty = the scene file name ("island.tscn" -> &"island").
@export var level_id: StringName = &""


func _ready() -> void:
	if level_id.is_empty():
		level_id = StringName(scene_file_path.get_file().get_basename())
	if not is_instance_valid(Game.player):
		add_child(load(Game.PLAYER_SCENE).instantiate())
	Game.enter_level(self)
	var spawn := get_node_or_null(^"Spawn") as Node3D
	if spawn:
		Game.place_player(spawn.global_transform)
	Events.report(&"entered", level_id)
