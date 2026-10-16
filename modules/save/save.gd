extends Node
## Save module (autoload "Save"): the player's progress, in their profile folder
## (save.json; see Profile).
##
## Any node with these two methods is saved:
##     func save_state() -> Dictionary
##     func load_state(data: Dictionary) -> void
## It's keyed by its `save_key` property if it has one, else by its node name.
##
## [b]Loading always replaces.[/b] Every saveable gets [code]load_state()[/code]
## when it becomes ready and whenever a profile is opened — with an empty
## dictionary when the file has nothing for it — so a new player or Start over
## can never inherit the last one's stones.
##
## [b]Writing needs no asking.[/b] Ordinary changes are batched per frame after
## Events.reported and Events.trial_ended. Events.save_requested, pause, focus
## loss and quit write synchronously.
## Tasks requests a write at activation and after applying completion + rewards.
## Unfinished tasks restart; inventory, decoration and training remain saved.
## Each write replaces the file via a temporary file, retaining the old save if
## writing or renaming fails.
##
## Files are JSON (types kept via JSON.from_native, never objects). A file from
## another [constant VERSION] is not loaded: that player starts fresh.

const GROUP := &"saveable"
const VERSION := 1

var _data: Dictionary = {}
var _queued := false


func _ready() -> void:
	_read()
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.get_children(): # autoloads that loaded before us
		_on_node_added(node)
	Events.reported.connect(func(_what: StringName, _id: StringName, _data_: Dictionary) -> void: request())
	Events.trial_ended.connect(func(_visual_skill: StringName, _ok: bool, _round: Dictionary) -> void: request())
	Events.save_requested.connect(write)
	Events.profile_closing.connect(write)
	Events.profile_opened.connect(func(_wiped: bool) -> void: reload())


func _notification(what: int) -> void:
	if not is_inside_tree(): # app focus can change before we're ready (e.g. an XR runtime window)
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			write()


## Writes at the end of this frame, once, however many things asked.
func request() -> void:
	if not _queued:
		_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_queued = false
	write()


func write() -> void:
	# Keep a queued end-of-frame write: later listeners to the same gameplay
	# event may still update saved state (e.g. Training after task completion).
	for node in get_tree().get_nodes_in_group(GROUP):
		_capture(node)
	var path := Profile.path(Profile.SAVE_FILE)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("[Save] Cannot open temporary save: %s" % path)
		return
	file.store_string(JSON.stringify(JSON.from_native({version = VERSION, nodes = _data}), "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		push_error("[Save] Could not replace save (%s): %s" % [error_string(error), path])


## Re-reads the file and puts every saveable back to what it says, throwing away
## anything not written yet. A profile being opened does this; so does a test
## proving a round trip, where writing first would only save the thing it was
## trying to check had survived.
func reload() -> void:
	_read()
	for node in get_tree().get_nodes_in_group(GROUP):
		_restore(node)


func _read() -> void:
	_data = {}
	var path := Profile.path(Profile.SAVE_FILE)
	if not FileAccess.file_exists(path):
		return
	var encoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	# Old plain JSON saves are not JSON.from_native envelopes. Reject them
	# before decoding, which otherwise raises an engine error instead of resetting.
	var parsed: Variant = JSON.to_native(encoded) if encoded is Dictionary and encoded.has("type") else null
	if parsed is Dictionary and parsed.get("version") == VERSION and parsed.get("nodes") is Dictionary:
		_data = parsed.nodes
	else:
		push_warning("[Save] Not a save this version can read, starting fresh: %s" % path)


func _on_node_added(node: Node) -> void:
	if not (node.has_method(&"save_state") and node.has_method(&"load_state")):
		return
	node.add_to_group(GROUP)
	node.tree_exiting.connect(_capture.bind(node), CONNECT_ONE_SHOT)
	if node.is_node_ready():
		_restore(node)
	else:
		node.ready.connect(_restore.bind(node), CONNECT_ONE_SHOT)


func _key(node: Node) -> String:
	var key := str(node.get(&"save_key")) if &"save_key" in node else ""
	return key if not key.is_empty() else str(node.name)


func _restore(node: Node) -> void:
	node.load_state(_data.get(_key(node), {}))


func _capture(node: Node) -> void:
	_data[_key(node)] = node.save_state()
