extends Node3D
## Isolated arrangements of real player/furniture code. Faults exist only here.

var layout: DecorLayout
var fault := ""
var obstacle: StaticBody3D
var _chase_height := INF
var _fault_anchor := Vector3.INF


func _ready() -> void:
	process_priority = 1000 # inject deliberate faults after the production button follows
	add_child(load(Game.PLAYER_SCENE).instantiate())
	layout = load("res://modules/placement/decor_layout.tscn").instantiate()
	add_child(layout)
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(8, 0.1, 8)
	shape.position.y = -0.05
	floor_body.add_child(shape)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.09, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	Game.enter_level(self)


func configure(data: Dictionary) -> void:
	Menu.close()
	for side in ["left", "right"]:
		var hand := Game.player.get_node("%sController/Hand" % side.capitalize()) as Hand
		hand.release()
	layout.load_state({})
	if is_instance_valid(obstacle):
		remove_child(obstacle)
		obstacle.queue_free()
	Inventory.spend(Inventory.all())
	var origin: Array = data.get("origin", [0, 0, 0])
	Game.player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(data.get("yaw", 0.0))),
		Vector3(origin[0], origin[1], origin[2]))
	var camera := Game.player.get_node(^"Camera") as Node3D
	camera.position = Vector3(0, data.eye_height, 0)
	camera.rotation_degrees = Vector3.ZERO
	fault = data.get("fault", "")
	_chase_height = INF
	_fault_anchor = Vector3.INF
	var button := layout.get_node(^"PutAwayButton") as PutAwayButton
	button.scale = Vector3.ONE * (0.03 if fault == "tiny" else 1.0)
	if data.has("item"):
		var side: String = data.get("side", "right")
		var spot := Vector3(-0.26 if side == "left" else 0.26, data.eye_height - 0.35, -0.30)
		var node := layout.spawn(StringName(data.item), Game.player.global_transform)
		node.global_position = Game.player.to_global(spot) - Game.player.global_basis * DecorLayout._local_bounds(node).get_center()
	if fault == "occluded" or fault == "path_blocked":
		obstacle = StaticBody3D.new()
		obstacle.name = "DeliberateObstacle"
		add_child(obstacle)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(0.8, 0.8, 0.02)
		obstacle.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.mesh.size = shape.shape.size
		obstacle.add_child(mesh)
		obstacle.global_transform = Game.player.global_transform
		obstacle.position += Game.player.global_basis * Vector3(0, data.eye_height - 0.15, -0.23)


func _process(_delta: float) -> void:
	var button := layout.get_node(^"PutAwayButton") as PutAwayButton
	if fault == "occluded" and is_instance_valid(obstacle):
		obstacle.collision_layer = 1 if is_instance_valid(button.item) else 0
		obstacle.visible = is_instance_valid(button.item)
	if not is_instance_valid(button.item):
		return
	match fault:
		"rising": # original bug: button follows the top of the held item
			button.global_position = button.item.global_position + Vector3.UP * (DecorLayout._local_bounds(button.item).end.y + 0.12)
		"far":
			button.global_position += Game.player.global_basis * Vector3(0, 0, -1)
		"chasing": # follows the holding hand up and down
			var hand := (button.item as Grabbable).holder
			if _chase_height == INF:
				_chase_height = hand.global_position.y
			button.global_position.y += hand.global_position.y - _chase_height
		"head_anchored": # previous fix: looking toward the item puts the prompt into it
			var camera := Game.player.get_node(^"Camera") as Node3D
			if _fault_anchor == Vector3.INF:
				_fault_anchor = camera.position + Basis(Vector3.UP, camera.rotation.y) * button.reach_offset
			button.global_position = Game.player.to_global(_fault_anchor)
