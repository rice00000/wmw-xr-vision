extends Node
## Save module (autoload "Save"). Zero-config persistence.
##
## Any node with these two methods is saved automatically:
##     func save_state() -> Dictionary
##     func load_state(data: Dictionary) -> void
## It's keyed by its `save_key` property if it has one, else by its node name.
## State is restored when the node becomes ready, captured when it leaves the tree
## (e.g. a room unloading) and written to disk on Events.save_requested, pause and quit.
##
## Files are JSON (types kept via JSON.from_native, never objects), one per slot:
## user://saves/<slot>.json. Pick a slot with use_slot() or `-- --slot=<name>`.

const DIR := "user://saves/"
const GROUP := &"saveable"

var slot := "default"
var _data: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=")
	_read()
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.get_children(): # autoloads that loaded before us
		_on_node_added(node)
	Events.save_requested.connect(write)


func _notification(what: int) -> void:
	if not is_inside_tree(): # app focus can change before we're ready (e.g. an XR runtime window)
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			write()


func write() -> void:
	for node in get_tree().get_nodes_in_group(GROUP):
		_capture(node)
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(JSON.from_native(_data), "\t"))


## Switch to another save slot (e.g. one per child), writing the current one out
## first so nothing is lost.
func use_slot(new_slot: String) -> void:
	write()
	slot = new_slot
	reload()


## Re-read this slot from disk and put every saveable back to what it says,
## throwing away anything not written yet. That is "discard my changes", and it
## is the only honest way to prove a save round trip: writing first would just
## save the thing you were trying to check had survived.
func reload() -> void:
	_read()
	for node in get_tree().get_nodes_in_group(GROUP):
		node.load_state(_data.get(_key(node), {}))


## New game: forget this slot and reset every saveable.
func wipe() -> void:
	_data.clear()
	DirAccess.remove_absolute(_path())
	for node in get_tree().get_nodes_in_group(GROUP):
		node.load_state({})


func _path() -> String:
	return "%s%s.json" % [DIR, slot]


func _read() -> void:
	_data = {}
	if not FileAccess.file_exists(_path()):
		return
	var parsed: Variant = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(_path())))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_warning("[Save] Unreadable save file: %s" % _path())


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
	if _data.has(_key(node)):
		node.load_state(_data[_key(node)])


func _capture(node: Node) -> void:
	_data[_key(node)] = node.save_state()
