extends ModuleCheck
## Debug uses native UI and opens only on the Menu + Y chord.


func _arm() -> void:
	update("panel not opened yet")
	Events.menu_toggled.connect(_on_ui_toggled)


func _teardown() -> void:
	if Events.menu_toggled.is_connected(_on_ui_toggled):
		Events.menu_toggled.disconnect(_on_ui_toggled)


func _on_ui_toggled(open: bool) -> void:
	if open and mod().is_open:
		pass_now("debug UI open in front of you")


func auto() -> void:
	Events.report(&"asked", &"debug")
	mod().close()
