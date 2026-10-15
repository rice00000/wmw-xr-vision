class_name Touchable
extends Area3D
## Something a hand can touch. Hands call touch(); extend this and override
## _on_touch(), or just connect the [signal touched] signal in the editor.
## Base for buttons, creatures and spirit orbs.

signal touched(hand: Node3D)

## Seconds before it reacts to a touch again.
@export var cooldown := 0.5

var _ready_at_ms := 0


## Returns true when the touch was accepted (hands vibrate on true).
func touch(hand: Node3D) -> bool:
	if Time.get_ticks_msec() < _ready_at_ms or not can_touch(hand):
		return false
	_ready_at_ms = Time.get_ticks_msec() + int(cooldown * 1000.0)
	_on_touch(hand)
	touched.emit(hand)
	return true


## Whether [param hand] may use this at all (hands only light up what they can use).
func can_touch(_hand: Node3D) -> bool:
	return true


func _on_touch(_hand: Node3D) -> void:
	pass
