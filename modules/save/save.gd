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
## [b]Writing needs no asking.[/b] Saved state only changes on a fact or a round,
## so the file is rewritten (once per frame at most) after every
## [signal Events.reported] and [signal Events.trial_ended], and on
## [signal Events.save_requested], pause, focus loss and quit. Turning the headset
## off mid-task loses nothing. Each write goes to a temporary file first, so a
## power cut leaves the last good save rather than half of a new one.
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
	Events.save_requested.connect(request)
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
		write.call_deferred()


func write() -> void:
	_queued = false
	for node in get_tree().get_nodes_in_group(GROUP):
		_capture(node)
	var path := Profile.path(Profile.SAVE_FILE)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(JSON.from_native({version = VERSION, nodes = _data}), "\t"))
	file.close()
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(path + ".tmp", path)


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
	var parsed: Variant = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(path)))
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
