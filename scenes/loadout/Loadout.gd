extends Control
## Loadout screen. The known ability pool is derived from the build
## (ClassSystem.known_abilities); the player equips a limited number into active
## hotbar slots. Mixed-aspect abilities can fully replace base ones or sit
## alongside them — entirely the player's choice. See DESIGN.md 3.5.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const CHARACTER_CREATION := "res://scenes/character_creation/CharacterCreation.tscn"
const LOBBY := "res://scenes/lobby/Lobby.tscn"

var build: CharacterBuild
var slots_label: Label
var class_label: Label
var pool_box: VBoxContainer
var continue_button: Button

func _ready() -> void:
	build = GameState.player_build
	if build == null:
		# No character to outfit — bounce to creation.
		get_tree().change_scene_to_file(CHARACTER_CREATION)
		return
	# Keep the equipped set honest if the build changed since last visit.
	ClassSystem.prune_loadout(build)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var header := Label.new()
	header.text = "Choose Your Abilities"
	header.add_theme_font_size_override("font_size", 28)
	col.add_child(header)

	class_label = Label.new()
	class_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	class_label.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	col.add_child(class_label)

	slots_label = Label.new()
	slots_label.add_theme_font_size_override("font_size", 20)
	col.add_child(slots_label)

	var hint := Label.new()
	hint.text = "Tap an ability to equip or unequip it. Equip mixed-class abilities to replace your base kit, or blend them — your call."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.72))
	col.add_child(hint)

	col.add_child(_divider())

	pool_box = VBoxContainer.new()
	pool_box.add_theme_constant_override("separation", 6)
	col.add_child(pool_box)

	col.add_child(_divider())

	continue_button = Button.new()
	continue_button.text = "Continue to Lobby"
	continue_button.custom_minimum_size = Vector2(0, 56)
	continue_button.pressed.connect(func():
		GameState.set_character(build)  # re-emit so listeners see the loadout
		get_tree().change_scene_to_file(LOBBY))
	col.add_child(continue_button)

	var back := Button.new()
	back.text = "Back to Character"
	back.pressed.connect(func(): get_tree().change_scene_to_file(CHARACTER_CREATION))
	col.add_child(back)

	_refresh()

func _refresh() -> void:
	var c := ClassSystem.resolve(build)
	class_label.text = "%s the %s  ·  Lv %d  ·  Tier %d" % [
		build.character_name, c["title"], c["total_level"], c["tier"]]
	slots_label.text = "Active slots:  %d / %d" % [build.loadout.size(), build.max_loadout_slots()]

	for child in pool_box.get_children():
		child.queue_free()

	var known := ClassSystem.known_abilities(build)
	if known.is_empty():
		var empty := Label.new()
		empty.text = "No abilities known yet — invest a level first."
		pool_box.add_child(empty)
		return

	# Group abilities by their source class for a readable pool.
	var by_source: Dictionary = {}
	var order: Array = []
	for a in known:
		var src: String = a["source_title"]
		if not by_source.has(src):
			by_source[src] = []
			order.append(src)
		by_source[src].append(a)

	var full := build.loadout.size() >= build.max_loadout_slots()
	for src in order:
		var src_label := Label.new()
		src_label.text = src
		src_label.add_theme_font_size_override("font_size", 18)
		src_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
		pool_box.add_child(src_label)

		for a in by_source[src]:
			var ability_name: String = a["name"]
			var equipped: bool = build.is_equipped(ability_name)
			var btn := Button.new()
			btn.toggle_mode = true
			btn.button_pressed = equipped
			btn.custom_minimum_size = Vector2(0, 48)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var mark := "★ " if equipped else "   "
			btn.text = "%s[T%d] %s" % [mark, a["tier"], ability_name]
			# Grey out unequipped abilities when slots are full.
			btn.disabled = full and not equipped
			btn.pressed.connect(func(): _toggle(ability_name))
			pool_box.add_child(btn)

func _toggle(ability_name: String) -> void:
	if build.is_equipped(ability_name):
		build.unequip(ability_name)
	else:
		if not build.equip(ability_name):
			# Slots full — bounce the toggle back and tell the player.
			slots_label.text = "Slots full (%d/%d) — unequip something first." % [
				build.loadout.size(), build.max_loadout_slots()]
			_refresh()
			return
	_refresh()

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.3, 0.25, 0.4)
	line.custom_minimum_size = Vector2(0, 2)
	return line
