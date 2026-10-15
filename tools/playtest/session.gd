extends Node
## Standalone test entry point. No production scenes/scripts are patched.
## JSON lines over localhost: observations, tracked hands, physical pokes and inputs.

var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _buffer := ""
var _busy := false
var _trackers: Dictionary = {}
var _player: Node3D
var _viewport: SubViewport
var _camera: Camera3D
var _eye_view := true
var _out := ""
var _log: FileAccess
var _recent: Array = []


func _ready() -> void:
	# The launcher always supplies a separate profile. Refuse accidental use of
	# a real player's; starting over through the menu is part of the test.
	if not String(Profile.id).begins_with("playtest"):
		push_error("Playtest needs --profile=playtest (or playtest_<name>)")
		get_tree().quit(2)
		return
	var port := 18765
	_out = ProjectSettings.globalize_path("res://build/playtest")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	seed(20261015)
	# These synthetic controllers have no physical vibration motor. This setting
	# is isolated by the playtest profile, just like the game's smoke test.
	Settings.set_value(&"haptics", 0.0)
	# Start over puts every setting back to its default, haptics included.
	Events.profile_opened.connect(func(_wiped: bool) -> void: Settings.set_value(&"haptics", 0.0))
	DirAccess.make_dir_recursive_absolute(_out)
	_log = FileAccess.open(_out.path_join("events.jsonl"), FileAccess.WRITE)
	Events.reported.connect(func(what: StringName, id: StringName, data: Dictionary) -> void:
		_event("fact", {what = what, id = id, data = _json(data)}))
	Narrator.line_started.connect(func(line: VoiceLine) -> void:
		_event("instruction", {text = line.text}))
	Events.trial_ended.connect(func(visual_skill: StringName, success: bool, data: Dictionary) -> void:
		_event("trial", {visual_skill = visual_skill, success = success, data = _json(data)}))
	add_child(load("res://main.tscn").instantiate())
	while not is_instance_valid(Game.level):
		await get_tree().process_frame
	_attach()
	if DisplayServer.get_name() != "headless":
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(1280, 800)
		_viewport.world_3d = get_viewport().world_3d
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_viewport)
		_camera = Camera3D.new()
		_camera.near = 0.05
		_camera.fov = 70
		_viewport.add_child(_camera)
	var error := _server.listen(port, "127.0.0.1")
	if error != OK:
		push_error("Playtest port %d: %s" % [port, error_string(error)])
		get_tree().quit(2)
		return
	print("PLAYTEST READY 127.0.0.1:%d output=%s" % [port, _out])


