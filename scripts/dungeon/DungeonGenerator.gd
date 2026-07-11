class_name DungeonGenerator
extends RefCounted
## v0.5 — deterministic, seed-driven dungeon layout generation.
##
## Pure data, no scene nodes: given the same seed, every peer derives the
## *identical* layout, so the authoritative server only has to share one int —
## geometry never crosses the wire. Everything dynamic (positions, enemy HP,
## loot) stays server-owned as before (DESIGN.md 4); the layout is just the
## shared board everyone agrees on.
##
## Shape: a random walk over a small grid places rooms; walked edges become
## corridors. BFS from the spawn room assigns each room a **depth**, which
## drives difficulty and loot quality — the farther you push, the harder it
## bites and the better it drops. The deepest room holds the exit portal.

const GRID := 5                  # cells per side of the placement grid
const CELL := 760.0              # world-space size of one grid cell
const ROOM_MIN := 460.0          # room edge length range (centered in cell)
const ROOM_MAX := 640.0
const CORRIDOR_WIDTH := 170.0
const MIN_ROOMS := 7
const MAX_ROOMS := 10
const ENEMY_CLEARANCE := 80.0    # keep spawns off the walls

## Generate a full layout. Returns:
## {
##   rooms:      [ { rect: Rect2, cell: Vector2i, depth: int, kind: String } ]
##   corridors:  [ Rect2 ]
##   walk_rects: [ Rect2 ]                    # rooms + corridors, for collision
##   spawn: int, exit: int                    # indices into rooms
##   enemies:    [ { pos: Vector2, room: int, depth: int, boss: bool } ]
##   portal_pos: Vector2
##   bounds:     Rect2                        # union of all floor, for minimap
## }
static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# --- 1. Random-walk placement: cells become rooms, walked edges corridors.
	var start := Vector2i(GRID / 2, GRID / 2)
	var cells: Array[Vector2i] = [start]
	var adj := {}                        # Vector2i -> Array[Vector2i]
	adj[start] = []
	var target := rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	var cur := start
	var guard := 400
	while cells.size() < target and guard > 0:
		guard -= 1
		var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
		var step: Vector2i = dirs[rng.randi_range(0, 3)]
		var nxt := cur + step
		if nxt.x < 0 or nxt.y < 0 or nxt.x >= GRID or nxt.y >= GRID:
			continue
		if not cells.has(nxt):
			cells.append(nxt)
			adj[nxt] = []
		if not (adj[cur] as Array).has(nxt):
			adj[cur].append(nxt)
			adj[nxt].append(cur)
		# Mostly keep walking; sometimes jump back to a visited cell so the
		# dungeon branches instead of being one long snake.
		cur = nxt if rng.randf() < 0.7 else cells[rng.randi_range(0, cells.size() - 1)]

	# --- 2. BFS depths from spawn — depth is the difficulty/loot dial.
	var depth := {start: 0}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n in adj[c]:
			if not depth.has(n):
				depth[n] = depth[c] + 1
				queue.append(n)

	# --- 3. Rooms: sized randomly, centered in their cell (centers stay
	# grid-aligned so every corridor is a straight rect — no L-bends needed).
	var rooms: Array = []
	var cell_index := {}                 # Vector2i -> index into rooms
	for cell in cells:
		var center := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
		var w := rng.randf_range(ROOM_MIN, ROOM_MAX)
		var h := rng.randf_range(ROOM_MIN, ROOM_MAX)
		cell_index[cell] = rooms.size()
		rooms.append({
			"rect": Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)),
			"cell": cell,
			"depth": int(depth.get(cell, 0)),
			"kind": "combat",
		})
	var exit_idx := 0
	for i in rooms.size():
		if int(rooms[i]["depth"]) > int(rooms[exit_idx]["depth"]):
			exit_idx = i
	var spawn_idx: int = cell_index[start]
	rooms[spawn_idx]["kind"] = "spawn"
	rooms[exit_idx]["kind"] = "exit"

	# --- 4. Corridors: one straight rect per walked edge, spanning between the
	# two room centers so it always overlaps both floors (seamless collision).
	var corridors: Array = []
	var seen := {}
	for cell in adj.keys():
		for n in adj[cell]:
			var key := _edge_key(cell, n)
			if seen.has(key):
				continue
			seen[key] = true
			var a: Vector2 = (rooms[cell_index[cell]]["rect"] as Rect2).get_center()
			var b: Vector2 = (rooms[cell_index[n]]["rect"] as Rect2).get_center()
			corridors.append(_corridor_rect(a, b))

	# --- 5. Enemy spawns: none in the spawn room; deeper rooms pack more and
	# meaner husks; the exit room adds a boss guarding the portal.
	var enemies: Array = []
	for i in rooms.size():
		if i == spawn_idx:
			continue
		var room: Dictionary = rooms[i]
		var d: int = room["depth"]
		var count: int = clampi(1 + d, 2, 5)
		for _j in count:
			enemies.append({
				"pos": _point_in(room["rect"], rng, ENEMY_CLEARANCE),
				"room": i, "depth": d, "boss": false,
			})
		if i == exit_idx:
			enemies.append({
				"pos": (room["rect"] as Rect2).get_center() + Vector2(0, -120),
				"room": i, "depth": d, "boss": true,
			})

	# --- 6. Bounds for the minimap.
	var bounds: Rect2 = rooms[0]["rect"]
	var walk_rects: Array = []
	for room in rooms:
		walk_rects.append(room["rect"])
		bounds = bounds.merge(room["rect"])
	for c in corridors:
		walk_rects.append(c)
		bounds = bounds.merge(c)

	return {
		"rooms": rooms,
		"corridors": corridors,
		"walk_rects": walk_rects,
		"spawn": spawn_idx,
		"exit": exit_idx,
		"enemies": enemies,
		"portal_pos": (rooms[exit_idx]["rect"] as Rect2).get_center(),
		"bounds": bounds,
	}

## True if a body of the given radius can stand at p — inside any floor rect
## with its full radius. Corridors overlap the rooms they join, so crossing a
## seam is always legal in at least one rect.
static func walkable(layout: Dictionary, p: Vector2, radius: float) -> bool:
	for r in layout["walk_rects"]:
		if (r as Rect2).grow(-radius).has_point(p):
			return true
	return false

## Index of the room containing p, or -1 (e.g. mid-corridor).
static func room_at(layout: Dictionary, p: Vector2) -> int:
	for i in layout["rooms"].size():
		if (layout["rooms"][i]["rect"] as Rect2).has_point(p):
			return i
	return -1

static func _corridor_rect(a: Vector2, b: Vector2) -> Rect2:
	var half := Vector2(CORRIDOR_WIDTH, CORRIDOR_WIDTH) * 0.5
	var tl := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - half
	return Rect2(tl, (b - a).abs() + half * 2.0)

static func _point_in(rect: Rect2, rng: RandomNumberGenerator, margin: float) -> Vector2:
	var inner := rect.grow(-margin)
	return Vector2(
		rng.randf_range(inner.position.x, inner.end.x),
		rng.randf_range(inner.position.y, inner.end.y))

static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var s := [a, b]
	s.sort()
	return "%s|%s" % [s[0], s[1]]
