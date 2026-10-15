class_name GroundGrid
extends RefCounted
## Where somebody on foot can go, read straight off the physics world, and the
## shortest way between two points (A* on a grid).
##
## Nothing is baked ahead of time. A cell is looked at the first time a search
## reaches it — one ray down for the ground, one capsule for room to stand — and
## remembered. A walk across open grass touches a narrow band of cells; a walk
## round a house touches a few more. That keeps it cheap on a headset and lets it
## run headless in the test suite, where it does not wait on a navigation server.
##
## [b]What blocks[/b]: static colliders ([StaticBody3D], [CSGShape3D]) taller than
## [member step_height] inside the capsule; ground steeper than ~45°; height jumps
## between neighbouring cells above [member step_height]; and no ground at all,
## which is what open water usually is. A water surface that does have a collider
## is blocked by putting it (or its parent) in the group [constant WATER_GROUP].
## Things you can pick up ([RigidBody3D]) never block.

const WATER_GROUP := &"water"
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## Cell size in metres. A doorway needs to be about 2 × ([member clearance] +
## cell / 2) wide to be found.
var cell := 0.5
## Kept free of walls all round the walker.
var clearance := 0.3
var body_height := 1.6
## Biggest step up or down between neighbouring cells.
var step_height := 0.35
## Give up after looking at this many cells: there is no way, or it is very far.
var max_nodes := 3000
## Cells sampled from the physics world so far. A [Search] stepped with a budget
## counts against this, so the cost of a frame is bounded.
var samples := 0

var _world: World3D
var _cells: Dictionary[Vector2i, float] = {} # NAN = cannot stand there
var _body := CapsuleShape3D.new()


## One A* search in progress, so a long one can be spread over several frames
## ([method advance]). [member path] is empty when it found no way.
class Search:
	extends RefCounted
	var to := Vector3.ZERO
	var start := Vector2i.ZERO
	var goal := Vector2i.ZERO
	var came: Dictionary[Vector2i, Vector2i] = {}
	var cost: Dictionary[Vector2i, float] = {}
	var closed: Dictionary[Vector2i, bool] = {}
	var heap_cost := PackedFloat32Array()
	var heap_cell: Array[Vector2i] = []
	var done := false
	var path := PackedVector3Array()


func _init(world: World3D) -> void:
	_world = world


## Forget everything sampled, e.g. after a building appears.
func clear() -> void:
	_cells.clear()


func to_cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / cell), roundi(point.z / cell))


## Ground height of [param at]'s cell, or NAN where nobody can stand.
## [param reference] is roughly how high the ground is there.
func height(at: Vector2i, reference: float) -> float:
	if not _cells.has(at):
		samples += 1
		_cells[at] = _sample(at, reference)
	return _cells[at]


func can_stand(point: Vector3) -> bool:
	return not is_nan(height(to_cell(point), point.y))


## The way from [param from] to [param to] as points on the ground, smoothed so
## it runs straight wherever it can, ending at [param to] (or the nearest place
## to it anyone can stand). Empty when there is no way. All in one go: use
## [method begin] and [method advance] to spread a search over frames.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var search := begin(from, to)
	advance(search, max_nodes * 9)
	return search.path


## Starts a search for [method advance] to carry on.
func begin(from: Vector3, to: Vector3) -> Search:
	var search := Search.new()
	search.to = to
	var start: Variant = _nearest(from, 4)
	var goal: Variant = _nearest(to, 4)
	if start == null or goal == null:
		search.done = true
		return search
	search.start = start
	search.goal = goal
	search.cost[search.start] = 0.0
	_push(search, search.start, _guess(search.start, search.goal))
	return search


## Carries [param search] on until it is done or [param budget] new cells have
## been sampled. Returns whether it is done.
func advance(search: Search, budget: int) -> bool:
	if search.done:
		return true
	var limit := samples + budget
	while not search.heap_cell.is_empty():
		if samples >= limit:
			return false
		var at := _pop(search)
		if at == search.goal:
			search.path = _smooth(search)
			search.done = true
			return true
		if search.closed.has(at):
			continue
		search.closed[at] = true
		if search.closed.size() > max_nodes:
			break
		var here := _cells[at]
		for step in NEIGHBOURS:
			var next := at + step
			if search.closed.has(next):
				continue
			var there := height(next, here)
			if is_nan(there) or absf(there - here) > step_height:
				continue
			var diagonal := step.x != 0 and step.y != 0
			if diagonal and (is_nan(height(at + Vector2i(step.x, 0), here))
					or is_nan(height(at + Vector2i(0, step.y), here))):
				continue # never cut a corner
			var through := search.cost[at] + (1.41421 if diagonal else 1.0)
			if through < search.cost.get(next, INF):
				search.cost[next] = through
				search.came[next] = at
				_push(search, next, through + _guess(next, search.goal))
	search.done = true
	return true


