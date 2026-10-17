class_name DecorLayout
extends Node3D
## Every piece of furniture the child has put out in the world, remembered (via
## the Save module) as id + transform. One per world: instance
## modules/placement/decor_layout.tscn once in the level, at the level's origin.
##
## In: Events.place_requested(id) from the wrist menu's bag page. One [code]id[/code]
## leaves the Inventory and its ItemDef.scene (a Placeable) appears in the child's
## free hand, near side first, square to the world, standing on what is below
## (or floating 0.4 m in front of them at hand height when both hands are full);
## reports "taken_out:<id>". Letting go leaves it standing ("placed:<id>").
##
## Out: while a hand holds one of these items, a "put away" button waits within
## reach in front of the player. Touching it with the other hand puts it back: +1 in the
## Inventory, "put_away:<id>", and it shrinks away. Two moves, no menu.
##
## Hand-placed children are left alone; only spawned items (meta "item_id") are saved.

const BUTTON := preload("res://modules/placement/put_away_button.tscn")
const META := &"item_id"

@export var save_key := &"decor_layout"
## Where the item goes when both hands are full: this far in front of the eyes.
@export var front_distance := 0.4

var _button: PutAwayButton


func _ready() -> void:
	Events.place_requested.connect(_on_place_requested)
	_button = BUTTON.instantiate() as PutAwayButton
	_button.top_level = true
	_button.pressed.connect(put_away)
	add_child(_button)
	_button.show_for(null)


## Creates the item's scene (ItemDef.scene) at [param xform] (global).
func spawn(item_id: StringName, xform: Transform3D) -> Node3D:
	var def := ItemDef.find(item_id)
	if def == null or def.scene == null:
		push_warning("[DecorLayout] No scene for item: %s" % item_id)
		return null
	var node := def.scene.instantiate() as Node3D
	node.set_meta(META, item_id)
	add_child(node)
	node.global_transform = xform
	if node is Grabbable:
		node.grabbed.connect(func(_hand: Node3D) -> void: _button.show_for(node))
		node.released.connect(func(_hand: Node3D) -> void: _on_item_released(node))
	return node


## Every saved item under this layout.
func items() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in get_children():
		if child.has_meta(META):
			found.append(child)
	return found


## Moves one [param item_id] from the Inventory into the child's hand. Does
## nothing (and returns null) when it is not owned or has no scene.
func take_out(item_id: StringName) -> Node3D:
	var inventory := Game.module(&"Inventory")
	var def := ItemDef.find(item_id)
	if inventory == null or def == null or def.scene == null or inventory.count(item_id) < 1:
		return null
	if not inventory.spend({item_id: 1}):
		return null
	var node := spawn(item_id, global_transform)
	var hand := _free_hand()
	var bounds := _local_bounds(node)
	var turn := Basis(Vector3.UP, snappedf(_player_yaw(), Placeable.TURN_STEP))
	if hand and node is Grabbable:
		var near := Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z) # the side facing the child
		node.global_transform = Transform3D(turn, hand.global_position).translated_local(-near)
		hand.hold(node)
	else:
		node.global_transform = Transform3D(turn, _front_spot()).translated_local(-bounds.get_center())
	Events.report(&"taken_out", item_id, {position = node.global_position})
	return node


## Back into the bag: +1 in the Inventory, "put_away:<id>", and the item goes.
func put_away(node: Node3D) -> void:
	if node == null or not is_instance_valid(node) or not node.has_meta(META):
		return
	var item_id: StringName = node.get_meta(META)
	node.remove_meta(META) # no longer saved, even while it shrinks
	var body := node as Grabbable
	if body:
		if body.holder and body.holder.get(&"held") == body:
			body.holder.set(&"held", null) # let go without "placed"
		body.holder = self # the bag has it now: no hand can take it while it shrinks
		body.freeze = true
		body.collision_layer = 0
	_button.show_for(_still_held(node))
	var inventory := Game.module(&"Inventory")
	if inventory:
		inventory.add(item_id, 1)
	Events.report(&"put_away", item_id, {position = node.global_position})
	var tween := node.create_tween()
	tween.tween_property(node, ^"scale", Vector3.ONE * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(node.queue_free)


func _on_place_requested(item_id: StringName) -> void:
	take_out(item_id)


## [id, transform local to the layout]. Furniture in a hand already stands
## where it would be let go, so a save mid-carry needs nothing more.
func save_state() -> Dictionary:
	var saved: Array = []
	for node in items():
		saved.append([node.get_meta(META), node.transform]) # direct children: already local
	return {items = saved}


func load_state(data: Dictionary) -> void:
	for node in items():
		remove_child(node)
		node.queue_free()
	_button.show_for(null)
	for entry: Array in data.get("items", []):
		spawn(entry[0], global_transform * (entry[1] as Transform3D))


## The button belongs to whatever is still in a hand once [param node] is let go.
func _on_item_released(node: Node3D) -> void:
	if _button.item == node or _button.item == null:
		_button.show_for(_still_held(node))


## Another layout item a hand is holding, or null.
func _still_held(except: Node3D) -> Node3D:
	for node in items():
		if node != except and node is Grabbable and (node as Grabbable).holder != null:
			return node
	return null


## An empty hand of the player's, the right one first.
func _free_hand() -> Node3D:
	var player := Game.player
	if not is_instance_valid(player):
		return null
	for path: NodePath in [^"RightController/Hand", ^"LeftController/Hand"]:
		var hand := player.get_node_or_null(path)
		if hand and hand.has_method(&"hold") and hand.get(&"held") == null:
			return hand
	return null


func _front_spot() -> Vector3:
	var player := Game.player
	if not is_instance_valid(player):
		return global_position
	var camera := player.get_node_or_null(^"Camera") as Node3D
	var eye: Vector3 = camera.global_position if camera else player.global_position + Vector3.UP * 1.3
	var forward := -camera.global_basis.z if camera else -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var height := eye.y - 0.45
	var hands := 0
	var sum := 0.0
	for path: NodePath in [^"RightController/Hand", ^"LeftController/Hand"]:
		var hand := player.get_node_or_null(path) as Node3D
		if hand:
			sum += hand.global_position.y
			hands += 1
	if hands > 0:
		height = sum / hands
	return Vector3(eye.x, height, eye.z) + forward * front_distance


func _player_yaw() -> float:
	var player := Game.player
	var camera := player.get_node_or_null(^"Camera") as Node3D if is_instance_valid(player) else null
	return camera.global_rotation.y if camera else 0.0


## The item's meshes' box in its own space.
static func _local_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inverse := node.global_transform.affine_inverse()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var local := (inverse * mesh.global_transform) * mesh.mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box
