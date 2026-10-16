extends Node
## Menu module (autoload "Menu"): the wrist menu, the only interface in the game.
##
## [b]On the wrist:[/b] a glowing star on the left wrist, and above it
## the current goal and how many Magic Stones the child has. The goal comes from
## [signal Events.goal_changed], so the wrist never polls anything. Touch the star
## with the other hand to open the menu. The wrist hides while the panel is open;
## the Home page's Close button closes it.
##
## [b]The panel[/b] opens in front of the child at chest height and stays where
## it opened (world-locked, not glued to the moving wrist, which would be
## unreadable). While it is open the game is paused ([method Game.hold_pause]),
## [signal Events.menu_toggled] says so, and "opened:menu" is reported. This
## module and Audio run while paused. Each controller has a [UIPointer] using
## its OpenXR aim pose. Rays intersect button faces directly, so selection works
## while physics is paused. The trigger clicks once until released.
##
## [b]Pages[/b], as tabs down the left: Home, Tasks, Shop, Bag, Settings. Every
## button has a shape and a word, lights up when pointed at, reads its
## label aloud after a moment, clicks (the sound table's "pressed" row), and
## buzzes the hand that pressed it. Long lists page three rows at a time.
##
## [b]Every other module is optional.[/b] With Tasks, Inventory or Save switched
## off, the page that needs it says so. The menu adds itself to [member
## Game.player] at runtime, like the Facilitator panel, so the player rig knows
## nothing about it.
##
## What it needs from the rig, all duck-typed: hands in group [code]hand[/code]
## (a [code]poke_point()[/code] method, when a hand has one, is used instead of
## its position, for a fingertip), [code]pulse()[/code] on a hand to buzz it, a
## camera child named Camera (or any [XRCamera3D]), and a left [XRController3D]
## for the star. Tracked nodes keep moving while the tree is paused, because
## OpenXR poses arrive by signal, not in [code]_process[/code].

const PAGES: Array[StringName] = [&"home", &"tasks", &"shop", &"bag", &"settings"]
const PAGE_NAMES := {
	&"home": "Home", &"tasks": "Tasks", &"shop": "Shop", &"bag": "Bag", &"settings": "Settings",
}
const STONE := &"magic_stone"

## Where the panel opens: this far in front of the eyes, this far below them.
const DISTANCE := 0.75
const BELOW_EYES := 0.20
const PANEL_SIZE := Vector2(0.58, 0.42)
const PANEL_COLOR := Color(0.07, 0.08, 0.16)
const TEXT_COLOR := Color(1.0, 1.0, 1.0)
const STATUS_COLOR := Color(1.0, 0.86, 0.3)
## Rows of a list shown at once; more go on further pages.
const ROWS := 3
const BUTTON_SIZE := Vector2(0.13, 0.075)
const TAB_SIZE := Vector2(0.105, 0.066)

## The star: a fingertip of the other hand this close touches it, and it can be
## touched again once that hand has moved this far off.
const STAR_RADIUS := 0.07
const STAR_RELEASE := 0.12
## Where the fingertip is on a hand without a poke_point(): this far ahead of it
## along -Z, the way the controller points.
const FINGERTIP := 0.06
## On the left controller: the star on the back of the wrist, the readout
## further up the forearm.
const STAR_AT := Vector3(0.0, 0.04, 0.075)
const READOUT_AT := Vector3(0.0, 0.03, 0.15)

const VOLUME_STEP := 0.1
const MIN_VOLUME := 0.1
const HAPTICS_STEP := 0.25
const TURN_STEPS: Array[float] = [15.0, 22.5, 30.0, 45.0, 60.0, 90.0]
const HEIGHT_STEP := 0.1
const MAX_HEIGHT := 0.8 ## m, either way

var is_open := false
var page: StringName = &"home"
## Listed in the shop instead of every [member ItemDef.in_shop] item, when not
## empty. For the test suite, which needs something to buy.
var shop_override: Array[ItemDef] = []

var _player: Node3D
var _left: Node3D
var _camera: Node3D
var _wrist: Node3D
var _star: Node3D
var _star_armed := false
var _star_hover := 0.0
var _star_hovered := false
var _goal_label: Label3D
var _stones_label: Label3D
var _stones_icon: Node3D
var _panel: Node3D
var _content: Node3D
var _buttons: Array[RayButton] = []
var _pointers: Array[UIPointer] = []
var _ui_open := false
var _status := ""
var _first_row := 0
var _confirm_start_over := false
var _dirty := false
var _carried: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # it is the thing you use while the world is paused
	add_to_group(&"xr_ui")
	Events.reported.connect(_on_reported)
	Events.menu_toggled.connect(_on_ui_toggled)
	Events.goal_changed.connect(_on_goal_changed)
	Events.profile_closing.connect(close)
	var inventory := _mod(&"Inventory")
	if inventory:
		inventory.changed.connect(_on_items_changed)
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.has_signal(&"pose_recentered"):
		xr.pose_recentered.connect(recentre) # after Game's handler, which re-centres the play space