func _attach() -> void:
	_player = Game.player
	_trackers.clear()
	for side in ["left", "right"]:
		var tracker := XRControllerTracker.new()
		tracker.name = StringName("/playtest/" + side)
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		XRServer.add_tracker(tracker)
		_trackers[side] = tracker
		_controller(side).tracker = tracker.name
		tracker.set_pose(&"default", Transform3D(Basis.IDENTITY,
			Vector3(-0.22 if side == "left" else 0.22, 1.0, -0.3)), Vector3.ZERO, Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input(&"primary", Vector2.ZERO)
		tracker.set_pose(&"aim", tracker.get_pose(&"default").transform, Vector3.ZERO, Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input(&"grip_click", false)
		tracker.set_input(&"trigger_click", false)


func _process(_delta: float) -> void:
	if is_instance_valid(Game.player) and _player != Game.player:
		_attach()
	if _camera and _eye_view:
		_camera.global_transform = Game.player.get_node("Camera").global_transform
	if not _server.is_listening():
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_buffer = ""
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_peer = null
		return
	if _busy:
		return
	var available := _peer.get_available_bytes()
	if available:
		_buffer += _peer.get_utf8_string(available)
	if "\n" in _buffer:
		var line := _buffer.get_slice("\n", 0)
		_buffer = _buffer.substr(line.length() + 1)
		_busy = true
		_dispatch(JSON.parse_string(line))


func _dispatch(request: Variant) -> void:
	var response: Dictionary
	if not request is Dictionary:
		response = {ok = false, error = "Expected a JSON object"}
	else:
		_event("command", request)
		response = await _execute(request)
	_event("result", response)
	_peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())
	_busy = false


func _execute(cmd: Dictionary) -> Dictionary:
	match cmd.get("op", "state"):
		"state":
			return {ok = true, state = _snapshot()}
		"wait":
			await _wait(float(cmd.get("seconds", 0.2)))
		"move":
			var side: String = cmd.get("hand", "right")
			if not _trackers.has(side):
				return {ok = false, error = "hand must be left or right"}
			var node := _resolve(str(cmd.get("to", "")))
			if not cmd.has("position") and node == null:
				return {ok = false, error = "No target: " + str(cmd.get("to"))}
			var spot := _vector(cmd.position) if cmd.has("position") else node.global_position
			spot += _vector(cmd.get("offset", [0, 0, 0]))
			var basis := Basis.from_euler(_vector(cmd.rotation) * PI / 180.0) if cmd.has("rotation") else _controller(side).global_basis
			await _move(side, Transform3D(basis, spot), float(cmd.get("seconds", 0.6)))
		"aim", "click":
			var target := _ui_target(str(cmd.get("to", "")))
			if target == Vector3.INF:
				return {ok = false, error = "No menu target: " + str(cmd.get("to"))}
			var side: String = cmd.get("hand", "right")
			if not _trackers.has(side):
				return {ok = false, error = "hand must be left or right"}
			var camera := Game.player.get_node(^"Camera") as Node3D
			var origin := camera.global_position + camera.global_basis * Vector3(
				-0.25 if side == "left" else 0.25, -0.35, -0.2)
			_trackers[side].set_input(&"trigger_click", false)
			await _move(side, Transform3D(Basis.looking_at(target - origin), origin), 0.3)
			if cmd.op == "click":
				_trackers[side].set_input(&"trigger_click", true)
				await _wait(0.12)
				_trackers[side].set_input(&"trigger_click", false)
				await _wait(0.12)
		"poke":
			var node := _resolve(str(cmd.get("to", "")))
			if node == null:
				return {ok = false, error = "No poke target: " + str(cmd.get("to"))}
			var side: String = cmd.get("hand", "right")
			if not _trackers.has(side):
				return {ok = false, error = "hand must be left or right"}
			if node is RayButton:
				return {ok = false, error = "Menu buttons use aim/click"}
			var basis := Basis.IDENTITY
			var face := node.global_position
			await _move(side, Transform3D(basis, face + basis.z * 0.16), 0.35)
			await _wait(0.12)
			await _move(side, Transform3D(basis, face + basis.z * 0.06), 0.25)
			await _wait(0.1)
			await _move(side, Transform3D(basis, face + basis.z * 0.23), 0.3)
		"button":
			var side: String = cmd.get("hand", "right")
			if not _trackers.has(side) or cmd.get("action", "") not in ["grip_click", "trigger_click", "by_button", "menu_button", "ax_button"]:
				return {ok = false, error = "Unknown hand or button"}
			_trackers[side].set_input(StringName(cmd.action), bool(cmd.get("pressed", true)))
			await _wait(0.12)
		"stick":
			var side: String = cmd.get("hand", "left")
			if not _trackers.has(side):
				return {ok = false, error = "hand must be left or right"}
			var axis: Array = cmd.get("axis", [0, 0])
			_trackers[side].set_input(&"primary", Vector2(axis[0], axis[1]).limit_length())
			await _wait(float(cmd.get("seconds", 0.5)))
			_trackers[side].set_input(&"primary", Vector2.ZERO)
		"teleport":
			var place := Place.find(get_tree(), StringName(cmd.get("to", "")))
			if not cmd.has("position") and place == null:
				return {ok = false, error = "Unknown place"}
			var spot := _vector(cmd.position) if cmd.has("position") else place.global_position
			spot += _vector(cmd.get("offset", [0, 0, 0]))
			# Explicit relocation uses the real teleport guard (including pause).
			# It does not claim to exercise ray aiming, pathfinding or walking.
			if not Game.player.get_node("Teleport").teleport_to(spot):
				return {ok = false, error = "Teleport refused (menu paused?)"}
			await _wait(0.2)
		"look":
			var head := Game.player.get_node("Camera") as Node3D
			var desired := Basis.from_euler(_vector(cmd.get("rotation", [0, 0, 0])) * PI / 180.0)
			var eye := head.global_position
			Game.player.global_basis = desired * head.transform.basis.inverse()
			Game.player.global_position += eye - head.global_position
		"view":
			if _camera == null:
				return {ok = false, error = "Rendering required"}
			_eye_view = cmd.get("mode", "eyes") == "eyes"
			if not _eye_view:
				_camera.look_at_from_position(_vector(cmd.position), _vector(cmd.at), Vector3.UP)
		"capture":
			if _viewport == null:
				return {ok = false, error = "Cannot capture with --headless"}
			await RenderingServer.frame_post_draw
			var filename := str(cmd.get("name", "capture")).get_file().get_basename() + ".png"
			var path := _out.path_join(filename)
			var error := _viewport.get_texture().get_image().save_png(path)
			return {ok = error == OK, path = path, state = _snapshot()}
		"quit":
			get_tree().create_timer(0.2).timeout.connect(get_tree().quit)
		_:
			return {ok = false, error = "Unknown op"}
	return {ok = true, state = _snapshot()}


func _controller(side: String) -> XRController3D:
	return Game.player.get_node("%sController" % side.capitalize())


func _move(side: String, end: Transform3D, seconds: float) -> void:
	seconds = clampf(seconds, 0.02, 30.0)
	var start := _controller(side).global_transform
	var begin := Time.get_ticks_msec()
	var elapsed := 0.0
	while elapsed < seconds:
		var at := start.interpolate_with(end, minf(elapsed / seconds, 1.0))
		_pose(side, at)
		await get_tree().process_frame
		elapsed = (Time.get_ticks_msec() - begin) / 1000.0
	_pose(side, end)
	await _wait(0.06) # allow collision overlaps to reach the existing Hand


func _pose(side: String, world: Transform3D) -> void:
	for pose in [&"default", &"aim"]:
		_trackers[side].set_pose(pose, Game.player.global_transform.affine_inverse() * world,
			Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(clampf(seconds, 0.02, 30.0), true).timeout


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _resolve(key: String) -> Node3D:
	if key == "star":
		return Game.player.find_child("Star", true, false) as Node3D
	if key.begins_with("/"):
		return get_node_or_null(NodePath(key)) as Node3D
	for node in get_tree().get_nodes_in_group(Trial.GROUP):
		if key == "target" and node is SearchTrial and node.is_running():
			return node.target()
		if key == "butterfly" and node is CatchTrial and node.is_running():
			return node.current()
	for node in _level_nodes() + Game.player.find_children("*", "Node3D", true, false):
		if node is Grabbable and str(node.id) == key:
			return node
		if node is RayButton and str(node.id) == key and node.is_visible_in_tree():
			return node
		if key == "put_away" and node is PutAwayButton and node.visible:
			return node
	return null


## The level's nodes; none while one level is being swapped for the next.
func _level_nodes() -> Array[Node]:
	return Game.level.find_children("*", "Node3D", true, false) if is_instance_valid(Game.level) else []


func _ui_target(key: String) -> Vector3:
	var button := _resolve(key) as RayButton
	if button:
		return button.global_position
	for panel: ViewportUI in get_tree().get_nodes_in_group(&"viewport_ui"):
		if panel.visible:
			for control: Button in panel.buttons():
				if str(control.name) == key or str(control.get_path()) == key:
					return panel.button_position(control)
	return Vector3.INF


func _snapshot() -> Dictionary:
	var objects: Array = []
	for node in _level_nodes():
		if node is Grabbable or node is Catchable or node is PutAwayButton:
			objects.append(_describe(node))
	var buttons: Array = []
	for node in Game.player.find_children("*", "Node3D", true, false):
		if node is RayButton and node.is_visible_in_tree():
			var entry := _describe(node)
			entry["speech"] = node.speech
			entry["hovered"] = node.hovered
			buttons.append(entry)
	for panel: ViewportUI in get_tree().get_nodes_in_group(&"viewport_ui"):
		if panel.visible:
			for button: Button in panel.buttons():
				buttons.append({id = str(button.name), path = str(button.get_path()),
					position = _json(panel.button_position(button)), visible = true, speech = button.text})
	var hands := {}
	for side in ["left", "right"]:
		var hand := _controller(side).get_node("Hand") as Hand
		hands[side] = {position = _json(hand.global_position), fingertip = _json(hand.poke_point()),
			held = str(hand.held.id) if is_instance_valid(hand.held) else ""}
	var places := {}
	for place in get_tree().get_nodes_in_group(Place.GROUP):
		places[str(place.id)] = _json(place.global_position)
	var trials: Array = []
	for node in get_tree().get_nodes_in_group(Trial.GROUP):
		var entry := {running = node.is_running(), path = str(node.get_path())}
		if node is SearchTrial and node.is_running():
			entry["target"] = _describe(node.target())
		if node is CatchTrial and node.is_running() and node.current():
			entry["target"] = _describe(node.current())
		trials.append(entry)
	return {pid = OS.get_process_id(), task = Tasks.current(), goal = Events.goal.text, waiting_for = Events.goal.waiting_for,
		menu_open = Menu.is_open, debug_open = Debug.is_open, menu_page = Menu.page, paused = get_tree().paused,
		inventory = Inventory.all(), hands = hands, places = places, objects = objects,
		buttons = buttons, trials = trials, recent = _recent.duplicate(),
		eye = _json(Game.player.get_node("Camera").global_position), profile = Profile.id}


func _describe(node: Node3D) -> Dictionary:
	return {id = str(node.get("id")) if "id" in node else str(node.name),
		path = str(node.get_path()), position = _json(node.global_position), visible = node.is_visible_in_tree()}


func _json(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _json(value[key])
		return result
	if value is Array:
		return value.map(_json)
	return value


func _event(kind: String, data: Dictionary) -> void:
	var entry := {ms = Time.get_ticks_msec(), kind = kind, data = data}
	if kind in ["fact", "instruction", "trial"]:
		_recent.append(entry)
		if _recent.size() > 15:
			_recent.pop_front()
	if _log:
		_log.store_line(JSON.stringify(entry))
		_log.flush()
