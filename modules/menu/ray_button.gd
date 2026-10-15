class_name RayButton
extends Node3D
## A menu button's appearance, rectangular ray target and hover speech.
## The menu owns controller input; buttons never track fingers or latch triggers.

enum Style {
	ACTION, ## the thing to do on this page
	TAB, ## a page along the side
	CHOSEN, ## the page you are on, or the setting that is set
	CAUTION, ## giving up, starting over
	NAV, ## more / back through a long list
}

const DWELL := 0.45
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

var _hover_time := 0.0
var _spoken := false
var _pressed_at := -100000
var _body: Node3D
var _frame: MeshInstance3D
var _chosen := false


static func create(button_id: StringName, label: String, icon: StringName, button_size: Vector2,
		style := Style.ACTION, say := "") -> RayButton:
	var button := RayButton.new()
	button.name = String(button_id)
	button.id = button_id
	button.size = button_size
	button.speech = say if not say.is_empty() else label.replace("\n", " ")
	button._build(label, icon, style)
	return button


## Distance to the front face, INF on a miss. Ignore hover enlargement so the
## target never changes size under the pointer. Back faces cannot be clicked.
func ray_distance(origin: Vector3, direction: Vector3) -> float:
	var inverse := global_transform.orthonormalized().affine_inverse()
	var start := inverse * origin
	var ray := inverse.basis * direction
	if ray.z >= -0.0001 or start.z <= THICKNESS:
		return INF
	var distance := (THICKNESS - start.z) / ray.z
	var hit := start + ray * distance
	return distance if absf(hit.x) <= size.x * 0.5 and absf(hit.y) <= size.y * 0.5 else INF


func sense(pointed: bool, delta: float) -> void:
	_set_hovered(pointed)
	if pointed:
		_hover_time += delta
		if _hover_time >= DWELL and not _spoken:
			_spoken = true
			Events.read_aloud.emit(speech)
	else:
		_hover_time = 0.0
		_spoken = false


## Carry hover speech and the visible click across a page rebuild.
func state() -> Dictionary:
	return {hover_time = _hover_time, spoken = _spoken, hovered = hovered, pressed_at = _pressed_at}


func restore(from: Dictionary) -> void:
	_hover_time = from.hover_time
	_spoken = from.spoken
	_pressed_at = from.pressed_at
	_set_hovered(from.hovered)
	if Time.get_ticks_msec() - _pressed_at < 120:
		flash()


## The press, seen: the slab sinks and comes back.
func flash() -> void:
	_pressed_at = Time.get_ticks_msec()
	_spoken = true
	if _body == null:
		return
	var tween := create_tween()
	tween.tween_property(_body, ^"position:z", -0.008, 0.06)
	tween.tween_property(_body, ^"position:z", 0.0, 0.12)


func _set_hovered(on: bool) -> void:
	if on == hovered:
		return
	hovered = on
	_frame.visible = on or _chosen
	scale = Vector3.ONE * (1.04 if on else 1.0)


func _build(label: String, icon: StringName, style: Style) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the press tween runs while the world is paused
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	# Selection and ray hover use the same simple frame, leaving icons legible.
	_chosen = style == Style.CHOSEN
	_frame = MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(size.x + 0.014, size.y + 0.014, THICKNESS * 0.6)
	_frame.mesh = frame_mesh
	_frame.position.z = THICKNESS * 0.3
	_frame.material_override = MenuIcons.material(MenuIcons.STAR)
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.visible = _chosen
	_body.add_child(_frame)
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
