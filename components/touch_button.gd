class_name TouchButton
extends Touchable
## A big button you press by touching it. Reports "pressed:<id>".

@export var id: StringName = &"button"
@export var text := ""


func _ready() -> void:
	if not text.is_empty():
		($Label as Label3D).text = text


## The position travels with the fact, not with a sound: the Audio module uses it
## to put the click at the button, and the research log gets where the child reached.
func _on_touch(_hand: Node3D) -> void:
	Events.report(&"pressed", id, {position = global_position})
	var mesh := $Mesh as Node3D
	var tween := create_tween()
	tween.tween_property(mesh, ^"position:z", -0.03, 0.08)
	tween.tween_property(mesh, ^"position:z", 0.0, 0.12)