func _process(delta: float) -> void:
	if not is_instance_valid(_player) or _player != Game.player:
		_attach()
	if _panel == null:
		return
	if _star and _wrist.is_visible_in_tree() and not is_open:
		_sense_star(delta)
	_sense_buttons(delta)
	if not is_open:
		return
	if _dirty and is_open:
		_dirty = false
		_show()


# -- opening and closing ------------------------------------------------------

func open() -> void:
	if is_open:
		return
	if _panel == null:
		_attach()
	if _panel == null:
		return
	get_tree().call_group(&"xr_ui", &"close")
	is_open = true
	page = &"home"
	_first_row = 0
	_status = ""
	_confirm_start_over = false
	_place_panel()
	_panel.visible = true
	_refresh_readout()
	_show()
	Game.hold_pause(&"menu", true)
	Events.menu_toggled.emit(true)
	Events.report(&"opened", &"menu")
	Events.read_aloud.emit(_page_speech())


func close() -> void:
	if not is_open:
		return
	is_open = false
	for pointer in _pointers:
		pointer.sample(false)
	_clear()
	if _panel:
		_panel.visible = false
	_refresh_readout()
	Game.hold_pause(&"menu", false)
	Events.menu_toggled.emit(false)
	Events.report(&"closed", &"menu")


## Puts the open panel back in front of the eyes, a frame after the headset has
## re-centred (holding the Meta button), so the child is never left facing away
## from the menu they are using.
func recentre() -> void:
	if not is_open:
		return
	await get_tree().process_frame
	if is_open and _panel:
		_place_panel()


func show_page(page_name: StringName) -> void:
	if not PAGES.has(page_name):
		return
	page = page_name
	_first_row = 0
	_status = ""
	_confirm_start_over = false
	if is_open:
		_show()
		Events.read_aloud.emit(_page_speech())


## Presses the visible button [param id] as a trigger would, minus the buzz.
## For the test suite. Returns false when no such button is showing.
func press(id: StringName) -> bool:
	var button := find_button(id)
	if button == null:
		return false
	_press(button, null)
	return true


func find_button(id: StringName) -> RayButton:
	for button in _buttons:
		if is_instance_valid(button) and button.id == id and button.is_inside_tree():
			return button
	return null


## Every button showing now, tabs included.
func buttons() -> Array[RayButton]:
	return _buttons.duplicate()


func star() -> Node3D:
	return _star


## Everything the open page says, joined, for tests.
func page_text() -> String:
	var lines := PackedStringArray()
	if _content:
		for label in _content.find_children("*", "Label3D", true, false):
			lines.append((label as Label3D).text)
	return "\n".join(lines)


## What the wrist says right now: goal, then stones.
func readout_text() -> String:
	var lines := PackedStringArray()
	if _goal_label and _goal_label.visible:
		lines.append(_goal_label.text)
	if _stones_label and _stones_label.visible:
		lines.append(_stones_label.text)
	return "\n".join(lines)


# -- the actions ---------------------------------------------------------------

## Buys one [param item] with Magic Stones. Not enough: a gentle "no", nothing
## spent, and the child is told how many more they need.
func buy(item: ItemDef) -> bool:
	var inventory := _mod(&"Inventory")
	if inventory == null or item == null:
		return false
	var where := _panel.global_position if _panel and _panel.is_inside_tree() else Vector3.ZERO
	if inventory.spend(item.cost):
		inventory.add(item.id)
		Events.report(&"bought", item.id, {position = where})
		Events.judge(&"reward", where)
		_say_status("You bought the %s! It is in your bag." % ItemDef.label(item.id))
		_dirty = true
		return true
	Events.judge(&"bad", where)
	_say_status("You need %s more." % _shortfall(inventory, item.cost))
	_dirty = true
	return false


## Out of the bag and into the hand: the placement layout answers the request
## (and takes it from the inventory); the menu gets out of the way. Where no
## layout is listening there is nowhere to put it, so the child is told, and the
## thing stays in the bag. Returns whether it went out.
func take_out(item_id: StringName) -> bool:
	if Events.place_requested.get_connections().is_empty():
		Events.judge(&"bad", _panel.global_position if _panel and _panel.is_inside_tree() else Vector3.ZERO)
		_say_status("There is nowhere to put the %s here. Try at home!" % ItemDef.label(item_id))
		_dirty = true
		return false
	Events.place_requested.emit(item_id)
	close()
	return true


