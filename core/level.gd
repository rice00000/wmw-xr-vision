class_name Level
extends Node3D
## Root script for every level scene (the island, the Test Room).
##
## On ready it registers with Game, puts the player on the child Marker3D
## named "Spawn" and reports "entered:<level_id>".
## Any level can also be run on its own (F6): a player is created for it.

## Empty = the scene file name ("island.tscn" -> &"island").
@export var level_id: StringName = &""
## Seated play: switch the player's stick walking off while this level is up.
## Smooth movement is the usual sickness trigger, and a child who has just gained
## sight has no history of matching what they see against what they feel.
## Teleport keeps working. Each level sets this for itself.
@export var seated := false


func _ready() -> void:
	if level_id.is_empty():
		level_id = StringName(scene_file_path.get_file().get_basename())
	if not is_instance_valid(Game.player):
		add_child(load(Game.PLAYER_SCENE).instantiate())
	Game.enter_level(self)
	var spawn := get_node_or_null(^"Spawn") as Node3D
	if spawn:
		Game.place_player(spawn.global_transform)
	_set_walking(not seated)
	Events.report(&"entered", level_id)


## Duck-typed like the rest of the player seam: a rig without a Locomotion node
## simply has nothing to switch.
func _set_walking(on: bool) -> void:
	if not is_instance_valid(Game.player):
		return
	var walking := Game.player.get_node_or_null(^"Locomotion")
	if walking and &"enabled" in walking:
		walking.enabled = on
