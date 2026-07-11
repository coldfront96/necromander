extends Control
## Inventory & equipment. Equip gear to boost combat numbers (the lateral power
## axis, DESIGN.md 3.7). Changes persist immediately, and if we're in a live
## session the server is told so its combat math uses the new gear.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const TOWN := "res://scenes/town/Town.tscn"

var build: CharacterBuild
var stats_label: Label
var equip_box: VBoxContainer
var bag_box: VBoxContainer

func _ready() -> void:
	build = GameState.player_build
	if build == null:
		get_tree().change_scene_to_file(MAIN_MENU)
		return

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

	var c := ClassSystem.resolve(build)
	var header := Label.new()
	header.text = "%s the %s — Gear" % [build.character_name, c["title"]]
	header.add_theme_font_size_override("font_size", 26)
	col.add_child(header)

	stats_label = Label.new()
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	col.add_child(stats_label)

	col.add_child(_divider())
	col.add_child(_heading("Equipped"))
	equip_box = VBoxContainer.new()
	equip_box.add_theme_constant_override("separation", 6)
	col.add_child(equip_box)

	col.add_child(_divider())
	col.add_child(_heading("Bag"))
	bag_box = VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", 6)
	col.add_child(bag_box)

	col.add_child(_divider())
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(func(): get_tree().change_scene_to_file(TOWN))
	col.add_child(back)

	_refresh()

func _refresh() -> void:
	var totals := build.equipped_stats()
	if totals.is_empty():
		stats_label.text = "Total gear bonus: none yet — equip something."
	else:
		var parts: Array = []
		for k in totals.keys():
			parts.append("+%d %s" % [int(totals[k]), LootSystem.stat_label(k)])
		stats_label.text = "Total gear bonus:  " + "   ".join(parts)

	# --- Equipped slots
	for child in equip_box.get_children():
		child.queue_free()
	for slot in CharacterBuild.GEAR_SLOTS:
		var item: Dictionary = build.equipment.get(slot, {})
		if item.is_empty():
			var empty := Label.new()
			empty.text = "%s:  (empty)" % slot.capitalize()
			empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
			equip_box.add_child(empty)
		else:
			var btn := _item_button(item, "%s — tap to unequip" % slot.capitalize())
			btn.pressed.connect(func(): _unequip(slot))
			equip_box.add_child(btn)

	# --- Bag
	for child in bag_box.get_children():
		child.queue_free()
	if build.inventory.is_empty():
		var empty := Label.new()
		empty.text = "Empty. Kill dummies in a run to find loot."
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
		bag_box.add_child(empty)
	else:
		for item in build.inventory:
			var captured: Dictionary = item
			var btn := _item_button(item, "tap to equip")
			btn.pressed.connect(func(): _equip(captured))
			bag_box.add_child(btn)

func _equip(item: Dictionary) -> void:
	build.equip_item(item)
	_commit()

func _unequip(slot: String) -> void:
	build.unequip(slot)
	_commit()

func _commit() -> void:
	GameState.save()
	# If we're in a live session, the server needs the new gear for combat.
	if NetworkManager.is_active():
		NetworkManager.push_local_update()
	_refresh()

# ---------------------------------------------------------------- ui helpers
func _item_button(item: Dictionary, hint: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 56)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", LootSystem.rarity_color(item.get("rarity", "common")))
	b.text = "%s   [%s]   %s" % [item.get("name", "Item"), "  ".join(LootSystem.stat_lines(item)), hint]
	return b

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	return l

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.3, 0.25, 0.4)
	line.custom_minimum_size = Vector2(0, 2)
	return line
