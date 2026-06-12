class_name CharacterBuild
extends Resource

## The running record of a character. A build is NOT a fixed class — the class
## identity is *derived* from the set of Aspects invested in. See DESIGN.md 3.2.

@export var character_name: String = "Unnamed"
@export var race: String = "Human"

## Aspect ID (e.g. "ARCANE") -> levels invested. The heart of the build.
@export var aspect_levels: Dictionary = {}

## Total character level == sum of all aspect investments.
func total_level() -> int:
	var sum := 0
	for v in aspect_levels.values():
		sum += int(v)
	return sum

## The set of Aspects this build draws from, sorted for stable lookup keys.
func aspect_set() -> Array:
	var keys := aspect_levels.keys()
	keys.sort()
	return keys

## Stable registry key, e.g. {ARCANE:5, DIVINE:1} -> "ARCANE,DIVINE".
func combination_key() -> String:
	return ",".join(aspect_set())

## Invest one level. Used at creation (first point) and every level-up.
## `deepen` an existing Aspect or `mix` in a brand-new one — same call.
func invest(aspect_id: String, amount: int = 1) -> void:
	aspect_levels[aspect_id] = int(aspect_levels.get(aspect_id, 0)) + amount

func level_in(aspect_id: String) -> int:
	return int(aspect_levels.get(aspect_id, 0))

func has_aspect(aspect_id: String) -> bool:
	return aspect_levels.has(aspect_id)

## Tier of the current hybrid tree = MINIMUM investment among present Aspects.
## This is the "weaker initially, unlimited ceiling" rule from DESIGN.md 3.4.
func hybrid_tier() -> int:
	if aspect_levels.is_empty():
		return 0
	var lowest := 1 << 30
	for v in aspect_levels.values():
		lowest = min(lowest, int(v))
	return lowest

func duplicate_build() -> CharacterBuild:
	var copy := CharacterBuild.new()
	copy.character_name = character_name
	copy.race = race
	copy.aspect_levels = aspect_levels.duplicate(true)
	return copy

func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"race": race,
		"aspect_levels": aspect_levels.duplicate(true),
	}

static func from_dict(d: Dictionary) -> CharacterBuild:
	var b := CharacterBuild.new()
	b.character_name = d.get("character_name", "Unnamed")
	b.race = d.get("race", "Human")
	b.aspect_levels = (d.get("aspect_levels", {}) as Dictionary).duplicate(true)
	return b