# -- building the wrist and the panel -------------------------------------------

func _attach() -> void:
	_player = Game.player
	_panel = null
	_star = null
	_wrist = null
	_buttons.clear()
	_pointers.clear()
	if not is_instance_valid(_player):
		return
	for controller: XRController3D in _player.find_children("*", "XRController3D", true, false):
		var pointer := UIPointer.new()
		pointer.name = "%sMenuPointer" % controller.name
		pointer.controller = controller
		_player.add_child(pointer)
		_pointers.append(pointer)
	_camera = _find_camera(_player)
	_left = _find_left(_player)
	if _left:
		_build_wrist(_left)
	_panel = Node3D.new()
	_panel.name = "WristMenuPanel"
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	var back := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(PANEL_SIZE.x, PANEL_SIZE.y, 0.01)
	back.mesh = box
	back.position.z = -0.006
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.material_override = MenuIcons.material(PANEL_COLOR)
	_panel.add_child(back)
	_content = Node3D.new()
	_content.name = "Content"
	_panel.add_child(_content)
	_player.add_child(_panel)
	if is_open: # the rig was replaced while open (a level swap): show it again
		is_open = false
		open()


func _build_wrist(controller: Node3D) -> void:
	_wrist = Node3D.new()
	_wrist.name = "WristMenu"
	_wrist.process_mode = Node.PROCESS_MODE_ALWAYS
	controller.add_child(_wrist)
	_star = MenuIcons.make(&"star", 0.045, MenuIcons.STAR)
	_star.name = "Star"
	_star.position = STAR_AT
	_star.rotation.x = -PI / 2.0 # lying on the back of the wrist, facing up
	_wrist.add_child(_star)
	_star_armed = false

	# Read from the elbow side, like a watch: top of the text toward the fingers.
	var readout := Node3D.new()
	readout.name = "Readout"
	readout.position = READOUT_AT
	readout.basis = Basis(Vector3.RIGHT, -PI / 2.0)
	_wrist.add_child(readout)
	_stones_icon = MenuIcons.make(&"stone", 0.022)
	_stones_icon.position = Vector3(-0.055, 0.02, 0.002)
	readout.add_child(_stones_icon)
	_stones_label = _text(readout, "", Vector3(-0.04, 0.02, 0.0), 0.12, 40, TEXT_COLOR, 0.00035)
	_stones_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_goal_label = _text(readout, "", Vector3(-0.065, 0.0, 0.0), 0.15, 30, TEXT_COLOR, 0.00035)
	_goal_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_refresh_readout()


func _refresh_readout() -> void:
	if _wrist:
		_wrist.visible = not is_open and not _ui_open
	if _goal_label == null or not is_instance_valid(_goal_label):
		return
	_goal_label.visible = _mod(&"Tasks") != null
	_goal_label.text = _goal() if not _goal().is_empty() else "Touch the star to choose a task"
	var inventory := _mod(&"Inventory")
	_stones_label.visible = inventory != null
	_stones_icon.visible = inventory != null
	if inventory:
		_stones_label.text = "%d  Magic Stones" % inventory.count(STONE)


## World-locked in front of the eyes, low enough to look down at like a book,
## tilted to face them.
func _place_panel() -> void:
	var eye := _camera.global_position if _camera else _player.global_position + Vector3.UP * 1.3
	var forward := -_camera.global_basis.z if _camera else -_player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var spot := eye + forward * DISTANCE + Vector3.DOWN * BELOW_EYES
	_panel.global_position = spot
	# -Z away from the eyes, so the face (+Z) looks back up at them.
	_panel.look_at(spot + (spot - eye).normalized(), Vector3.UP)


# -- sensing hands ---------------------------------------------------------------

## [hand, fingertip] for every hand, leaving out any under [param skip] (the
## hand the star is on cannot touch its own wrist).
func _hands(skip: Node) -> Array:
	var found := []
	for hand in get_tree().get_nodes_in_group(&"hand"):
		if not (hand is Node3D) or not hand.is_inside_tree():
			continue
		if skip and skip.is_ancestor_of(hand):
			continue
		var point: Vector3
		if hand.has_method(&"poke_point"):
			point = hand.poke_point()
		else: # where a fingertip would be on a hand that cannot say
			point = hand.global_position - hand.global_basis.z * FINGERTIP
		found.append([hand, point])
	return found


