class_name Player
extends XROrigin3D
## The player rig: headset camera, two hands and optional movement nodes.
##
## The rest of the game only relies on three things, so this whole scene can be
## replaced (e.g. by a Godot XR Tools rig) as long as the new one keeps them:
##   - it sets Game.player to itself,
##   - its hands call touch() / grab() on things (see hand.gd),
##   - its head calls player_entered() on Zones.
## Child nodes (Locomotion, Teleport, DesktopControls, Subtitle...) can be deleted freely.

@onready var camera := $Camera as XRCamera3D


func _enter_tree() -> void:
	Game.player = self


func _exit_tree() -> void:
	if Game.player == self:
		Game.player = null


func _ready() -> void:
	$Camera/HeadSensor.area_entered.connect(_on_head_entered)
	for controller: XRController3D in [$LeftController, $RightController]:
		controller.button_pressed.connect(_on_button_pressed)


## Moves the rig so the player's head (not the play-area centre) stands on [param xform].
func place(xform: Transform3D) -> void:
	global_transform = xform
	var head := camera.global_position - global_position
	global_position -= Vector3(head.x, 0.0, head.z)


func _on_head_entered(area: Area3D) -> void:
	if area.has_method(&"player_entered"):
		area.player_entered(self)


func _on_button_pressed(action: String) -> void:
	if action == "by_button": # B / Y: "what should I do?"
		Events.report(&"asked", &"help")
