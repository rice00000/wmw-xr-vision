class_name PokeButton
extends Node3D
## One wrist-menu button: a big slab with a shape and a short word, pressed by
## pushing a fingertip into its face.
##
## It does not look for hands itself. The menu runs while the world is paused,
## and a paused world does not step physics, so there are no Area3D overlaps to
## listen to. Instead the menu measures every hand against every button each
## frame and tells the button how deep the nearest fingertip is ([method sense]);
## the button turns that into hover, read-aloud and exactly one press per poke.
##
## The face is at +Z, toward the child. Depth is measured along -Z from it:
## positive is in front, zero is touching, negative is pushed in.

enum Style {
	ACTION, ## the thing to do on this page
	TAB, ## a page along the side
	CHOSEN, ## the page you are on, or the setting that is set
	CAUTION, ## giving up, starting over
	NAV, ## more / back through a long list
}

## Fingertip this close in front of the face lights the button and, after
## [constant DWELL], reads its label aloud.
const HOVER_DEPTH := 0.06
## This close (or pushed in) presses.
const PRESS_DEPTH := 0.012
## A pressed button presses again only once the fingertip has come back out
## past this, and [constant REARM] has passed: one poke, one press.
const RELEASE_DEPTH := 0.03
const REARM := 0.35
const DWELL := 0.45
## Sideways slack around the face, so a finger at the very edge still counts.
const MARGIN := 0.01
## Behind the face further than this is reaching through, not pressing.
const BEHIND := 0.06
const THICKNESS := 0.018

const FACES := {
	Style.ACTION: Color(1.0, 0.82, 0.22),
	Style.TAB: Color(0.62, 0.78, 1.0),
	Style.CHOSEN: Color(1.0, 1.0, 1.0),
	Style.CAUTION: Color(1.0, 0.6, 0.5),
	Style.NAV: Color(0.78, 0.82, 0.9),
}

## Reported as "pressed:<id>", which is also how the sound table finds its click.
var id: StringName
## Read aloud after a short hover. Longer than the label when that helps:
## "Buy the Chair for 2 Magic Stones", not "Buy".
var speech := ""
var size := Vector2(0.11, 0.07)
## Called with no arguments on a press. Empty = the press is only reported.
var action := Callable()

var hovered := false

var _armed := false # a new button waits for a fingertip to be clearly in front first
var _rearm_at := 0
var _hover_time := 0.0
var _spoken := false
## Depth last frame, INF when no fingertip was over the face. A press is a
## crossing of the face from in front, so a hand pulled back out through the
## panel, or slid sideways onto it, never presses.
var _last_depth := INF
var _pressed_at := -100000
var _body: Node3D


static func create(button_id: StringName, label: String, icon: StringName, button_size: Vector2,
		style := Style.ACTION, say := "") -> PokeButton:
	var button := PokeButton.new()
	button.name = String(button_id)
	button.id = button_id
	button.size = button_size
	button.speech = say if not say.is_empty() else label.replace("\n", " ")
	button._build(label, icon, style)
	return button


## Where [param point] is relative to the face: (sideways overshoot, depth).
## The overshoot is 0 when the point is over the face. Measured without the
## hover enlargement, so lighting up never widens what a fingertip can press.
func measure(point: Vector3) -> Vector2:
	var local := global_transform.orthonormalized().affine_inverse() * point
	var over := maxf(absf(local.x) - size.x * 0.5, absf(local.y) - size.y * 0.5)
	return Vector2(maxf(over, 0.0), local.z - THICKNESS)


## Fed once a frame by the menu with the depth of the fingertip that chose this
## button (INF when none did). Returns true on the frame this becomes a press:
## armed, and the fingertip went from in front of the face to touching it.
func sense(depth: float, delta: float) -> bool:
	var now := Time.get_ticks_msec()
	var near := depth <= HOVER_DEPTH and depth >= -BEHIND
	_set_hovered(near)
	if near:
		_hover_time += delta
		if _hover_time >= DWELL and not _spoken:
			_spoken = true
			Events.read_aloud.emit(speech)
	else:
		_hover_time = 0.0
		_spoken = false
	var last := _last_depth
	_last_depth = depth
	if not _armed:
		if depth > RELEASE_DEPTH and now >= _rearm_at: # in front, or away entirely
			_armed = true
		return false
	var crossed := last > PRESS_DEPTH and last < INF and depth <= PRESS_DEPTH and depth >= -BEHIND
	if not crossed:
		return false
	_armed = false
	_rearm_at = now + roundi(REARM * 1000.0)
	_pressed_at = now
	_spoken = true # it was pressed; reading the label now would talk over the result
	return true


## Everything a fingertip has done to this button, so a page rebuilt under a
## finger that is still there carries on as the same button: no second press,
## no reading the label again, and the press still seen.
func state() -> Dictionary:
	return {
		armed = _armed, rearm_at = _rearm_at, hover_time = _hover_time, spoken = _spoken,
		hovered = hovered, last_depth = _last_depth, pressed_at = _pressed_at,
	}


func restore(from: Dictionary) -> void:
	_armed = from.armed
	_rearm_at = from.rearm_at
	_hover_time = from.hover_time
	_spoken = from.spoken
	_last_depth = from.last_depth
	_pressed_at = from.pressed_at
	_set_hovered(from.hovered)
	if Time.get_ticks_msec() - _pressed_at < 120:
		flash()


## The press, seen: the slab sinks and comes back.
func flash() -> void:
	if _body == null:
		return
	var tween := create_tween()
	tween.tween_property(_body, ^"position:z", -0.008, 0.06)
	tween.tween_property(_body, ^"position:z", 0.0, 0.12)


func _set_hovered(on: bool) -> void:
	if on == hovered:
		return
	hovered = on
	Hover.set_hovered(self, on)
	scale = Vector3.ONE * (1.06 if on else 1.0)


func _build(label: String, icon: StringName, style: Style) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the press tween runs while the world is paused
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	if style == Style.CHOSEN:
		# The page you are on is told by a frame and by standing out, not by colour.
		var frame := MeshInstance3D.new()
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3(size.x + 0.014, size.y + 0.014, THICKNESS * 0.6)
		frame.mesh = frame_mesh
		frame.position.z = THICKNESS * 0.3
		frame.material_override = MenuIcons.material(MenuIcons.STAR)
		_body.add_child(frame)
	var slab := MeshInstance3D.new()
	slab.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, THICKNESS)
	slab.mesh = mesh
	slab.position.z = THICKNESS * 0.5 + (0.006 if style == Style.CHOSEN else 0.0)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slab.material_override = MenuIcons.material(FACES[style])
	_body.add_child(slab)
	var face := slab.position.z + THICKNESS * 0.5 + 0.001
	var text_left := -size.x * 0.5 + 0.008
	if not icon.is_empty():
		var picture := MenuIcons.make(icon, minf(size.y * 0.55, 0.034))
		picture.position = Vector3(-size.x * 0.5 + 0.024, 0.0, face + 0.002)
		_body.add_child(picture)
		text_left = -size.x * 0.5 + 0.044
	var text := Label3D.new()
	text.name = "Label"
	text.text = label
	text.pixel_size = 0.0004
	text.font_size = 36 if label.length() <= 6 else 30
	text.outline_size = 0
	text.modulate = MenuIcons.INK
	text.double_sided = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.width = (size.x * 0.5 - 0.006 - text_left) / text.pixel_size
	text.position = Vector3((text_left + size.x * 0.5 - 0.006) * 0.5, 0.0, face)
	_body.add_child(text)
