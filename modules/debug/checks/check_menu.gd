extends ModuleCheck
## Menu: the wrist menu opens from the star, pauses the world while it is open,
## and lets it go again when it closes.
##
## Decided on [signal Events.menu_toggled] rather than polled, because the
## station's own poll timer stops with the rest of the world while the menu is
## open — which is the very thing being checked.

var _paused_while_open := false
var _opened := false


func _arm() -> void:
	_opened = false
	if not Events.menu_toggled.is_connected(_on_menu_toggled):
		Events.menu_toggled.connect(_on_menu_toggled)
	update("menu not opened yet")


func _teardown() -> void:
	if Events.menu_toggled.is_connected(_on_menu_toggled):
		Events.menu_toggled.disconnect(_on_menu_toggled)


func _on_menu_toggled(open: bool) -> void:
	if verdict != Verdict.WAITING:
		return
	if open:
		_opened = true
		_paused_while_open = get_tree().paused
		update("open, world %s" % ("paused" if _paused_while_open else "NOT paused"))
		return
	if not _opened:
		return
	var trace := "paused while open: %s, running after: %s" % [
		"yes" if _paused_while_open else "NO", "yes" if not get_tree().paused else "NO"]
	if _paused_while_open and not get_tree().paused:
		pass_now(trace)
	else:
		fail_now(trace)


## The tester's part: open it as the star would, then press Close as a finger would.
func auto() -> void:
	mod().open()
	if not mod().press(&"menu_close"):
		mod().close()
