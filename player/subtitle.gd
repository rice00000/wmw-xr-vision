extends Label3D
## Shows Events.instruction texts in front of the player's eyes, one after another.

const SECONDS_PER_CHAR := 0.06
const MIN_SECONDS := 3.0

var _queue: Array[String] = []


func _ready() -> void:
	visible = false
	Events.instruction.connect(_on_instruction)


func _on_instruction(message: String, _voice: AudioStream) -> void:
	if message.is_empty():
		return
	_queue.append(message)
	if not visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		visible = false
		return
	text = _queue.pop_front()
	visible = true
	await get_tree().create_timer(maxf(MIN_SECONDS, text.length() * SECONDS_PER_CHAR)).timeout
	_show_next()
