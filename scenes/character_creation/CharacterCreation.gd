extends Control
## Character creation + the signature "deepen vs mix" level-up loop, all on one
## screen so the core fantasy is immediately playable. Choose Race + a starting
## Aspect, then invest level-ups by deepening an Aspect or mixing in a new one.
## The emergent class title updates live (DESIGN.md 3.2–3.4).

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const LOADOUT := "res://scenes/loadout/Loadout.tscn"
const RACES := ["Human", "Elf", "Dwarf", "Orc", "Halfling", "Tiefling"]

var build: CharacterBuild
var name_edit: LineEdit
var race_option: OptionButton
var class_label: Label
var tagline_label: Label
var tier_label: Label
var aspect_lines: Label
var abilities_label: Label
var identity_prompt: Label
var identity_box: VBoxContainer
var options_box: VBoxContainer
var confirm_button: Button

func _ready() -> void:
	build = CharacterBuild.new()

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	# Pad content away from the screen edge; the column lives inside the margin.
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	col.add_child(_header("Forge Your Character"))

	# --- Name
	col.add_child(_label("Name"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Enter a name"
	name_edit.text = "Adventurer"
	name_edit.text_changed.connect(func(t): build.character_name = t)
	build.character_name = name_edit.text
	col.add_child(name_edit)

	# --- Race
	col.add_child(_label("Race"))
	race_option = OptionButton.new()
	for r in RACES:
		race_option.add_item(r)
	race_option.item_selected.connect(func(i): build.race = RACES[i])
	build.race = RACES[0]
	col.add_child(race_option)

	col.add_child(_divider())

	# --- Live class readout
	class_label = _header("Wanderer")
	class_label.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	col.add_child(class_label)

	tagline_label = _label("Choose a starting path below.")
	tagline_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	col.add_child(tagline_label)

	tier_label = _label("")
	col.add_child(tier_label)

	aspect_lines = _label("")
	col.add_child(aspect_lines)

	abilities_label = _label("")
	abilities_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	col.add_child(abilities_label)

	# --- Identity picker: abilities unlock automatically, but WHO you are is your
	# choice. Only shown once you qualify for more than one identity.
	identity_prompt = _label("Identity (you choose who you are):")
	col.add_child(identity_prompt)
	identity_box = VBoxContainer.new()
	identity_box.add_theme_constant_override("separation", 6)
	col.add_child(identity_box)

	col.add_child(_divider())

	# --- The fork in the road
	var prompt := _label("Invest your next level:")
	prompt.add_theme_font_size_override("font_size", 20)
	col.add_child(prompt)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	col.add_child(options_box)

	col.add_child(_divider())

	# --- Footer actions
	confirm_button = Button.new()
	confirm_button.text = "Confirm & Choose Abilities"
	confirm_button.custom_minimum_size = Vector2(0, 56)
	confirm_button.pressed.connect(_on_confirm)
	col.add_child(confirm_button)

	var back := Button.new()
	back.text = "Back to Menu"
	back.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU))
	col.add_child(back)

	_refresh()

# ---------------------------------------------------------------- core update
func _refresh() -> void:
	var has_started := build.total_level() > 0
	var c := ClassSystem.resolve(build)

	if has_started:
		class_label.text = "%s  (Lv %d)" % [c["title"], c["total_level"]]
		tagline_label.text = c["tagline"]
		tier_label.text = "Hybrid tier: %d   ·   Path: %s" % [
			c["tier"], " + ".join(_pretty_aspects(c["aspect_set"]))]
		aspect_lines.text = _aspect_breakdown() + "\n" + _power_line()
		abilities_label.text = "Abilities: " + (", ".join(c["abilities"]) if not c["abilities"].is_empty() else "—")
	else:
		class_label.text = "Wanderer"
		tagline_label.text = "Choose a starting path below."
		tier_label.text = ""
		aspect_lines.text = ""
		abilities_label.text = ""

	confirm_button.disabled = not has_started
	_rebuild_identity()
	_rebuild_options(has_started)

## Identity picker. Abilities unlock automatically (the discovery); the player
## chooses which class they present as. Hidden when there's no real choice yet.
func _rebuild_identity() -> void:
	for child in identity_box.get_children():
		child.queue_free()
	var identities := ClassSystem.qualifying_identities(build)
	# Only a choice worth showing once you qualify for 2+ identities.
	var show := identities.size() > 1
	identity_prompt.visible = show
	identity_box.visible = show
	if not show:
		return
	var active := ClassSystem.active_identity_key(build)
	for entry in identities:
		var key: String = entry["key"]
		var is_active := key == active
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = is_active
		btn.custom_minimum_size = Vector2(0, 44)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var mark := "● " if is_active else "○ "
		var tags := ""
		if entry["aspects"] == 1:
			tags += "  (base)"
		if entry["is_default"]:
			tags += "  ★ emergent"
		btn.text = "%s%s%s" % [mark, entry["title"], tags]
		btn.pressed.connect(func(): _choose_identity(key, entry["is_default"]))
		identity_box.add_child(btn)

func _choose_identity(key: String, is_default: bool) -> void:
	# Selecting the emergent default clears the override so it keeps auto-tracking.
	build.chosen_identity = "" if is_default else key
	_refresh()

## Show every fork: at creation only the 3 starting Aspects; after that, every
## Aspect (deepen existing or mix new), each previewing the resulting class.
func _rebuild_options(has_started: bool) -> void:
	for child in options_box.get_children():
		child.queue_free()

	# No hard cap — leveling continues forever (DESIGN.md 3.7). Past the soft cap
	# we just note that raw level power has mostly flattened.
	if build.past_soft_cap():
		var note := _label("Past soft cap (%d): each level now adds little raw power — lean on gear, build synergy & Ascension." % CharacterBuild.LEVEL_SOFT_CAP)
		note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		options_box.add_child(note)

	var candidate_ids: Array
	if not has_started:
		candidate_ids = ClassSystem.starting_aspects()
	else:
		candidate_ids = ClassSystem.all_aspect_ids()

	for id in candidate_ids:
		var preview := ClassSystem.preview_invest(build, id)
		var verb := "Mix in" if preview.get("is_new_aspect", true) else "Deepen"
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 56)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var becomes: String = preview["title"]
		btn.text = "%s %s  →  %s" % [verb, ClassSystem.aspect_display(id), becomes]
		if not preview.get("is_known", false):
			btn.text += "  (uncharted)"
		btn.pressed.connect(func(): _invest(id))
		options_box.add_child(btn)

func _invest(aspect_id: String) -> void:
	build.invest(aspect_id, 1)
	_refresh()

# ---------------------------------------------------------------- confirm
func _on_confirm() -> void:
	if build.character_name.strip_edges() == "":
		build.character_name = "Adventurer"
	GameState.set_character(build)
	get_tree().change_scene_to_file(LOADOUT)

# ---------------------------------------------------------------- ui helpers
func _aspect_breakdown() -> String:
	var parts: Array = []
	for id in build.aspect_set():
		parts.append("%s %d" % [ClassSystem.aspect_display(id), build.level_in(id)])
	return "Investments:  " + ("   ".join(parts) if not parts.is_empty() else "—")

func _power_line() -> String:
	var pct := int(round(build.level_power_ratio() * 100.0))
	return "Level power: %d  (%d%% of the curve spent — flattens as you climb)" % [
		int(build.level_power()), pct]

func _pretty_aspects(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(ClassSystem.aspect_display(id))
	return out

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	return l

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.3, 0.25, 0.4)
	line.custom_minimum_size = Vector2(0, 2)
	return line
