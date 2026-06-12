extends Control
## Title screen. Entry point. UI built in code so the scene file stays trivial
## and version-control friendly.

const CHARACTER_CREATION := "res://scenes/character_creation/CharacterCreation.tscn"
const LOBBY := "res://scenes/lobby/Lobby.tscn"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.075, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 18)
	add_child(root)

	var title := Label.new()
	title.text = "NECROMANDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Every road could lead to power."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	root.add_child(subtitle)

	root.add_child(_spacer(30))

	root.add_child(_menu_button("New Character", _on_new_character))
	root.add_child(_menu_button("Multiplayer Lobby", _on_lobby))
	root.add_child(_menu_button("Quit", _on_quit))

func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _on_new_character() -> void:
	get_tree().change_scene_to_file(CHARACTER_CREATION)

func _on_lobby() -> void:
	if not GameState.has_character():
		# Need a character before joining a party. Send them to creation first.
		get_tree().change_scene_to_file(CHARACTER_CREATION)
		return
	get_tree().change_scene_to_file(LOBBY)

func _on_quit() -> void:
	get_tree().quit()