func _sense_star(delta: float) -> void:
	if not _star.is_inside_tree():
		return
	var nearest := INF
	var toucher: Node = null
	for pair: Array in _hands(_left):
		var distance: float = (pair[1] as Vector3).distance_to(_star.global_position)
		if distance < nearest:
			nearest = distance
			toucher = pair[0]
	var near := nearest < STAR_RADIUS * 2.0
	if near != _star_hovered:
		_star_hovered = near
		Hover.set_hovered(_star, near)
		_star_hover = 0.0
	if near:
		_star_hover += delta
		if _star_hover >= RayButton.DWELL and _star_hover - delta < RayButton.DWELL:
			Events.read_aloud.emit("Your magic star. Touch it to open the menu.")
	if not _star_armed:
		if nearest > STAR_RELEASE:
			_star_armed = true
		return
	if nearest <= STAR_RADIUS:
		_star_armed = false
		_star_hover = INF # touched, not pointed at: no need to read it out
		if toucher and toucher.has_method(&"pulse"):
			toucher.pulse()
		open()


## One target per ray; one click per frame, even if both triggers fire.
## Input edges live on the pointers, so rebuilding a page cannot repeat a click.
func _sense_buttons(delta: float) -> void:
	var hovered: Array[RayButton] = []
	var clicked: RayButton = null
	var hand: Node = null
	for pointer in _pointers:
		var pressed := pointer.sample(is_open)
		if not pointer.visible:
			continue
		var best: RayButton = null
		var distance := UIPointer.LENGTH
		for button in _buttons:
			var hit := button.ray_distance(pointer.global_position, -pointer.global_basis.z)
			if hit < distance:
				distance = hit
				best = button
		pointer.draw_ray(distance, best != null)
		if best:
			hovered.append(best)
			if pressed and clicked == null:
				clicked = best
				hand = pointer.controller.get_node(^"Hand")
	for button in _buttons:
		button.sense(hovered.has(button), delta)
	if clicked:
		_press(clicked, hand)


func _press(button: RayButton, hand: Node) -> void:
	button.flash()
	Events.report(&"pressed", button.id, {position = button.global_position})
	if hand and hand.has_method(&"pulse"):
		hand.pulse()
	if button.action.is_valid():
		button.action.call()


# -- pages -----------------------------------------------------------------------

## A row is {text, icon?, buttons: [button specs]}; a button spec is the
## arguments of [method RayButton.create] plus an action.
##
## Rebuilt whenever anything on it changes. A button with the same id on the new
## page takes over the old one's hover and feedback, so the label is not read
## again over the result and the click is still seen.
func _show() -> void:
	_carried.clear()
	for button in _buttons:
		if is_instance_valid(button):
			_carried[button.id] = button.state()
	_clear()
	if _content == null:
		return
	for i in PAGES.size():
		var tab_page := PAGES[i]
		var tab := _add_button({
			id = StringName("menu_tab_%s" % tab_page), label = PAGE_NAMES[tab_page], icon = tab_page,
			size = TAB_SIZE, style = RayButton.Style.CHOSEN if tab_page == page else RayButton.Style.TAB,
			say = "%s page" % PAGE_NAMES[tab_page], action = show_page.bind(tab_page),
		})
		tab.position = Vector3(-0.225, 0.15 - i * 0.075, 0.0)
	var left := -0.155
	var right := 0.275
	_text(_content, PAGE_NAMES[page], Vector3(left, 0.178, 0.001), right - left, 52, TEXT_COLOR)
	var status := _status if not _status.is_empty() else _page_status()
	if not status.is_empty():
		_text(_content, status, Vector3(left, 0.135, 0.001), right - left, 34, STATUS_COLOR)
	var rows := _rows()
	_first_row = clampi(_first_row, 0, maxi(rows.size() - 1, 0) / ROWS * ROWS)
	var shown := rows.slice(_first_row, _first_row + ROWS)
	for r in shown.size():
		_lay_row(shown[r], 0.075 - r * 0.085, left, right)
	if rows.size() > ROWS:
		_lay_paging(rows.size(), left, right)


func _rows() -> Array:
	match page:
		&"tasks":
			return _task_rows()
		&"shop":
			return _shop_rows()
		&"bag":
			return _bag_rows()
		&"settings":
			return _settings_rows()
	return _home_rows()


