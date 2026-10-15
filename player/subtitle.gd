extends Label3D
## Shows Events.instruction texts in front of the player's eyes, one after another.
## Nothing at all while Settings.subtitles is off (the guide still speaks).

const SECONDS_PER_CHAR := 0.06
const MIN_SECONDS := 3.0

var _queue: Array[String] = []
## Bumped whenever the line on show is dropped, so a timer still running for it
## cannot cut the next line short.
var _generation := 0


func _ready() -> void:
	visible = false
	Events.instruction.connect(_on_instruction)
	Settings.changed.connect(_on_setting_changed)


func _on_instruction(message: String, _voice: AudioStream) -> void:
	if message.is_empty() or not Settings.value(&"subtitles"):
		return
	_queue.append(message)
	if not visible:
		_show_next()


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"subtitles" and not value:
		_queue.clear()
		_generation += 1
		visible = false


func _show_next() -> void:
	if _queue.is_empty() or not Settings.value(&"subtitles"):
		visible = false
		return
	text = _queue.pop_front()
	visible = true
	_generation += 1
	var shown := _generation
	await get_tree().create_timer(maxf(MIN_SECONDS, text.length() * SECONDS_PER_CHAR)).timeout
	if shown == _generation:
		_show_next()
