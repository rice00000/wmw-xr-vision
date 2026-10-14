extends Node
## App lifecycle (autoload "Game"): XR startup, level switching and optional-module lookup.

## The player rig used everywhere. Swap this one line to change how the player is built.
const PLAYER_SCENE := "res://player/player.tscn"
## Seconds the view stays faded out while a level loads.
const FADE_TIME := 0.25

## True when an OpenXR session drives the screen; false means desktop fallback.
var is_xr := false
## The active player rig. Registers itself when it enters the tree.
var player: Node3D
## The active level root. Set by Level when it becomes ready.
var level: Node
## Where levels are swapped in (set by main.tscn). Null when a level runs on its own (F6).
var level_root: Node

var _xr: XRInterface
var _changing := false


func _ready() -> void:
	_start_xr()


## Returns the autoload called [param module_name], or null when it's switched off.
## Use it for optional dependencies so modules stay removable:
## [codeblock]
## var inventory := Game.module(&"Inventory")
## if inventory: inventory.add(&"coin")
## [/codeblock]
func module(module_name: StringName) -> Node:
	if not ProjectSettings.has_setting("autoload/%s" % module_name):
		return null
	return get_tree().root.get_node_or_null(NodePath(String(module_name)))


func change_level(path: String) -> void:
	if _changing:
		return
	_changing = true
	Events.level_changing.emit(path)
	await get_tree().create_timer(FADE_TIME).timeout
	if level_root == null:
		get_tree().change_scene_to_file(path) # standalone level: the next one brings its own player
	else:
		if is_instance_valid(level):
			level_root.remove_child(level)
			level.queue_free()
		level_root.add_child(load(path).instantiate())
	_changing = false


## Called by Level once it is ready.
func enter_level(new_level: Node) -> void:
	level = new_level
	Events.level_changed.emit(new_level)


## Puts the player's feet on [param xform], using the rig's own place() when it has one.
func place_player(xform: Transform3D) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method(&"place"):
		player.place(xform)
	else:
		player.global_transform = xform


func _start_xr() -> void:
	_xr = XRServer.find_interface("OpenXR")
	if _xr == null or not _xr.is_initialized():
		print("[Game] No XR runtime, using desktop mode.")
		return
	is_xr = true
	var viewport := get_viewport()
	viewport.use_xr = true
	if RenderingServer.get_rendering_device():
		viewport.vrs_mode = Viewport.VRS_XR # foveated rendering where supported
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED) # the headset paces frames
	_xr.session_begun.connect(_on_session_begun)
	_xr.session_visible.connect(_on_session_visible)
	_xr.session_focussed.connect(_on_session_focussed)
	_xr.session_stopping.connect(Events.save_requested.emit)
	_xr.pose_recentered.connect(XRServer.center_on_hmd.bind(XRServer.RESET_BUT_KEEP_TILT, true))


func _on_session_begun() -> void:
	var hz: float = _xr.get(&"display_refresh_rate")
	if hz > 0.0:
		Engine.physics_ticks_per_second = roundi(hz) # smooth hands at 72/90/120 Hz


## The system menu is over the app: pause and save.
func _on_session_visible() -> void:
	get_tree().paused = true
	Events.save_requested.emit()


func _on_session_focussed() -> void:
	get_tree().paused = false
