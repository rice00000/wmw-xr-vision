extends Node
## A short file/playback check, on its own throwaway profile. No XR or system TTS.

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error(label)


func _run() -> void:
	Settings.set_value(&"read_aloud", true)
	for text in [
		"Find the cup.",
		"Hello! I am your wizard. Take the glowing ball from my hand. Squeeze to hold it.",
		"Menu. Point at a button and press the trigger to choose. Now: Follow me to the picnic table!. You have 1234 Magic Stones.",
		"Accept Find It. Trains: Finding things in a mess. It gives 2 Magic Stones.",
		"Buy the Chair for 3 Magic Stones", "You need 2 Magic Stones more.",
		"Volume 70 percent", "Turn 23 degrees", "Turn read aloud off",
	]:
		var paths := BakedSpeech.paths_for(text)
		_check(not paths.is_empty(), "Speech resolves: %s" % text)
		for path in paths:
			_check(ResourceLoader.exists(path), "Imported speech exists: %s" % path)
	for task in TaskDef.all():
		for step in task.steps:
			if not step.instruction.is_empty():
				_check(not BakedSpeech.paths_for(step.instruction).is_empty(), "Task instruction: %s" % task.id)
		if not task.completed_text.is_empty():
			_check(not BakedSpeech.paths_for(task.completed_text).is_empty(), "Task completion: %s" % task.id)
	for list in TaskListDef.all():
		for action in ["Show", "Hide"]:
			var text := "%s %s" % [action, list.title]
			_check(not BakedSpeech.paths_for(text).is_empty(), "Task-list read-aloud: %s" % text)
	var menu := get_node("/root/Menu")
	for page in menu.PAGES:
		menu.page = page
		_check(not BakedSpeech.paths_for(menu._page_speech()).is_empty(), "Menu page: %s" % page)
		for row: Dictionary in menu._rows():
			for button: Dictionary in row.get("buttons", []):
				var text: String = button.get("say", button.get("label", ""))
				_check(not BakedSpeech.paths_for(text).is_empty(), "Menu button: %s" % text)
	Narrator.clear()
	Narrator.read_pace = 0.0
	Narrator.min_seconds = 0.01
	Narrator.say("Find the cup.")
	_check(Audio._guide.playing and Audio._guide.stream.get_length() > 0.0, "Narrator plays a real baked file")
	Events.read_aloud.emit("Shop page")
	_check(not Audio._reader.playing, "Menu speech never interrupts the guide")
	# Bound the check even if a broken finished callback leaves the Narrator waiting.
	for _i in 40:
		if Narrator.is_quiet():
			break
		await get_tree().create_timer(0.1).timeout
	_check(Narrator.is_quiet(), "Baked playback reports completion to the Narrator")
	Events.read_aloud.emit("Volume 70 percent")
	_check(Audio._reader.playing, "Dynamic read-aloud plays baked segments")
	Settings.set_value(&"read_aloud", false)
	_check(not Audio._reader.playing, "Read-aloud off stops the reader")
	await get_tree().create_timer(0.1).timeout # let the audio mixer release the stopped playlist
	print("BAKED_SPEECH_CHECK: %s" % ("PASS" if _failures == 0 else "%d failures" % _failures))
	get_tree().quit.call_deferred(_failures)
