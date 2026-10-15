class_name GuideCharacter
extends Node3D
## The guide character: walks ahead to wherever the current task
## happens, and otherwise keeps the child company.
##
## It knows nothing about tasks beyond [signal Events.goal_changed]: when the
## goal names a [Place], it finds a way there on foot ([GroundGrid], so never
## through a house or across water), stops about [member stand_off] metres from it
## and turns to the child, gesturing until they arrive. A child who falls more
## than [member fall_behind] metres behind is waited for and beckoned. With no
## place it stays a few metres away, never closer than [member too_close], and
## steps aside when the child walks towards it. It "talks" (bobs, staff glowing)
## while the Narrator is saying a line.
##
## When the current step waits for "grabbed:<ball_id>" it holds out a glowing
## ball for the child to take — the welcome's first lesson.
##
## A scene node: put [code]modules/guide/guide_character.tscn[/code] in the level. The look
## is [code]content/characters/wizard.tscn[/code]; this script moves the optional
## pivots Body, ArmLeft, ArmRight and StaffTip in it if they are there.

enum Mode {
	NEAR, ## nothing to show: stay close to the child
	LEAD, ## walking to the goal's place
	WAIT, ## stopped on the way, the child fell behind
	THERE, ## standing by the place, waiting for the child
}

@export var walk_speed := 1.3
## How far from the goal's [Place] it stops.
@export var stand_off := 1.5
## Stop and wait when the child is this far behind.
@export var fall_behind := 10.0
## Walk on once the child is this close again.
@export var catch_up := 5.0
## Where it stands with nothing to show, from the child.
@export var near_distance := 2.4
## Never closer than this: it steps away.
@export var too_close := 1.0
## Never further than this with nothing to show: it comes back.
@export var too_far := 3.0
@export var ball_scene: PackedScene
@export var ball_id: StringName = &"magic_ball"
## How far from the place it stands while holding the ball out, so it is in reach.
@export var ball_stand_off := 1.1
## Ground cells it may look at per physics frame while working out a way. A
## search that needs more carries on next frame, so no frame pays for a long one.
@export var samples_per_frame := 48
## After finding no way to stand near the child, wait this long before trying again.
@export var retry_after := 4.0

var mode := Mode.NEAR

@onready var _visual := $Visual as Node3D
@onready var _hold := $BallHold as Marker3D

var _grid: GroundGrid
## The way being worked out, a few cells a frame.
var _search: GroundGrid.Search
## Whether [member _search] is for the goal (else for a spot near the child).
var _search_leads := false
## Spots by the goal still to try if the current search finds no way.
var _spots: Array[Vector3] = []
## Where to appear by magic if none of [member _spots] can be walked to.
var _fallback := Vector3.ZERO
var _place_id: StringName = &""
var _path := PackedVector3Array()
var _ball: Grabbable
var _offering := false
var _replan_at := 0
var _poofing := false
## A new goal is waiting to be planned. Planning happens on a physics frame, once
## the level's colliders are in the physics world.
var _dirty := false
var _frames := 0
var _time := 0.0
var _child_last := Vector3.INF
var _child_velocity := Vector3.ZERO
var _angles: Dictionary[StringName, float] = {}
var _rests: Dictionary[StringName, Basis] = {}


func _ready() -> void:
	Events.goal_changed.connect(_on_goal_changed)
	for pivot_name: StringName in [&"ArmLeft", &"ArmRight"]:
		var pivot := _pivot(pivot_name)
		if pivot:
			_rests[pivot_name] = pivot.basis
	(func() -> void: _on_goal_changed(Events.goal)).call_deferred() # the goal as it is then, not now


## The [Place] id it is leading to, or &"" when it is keeping the child company.
func leading_to() -> StringName:
	return _place_id


## The rest of the way, as points on the ground.
func path() -> PackedVector3Array:
	return _path


## Whether it is holding the ball out right now.
func is_offering() -> bool:
	return _offering and is_instance_valid(_ball) and _ball.holder == null


func ball() -> Grabbable:
	return _ball if is_instance_valid(_ball) else null


## The Narrator is saying a line: it is this character's voice.
func is_talking() -> bool:
	return Narrator.current != null and not Narrator.is_paused()


func _on_goal_changed(goal: Goal) -> void:
	var found := Place.find(get_tree(), goal.place) if not goal.place.is_empty() else null
	var id: StringName = goal.place if found else &""
	var offer := ball_scene != null and goal.waiting_for == "grabbed:%s" % ball_id
	if id != _place_id or offer != _offering:
		_place_id = id
		_offering = offer
		_dirty = true
	_update_ball()


# -- where to go --------------------------------------------------------------

func _plan() -> void:
	_path = PackedVector3Array()
	_search = null
	_replan_at = 0
	var place := Place.find(get_tree(), _place_id) if not _place_id.is_empty() else null
	if place == null: # no goal, or its place went away while this waited to plan
		_place_id = &""
		mode = Mode.NEAR
		return
	mode = Mode.LEAD
	_spots = _spots_by(place)
	_fallback = _spots[0] if not _spots.is_empty() else place.global_position
	_next_spot()


