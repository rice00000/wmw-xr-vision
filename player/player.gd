class_name Player
extends XROrigin3D
## The player rig: headset camera, two hands and optional movement nodes.
##
## The rest of the game only relies on three things, so this whole scene can be
## replaced (e.g. by a Godot XR Tools rig) as long as the new one keeps them:
##   - it sets Game.player to itself,
##   - its hands call touch() / grab() on things (see hand.gd),
##   - its head calls player_entered() on Zones.
## Child nodes (Locomotion, Teleport, Subtitle, Feedback...) can be deleted freely.
##
## The rig runs with PROCESS_MODE_ALWAYS so head and hands keep tracking while the
## wrist menu pauses the tree; its movement and hands check the pause themselves.

@onready var camera := $Camera as XRCamera3D

var _menu_down := false
var _y_down := false
var _chord_used := false


func _enter_tree() -> void:
	Game.player = self


func _exit_tree() -> void:
	if Game.player == self:
		Game.player = null


func _ready() -> void:
	$Camera/HeadSensor.area_entered.connect(_on_head_entered)
	for controller: XRController3D in [$LeftController, $RightController]:
		controller.button_pressed.connect(_on_button_pressed.bind(controller))
		controller.button_released.connect(_on_button_released.bind(controller))


## Moves the rig so the player's head (not the play-area centre) stands on [param xform].
func place(xform: Transform3D) -> void:
	global_transform = xform
	var head := camera.global_position - global_position
	global_position -= Vector3(head.x, 0.0, head.z)


func _on_head_entered(area: Area3D) -> void:
	if area.has_method(&"player_entered"):
		area.player_entered(self)


## Menu and Y are release actions until their overlap consumes both as Debug.
## A chord fires once, in either order, and stays consumed until both are up.
func _on_button_pressed(action: String, controller: XRController3D) -> void:
	if controller == $LeftController:
		if action == "menu_button":
			_menu_down = true
		elif action == "by_button":
			_y_down = true
		if _menu_down and _y_down and not _chord_used:
			_chord_used = true
			Events.report(&"asked", &"debug")
	elif action == "by_button": # right B still asks immediately
		Events.report(&"asked", &"help")


func _on_button_released(action: String, controller: XRController3D) -> void:
	if controller != $LeftController:
		return
	if action == "menu_button":
		if _menu_down and not _chord_used:
			Events.report(&"asked", &"menu")
		_menu_down = false
	elif action == "by_button":
		if _y_down and not _chord_used:
			Events.report(&"asked", &"help")
		_y_down = false
	if not _menu_down and not _y_down:
		_chord_used = false
