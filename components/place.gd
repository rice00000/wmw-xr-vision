class_name Place
extends Marker3D
## A named spot in the world that tasks and the guide refer to by id
## (TaskStep.place, Events.goal_changed). Stand it where the child should end up,
## facing the way they should look. Tasks never know the map; the map never knows tasks.

const GROUP := &"place"

@export var id: StringName = &""
@export var display_name := ""


func _enter_tree() -> void:
	add_to_group(GROUP)


static func find(tree: SceneTree, place_id: StringName) -> Place:
	for node in tree.get_nodes_in_group(GROUP):
		if node is Place and node.id == place_id:
			return node
	return null
