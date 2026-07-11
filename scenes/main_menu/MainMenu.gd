extends Control
## Title screen. Entry point. UI built in code so the scene file stays trivial
## and version-control friendly.

const CHARACTER_CREATION := "res://scenes/character_creation/CharacterCreation.tscn"
const TOWN := "res://scenes/town/Town.tscn"

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

	# Auto-load an existing save so Continue / Inventory work across launches.
	if GameState.player_build == null and SaveSystem.has_save():
		var loaded := SaveSystem.load_build()
		if loaded != null:
			GameState.player_build = loaded

	# Town (v0.7) is the hub: shop, respec, gear, abilities, and the lobby all
	# live there — the title screen just gets you a character and in.
	if GameState.has_character():
		var c := ClassSystem.resolve(GameState.player_build)
		root.add_child(_menu_button("Continue — %s (Lv %d %s)" % [
			GameState.player_build.character_name, c["total_level"], c["title"]], _on_continue))
	root.add_child(_menu_button("New Character", _on_new_character))
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

func _on_continue() -> void:
	get_tree().change_scene_to_file(TOWN)

func _on_new_character() -> void:
	get_tree().change_scene_to_file(CHARACTER_CREATION)

func _on_quit() -> void:
	get_tree().quit()
