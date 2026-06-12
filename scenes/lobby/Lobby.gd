extends Control
## Multiplayer lobby. Host a party (become the authoritative server) or join one
## by address. The roster is server-synced via NetworkManager (DESIGN.md 4).

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"

var address_edit: LineEdit
var port_edit: LineEdit
var status_label: Label
var roster_box: VBoxContainer
var host_button: Button
var join_button: Button
var leave_button: Button
var ready_button: Button

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Party Lobby"
	title.add_theme_font_size_override("font_size", 32)
	col.add_child(title)

	var who := GameState.current_class()
	var me := Label.new()
	me.text = "You: %s the %s" % [
		GameState.player_build.character_name if GameState.has_character() else "Guest",
		who.get("title", "Wanderer")]
	me.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	col.add_child(me)

	# --- Connection controls
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Host address"
	address_edit.text = "127.0.0.1"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address_edit)

	port_edit = LineEdit.new()
	port_edit.placeholder_text = "Port"
	port_edit.text = str(NetworkManager.DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(90, 0)
	row.add_child(port_edit)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	col.add_child(btn_row)

	host_button = _btn("Host", _on_host)
	join_button = _btn("Join", _on_join)
	leave_button = _btn("Leave", _on_leave)
	btn_row.add_child(host_button)
	btn_row.add_child(join_button)
	btn_row.add_child(leave_button)

	status_label = Label.new()
	status_label.text = "Not connected."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status_label)

	var div := ColorRect.new()
	div.color = Color(0.3, 0.25, 0.4)
	div.custom_minimum_size = Vector2(0, 2)
	col.add_child(div)

	var party_label := Label.new()
	party_label.text = "Party"
	party_label.add_theme_font_size_override("font_size", 20)
	col.add_child(party_label)

	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 6)
	col.add_child(roster_box)

	ready_button = _btn("Toggle Ready", _on_ready)
	col.add_child(ready_button)

	var back := _btn("Back to Menu", func(): _on_leave(); get_tree().change_scene_to_file(MAIN_MENU))
	col.add_child(back)

	# --- Wire up NetworkManager signals
	NetworkManager.lobby_updated.connect(_on_lobby_updated)
	NetworkManager.server_started.connect(func(port): _set_status("Hosting on port %d. Share your IP to let friends join." % port))
	NetworkManager.connection_succeeded.connect(func(): _set_status("Connected to host."))
	NetworkManager.connection_failed.connect(func(reason): _set_status("⚠ " + reason))

	_on_lobby_updated(NetworkManager.players)
	_update_buttons()

# ---------------------------------------------------------------- actions
func _on_host() -> void:
	if NetworkManager.host_game(_port()):
		_set_status("Starting host…")
	_update_buttons()

func _on_join() -> void:
	var addr := address_edit.text.strip_edges()
	if addr == "":
		_set_status("Enter a host address first.")
		return
	if NetworkManager.join_game(addr, _port()):
		_set_status("Connecting to %s…" % addr)
	_update_buttons()

func _on_leave() -> void:
	NetworkManager.leave()
	_set_status("Left the lobby.")
	_update_buttons()

func _on_ready() -> void:
	if not NetworkManager.is_active():
		return
	var me := NetworkManager.players.get(NetworkManager.local_id(), {})
	NetworkManager.set_ready(not me.get("ready", false))

# ---------------------------------------------------------------- ui
func _on_lobby_updated(players: Dictionary) -> void:
	for child in roster_box.get_children():
		child.queue_free()
	if players.is_empty():
		var empty := Label.new()
		empty.text = "No one here yet."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		roster_box.add_child(empty)
	else:
		var ids := players.keys()
		ids.sort()
		for id in ids:
			var info: Dictionary = players[id]
			var line := Label.new()
			var tag := " (host)" if id == 1 else ""
			var ready_mark := "✓" if info.get("ready", false) else "…"
			line.text = "[%s] %s — %s the %s%s" % [
				ready_mark, str(id), info.get("name", "?"),
				info.get("class_title", "Wanderer"), tag]
			roster_box.add_child(line)
	_update_buttons()

func _update_buttons() -> void:
	var active := NetworkManager.is_active()
	host_button.disabled = active
	join_button.disabled = active
	leave_button.disabled = not active
	ready_button.disabled = not active

func _set_status(text: String) -> void:
	status_label.text = text

func _port() -> int:
	var p := int(port_edit.text)
	return p if p > 0 else NetworkManager.DEFAULT_PORT

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b
