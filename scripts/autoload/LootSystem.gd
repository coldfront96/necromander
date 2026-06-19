extends Node
## Autoload. Data-driven loot generation. Rolls a base + rarity + affixes into an
## item instance (a plain Dictionary so it serializes for save files and RPCs).
## Gear is the lateral power axis the soft-cap model relies on (DESIGN.md 3.7) —
## it scales without the level cap. Adding items is a data change (data/items.json).

const ITEMS_PATH := "res://data/items.json"
const STAT_LABELS := {"damage_pct": "% Damage", "heal_pct": "% Healing", "max_hp": "Max HP"}

var bases: Dictionary = {}
var rarities: Dictionary = {}
var affixes: Dictionary = {}
var _seq: int = 0

func _ready() -> void:
	var f := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		push_error("LootSystem: could not open %s" % ITEMS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("LootSystem: items.json is not a JSON object")
		return
	bases = parsed.get("bases", {})
	rarities = parsed.get("rarities", {})
	affixes = parsed.get("affixes", {})

## Roll a fresh item instance scaled by item level.
func roll_drop(ilvl: int) -> Dictionary:
	var rarity := _weighted_rarity()
	var base_name := _random_key(bases)
	var base: Dictionary = bases[base_name]
	var r: Dictionary = rarities[rarity]
	var mult: float = r.get("mult", 1.0)
	var scale := mult * (1.0 + 0.12 * float(max(ilvl, 1) - 1))

	var stats := {}
	# Primary stat from the base type.
	var primary: String = base["stat"]
	stats[primary] = round(float(base["base"]) * scale)
	# Random affixes.
	var affix_count := int(r.get("affixes", 0))
	var affix_keys := affixes.keys()
	for i in affix_count:
		var key: String = affix_keys[randi() % affix_keys.size()]
		var a: Dictionary = affixes[key]
		var roll := randf_range(float(a["min"]), float(a["max"])) * mult
		stats[key] = round(float(stats.get(key, 0.0)) + roll)

	_seq += 1
	return {
		"id": "%d_%d" % [Time.get_ticks_msec(), _seq],
		"base": base_name,
		"slot": base["slot"],
		"rarity": rarity,
		"ilvl": max(ilvl, 1),
		"stats": stats,
		"name": "%s %s" % [rarity.capitalize(), base_name],
	}

func _weighted_rarity() -> String:
	var total := 0.0
	for k in rarities.keys():
		total += float(rarities[k].get("weight", 0))
	var pick := randf() * total
	for k in rarities.keys():
		pick -= float(rarities[k].get("weight", 0))
		if pick <= 0.0:
			return k
	return rarities.keys()[0]

func _random_key(d: Dictionary) -> String:
	var keys := d.keys()
	return keys[randi() % keys.size()]

# ---------------------------------------------------------------- presentation
func rarity_color(rarity: String) -> Color:
	var hex: String = rarities.get(rarity, {}).get("color", "ffffff")
	return Color.html(hex)

func stat_label(stat_key: String) -> String:
	return STAT_LABELS.get(stat_key, stat_key)

## Human-readable stat lines for an item, e.g. ["+12 % Damage", "+15 Max HP"].
func stat_lines(item: Dictionary) -> Array:
	var lines: Array = []
	var stats: Dictionary = item.get("stats", {})
	for k in stats.keys():
		lines.append("+%d %s" % [int(stats[k]), stat_label(k)])
	return lines
