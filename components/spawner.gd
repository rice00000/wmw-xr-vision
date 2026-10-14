class_name Spawner
extends Marker3D
## Keeps [member alive] copies of [member scene] around this point.
## When one disappears (caught, escaped...) a new one comes after [member delay].

@export var scene: PackedScene
@export var alive := 1
## Stop after this many spawns in total. 0 = endless.
@export var total := 0
@export var delay := 1.0

var _spawned := 0


func _ready() -> void:
	child_exiting_tree.connect(_on_child_exiting)
	for _i in alive:
		_spawn()


func _spawn() -> void:
	if scene == null or not is_inside_tree() or (total > 0 and _spawned >= total):
		return
	_spawned += 1
	add_child(scene.instantiate())


func _on_child_exiting(_child: Node) -> void:
	get_tree().create_timer(delay).timeout.connect(_spawn)