func _home_rows() -> Array:
	var rows := []
	var tasks := _mod(&"Tasks")
	if tasks:
		var goal := _goal() if not _goal().is_empty() else "Nothing to do right now. Pick one on the Tasks page!"
		rows.append({text = "Now: %s" % goal})
	else:
		rows.append({text = "Tasks are switched off."})
	var inventory := _mod(&"Inventory")
	if inventory:
		rows.append({text = _amount(STONE, inventory.count(STONE)), icon = &"stone"})
	else:
		rows.append({text = "The Inventory is switched off, so there are no Magic Stones."})
	var actions := []
	if tasks and tasks.has_method(&"remind"):
		actions.append({id = &"menu_where", label = "Where do I go?", icon = &"where",
			size = Vector2(0.22, 0.075), say = "Where do I go? The guide will show you.", action = _where})
	actions.append({id = &"menu_close", label = "Close", icon = &"close",
		say = "Close the menu", action = close})
	rows.append({text = "", buttons = actions})
	return rows


func _task_rows() -> Array:
	var tasks := _mod(&"Tasks")
	if tasks == null:
		return [{text = "Tasks are switched off."}]
	var current := _current_task(tasks)
	if not current.is_empty():
		var info := _describe(tasks, current)
		var rows := [{text = "%s\n%s" % [info.title, _trains(info)]}]
		if not _goal().is_empty():
			rows.append({text = "Now: %s" % _goal()})
		var give_up := []
		if tasks.has_method(&"abandon") and info.get("can_abandon", true):
			give_up.append({id = &"menu_give_up", label = "Give up", icon = &"give_up",
				style = RayButton.Style.CAUTION, say = "Give up %s" % info.title,
				action = _give_up.bind(current)})
		rows.append({text = "Reward: %s" % _rewards(info), icon = &"stone", buttons = give_up})
		return rows
	var offers: Array = tasks.offers() if tasks.has_method(&"offers") else []
	if offers.is_empty():
		return [{text = "No new tasks right now. Look around the island!"}]
	var rows := []
	for task_id: StringName in offers:
		var info := _describe(tasks, task_id)
		rows.append({
			text = "%s\n%s  -  %s" % [info.title, _trains(info), _rewards(info)],
			buttons = [{
				id = StringName("menu_accept_%s" % task_id), label = "Accept", icon = &"accept",
				say = "Accept %s. %s. It gives %s." % [info.title, _trains(info), _rewards(info)],
				action = _accept.bind(task_id),
			}],
		})
	return rows


func _shop_rows() -> Array:
	var inventory := _mod(&"Inventory")
	if inventory == null:
		return [{text = "The shop needs the Inventory, which is switched off."}]
	var items := _shop_items()
	if items.is_empty():
		return [{text = "Nothing in the shop yet."}]
	var rows := []
	for item in items:
		var item_name := ItemDef.label(item.id)
		var price := _price(item.cost)
		rows.append({
			text = "%s\n%s" % [item_name, price],
			buttons = [{
				id = StringName("menu_buy_%s" % item.id), label = "Buy", icon = &"buy",
				say = "Buy the %s for %s" % [item_name, price], action = buy.bind(item),
			}],
		})
	return rows


func _bag_rows() -> Array:
	var inventory := _mod(&"Inventory")
	if inventory == null:
		return [{text = "The bag needs the Inventory, which is switched off."}]
	var rows := []
	var owned: Dictionary = inventory.all()
	var ids: Array = owned.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return ItemDef.label(a) < ItemDef.label(b))
	for item_id: StringName in ids:
		var def := ItemDef.find(item_id)
		if def == null or def.scene == null or owned[item_id] <= 0:
			continue
		var item_name := ItemDef.label(item_id)
		rows.append({
			text = "%s   x%d" % [item_name, owned[item_id]],
			buttons = [{
				id = StringName("menu_take_out_%s" % item_id), label = "Take out", icon = &"take_out",
				say = "Take out a %s" % item_name, action = take_out.bind(item_id),
			}],
		})
	if rows.is_empty():
		return [{text = "Your bag is empty. Things you buy in the shop go here."}]
	return rows


