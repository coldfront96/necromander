extends Node
## Autoload (v0.8). Data-driven dungeon content: enemy archetypes and run tiers.
## Adding a husk variant or a difficulty tier is a data change (data/enemies.json,
## data/tiers.json) — the engine never needs editing for new content, same
## philosophy as the class registry (DESIGN.md pillar 3).

const ENEMIES_PATH := "res://data/enemies.json"
const TIERS_PATH := "res://data/tiers.json"

## Fallback so a typo in a data file degrades to a fightable enemy, not a crash.
const DEFAULT_ARCHETYPE := {
	"name": "Husk", "hp": 70.0, "dmg": 6.0, "speed": 95.0,
	"attack_range": 90.0, "keep_range": 0.0, "interval": 1.5,
	"radius": 24.0, "color": "d94d52", "ranged": false,
}
const DEFAULT_TIER := {
	"name": "Ashen Halls", "suggested_level": 1,
	"stat_mult": 1.0, "reward_mult": 1.0, "ilvl_bonus": 0, "blurb": "",
}

var archetypes: Dictionary = {}
var tiers: Array = []

func _ready() -> void:
	archetypes = _read_json(ENEMIES_PATH).get("archetypes", {})
	tiers = _read_json(TIERS_PATH).get("tiers", [])

func archetype(key: String) -> Dictionary:
	return archetypes.get(key, DEFAULT_ARCHETYPE)

func archetype_color(key: String) -> Color:
	return Color.html(archetype(key).get("color", "d94d52"))

func tier(index: int) -> Dictionary:
	if tiers.is_empty():
		return DEFAULT_TIER
	return tiers[clampi(index, 0, tiers.size() - 1)]

func tier_count() -> int:
	return maxi(tiers.size(), 1)

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DungeonData: could not open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DungeonData: %s is not a JSON object" % path)
		return {}
	return parsed
