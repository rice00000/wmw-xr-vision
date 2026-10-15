extends Label3D
## Shows the line the Narrator is saying, in front of the player's eyes. It keeps
## no queue or clock of its own: the line on screen is the line being spoken.
## Hidden while the world is paused (the line restarts, voice and text together,
## when it runs again) and while Settings.subtitles is off (the guide still speaks).


func _ready() -> void:
	text = ""
	visible = false
	Narrator.line_started.connect(func(line: VoiceLine) -> void:
		text = line.text
		_refresh())
	Narrator.line_ended.connect(func(line: VoiceLine) -> void:
		if text == line.text:
			text = ""
		_refresh())
	Narrator.paused_changed.connect(func(_paused: bool) -> void: _refresh())
	Settings.changed.connect(func(key: StringName, _value: Variant) -> void:
		if key == &"subtitles":
			_refresh())
	if Narrator.current:
		text = Narrator.current.text
	_refresh()


func _refresh() -> void:
	visible = not text.is_empty() and Settings.value(&"subtitles") and not Narrator.is_paused()
