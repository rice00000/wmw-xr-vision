extends RefCounted
## Engine facts only. Python owns body dimensions, thresholds and verdicts.


static func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func basis(value: Basis) -> Array:
	return [vector(value.x), vector(value.y), vector(value.z)]


static func pose() -> Dictionary:
	var player := Game.player
	var camera := player.get_node(^"Camera") as Node3D
	var hands := {}
	for side in ["left", "right"]:
		var hand := player.get_node("%sController/Hand" % side.capitalize()) as Hand
		hands[side] = {position = vector(hand.global_position),
			basis = basis(hand.global_basis), fingertip = vector(hand.poke_point()),
			held = str(hand.held.id) if is_instance_valid(hand.held) else "",
			held_path = str(hand.held.get_path()) if is_instance_valid(hand.held) else "",
			radius = (hand.get_node(^"Shape").shape as SphereShape3D).radius}
	return {eye = vector(camera.global_position), eye_basis = basis(camera.global_basis),
		seconds = Time.get_ticks_usec() / 1000000.0,
		rig_position = vector(player.global_position), rig_basis = basis(player.global_basis), hands = hands}


static func target(node: Node3D) -> Dictionary:
	var box := AABB()
	var first := true
	var corners: Array = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var bounds := mesh.global_transform * mesh.mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
		for i in 8:
			corners.append(vector(mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(i)))
	var point := box.get_center() if node is Grabbable else node.global_position
	var radius := 0.0
	for shape: CollisionShape3D in node.find_children("*", "CollisionShape3D", false, false):
		if shape.shape is SphereShape3D:
			radius = (shape.shape as SphereShape3D).radius * shape.global_basis.get_scale().x
	var allowed: Array = []
	var grasp := {}
	for side in ["left", "right"]:
		var hand := Game.player.get_node("%sController/Hand" % side.capitalize()) as Hand
		if not node.has_method(&"can_touch") or node.can_touch(hand):
			allowed.append(side)
		if node is Grabbable:
			grasp[side] = _grasp_surface(node, hand.global_position)
	if node == Menu.star():
		allowed = ["right"]
		radius = Menu.STAR_RADIUS
	var camera := Game.player.get_node(^"Camera") as Node3D
	var blockers: Array = []
	var clear := 0
	# Multiple rays avoid accepting a marker with only one visible corner.
	var spread := minf(box.size.x, box.size.y) * 0.25
	var exclude: Array[RID] = []
	if node is CollisionObject3D:
		exclude.append(node.get_rid())
	for offset: Vector2 in [Vector2.ZERO, Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		var end := point + (camera.global_basis.x * offset.x + camera.global_basis.y * offset.y) * spread
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, end)
		query.exclude = exclude
		query.hit_from_inside = true
		var hit := node.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			clear += 1
		else:
			blockers.append(str(hit.collider.get_path()))
	return {id = str(node.get("id")) if "id" in node else str(node.name),
		path = str(node.get_path()), point = vector(point), position = vector(node.global_position),
		visible = node.is_visible_in_tree(), visual_corners = corners, touch_radius = radius,
		allowed_hands = allowed, clear_fraction = clear / 5.0, blockers = blockers,
		grasp = grasp,
		basis = basis(node.global_basis),
		done = node is Catchable and node.is_done(),
		ray_size = [node.size.x, node.size.y] if node is RayButton else [],
		occlusion_model = "physics collision proxies"}


static func _grasp_surface(node: Node3D, hand: Vector3) -> Dictionary:
	var nearest := INF
	var result := {}
	for shape: CollisionShape3D in node.find_children("*", "CollisionShape3D", false, false):
		var local := shape.to_local(hand)
		var point: Vector3
		var normal: Vector3
		if shape.shape is BoxShape3D:
			var half := (shape.shape as BoxShape3D).size * 0.5
			point = local.clamp(-half, half)
			if point.is_equal_approx(local):
				var gaps := half - local.abs()
				var axis := gaps.min_axis_index()
				normal = Vector3.ZERO
				normal[axis] = -1.0 if local[axis] < 0 else 1.0
				point[axis] = normal[axis] * half[axis]
			else:
				normal = (local - point).normalized()
		elif shape.shape is SphereShape3D:
			normal = local.normalized() if not local.is_zero_approx() else Vector3.BACK
			point = normal * (shape.shape as SphereShape3D).radius
		else:
			continue
		var world_point := shape.to_global(point)
		var separation := hand.distance_to(world_point)
		if separation < nearest:
			nearest = separation
			result = {point = vector(world_point), approach = vector((shape.global_basis * normal).normalized())}
	return result


static func sweep(hand: Hand, points: Array, radius: float, contact: Node3D) -> Dictionary:
	var excluded: Array[RID] = []
	# A held object's own holder necessarily overlaps it. The other hand may not pass through it.
	if is_instance_valid(hand.held):
		excluded.append(hand.held.get_rid())
	if contact is Grabbable:
		excluded.append(contact.get_rid()) # intended grasp contact
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.exclude = excluded
	var space := hand.get_world_3d().direct_space_state
	for i in points.size():
		var p: Array = points[i]
		query.transform.origin = Vector3(p[0], p[1], p[2])
		query.motion = Vector3.ZERO
		var hits := space.intersect_shape(query, 1)
		if not hits.is_empty():
			return {clear = false, segment = i, blocker = str(hits[0].collider.get_path())}
		if i + 1 < points.size():
			var next: Array = points[i + 1]
			query.motion = Vector3(next[0], next[1], next[2]) - query.transform.origin
			var fraction := space.cast_motion(query)
			if fraction[0] < 1.0:
				return {clear = false, segment = i, safe_fraction = fraction[0]}
	return {clear = true}
