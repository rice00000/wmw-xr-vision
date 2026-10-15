extends Node
## The rig's part of every judgement (Events.feedback): the hand nearest to where
## it happened vibrates in a pattern of its own per kind, and a shape mark rises
## and fades there — a tick for good, a cross for bad, a star for a reward. Shape,
## rhythm and (from the Audio module) sound, so nothing is told by colour alone.
## The marks' looks are scenes under content/effects/, swappable without code.

const MARKS := {
	&"good": preload("res://content/effects/mark_good.tscn"),
	&"bad": preload("res://content/effects/mark_bad.tscn"),
	&"reward": preload("res://content/effects/mark_reward.tscn"),
}
## The word each mark's shape is known by, for tests and logs.
const SHAPES := {&"good": &"tick", &"bad": &"cross", &"reward": &"star"}

## Seconds a mark takes to rise and fade.
@export var seconds := 1.0
@export var rise := 0.25
## Marks start this far above the judged point, so the object does not hide them.
@export var lift := 0.15
@export var mark_scale := 1.3

## The last mark spawned (freed once it has faded), a test seam.
var last_mark: Node3D


func _ready() -> void:
	Events.feedback.connect(_on_feedback)


func _on_feedback(kind: StringName, position: Vector3) -> void:
	var hand := _nearest_hand(position)
	if hand:
		hand.play(kind)
	if MARKS.has(kind):
		last_mark = _spawn_mark(kind, position)


func _spawn_mark(kind: StringName, position: Vector3) -> Node3D:
	var mark := (MARKS[kind] as PackedScene).instantiate() as Node3D
	mark.set_meta(&"shape", SHAPES[kind])
	var world: Node = Game.level if is_instance_valid(Game.level) else get_parent().get_parent()
	if world == null:
		return null
	world.add_child(mark)
	mark.process_mode = Node.PROCESS_MODE_ALWAYS
	mark.global_position = position + Vector3.UP * lift
	var camera := get_parent().get_node_or_null(^"Camera") as Node3D
	if camera and not camera.global_position.is_equal_approx(mark.global_position):
		var eye := camera.global_position
		eye.y = mark.global_position.y # stay upright, face the child
		if not eye.is_equal_approx(mark.global_position):
			mark.look_at(eye, Vector3.UP, true)
	mark.scale = Vector3.ONE * mark_scale * 0.6
	var meshes := mark.find_children("*", "GeometryInstance3D", true, false)
	var tween := mark.create_tween().set_parallel()
	tween.tween_property(mark, ^"scale", Vector3.ONE * mark_scale, seconds * 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(mark, ^"global_position:y", mark.global_position.y + rise, seconds) \
		.set_ease(Tween.EASE_OUT)
	if kind == &"reward":
		tween.tween_property(mark, ^"rotation:y", mark.rotation.y + TAU, seconds)
	for mesh: GeometryInstance3D in meshes:
		tween.tween_property(mesh, ^"transparency", 1.0, seconds * 0.5).set_delay(seconds * 0.5)
	tween.chain().tween_callback(mark.queue_free)
	return mark


func _nearest_hand(position: Vector3) -> Node:
	var best: Node = null
	var best_distance := INF
	for hand in get_parent().find_children("*", "Area3D", true, false):
		if hand.is_in_group(&"hand") and hand.has_method(&"play"):
			var distance: float = hand.global_position.distance_squared_to(position)
			if distance < best_distance:
				best = hand
				best_distance = distance
	return best
