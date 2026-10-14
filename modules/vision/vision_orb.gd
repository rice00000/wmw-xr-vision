class_name VisionOrb
extends Touchable
## Whitebox stand-in for a spirit: touch it to switch its visual ability on / off.
## Reports "used:<id>". Does nothing visible when the Vision module is off.

@export var profile: VisionProfile
@export var id: StringName = &"spirit"


func _ready() -> void:
	var label := get_node_or_null(^"Label") as Label3D
	if label and profile:
		label.text = profile.display_name


func _on_touch(_hand: Node3D) -> void:
	var vision := Game.module(&"Vision")
	if vision:
		vision.toggle(profile)
	Events.report(&"used", id)
