class_name Scatter
extends Node3D
## Scatters random copies of [member scenes] on the ground in a circle (visual clutter).
## With a [member skill] set, the amount follows the player's Training level for it,
## so busier scenes come automatically as the player gets better.

@export var scenes: Array[PackedScene] = []
@export var radius := 4.0
@export var min_count := 10
@export var max_count := 40
## Training skill that sets the amount. Empty = always [member min_count].
@export var skill: StringName = &""
## Same layout every time when non-zero.
@export var random_seed := 0


func _ready() -> void:
	if scenes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	var difficulty := 0.0
	var training := Game.module(&"Training")
	if training and not skill.is_empty():
		difficulty = training.level(skill)
	for _i in roundi(lerpf(min_count, max_count, difficulty)):
		var node := scenes[rng.randi() % scenes.size()].instantiate() as Node3D
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * radius
		node.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		node.rotation.y = rng.randf() * TAU
		node.scale *= rng.randf_range(0.8, 1.3)
		add_child(node)