## Starts looking for a way to the next spot by the goal, or, with none left
## (boxed in, or the place is somewhere no one can walk to), does magic.
func _next_spot() -> void:
	if _spots.is_empty():
		_poof_to(_fallback)
		return
	_search = _ground().begin(global_position, _spots.pop_front())
	_search_leads = true


## Carries the search in progress on by one frame's worth of cells.
func _pump_search() -> void:
	if _search == null or not _ground().advance(_search, samples_per_frame):
		return
	var found := _search.path
	_search = null
	if _search_leads:
		if found.is_empty():
			_next_spot()
		else:
			_path = found
	elif found.is_empty():
		_replan_at = Time.get_ticks_msec() + roundi(retry_after * 1000.0)
	else:
		_path = found


## Where to stand by [param place], best first: beside it, so the child's view
## of the station stays clear — or in front, holding the ball out.
func _spots_by(place: Place) -> Array[Vector3]:
	var distance := ball_stand_off if _offering else stand_off
	var right := _flat(place.global_basis.x).normalized()
	var back := _flat(place.global_basis.z).normalized()
	var at := place.global_position
	var sides: Array[Vector3] = [at + right * distance, at - right * distance]
	sides.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(global_position) < b.distance_squared_to(global_position))
	var order: Array[Vector3] = []
	if _offering:
		order.append(at - back * distance)
	order.append_array(sides)
	order.append(at + back * distance)
	if not _offering:
		order.append(at - back * distance)
	var spots: Array[Vector3] = []
	for spot in order:
		if _ground().can_stand(spot):
			spots.append(spot)
	return spots


func _ground() -> GroundGrid:
	if _grid == null:
		_grid = GroundGrid.new(get_world_3d())
	return _grid


# -- every frame ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	_frames += 1
	if _dirty and _frames > 2:
		_dirty = false
		_plan()
	if not _dirty and _frames > 2:
		_pump_search()
	var child: Variant = _child_position()
	_track(child, delta)
	var walking := false
	if not _poofing and not _dirty and _frames > 2:
		match mode:
			Mode.LEAD:
				if child != null and _fell_behind(child):
					mode = Mode.WAIT
				else:
					walking = _walk(delta)
					if not walking and _search == null:
						mode = Mode.THERE
			Mode.WAIT:
				if child == null or _flat(child - global_position).length() < catch_up:
					mode = Mode.LEAD
				else:
					_face(child - global_position, delta)
			Mode.THERE:
				if child != null:
					_face(child - global_position, delta)
			Mode.NEAR:
				walking = _stay_near(child, delta)
	_animate(walking, delta)
	_carry_ball()


func _stay_near(child: Variant, delta: float) -> bool:
	if child == null:
		return _walk(delta)
	var now := Time.get_ticks_msec()
	if _search == null and now >= _replan_at and _uncomfortable(child):
		_replan_at = now + 900
		var spot: Variant = _spot_near_child(child)
		if spot == null:
			_replan_at = now + roundi(retry_after * 1000.0)
		else:
			_search = _ground().begin(global_position, spot)
			_search_leads = false
	if _walk(delta):
		return true
	_face(child - global_position, delta)
	return false


## Too close, too far, or standing where the child is walking.
func _uncomfortable(child: Vector3) -> bool:
	var offset := _flat(global_position - child)
	var distance := offset.length()
	if distance < too_close or distance > (ball_stand_off + 0.5 if _offering else too_far):
		return true
	if _child_velocity.length() > 0.5 and distance < 2.0:
		return _child_velocity.normalized().dot(offset.normalized()) > 0.6
	return false


## A spot [member near_distance] off to one side of where the child is heading
## or looking, on whichever side is nearer.
func _spot_near_child(child: Vector3) -> Variant:
	var forward := _child_velocity if _child_velocity.length() > 0.3 else _child_facing()
	forward = _flat(forward).normalized()
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	var spots: Array[Vector3] = []
	var distance := ball_stand_off if _offering else near_distance
	var angles := [20.0, -20.0, 150.0, -150.0] if _offering else [55.0, -55.0, 150.0, -150.0]
	for degrees: float in angles:
		spots.append(child + forward.rotated(Vector3.UP, deg_to_rad(degrees)) * distance)
	var sides := spots.slice(0, 2)
	sides.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(global_position) < b.distance_squared_to(global_position))
	for spot: Vector3 in sides + spots.slice(2):
		spot.y = global_position.y
		if _ground().can_stand(spot):
			return spot
	return null


## The child is far behind: further from where we are going than the guide is.
func _fell_behind(child: Vector3) -> bool:
	if _path.is_empty() or _flat(child - global_position).length() <= fall_behind:
		return false
	var end := _path[_path.size() - 1]
	return _flat(child - end).length() > _flat(global_position - end).length()


