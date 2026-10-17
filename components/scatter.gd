class_name Scatter
extends Node3D
## Lays copies of scenes out on the plane through this point without stacking
## them (visual clutter).
##
## On its own it fills a level once, with the amount following the player's
## Training level for [member visual_skill], so busier scenes come as the child improves.
## A task drives it per round with [method place] instead, which also returns what
## it placed and can crowd the objects together.

@export var scenes: Array[PackedScene] = []
@export var radius := 4.0
## Compress placement depth without scaling objects. Useful for reachable tabletop rows.
@export_range(0.05, 1.0) var depth_scale := 1.0
@export var min_count := 10
@export var max_count := 40
## Training visual skill that sets the amount. Empty = always [member min_count].
@export var visual_skill: StringName = &""
## Same layout every time when non-zero.
@export var random_seed := 0
## Smallest gap between two objects, at crowding 0.
@export var spacing := 0.3
## Random size variation, 0-1. Looks natural for scenery, but it is a size cue a
## vision task would be measuring against, so it stays off by default.
@export_range(0.0, 1.0) var scale_jitter := 0.0
## Place each scene at most once, shuffled ([param count] is capped at the number
## of scenes). Tasks that name one object by id need this: two of the same thing
## would make "find the cup" ambiguous.
@export var unique := false


func _ready() -> void:
	if not scenes.is_empty():
		place(scenes, _auto_count())


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


## Places [param count] random picks from [param from] and returns them, in the
## order they went down.
##
## [param crowding] (0-1) pulls everything into a tighter cluster and lets the
## objects sit closer, so from where the child is they start to overlap — the
## difficulty the design calls "more overlap".
func place(from: Array[PackedScene], count: int, crowding := 0.0, seed_override := 0) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	if from.is_empty() or count <= 0:
		return placed
	var rng := RandomNumberGenerator.new()
	var chosen_seed := seed_override if seed_override != 0 else random_seed
	if chosen_seed != 0:
		rng.seed = chosen_seed
	crowding = clampf(crowding, 0.0, 1.0)
	var spread := radius * lerpf(1.0, 0.35, crowding)
	var gap := spacing * lerpf(1.0, 0.1, crowding)
	var pool: Array[PackedScene] = from.duplicate()
	if unique:
		pool.shuffle()
		count = mini(count, pool.size())
	var spots: Array[Vector2] = []
	for i in count:
		var spot := _free_spot(rng, spread, gap, spots)
		spots.append(spot)
		var scene := pool[i] if unique else pool[rng.randi() % pool.size()]
		var node := scene.instantiate() as Node3D
		if node == null:
			continue
		node.position = Vector3(spot.x, 0.0, spot.y)
		node.rotation.y = rng.randf() * TAU
		if scale_jitter > 0.0:
			node.scale *= 1.0 + rng.randf_range(-scale_jitter, scale_jitter)
		add_child(node)
		placed.append(node)
	return placed


## Moves [param node] onto the line between the player's head and [param anchor],
## [param fraction] of the way along, so it covers part of the anchor from where
## the child is sitting.
func occlude(node: Node3D, anchor: Node3D, fraction := 0.45) -> void:
	var player := Game.player
	if node == null or anchor == null or not is_instance_valid(player):
		return
	var eye: Vector3 = player.get_node(^"Camera").global_position if player.has_node(^"Camera") else player.global_position
	var from := Vector3(eye.x, anchor.global_position.y, eye.z)
	node.global_position = from.lerp(anchor.global_position, clampf(fraction, 0.05, 0.95))


## How many to place when no task is driving this.
func _auto_count() -> int:
	var difficulty := 0.0
	var training := Game.module(&"Training")
	if training and not visual_skill.is_empty():
		difficulty = training.level(visual_skill)
	return roundi(lerpf(min_count, max_count, difficulty))


## A point in the disc at least [param gap] from the ones already taken; gives up
## on the loosest option rather than hanging when the disc is full.
func _free_spot(rng: RandomNumberGenerator, spread: float, gap: float, taken: Array[Vector2]) -> Vector2:
	var best := Vector2.ZERO
	var best_clearance := -1.0
	for _attempt in 12:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * spread
		var spot := Vector2(cos(angle), sin(angle) * depth_scale) * distance
		var clearance := INF
		for other in taken:
			clearance = minf(clearance, spot.distance_to(other))
		if clearance >= gap:
			return spot
		if clearance > best_clearance:
			best_clearance = clearance
			best = spot
	return best
