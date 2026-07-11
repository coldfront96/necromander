extends Control
## v0.7 — Emberrest, the camp between runs. The hub of the target game loop
## (DESIGN.md 5): manage your character, spend your spoils, party up, dive
## again. Everything here is solo/local; multiplayer starts at the lobby.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const LOBBY := "res://scenes/lobby/Lobby.tscn"
const SHOP := "res://scenes/town/Shop.tscn"
const RESPEC := "res://scenes/town/Respec.tscn"
const LOADOUT := "res://scenes/loadout/Loadout.tscn"
const INVENTORY := "res://scenes/inventory/Inventory.tscn"

var build: CharacterBuild

func _ready() -> void:
	build = GameState.player_build
	if build == null:
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.13)
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
	title.text = "EMBERREST"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	col.add_child(title)

	var flavor := Label.new()
	flavor.text = "The last camp before the deep. Rest, trade, choose your road."
	flavor.add_theme_color_override("font_color", Color(0.65, 0.6, 0.7))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(flavor)

	col.add_child(_divider())

	# --- Character summary
	var c := ClassSystem.resolve(build)
	var who := Label.new()
	who.text = "%s the %s  ·  Lv %d" % [build.character_name, c["title"], build.total_level()]
	who.add_theme_font_size_override("font_size", 24)
	who.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	col.add_child(who)

	var wallet := Label.new()
	wallet.text = "XP %d / %d   ·   %d gold   ·   %d Respec Token%s" % [
		build.xp, build.xp_to_next(), build.gold,
		build.respec_tokens, "" if build.respec_tokens == 1 else "s"]
	wallet.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	col.add_child(wallet)

	col.add_child(_divider())

	# --- Actions. An unfinished respec gates the dungeon: a build with
	# unallocated points has no business fighting.
	var mid_respec := build.free_points > 0

	var dive := _btn("Enter the Dungeon  (party up)", func(): get_tree().change_scene_to_file(LOBBY))
	dive.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	dive.disabled = mid_respec
	col.add_child(dive)
	if mid_respec:
		var warn := Label.new()
		warn.text = "⚠ Finish your respec first — you have %d unallocated point%s." % [
			build.free_points, "" if build.free_points == 1 else "s"]
		warn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.42))
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(warn)

	col.add_child(_btn("Shop", func(): get_tree().change_scene_to_file(SHOP)))

	var respec_text := "Finish Respec  (%d points left)" % build.free_points if mid_respec \
		else "Respec  (%d token%s)" % [build.respec_tokens, "" if build.respec_tokens == 1 else "s"]
	col.add_child(_btn(respec_text, func(): get_tree().change_scene_to_file(RESPEC)))

	col.add_child(_btn("Abilities (loadout)", func(): get_tree().change_scene_to_file(LOADOUT)))
	col.add_child(_btn("Gear (inventory)", func(): get_tree().change_scene_to_file(INVENTORY)))

	col.add_child(_divider())
	col.add_child(_btn("Back to Title", func(): get_tree().change_scene_to_file(MAIN_MENU)))

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.3, 0.25, 0.4)
	line.custom_minimum_size = Vector2(0, 2)
	return line
