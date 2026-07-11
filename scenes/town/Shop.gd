extends Control
## v0.7 — the Emberrest shop. Data-driven catalog (data/shop.json): adding an
## offer is a data change; only the *effect* of a new offer id needs code.
## Sells the two things the design demands first: Respec Tokens (DESIGN.md 3.6,
## the deliberate identity-change path) and a gamble cache (the classic ARPG
## gold sink, so gold keeps mattering after your gear plateaus).

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const TOWN := "res://scenes/town/Town.tscn"
const CATALOG_PATH := "res://data/shop.json"

## Gamble cache item level scales with character level, capped at the same
## ceiling dungeon drops respect — the shop must never beat the deep rooms.
const GAMBLE_ILVL_DIV := 2
const GAMBLE_MAX_ILVL := 12

var build: CharacterBuild
var offers: Array = []
var gold_label: Label
var result_label: Label
var offers_box: VBoxContainer

func _ready() -> void:
	build = GameState.player_build
	if build == null:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	_load_catalog()

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
	title.text = "The Emberrest Shop"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	col.add_child(title)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 20)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	col.add_child(gold_label)

	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(result_label)

	col.add_child(_divider())

	offers_box = VBoxContainer.new()
	offers_box.add_theme_constant_override("separation", 10)
	col.add_child(offers_box)

	col.add_child(_divider())
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(func(): get_tree().change_scene_to_file(TOWN))
	col.add_child(back)

	_refresh()

func _load_catalog() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("Shop: could not open %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Shop: shop.json is not a JSON object")
		return
	offers = parsed.get("offers", [])

func _refresh() -> void:
	gold_label.text = "Your gold: %d   ·   Respec Tokens: %d" % [build.gold, build.respec_tokens]
	for child in offers_box.get_children():
		child.queue_free()
	for offer in offers:
		offers_box.add_child(_offer_row(offer))

func _offer_row(offer: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var price := int(offer.get("price", 0))
	var buy := Button.new()
	buy.text = "%s — %d g" % [offer.get("name", "?"), price]
	buy.custom_minimum_size = Vector2(0, 52)
	buy.alignment = HORIZONTAL_ALIGNMENT_LEFT
	buy.disabled = build.gold < price
	buy.pressed.connect(func(): _buy(offer))
	row.add_child(buy)

	var desc := Label.new()
	desc.text = offer.get("desc", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.72))
	row.add_child(desc)
	return row

## Purchases are local: gold was already granted by the authoritative server
## during runs; spending it is the owner's business (like equipping gear).
func _buy(offer: Dictionary) -> void:
	var price := int(offer.get("price", 0))
	if build.gold < price:
		return
	match offer.get("id", ""):
		"respec_token":
			build.gold -= price
			build.respec_tokens += 1
			_say("Bought a Respec Token. Visit the Respec tent when you're ready to walk a new road.", Color(0.42, 1.0, 0.81))
		"gamble":
			build.gold -= price
			var ilvl := clampi(1 + build.total_level() / GAMBLE_ILVL_DIV, 1, GAMBLE_MAX_ILVL)
			var item := LootSystem.roll_drop(ilvl)
			build.inventory.append(item)
			_say("The cache held: %s  (%s)" % [item.get("name", "?"), ", ".join(LootSystem.stat_lines(item))],
				LootSystem.rarity_color(item.get("rarity", "common")))
		_:
			push_warning("Shop: unknown offer id '%s'" % offer.get("id", ""))
			return
	GameState.save()
	_refresh()

func _say(text: String, col: Color) -> void:
	result_label.text = text
	result_label.add_theme_color_override("font_color", col)

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.3, 0.25, 0.4)
	line.custom_minimum_size = Vector2(0, 2)
	return line