func _walk(delta: float) -> bool:
	if _path.is_empty():
		return false
	var target := _path[0]
	var to := target - global_position
	var flat := _flat(to)
	var stride := walk_speed * delta
	if flat.length() <= stride:
		global_position = target
		_path.remove_at(0)
	else:
		var share := stride / flat.length()
		global_position += Vector3(flat.x * share, to.y * share, flat.z * share)
		_face(flat, delta)
	return true


func _face(direction: Vector3, delta: float) -> void:
	var flat := _flat(direction)
	if flat.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(1.0, delta * 8.0))


func _poof_to(spot: Vector3) -> void:
	_poofing = true
	var tween := create_tween()
	tween.tween_property(self, ^"scale", Vector3.ONE * 0.05, 0.3)
	tween.tween_callback(func() -> void: global_position = spot)
	tween.tween_property(self, ^"scale", Vector3.ONE, 0.3)
	tween.tween_callback(func() -> void: _poofing = false)


func _child_position() -> Variant:
	var player := Game.player
	if not is_instance_valid(player):
		return null
	var head := player.get_node_or_null(^"Camera") as Node3D
	var at := (head if head else player).global_position
	return Vector3(at.x, global_position.y, at.z)


func _child_facing() -> Vector3:
	var head := Game.player.get_node_or_null(^"Camera") as Node3D if is_instance_valid(Game.player) else null
	return -head.global_basis.z if head else Vector3.FORWARD


func _track(child: Variant, delta: float) -> void:
	if child == null or delta <= 0.0:
		return
	if _child_last != Vector3.INF:
		var velocity: Vector3 = (child - _child_last) / delta
		_child_velocity = _child_velocity.lerp(velocity, minf(1.0, delta * 4.0))
	_child_last = child


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# -- the ball -------------------------------------------------------------------

func _update_ball() -> void:
	if _offering and not is_instance_valid(_ball):
		_ball = ball_scene.instantiate() as Grabbable
		if _ball == null:
			return
		get_parent().add_child(_ball)
		_ball.global_transform = _hold.global_transform
		_ball.released.connect(_on_ball_released.bind(_ball))
	elif not _offering and is_instance_valid(_ball) and _ball.holder == null:
		_vanish(_ball)


func _carry_ball() -> void:
	if _offering and is_instance_valid(_ball) and _ball.holder == null and _ball.freeze:
		_ball.global_transform = _hold.global_transform


func _on_ball_released(_hand: Node3D, ball: Grabbable) -> void:
	if not _offering:
		# On the ball, so the wait dies with it if it is freed first.
		var wait := ball.create_tween()
		wait.tween_interval(1.5)
		wait.tween_callback(_vanish.bind(ball))


func _vanish(ball: Grabbable) -> void:
	if ball.holder != null:
		return
	if ball == _ball:
		_ball = null
	var tween := ball.create_tween()
	tween.tween_property(ball, ^"scale", Vector3.ONE * 0.01, 0.4)
	tween.tween_callback(ball.queue_free)


# -- looking alive --------------------------------------------------------------

func _animate(walking: bool, delta: float) -> void:
	var talking := is_talking()
	var bob := 0.0
	if walking:
		bob = absf(sin(_time * 7.0)) * 0.035
	elif talking:
		bob = absf(sin(_time * 9.0)) * 0.02
	_visual.position.y = lerpf(_visual.position.y, bob, minf(1.0, delta * 12.0))

	var left := 0.0
	var right := 0.0
	if mode == Mode.WAIT:
		left = 2.2 + 0.45 * sin(_time * 7.0) # beckoning, high and waving
	elif is_offering():
		left = 1.2 # holding the ball out
	elif walking:
		left = sin(_time * 7.0) * 0.35
	if mode == Mode.THERE and fmod(_time, 4.0) < 1.4:
		right = 1.3 + 0.2 * sin(_time * 9.0) # "over here!"
	elif walking:
		right = -sin(_time * 7.0) * 0.25
	_swing(&"ArmLeft", left, delta)
	_swing(&"ArmRight", right, delta)

	var tip := _pivot(&"StaffTip")
	if tip:
		tip.scale = Vector3.ONE * (1.0 + (0.5 * absf(sin(_time * 8.0)) if talking else 0.0))


## Rotates a pivot forward-and-up by [param angle] radians from its rest pose.
func _swing(pivot_name: StringName, angle: float, delta: float) -> void:
	var pivot := _pivot(pivot_name)
	if pivot == null or not _rests.has(pivot_name):
		return
	var current := lerpf(_angles.get(pivot_name, 0.0), angle, minf(1.0, delta * 10.0))
	_angles[pivot_name] = current
	pivot.basis = _rests[pivot_name] * Basis(Vector3.RIGHT, current)


func _pivot(pivot_name: StringName) -> Node3D:
	return _visual.find_child(String(pivot_name), true, false) as Node3D if _visual else null
