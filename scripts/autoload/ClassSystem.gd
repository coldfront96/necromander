extends Node
## Autoload. The class-mixing engine. Loads the data-driven registry and resolves
## a CharacterBuild's emergent class identity. Adding classes/aspects is a pure
## data change in data/combinations.json — this engine never needs editing for
## new combinations. See DESIGN.md section 3.

const REGISTRY_PATH := "res://data/combinations.json"

## Identity affinity: your chosen identity grants a small bonus to abilities
## drawn from its Aspects — real, but deliberately non-dominant so identity is a
## meaningful choice, never the whole game. Scales with your tier in that
## identity, hard-capped. (DESIGN.md 3.3.) Tunable.
const AFFINITY_PER_TIER := 2  ## % bonus per identity tier
const AFFINITY_CAP := 10      ## max % the affinity can ever reach

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

## Resolve the active class for a build. Abilities unlock automatically from the
## build's Aspects, but the *identity* is the player's choice: their chosen
## identity if still valid, otherwise the emergent default (the most specific
## class their Aspects form). See DESIGN.md 3.3.
func resolve(build: CharacterBuild) -> Dictionary:
	var key := active_identity_key(build)
	var entry: Dictionary = classes.get(key, {})
	var req := _aspects_of(key)
	var tier := _entry_tier(build, req) if not req.is_empty() else 0
	return {
		"title": entry.get("title", "Wanderer"),
		"tagline": entry.get("tagline", "An undefined path."),
		"abilities": entry.get("abilities", []),
		"tier": tier,
		"identity_key": key,
		"aspect_set": build.aspect_set(),
		"is_known": classes.has(key),
		"total_level": build.total_level(),
		"is_default_identity": build.chosen_identity == "" or build.chosen_identity == _default_identity_key(build),
		"affinity": identity_affinity(build),
	}

## The bonus granted by the build's current chosen identity. Applies to abilities
## whose source Aspects are within the identity's Aspect set. Empty for Wanderer.
func identity_affinity(build: CharacterBuild) -> Dictionary:
	var key := active_identity_key(build)
	if key == "":
		return {}
	var entry: Dictionary = classes.get(key, {})
	var req := _aspects_of(key)
	return {
		"identity": entry.get("title", key),
		"bonus_pct": affinity_pct_for_tier(_entry_tier(build, req)),
		"scope_aspects": req,
		"passive": entry.get("affinity", "Sharper command of your chosen path."),
	}

## The affinity % for a given identity tier (shared so the picker can preview it).
func affinity_pct_for_tier(tier: int) -> int:
	return min(max(tier, 0) * AFFINITY_PER_TIER, AFFINITY_CAP)

## Does an ability (by its source class key) benefit from the active affinity?
## True when the ability's source Aspects are all within the identity's Aspects.
func ability_gets_affinity(build: CharacterBuild, source_key: String) -> bool:
	var identity := active_identity_key(build)
	if identity == "":
		return false
	var identity_aspects := _aspects_of(identity)
	for a in _aspects_of(source_key):
		if not identity_aspects.has(a):
			return false
	return true

## The class key the build presents as: the player's choice if still valid,
## else the emergent default.
func active_identity_key(build: CharacterBuild) -> String:
	if build.aspect_levels.is_empty():
		return ""
	var chosen := build.chosen_identity
	if chosen != "" and classes.has(chosen) and _build_has_all(build, _aspects_of(chosen)):
		return chosen
	return _default_identity_key(build)

## The emergent default identity = the most specific registered class the build
## qualifies for (most Aspects; tie-break highest tier). This is the same result
## the old fully-automatic model produced.
func _default_identity_key(build: CharacterBuild) -> String:
	var best := ""
	var best_size := 0
	var best_tier := -1
	for key in classes.keys():
		var req := _aspects_of(key)
		if not _build_has_all(build, req):
			continue
		var t := _entry_tier(build, req)
		if t <= 0:
			continue
		var size := req.size()
		if size > best_size or (size == best_size and t > best_tier):
			best_size = size
			best_tier = t
			best = key
	return best

## Every class identity the build currently qualifies to present as (base classes
## for each Aspect, plus every hybrid whose Aspects you hold). Powers the identity
## picker. Sorted simple→complex. Each: { key, title, aspects, tier, is_default }.
func qualifying_identities(build: CharacterBuild) -> Array:
	var default_key := _default_identity_key(build)
	var out: Array = []
	for key in classes.keys():
		var req := _aspects_of(key)
		if not _build_has_all(build, req):
			continue
		var tier := _entry_tier(build, req)
		if tier <= 0:
			continue
		out.append({
			"key": key,
			"title": classes[key].get("title", key),
			"aspects": req.size(),
			"tier": tier,
			"is_default": key == default_key,
		})
	out.sort_custom(func(a, b): return a["aspects"] < b["aspects"] or (a["aspects"] == b["aspects"] and a["title"] < b["title"]))
	return out

## Clear a chosen identity the build no longer qualifies for (e.g. after respec).
func prune_identity(build: CharacterBuild) -> void:
	if build.chosen_identity == "":
		return
	if not classes.has(build.chosen_identity) or not _build_has_all(build, _aspects_of(build.chosen_identity)):
		build.chosen_identity = ""

## Preview what class you'd become if you invested the next level into `aspect_id`.
## Always previews the EMERGENT default (ignores a locked identity) so the fork
## always teases the new class the mix could open. (DESIGN.md 3.2 / 3.3.)
func preview_invest(build: CharacterBuild, aspect_id: String) -> Dictionary:
	var hypothetical := build.duplicate_build()
	hypothetical.chosen_identity = ""  # show the discovery, not the locked title
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

## The Aspect ids of a combination key, as a plain Array. (String.split returns
## a PackedStringArray; we normalize so it slots into Array-typed params.)
func _aspects_of(key: String) -> Array:
	if key == "":
		return []
	return Array(key.split(","))

## Every ability the build currently knows, with its source class and tier.
## Returns an Array of { name, tier, source_key, source_title }.
func known_abilities(build: CharacterBuild) -> Array:
	var out: Array = []
	for key in classes.keys():
		var required := _aspects_of(key)
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