func _settings_rows() -> Array:
	var rows := [
		_slider_row(&"volume_master", "Volume", VOLUME_STEP),
		_slider_row(&"volume_voice", "Voice", VOLUME_STEP),
		_switch_row(&"read_aloud", "Read aloud"),
		_switch_row(&"subtitles", "Subtitles"),
		_slider_row(&"haptics", "Vibration", HAPTICS_STEP),
	]
	var teleport: bool = Settings.value(&"move_mode") == &"teleport"
	rows.append({text = "Move by\n%s" % ("Teleport only" if teleport else "Walking"), buttons = [
		{id = &"menu_set_move_walk", label = "Walk", icon = &"walk",
			style = RayButton.Style.ACTION if teleport else RayButton.Style.CHOSEN,
			say = "Move by walking with the stick", action = _choose.bind(&"move_mode", &"walk", "Walking")},
		{id = &"menu_set_move_teleport", label = "Teleport", icon = &"teleport",
			style = RayButton.Style.CHOSEN if teleport else RayButton.Style.ACTION,
			say = "Move by teleport only", action = _choose.bind(&"move_mode", &"teleport", "Teleport only")},
	]})
	rows.append({text = "Turn\n%d degrees" % roundi(Settings.value(&"turn_degrees")), buttons = [
		{id = &"menu_set_turn_degrees_down", label = "Less", icon = &"minus", say = "Turn less",
			action = _turn.bind(-1)},
		{id = &"menu_set_turn_degrees_up", label = "More", icon = &"plus", say = "Turn more",
			action = _turn.bind(1)},
	]})
	rows.append({text = "View height\n%s" % _height_words(Settings.value(&"height")), buttons = [
		{id = &"menu_set_height_down", label = "Lower", icon = &"minus", say = "View lower",
			action = _raise.bind(-HEIGHT_STEP)},
		{id = &"menu_set_height_up", label = "Higher", icon = &"plus", say = "View higher",
			action = _raise.bind(HEIGHT_STEP)},
	]})
	if _mod(&"Save") == null:
		rows.append({text = "Start over needs Saving, which is switched off."})
	elif _confirm_start_over:
		rows.append({text = "Really start again?", buttons = [
			{id = &"menu_start_over_yes", label = "Yes", icon = &"yes", style = RayButton.Style.CAUTION,
				say = "Yes, start over from the very beginning", action = _start_over},
			{id = &"menu_start_over_no", label = "No", icon = &"no", say = "No, keep playing",
				action = _cancel_start_over},
		]})
	else:
		rows.append({text = "Start over", buttons = [
			{id = &"menu_start_over", label = "Start over", icon = &"start_over",
				style = RayButton.Style.CAUTION, say = "Start over from the very beginning",
				action = _ask_start_over},
		]})
	return rows


func _slider_row(key: StringName, label: String, step: float) -> Dictionary:
	var percent := roundi(float(Settings.value(key)) * 100.0)
	return {text = "%s\n%d%%" % [label, percent], buttons = [
		{id = StringName("menu_set_%s_down" % key), label = "Less", icon = &"minus", say = "%s down" % label,
			action = _nudge.bind(key, -step, label)},
		{id = StringName("menu_set_%s_up" % key), label = "More", icon = &"plus", say = "%s up" % label,
			action = _nudge.bind(key, step, label)},
	]}


func _switch_row(key: StringName, label: String) -> Dictionary:
	var on: bool = Settings.value(key)
	return {text = "%s\n%s" % [label, "On" if on else "Off"], buttons = [
		{id = StringName("menu_set_%s_toggle" % key), label = "Turn off" if on else "Turn on",
			icon = &"off" if on else &"on", say = "Turn %s %s" % [label.to_lower(), "off" if on else "on"],
			action = _choose.bind(key, not on, "On" if not on else "Off")},
	]}


func _page_status() -> String:
	var inventory := _mod(&"Inventory")
	match page:
		&"shop":
			return "You have %s" % _amount(STONE, inventory.count(STONE)) if inventory else ""
		&"tasks":
			var tasks := _mod(&"Tasks")
			if tasks and _current_task(tasks).is_empty():
				return "Pick one. You can do one task at a time."
	return ""


## Said when a page comes up, so the page is known without reading it.
func _page_speech() -> String:
	var inventory := _mod(&"Inventory")
	match page:
		&"home":
			var line := "Menu. Point at a button and press the trigger to choose."
			if not _goal().is_empty():
				line += " Now: %s." % _goal()
			if inventory:
				line += " You have %s." % _amount(STONE, inventory.count(STONE))
			return line
		&"tasks":
			var tasks := _mod(&"Tasks")
			if tasks == null:
				return "Tasks."
			var current := _current_task(tasks)
			if not current.is_empty():
				return "Tasks. You are doing %s." % _describe(tasks, current).title
			var offers: Array = tasks.offers() if tasks.has_method(&"offers") else []
			return "Tasks. %d to choose from." % offers.size()
		&"shop":
			return "Shop. You have %s." % _amount(STONE, inventory.count(STONE)) if inventory else "Shop."
		&"bag":
			return "Bag."
	return "Settings."


# -- what the buttons do -----------------------------------------------------------

func _where() -> void:
	var tasks := _mod(&"Tasks")
	close()
	if tasks:
		tasks.remind()


func _accept(task_id: StringName) -> void:
	var tasks := _mod(&"Tasks")
	if tasks == null or not tasks.has_method(&"accept"):
		return
	if tasks.accept(task_id): # reports accepted:<id> itself, which is heard
		close()
		return
	Events.judge(&"bad", _panel.global_position)
	_say_status("That task can't be started right now.")
	_dirty = true


