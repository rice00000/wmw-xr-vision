extends Node
## Voice module (autoload "Voice"): plays instruction voice clips one at a time.
## This is the only audio seam: replace this file with a Wwise / FMOD bridge
## and gameplay code doesn't change.

var _player := AudioStreamPlayer.new()
var _queue: Array[AudioStream] = []


func _ready() -> void:
	add_child(_player)
	_player.finished.connect(_play_next)
	Events.instruction.connect(_on_instruction)


func _on_instruction(_text: String, voice: AudioStream) -> void:
	if voice == null:
		return
	_queue.append(voice)
	if not _player.playing:
		_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		return
	_player.stream = _queue.pop_front()
	_player.play()
