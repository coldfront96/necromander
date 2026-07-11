extends Control
## v0.7 — the Respec tent (DESIGN.md 3.6). Spending a Respec Token refunds
## EVERY invested level as free points, then the same deepen-vs-mix fork from
## creation/level-ups re-allocates them one at a time, with live class
## previews. XP is untouched — these levels were already paid for.
##
## Leaving mid-respec is safe: free points persist, and Town gates the dungeon
## until they're all spent.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const TOWN := "res://scenes/town/Town.tscn"
const LOADOUT := "res://scenes/loadout/Loadout.tscn"

var build: CharacterBuild
var class_label: Label
var detail_label: Label
var points_label: Label
var action_box: VBoxContainer

func _ready() -> void:
	build = GameState.player_build
	if build == null:
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.12)
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
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.text = "The Respec Tent"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	col.add_child(title)

	class_label = Label.new()
	class_label.add_theme_font_size_override("font_size", 22)
	class_label.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	col.add_child(class_label)

	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	col.add_child(detail_label)

	points_label = Label.new()
	points_label.add_theme_font_size_override("font_size", 20)
	points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	col.add_child(points_label)

	col.add_child(_divider())

	action_box = VBoxContainer.new()
	action_box.add_theme_constant_override("separation", 8)
	col.add_child(action_box)

	col.add_child(_divider())
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(func(): get_tree().change_scene_to_file(TOWN))
	col.add_child(back)

	_refresh()

func _refresh() -> void:
	var c := ClassSystem.resolve(build)
	class_label.text = "%s the %s  ·  Lv %d" % [build.character_name, c["title"], build.total_level()]
	detail_label.text = _aspect_breakdown()

	for child in action_box.get_children():
		child.queue_free()

	if build.free_points > 0:
		_build_reinvest_ui()
	else:
		_build_offer_ui()

# --- State A: offer the reset -------------------------------------------------
func _build_offer_ui() -> void:
	points_label.text = "Respec Tokens: %d" % build.respec_tokens

	var explain := Label.new()
	explain.text = "Spend one token to refund all %d invested levels as free points, then walk any road you like. Banked XP and gear are untouched. (Swapping active abilities is always free — this is for changing WHO you are.)" % build.total_level()
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.add_theme_color_override("font_color", Color(0.6, 0.6, 0.72))
	action_box.add_child(explain)

	var spend := Button.new()
	spend.text = "Spend 1 Respec Token — refund %d levels" % build.total_level()
	spend.custom_minimum_size = Vector2(0, 56)
	spend.disabled = build.respec_tokens <= 0 or build.total_level() == 0
	spend.pressed.connect(_do_respec)
	action_box.add_child(spend)

	if build.respec_tokens <= 0:
		var hint := Label.new()
		hint.text = "No tokens — the Shop sells them for gold."
		hint.add_theme_color_override("font_color", Color(1.0, 0.55, 0.42))
		action_box.add_child(hint)

func _do_respec() -> void:
	if not build.respec():
		return
	# A bare build qualifies for nothing: drop the stale loadout and identity.
	ClassSystem.prune_loadout(build)
	ClassSystem.prune_identity(build)
	GameState.save()
	_refresh()

# --- State B: re-invest the refunded points ------------------------------------
func _build_reinvest_ui() -> void:
	points_label.text = "Free points to allocate: %d" % build.free_points

	if build.total_level() == 0:
		var fresh := Label.new()
		fresh.text = "A blank slate. Your first point picks your new foundation — any Aspect, not just the starting three. That's what the token bought."
		fresh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fresh.add_theme_color_override("font_color", Color(0.6, 0.6, 0.72))
		action_box.add_child(fresh)

	for id in ClassSystem.all_aspect_ids():
		var preview := ClassSystem.preview_invest(build, id)
		var verb := "Mix in" if preview.get("is_new_aspect", true) else "Deepen"
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 52)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s %s  →  %s" % [verb, ClassSystem.aspect_display(id), preview["title"]]
		if not preview.get("is_known", false):
			btn.text += "  (uncharted)"
		btn.pressed.connect(func(): _spend_point(id))
		action_box.add_child(btn)

func _spend_point(aspect_id: String) -> void:
	if not build.invest_free_point(aspect_id):
		return
	GameState.save()
	if build.free_points == 0:
		# Rebuilt: send them straight to abilities — the new road needs a kit.
		GameState.set_character(build)
		get_tree().change_scene_to_file(LOADOUT)
		return
	_refresh()

# --- helpers -------------------------------------------------------------------
func _aspect_breakdown() -> String:
	var parts: Array = []
	for id in build.aspect_set():
		parts.append("%s %d" % [ClassSystem.aspect_display(id), build.level_in(id)])
	return "Investments:  " + ("   ".join(parts) if not parts.is_empty() else "— none —")

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.3, 0.25, 0.4)
	line.custom_minimum_size = Vector2(0, 2)
	return line
