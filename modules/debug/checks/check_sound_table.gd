extends ModuleCheck
## Audio, the table: a button is heard with no audio code behind the button.
##
## This is the station that proves the design claim. It touches an ordinary
## [TouchButton] — a component containing no audio whatsoever, connected to
## nothing here — and checks that a sound came out and that the table chose it.
## It also checks that an unknown button still falls back to the general
## [code]pressed[/code] row, which is what makes "every button in the game has
## a sound" one line of data rather than a job.
##
## The waiting line shows the keys the game has sent that no row answers. That
## list is the table's to-do list, and the failure mode a sound system quietly
## dies of is letting it grow.

var _button: TouchButton


func _arm() -> void:
	_button = add_button(&"beep", "Press me")
	update(_line())


func _on_press(id: StringName) -> void:
	if id != &"beep":
		return
	var key := "pressed.%s" % button_id(&"beep")
	var problems: PackedStringArray = mod().table.errors
	var played: PackedStringArray = mod().played
	var last := played[played.size() - 1] if not played.is_empty() else "nothing"
	# A button nobody has ever named must still be heard, through the plain
	# "pressed" row. That is the whole point of the dotted fallback.
	var fallback: SoundDef = mod().table.lookup("pressed.no_such_button_anywhere")
	if not problems.is_empty():
		fail_now("%d problems in the table, first: %s" % [problems.size(), problems[0]])
	elif not last.begins_with(key):
		fail_now("the button made no sound; the last one was %s" % last)
	elif fallback == null or fallback.key != "pressed":
		fail_now("an unnamed button would be silent: no 'pressed' row to fall back to")
	else:
		pass_now("%s, and any other button falls back to 'pressed'" % last)


func _tick() -> void:
	if verdict == Verdict.WAITING:
		update(_line())


func _line() -> String:
	var rows: int = mod().table.rows.size()
	var problems: int = mod().table.errors.size()
	var missing: PackedStringArray = PackedStringArray(mod().unmapped.keys())
	var line := "%d rows, %d problems, %d keys with no row" % [rows, problems, missing.size()]
	if not missing.is_empty():
		line += "   (%s)" % ", ".join(missing.slice(0, 3))
	return line


## Touch the real button, rather than calling the handler: the claim being
## checked is that pressing it is enough.
func auto() -> void:
	if _button:
		_button.touch(null)
