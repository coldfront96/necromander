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
