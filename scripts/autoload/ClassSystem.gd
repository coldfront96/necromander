extends Node
## Autoload. The class-mixing engine. Loads the data-driven registry and resolves
## a CharacterBuild's emergent class identity. Adding classes/aspects is a pure
## data change in data/combinations.json — this engine never needs editing for
## new combinations. See DESIGN.md section 3.

const REGISTRY_PATH := "res://data/combinations.json"

var aspects: Dictionary = {}   # id -> { display, blurb, starting }
var classes: Dictionary = {}   # combination_key -> { title, tagline, abilities }

func _ready() -> void:
	_load_registry()

func _load_registry() -> void:
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		push_error("ClassSystem: could not open %s" % REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ClassSystem: registry is not a JSON object")
		return
	aspects = parsed.get("aspects", {})
	classes = parsed.get("classes", {})

## The Aspects offered at character creation.
func starting_aspects() -> Array:
	var out: Array = []
	for id in aspects.keys():
		if (aspects[id] as Dictionary).get("starting", false):
			out.append(id)
	out.sort()
	return out

func all_aspect_ids() -> Array:
	var keys := aspects.keys()
	keys.sort()
	return keys

func aspect_display(id: String) -> String:
	return (aspects.get(id, {}) as Dictionary).get("display", id)

## Resolve the current class for a build. Returns a dictionary describing the
## emergent identity, including tier and the next abilities unlocking.
func resolve(build: CharacterBuild) -> Dictionary:
	var key := build.combination_key()
	var entry: Dictionary = classes.get(key, {})
	var title: String = entry.get("title", "Wanderer")
	var tier := build.hybrid_tier()
	return {
		"title": title,
		"tagline": entry.get("tagline", "An undefined path."),
		"abilities": entry.get("abilities", []),
		"tier": tier,
		"combination_key": key,
		"aspect_set": build.aspect_set(),
		"is_known": classes.has(key),
		"total_level": build.total_level(),
	}

## Preview what class you'd become if you invested the next level into `aspect_id`.
## Powers the "deepen vs mix" level-up screen (DESIGN.md 3.2 / roadmap v0.1).
func preview_invest(build: CharacterBuild, aspect_id: String) -> Dictionary:
	var hypothetical := build.duplicate_build()
	hypothetical.invest(aspect_id, 1)
	var result := resolve(hypothetical)
	result["is_new_aspect"] = not build.has_aspect(aspect_id)
	return result

## All possible next-level outcomes (every deepen + every available mix),
## so the UI can show every fork in the road at once.
func level_up_options(build: CharacterBuild) -> Array:
	var options: Array = []
	for id in all_aspect_ids():
		options.append({
			"aspect_id": id,
			"aspect_display": aspect_display(id),
			"result": preview_invest(build, id),
		})
	return options

# ================================================================ loadouts
# The KNOWN ability pool is derived, not stored: any class entry whose required
# Aspects are all present in the build contributes its abilities, gated by the
# player's tier in those Aspects. Ability tier == its index in the class list
# (1st = Tier 1, ...). So a Mage who dips Divine automatically begins knowing
# the Tier-1 Necromancer ability. See DESIGN.md 3.5.

## Player's tier within a specific class entry = the MINIMUM investment among
## that entry's required Aspects (mirrors the hybrid-tier rule, DESIGN.md 3.4).
func _entry_tier(build: CharacterBuild, required: Array) -> int:
	var lowest := 1 << 30
	for aspect_id in required:
		lowest = min(lowest, build.level_in(aspect_id))
	return lowest if lowest != (1 << 30) else 0

func _build_has_all(build: CharacterBuild, required: Array) -> bool:
	for aspect_id in required:
		if not build.has_aspect(aspect_id):
			return false
	return true

## Every ability the build currently knows, with its source class and tier.
## Returns an Array of { name, tier, source_key, source_title }.
func known_abilities(build: CharacterBuild) -> Array:
	var out: Array = []
	for key in classes.keys():
		var required: Array = (key as String).split(",")
		if not _build_has_all(build, required):
			continue
		var tier := _entry_tier(build, required)
		if tier <= 0:
			continue
		var entry: Dictionary = classes[key]
		var abilities: Array = entry.get("abilities", [])
		for i in abilities.size():
			if i + 1 <= tier:  # unlocked at this entry tier
				out.append({
					"name": abilities[i],
					"tier": i + 1,
					"source_key": key,
					"source_title": entry.get("title", key),
				})
	return out

func known_ability_names(build: CharacterBuild) -> Array:
	var names: Array = []
	for a in known_abilities(build):
		names.append(a["name"])
	return names

## Drop any equipped abilities the build no longer knows (e.g. after a respec).
## Returns the number of abilities removed.
func prune_loadout(build: CharacterBuild) -> int:
	var known := known_ability_names(build)
	var kept: Array = []
	for n in build.loadout:
		if known.has(n):
			kept.append(n)
	var removed := build.loadout.size() - kept.size()
	build.loadout = kept
	return removed
