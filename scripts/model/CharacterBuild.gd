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

## The class identity the player chooses to present as. Abilities unlock
## automatically from your Aspects (the discovery), but WHO you are is your
## choice — pick any class you qualify for. Empty = use the emergent default
## (the most specific class your Aspects form). See DESIGN.md 3.3.
@export var chosen_identity: String = ""

## Infinite, horizontal post-soft-cap progression (paragon-style). Grants loadout
## slots (capped) and cosmetics — never raw power. See DESIGN.md 3.7.
@export var ascension_rank: int = 0

## Gear — the lateral power axis (DESIGN.md 3.7 / v0.4). Items are plain dicts so
## they serialize for save files and RPCs.
@export var inventory: Array = []            ## item dicts not currently equipped
@export var equipment: Dictionary = {}       ## slot -> item dict
@export var gold: int = 0                     ## currency (respec tokens, shop)

## Banked experience toward the next level (v0.6). XP is granted by the
## authoritative server during runs; *spending* it — the deepen-vs-mix fork —
## is always the player's choice (level_up below).
@export var xp: int = 0

const GEAR_SLOTS := ["weapon", "armor", "trinket"]

## Equip an item from inventory; any item already in that slot returns to the bag.
func equip_item(item: Dictionary) -> void:
	var slot: String = item.get("slot", "")
	if slot == "":
		return
	inventory.erase(item)
	if equipment.has(slot) and not (equipment[slot] as Dictionary).is_empty():
		inventory.append(equipment[slot])
	equipment[slot] = item

func unequip(slot: String) -> void:
	if equipment.has(slot) and not (equipment[slot] as Dictionary).is_empty():
		inventory.append(equipment[slot])
		equipment.erase(slot)

## Summed stats across all equipped items (e.g. {"damage_pct": 14, "max_hp": 30}).
func equipped_stats() -> Dictionary:
	var totals := {}
	for slot in equipment.keys():
		var item: Dictionary = equipment[slot]
		for k in (item.get("stats", {}) as Dictionary).keys():
			totals[k] = float(totals.get(k, 0.0)) + float(item["stats"][k])
	return totals


# --- Soft-cap power model (DESIGN.md 3.7) -------------------------------------
# Leveling is UNCAPPED. But the raw stat power a level contributes follows a
# diminishing curve: big gains early, asymptotically flattening toward a ceiling.
# So levels matter a lot at first, then get outshined by other power systems
# (gear, build synergy, Ascension). This keeps PvP sane — no amount of grinding
# pushes the level term past LEVEL_POWER_MAX — while never imposing a hard wall.
const LEVEL_POWER_MAX := 500.0      ## asymptotic ceiling of level's stat contribution
const LEVEL_POWER_FALLOFF := 0.972  ## per-level approach rate (closer to 1 = slower)
## The level by which the curve is ~95% spent. Past here, leveling is mostly
## about unlocking ability tiers and horizontal progression, not raw power.
const LEVEL_SOFT_CAP := 100

const BASE_SLOTS := 3
## PvP-sanity ceiling on how many extra slots Ascension can ever grant.
const MAX_ASCENSION_SLOTS := 4

## Diminishing raw stat power contributed by character level. Asymptotic to
## LEVEL_POWER_MAX — the heart of the soft-cap model.
func level_power() -> float:
	return round(LEVEL_POWER_MAX * (1.0 - pow(LEVEL_POWER_FALLOFF, total_level())))

## How "spent" the level curve is, 0..1. For UI ("levels now matter less").
func level_power_ratio() -> float:
	return 1.0 - pow(LEVEL_POWER_FALLOFF, total_level())

## True once past the soft cap — informational only; leveling still continues.
func past_soft_cap() -> bool:
	return total_level() >= LEVEL_SOFT_CAP

## How many abilities may be active at once. Grows slowly with level (capped at
## the soft cap so it stays a fair PvP lever), plus a capped Ascension bonus.
func max_loadout_slots() -> int:
	var capped_level := min(total_level(), LEVEL_SOFT_CAP)
	var from_levels := int(capped_level / 10)            # +1 every 10 levels (0..10)
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

# --- XP (v0.6) ----------------------------------------------------------------
# The cost curve grows with total level, so early levels come fast (the on-ramp)
# and later ones slow down — which pairs with level_power() flattening: past the
# soft cap you still *can* level, it just takes longer and grants mostly breadth.
const XP_BASE := 50
const XP_PER_LEVEL := 25

## XP needed to bank the next level at the current total level.
func xp_to_next() -> int:
	return XP_BASE + XP_PER_LEVEL * total_level()

func can_level_up() -> bool:
	return xp >= xp_to_next()

## Spend banked XP to invest one level — the signature deepen-vs-mix fork
## (DESIGN.md 3.2), now paid for with XP earned in runs. Returns false if the
## bank can't cover the cost. Cost is locked in before the invest, since
## investing raises total_level (and with it the *next* level's price).
func level_up(aspect_id: String) -> bool:
	var cost := xp_to_next()
	if xp < cost:
		return false
	xp -= cost
	invest(aspect_id, 1)
	return true

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
	copy.chosen_identity = chosen_identity
	copy.inventory = inventory.duplicate(true)
	copy.equipment = equipment.duplicate(true)
	copy.gold = gold
	copy.xp = xp
	return copy

func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"race": race,
		"aspect_levels": aspect_levels.duplicate(true),
		"loadout": loadout.duplicate(),
		"ascension_rank": ascension_rank,
		"chosen_identity": chosen_identity,
		"inventory": inventory.duplicate(true),
		"equipment": equipment.duplicate(true),
		"gold": gold,
		"xp": xp,
	}

static func from_dict(d: Dictionary) -> CharacterBuild:
	var b := CharacterBuild.new()
	b.character_name = d.get("character_name", "Unnamed")
	b.race = d.get("race", "Human")
	b.aspect_levels = (d.get("aspect_levels", {}) as Dictionary).duplicate(true)
	b.loadout = (d.get("loadout", []) as Array).duplicate()
	b.ascension_rank = int(d.get("ascension_rank", 0))
	b.chosen_identity = d.get("chosen_identity", "")
	b.inventory = (d.get("inventory", []) as Array).duplicate(true)
	b.equipment = (d.get("equipment", {}) as Dictionary).duplicate(true)
	b.gold = int(d.get("gold", 0))
	b.xp = int(d.get("xp", 0))
	return b