## Straight line from [param a] to [param b] with ground all the way and no step
## too high.
func clear_line(a: Vector3, b: Vector3) -> bool:
	return _clear_line(a, b)


# -- internals --------------------------------------------------------------

## The cells found, as points, string-pulled: from each point, jump to the
## furthest one in plain sight.
func _smooth(search: Search) -> PackedVector3Array:
	var cells: Array[Vector2i] = [search.goal]
	var at := search.goal
	while at != search.start:
		at = search.came[at]
		cells.push_front(at)
	var points: Array[Vector3] = []
	for each in cells:
		points.append(Vector3(each.x * cell, _cells[each], each.y * cell))
	if points.size() == 1:
		points.append(points[0]) # already there: one step on the spot
	var path := PackedVector3Array()
	var i := 0
	while i < points.size() - 1:
		var j := points.size() - 1
		while j > i + 1 and not _clear_line(points[i], points[j]):
			j -= 1
		path.append(points[j])
		i = j
	var to := search.to
	if can_stand(to) and to_cell(to) == search.goal:
		path[path.size() - 1] = Vector3(to.x, path[path.size() - 1].y, to.z)
	return path


## Octile distance: exact on an empty 8-connected grid, so A* stays optimal.
func _guess(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return dx + dy - 0.58579 * mini(dx, dy)


## The standable cell closest to [param point], up to [param rings] cells away.
func _nearest(point: Vector3, rings: int) -> Variant:
	var centre := to_cell(point)
	if not is_nan(height(centre, point.y)):
		return centre
	for ring in range(1, rings + 1):
		var best: Variant = null
		var best_distance := INF
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var at := centre + Vector2i(dx, dy)
				if is_nan(height(at, point.y)):
					continue
				var distance := Vector2(at.x * cell - point.x, at.y * cell - point.z).length()
				if distance < best_distance:
					best_distance = distance
					best = at
		if best != null:
			return best
	return null


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var samples := maxi(1, ceili(flat.length() / (cell * 0.5)))
	var previous := a.y
	for i in range(1, samples + 1):
		var point := a.lerp(b, float(i) / samples)
		var ground := height(to_cell(point), previous)
		if is_nan(ground) or absf(ground - previous) > step_height:
			return false
		previous = ground
	return true


func _sample(at: Vector2i, reference: float) -> float:
	var space := _world.direct_space_state
	if space == null:
		return NAN
	var x := at.x * cell
	var z := at.y * cell
	var exclude: Array[RID] = []
	var ground := NAN
	for _attempt in 6:
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(x, reference + 2.0, z), Vector3(x, reference - 4.0, z), 0xFFFFFFFF, exclude)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or _is_water(hit.collider):
			return NAN
		if not _is_solid(hit.collider):
			exclude.append(hit.rid) # something loose lying there: look underneath
			continue
		if hit.normal.y < 0.7:
			return NAN
		ground = hit.position.y
		break
	if is_nan(ground):
		return NAN
	_body.radius = clearance
	_body.height = maxf(body_height - step_height, clearance * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body
	query.transform = Transform3D(Basis.IDENTITY, Vector3(x, ground + step_height + _body.height * 0.5, z))
	for result in space.intersect_shape(query, 8):
		if _is_solid(result.collider):
			return NAN
	return ground


func _is_solid(collider: Object) -> bool:
	return collider is StaticBody3D or collider is CSGShape3D


func _is_water(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return false
	return node.is_in_group(WATER_GROUP) or (node.get_parent() != null and node.get_parent().is_in_group(WATER_GROUP))


func _push(search: Search, at: Vector2i, priority: float) -> void:
	search.heap_cost.append(priority)
	search.heap_cell.append(at)
	var i := search.heap_cell.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if search.heap_cost[parent] <= search.heap_cost[i]:
			break
		_swap(search, i, parent)
		i = parent


func _pop(search: Search) -> Vector2i:
	var top := search.heap_cell[0]
	var last := search.heap_cell.size() - 1
	_swap(search, 0, last)
	search.heap_cell.remove_at(last)
	search.heap_cost.remove_at(last)
	var i := 0
	var size := search.heap_cell.size()
	while true:
		var smallest := i
		var left := i * 2 + 1
		var right := left + 1
		if left < size and search.heap_cost[left] < search.heap_cost[smallest]:
			smallest = left
		if right < size and search.heap_cost[right] < search.heap_cost[smallest]:
			smallest = right
		if smallest == i:
			break
		_swap(search, i, smallest)
		i = smallest
	return top


func _swap(search: Search, a: int, b: int) -> void:
	var cost := search.heap_cost[a]
	search.heap_cost[a] = search.heap_cost[b]
	search.heap_cost[b] = cost
	var at := search.heap_cell[a]
	search.heap_cell[a] = search.heap_cell[b]
	search.heap_cell[b] = at
