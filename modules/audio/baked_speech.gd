class_name BakedSpeech
extends RefCounted
## Resolve authored words to files. The game never synthesizes speech.

const INDEX := "res://content/audio/generated/index.json"
static var _clips: Dictionary = {}
static var _keys: Array = []
static var _modified := ""


static func normalize(text: String) -> String:
	var punctuation := RegEx.create_from_string("[^\\p{L}\\p{N}']+")
	return punctuation.sub(text.to_lower(), " ", true).strip_edges()


static func paths_for(text: String) -> PackedStringArray:
	var revision := FileAccess.get_md5(INDEX) if OS.has_feature("editor") else "exported"
	if revision != _modified:
		_modified = revision
		_clips = JSON.parse_string(FileAccess.get_file_as_string(INDEX)).clips
		_keys = _clips.keys()
		_keys.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var remaining := normalize(text)
	var paths := PackedStringArray()
	while not remaining.is_empty():
		var found := ""
		for key: String in _keys:
			if remaining == key or remaining.begins_with(key + " "):
				found = key
				break
		if found.is_empty():
			var word := remaining.get_slice(" ", 0)
			if not word.is_valid_int():
				push_error("[Speech] Unbaked text: %s. Add it to content/audio/speech.tts." % text)
				return []
			for digit in word:
				paths.append(_clips[digit])
			found = word
		else:
			paths.append(_clips[found])
		remaining = remaining.substr(found.length()).strip_edges()
	return paths


static func stream(text: String) -> AudioStream:
	var paths := paths_for(text)
	if paths.is_empty():
		return null
	if paths.size() == 1:
		return load(paths[0]) as AudioStream
	var playlist := AudioStreamPlaylist.new()
	playlist.loop = false
	playlist.fade_time = 0.0
	playlist.stream_count = paths.size()
	for i in paths.size():
		playlist.set_list_stream(i, load(paths[i]) as AudioStream)
	return playlist
