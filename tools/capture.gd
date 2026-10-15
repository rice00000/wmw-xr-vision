extends SceneTree
## Photographs a level without a headset: one PNG from child eye height (1.2 m)
## at the Spawn and at every Place, looking the way each one faces, plus a
## high overview. For checking how a level looks from the command line.
##
##   godot --xr-mode off --path . -s res://tools/capture.gd -- <level> <out dir>
##
## <level> is a folder name under levels/ or a res:// path. Needs a real
## renderer, so not --headless; a window opens for a few seconds.

const EYE := 1.2


func _initialize() -> void:
	# Game looks for an XR runtime on _ready and pops a blocking alert when there
	# is none. Autoloads are in the tree but not ready yet, so swap that out.
	var game := root.get_node_or_null(^"Game")
	if game:
		var quiet := GDScript.new()
		quiet.source_code = "extends \"res://core/game.gd\"\nfunc _ready() -> void:\n\tpass\n"
		quiet.reload()
		game.set_script(quiet)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -s res://tools/capture.gd -- <level> <out dir>")
		quit(1)
		return
	var path := args[0] if args[0].begins_with("res://") else "res://levels/%s/%s.tscn" % [args[0], args[0]]
	var out := args[1]
	DirAccess.make_dir_recursive_absolute(out)
	var level := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await process_frame
	var game := root.get_node(^"Game")
	if is_instance_valid(game.player):
		game.player.queue_free()

	var shots: Array = []
	var spawn := level.get_node_or_null(^"Spawn") as Node3D
	if spawn:
		shots.append(["spawn", spawn.global_transform])
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for node in get_nodes_in_group(Place.GROUP):
		var place := node as Place
		if not level.is_ancestor_of(place):
			continue
		shots.append([String(place.id), place.global_transform])
		lo = lo.min(place.global_position)
		hi = hi.max(place.global_position)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	for shot in shots:
		var at: Transform3D = shot[1]
		var forward := -at.basis.z
		forward.y = 0.0
		var eye := at.origin + Vector3.UP * EYE
		cam.look_at_from_position(eye, eye + forward.normalized(), Vector3.UP)
		await _save(out, shot[0])
	if lo != Vector3.INF:
		var centre := (lo + hi) / 2.0
		var size := maxf(hi.x - lo.x, hi.z - lo.z)
		cam.look_at_from_position(centre + Vector3(0, size * 0.75, size), centre, Vector3.UP)
		await _save(out, "overview")
	quit()


func _save(out: String, shot_name: String) -> void:
	for i in 10: # let shadows and visibility ranges settle
		await process_frame
	root.get_texture().get_image().save_png(out.path_join(shot_name + ".png"))
	print("%-12s %3d draw calls (+%d shadow)" % [shot_name,
		root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
