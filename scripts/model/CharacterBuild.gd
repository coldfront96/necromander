class_name CharacterBuild
extends Resource

## The running record of a character. A build is NOT a fixed class — the class
## identity is *derived* from the set of Aspects invested in. See DESIGN.md 3.2.

@export var character_name: String = "Unnamed"
@export var race: String = "Human"

## Aspect ID (e.g. "ARCANE") -> levels invested. The heart of the build.
@export var aspect_levels: Dictionary = {}

## Ability names the player has chosen to keep ACTIVE on the hotbar. The pool of
## *known* abilities is derived from the build (ClassSystem.known_abilities);
## this is just the equipped subset. See DESIGN.md 3.5.
@export var loadout: Array = []

## Infinite, horizontal post-cap progression (paragon-style). Grants loadout
## slots (capped) and cosmetics — never raw power. See DESIGN.md 3.7.
@export var ascension_rank: int = 0

## Vertical level cap. Past this, only Ascension rank grows.
const LEVEL_CAP := 60
const BASE_SLOTS := 3
## PvP-sanity ceiling on how many extra slots Ascension can ever grant.
const MAX_ASCENSION_SLOTS := 4

## True once the character has hit the vertical cap and can only Ascend further.
func at_level_cap() -> bool:
	return total_level() >= LEVEL_CAP

## How many abilities may be active at once. Grows slowly with level, plus a
## capped contribution from Ascension. Tunable — see DESIGN.md 3.7.
func max_loadout_slots() -> int:
	var capped_level := min(total_level(), LEVEL_CAP)
	var from_levels := int(capped_level / 10)            # +1 every 10 levels (0..6)
	var from_ascension := min(int(ascension_rank / 2), MAX_ASCENSION_SLOTS)
	return BASE_SLOTS + from_levels + from_ascension

func is_equipped(ability_name: String) -> bool:
	return loadout.has(ability_name)

## Equip an ability into an active slot. Returns false if slots are full.
func equip(ability_name: String) -> bool:
	if is_equipped(ability_name):
		return true
	if loadout.size() >= max_loadout_slots():
		return false
	loadout.append(ability_name)
	return true

func unequip(ability_name: String) -> void:
	loadout.erase(ability_name)

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
	copy.loadout = loadout.duplicate()
	copy.ascension_rank = ascension_rank
	return copy

func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"race": race,
		"aspect_levels": aspect_levels.duplicate(true),
		"loadout": loadout.duplicate(),
		"ascension_rank": ascension_rank,
	}

static func from_dict(d: Dictionary) -> CharacterBuild:
	var b := CharacterBuild.new()
	b.character_name = d.get("character_name", "Unnamed")
	b.race = d.get("race", "Human")
	b.aspect_levels = (d.get("aspect_levels", {}) as Dictionary).duplicate(true)
	b.loadout = (d.get("loadout", []) as Array).duplicate()
	b.ascension_rank = int(d.get("ascension_rank", 0))
	return b