func _give_up(task_id: StringName) -> void:
	var tasks := _mod(&"Tasks")
	if tasks == null:
		return
	var title: String = _describe(tasks, task_id).title
	tasks.abandon()
	if _current_task(tasks) == task_id:
		_say_status("%s can't be given up. Keep going!" % title)
	else:
		_say_status("You stopped %s. Pick another one any time." % title)
	_dirty = true


func _nudge(key: StringName, step: float, label: String) -> void:
	var value := clampf(snappedf(float(Settings.value(key)) + step, 0.01), _floor(key), 1.0)
	Settings.set_value(key, value)
	_say_status("%s %d percent" % [label, roundi(value * 100.0)])
	_dirty = true


## The menu never turns the sound all the way off: a child who cannot read
## finds "More" again by its click and its voice.
func _floor(key: StringName) -> float:
	return MIN_VOLUME if key in [&"volume_master", &"volume_voice"] else 0.0


func _choose(key: StringName, value: Variant, spoken: String) -> void:
	Settings.set_value(key, value)
	_say_status(spoken)
	_dirty = true


func _turn(direction: int) -> void:
	var now: float = Settings.value(&"turn_degrees")
	var index := 0
	for i in TURN_STEPS.size():
		if absf(TURN_STEPS[i] - now) < absf(TURN_STEPS[index] - now):
			index = i
	var value := TURN_STEPS[clampi(index + direction, 0, TURN_STEPS.size() - 1)]
	Settings.set_value(&"turn_degrees", value)
	_say_status("Turn %d degrees" % roundi(value))
	_dirty = true


func _raise(step: float) -> void:
	var value := clampf(snappedf(float(Settings.value(&"height")) + step, HEIGHT_STEP), -MAX_HEIGHT, MAX_HEIGHT)
	Settings.set_value(&"height", value)
	_say_status("View %s" % _height_words(value, "centimetres"))
	_dirty = true


func _height_words(height: float, unit := "cm") -> String:
	var cm := roundi(height * 100.0)
	if cm == 0:
		return "as you are"
	return "%d %s %s" % [absi(cm), unit, "higher" if cm > 0 else "lower"]


func _ask_start_over() -> void:
	_confirm_start_over = true
	_say_status("Start again from the very beginning? Press Yes to start over, or No.")
	_dirty = true


func _cancel_start_over() -> void:
	_confirm_start_over = false
	_say_status("")
	_dirty = true


## This player's game from the very beginning: progress and settings back to
## new, the research log kept (Profile).
func _start_over() -> void:
	close()
	Profile.start_over()


func _say_status(text: String) -> void:
	_status = text
	if not text.is_empty():
		Events.read_aloud.emit(text)


func _next(step: int) -> void:
	_first_row = maxi(_first_row + step * ROWS, 0)
	_dirty = true


# -- laying out -------------------------------------------------------------------

func _lay_row(row: Dictionary, y: float, left: float, right: float) -> void:
	var specs: Array = row.get("buttons", [])
	var edge := right
	for i in range(specs.size() - 1, -1, -1):
		var button := _add_button(specs[i])
		button.position = Vector3(edge - button.size.x * 0.5, y, 0.0)
		edge -= button.size.x + 0.012
	var text: String = row.get("text", "")
	if text.is_empty():
		return
	var start := left
	if row.has("icon"):
		var icon := MenuIcons.make(row.icon, 0.026)
		icon.position = Vector3(left + 0.013, y, 0.004)
		_content.add_child(icon)
		start += 0.032
	_text(_content, text, Vector3(start, y, 0.001), edge - 0.01 - start, 40, TEXT_COLOR)


func _lay_paging(total: int, left: float, right: float) -> void:
	var pages := ceili(float(total) / ROWS)
	var at := _first_row / ROWS + 1
	var y := -0.17
	if at > 1:
		var back := _add_button({id = &"menu_prev", label = "Back", icon = &"prev",
			size = Vector2(0.13, 0.06), style = RayButton.Style.NAV, say = "Back", action = _next.bind(-1)})
		back.position = Vector3(left + 0.065, y, 0.0)
	if at < pages:
		var more := _add_button({id = &"menu_next", label = "More", icon = &"next",
			size = Vector2(0.13, 0.06), style = RayButton.Style.NAV, say = "More", action = _next.bind(1)})
		more.position = Vector3(right - 0.065, y, 0.0)
	_text(_content, "%d / %d" % [at, pages], Vector3((left + right) * 0.5 - 0.04, y, 0.001), 0.08, 30,
		TEXT_COLOR, 0.0004, HORIZONTAL_ALIGNMENT_CENTER)


func _add_button(spec: Dictionary) -> RayButton:
	var button := RayButton.create(spec.id, spec.label, spec.get("icon", &""),
		spec.get("size", BUTTON_SIZE), spec.get("style", RayButton.Style.ACTION), spec.get("say", ""))
	button.action = spec.get("action", Callable())
	_content.add_child(button)
	_buttons.append(button)
	if _carried.has(button.id):
		button.restore(_carried[button.id])
	return button


## A text box whose left edge is at [param at].x and whose middle is at its y.
func _text(parent: Node3D, text: String, at: Vector3, width: float, font_size: int, color: Color,
		pixel := 0.0004, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = pixel
	label.font_size = font_size
	label.outline_size = 8
	label.outline_modulate = Color.BLACK
	label.modulate = color
	label.double_sided = false
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = maxf(width, 0.02) / pixel
	# A left-aligned Label3D starts at its origin; a centred one is centred on it.
	label.position = at + Vector3(maxf(width, 0.02) * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 0.0, 0.0, 0.0)
	parent.add_child(label)
	return label


func _clear() -> void:
	_buttons.clear()
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


# -- reading other modules, every one of them optional ------------------------------

func _mod(module_name: StringName) -> Node:
	return Game.module(module_name)


func _current_task(tasks: Node) -> StringName:
	if tasks.has_method(&"current"):
		return tasks.current()
	if tasks.has_method(&"active"): # before the one-task Tasks API lands
		var active: Array = tasks.active()
		return active[0] if not active.is_empty() else &""
	return &""


func _describe(tasks: Node, task_id: StringName) -> Dictionary:
	var info: Dictionary = tasks.describe(task_id) if tasks.has_method(&"describe") else {}
	if not info.has("title") or str(info.title).is_empty():
		info.title = String(task_id).capitalize()
	return info


func _trains(info: Dictionary) -> String:
	var visual_skills: PackedStringArray = PackedStringArray(info.get("visual_skills", []))
	return "Trains: %s" % ", ".join(visual_skills) if not visual_skills.is_empty() else "Just for fun"


func _rewards(info: Dictionary) -> String:
	var rewards: Dictionary = info.get("rewards", {})
	return _price(rewards) if not rewards.is_empty() else "no reward"


func _price(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts := PackedStringArray()
	for item_id: StringName in cost:
		parts.append(_amount(item_id, cost[item_id]))
	return ", ".join(parts)


func _shortfall(inventory: Node, cost: Dictionary) -> String:
	for item_id: StringName in cost:
		var missing: int = cost[item_id] - inventory.count(item_id)
		if missing > 0:
			return _amount(item_id, missing)
	return "nothing"


## "1 Magic Stone", "3 Magic Stones".
func _amount(item_id: StringName, count: int) -> String:
	var item_name := ItemDef.label(item_id)
	return "%d %s%s" % [count, item_name, "" if count == 1 or item_name.ends_with("s") else "s"]


func _shop_items() -> Array[ItemDef]:
	if not shop_override.is_empty():
		return shop_override
	var items: Array[ItemDef] = []
	for item in ItemDef.all():
		if item.in_shop:
			items.append(item)
	items.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return ItemDef.label(a.id) < ItemDef.label(b.id))
	return items


func _find_camera(player: Node) -> Node3D:
	var camera := player.get_node_or_null(^"Camera") as Node3D
	if camera:
		return camera
	var found := player.find_children("*", "XRCamera3D", true, false)
	return found[0] as Node3D if not found.is_empty() else null


func _find_left(player: Node) -> Node3D:
	var left := player.get_node_or_null(^"LeftController") as Node3D
	if left:
		return left
	for controller in player.find_children("*", "XRController3D", true, false):
		if (controller as XRController3D).tracker == &"left_hand":
			return controller
	return null


## The goal's line for the wrist and the pages: always the published one.
func _goal() -> String:
	return Events.goal.text


func _on_goal_changed(_goal_now: Goal) -> void:
	_refresh_readout()
	if is_open:
		_dirty = true


func _on_items_changed(_item_id: StringName, _count: int) -> void:
	_refresh_readout()
	if is_open:
		_dirty = true


func _on_reported(what: StringName, id: StringName, _data: Dictionary) -> void:
	if what == &"asked" and id == &"menu":
		if is_open:
			close()
		else:
			open()


func _on_ui_toggled(open_now: bool) -> void:
	_ui_open = open_now
	_refresh_readout()
