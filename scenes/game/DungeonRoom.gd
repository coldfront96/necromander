extends Node2D
## v0.2–v0.5 — a shared, server-authoritative procedural dungeon.
##
## Authority model (DESIGN.md 4): the SERVER owns all truth — positions, HP,
## cooldowns, enemy state, and every damage/heal roll. Clients send only intent
## (steer here / cast this) and render the snapshots the server broadcasts. No
## client can move itself, hurt an enemy, or heal itself directly — it can only
## ask, and the server decides. Identity affinity (DESIGN.md 3.3) is applied
## server-side so build choices actually change your numbers.
##
## v0.5: the room is now a seed-generated dungeon (DungeonGenerator). The host
## rolls the seed; every peer derives the identical layout locally, so only
## dynamic state crosses the wire. Rooms get harder — and drop better loot —
## the deeper they sit; clear the deepest room to open the exit portal, step
## in, and the party extracts back to the lobby with a bonus reward.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const LOBBY := "res://scenes/lobby/Lobby.tscn"

# --- Movement
const SPEED := 240.0
const BROADCAST_HZ := 20.0
const AVATAR_RADIUS := 22.0

# --- Combat
const COMBAT_HZ := 10.0
const ENEMY_RADIUS := 24.0
const BOSS_RADIUS := 36.0
const ENEMY_HP := 70.0
const ENEMY_ATTACK_INTERVAL := 1.5
const ENEMY_ATTACK_RANGE := 90.0
const ENEMY_ATTACK_DAMAGE := 6.0
const ENEMY_AGGRO_RANGE := 300.0
const ENEMY_SPEED := 95.0
const ENEMY_DEPTH_HP := 0.35       # +35% HP per depth beyond the first room
const ENEMY_DEPTH_DMG := 0.20      # +20% damage per depth beyond the first
const BOSS_HP_MULT := 3.2
const BOSS_DMG_MULT := 1.6
const PLAYER_BASE_HP := 80.0
const PLAYER_RESPAWN := 3.0

# --- Loot (v0.4) — item level now scales with room depth (v0.5)
const DROP_CHANCE := 0.7
const PICKUP_RADIUS := 46.0
const LOOT_MAX_ILVL := 12

# --- Exit portal (v0.5)
const PORTAL_RADIUS := 42.0
const EXTRACT_DELAY := 3.5

# --- XP (v0.6) — party-shared: every member earns full XP on any kill, so
# co-op never devolves into kill-stealing. Depth is the multiplier, extraction
# pays a completion bonus. Spending XP (deepen vs mix) happens in-run too.
const XP_PER_KILL := 14.0
const XP_DEPTH_BONUS := 0.5        # +50% per depth beyond the first room
const XP_BOSS_MULT := 4.0
const XP_EXTRACT_BASE := 40
const XP_EXTRACT_PER_DEPTH := 30

const PALETTE := [
	Color(0.61, 0.42, 1.0), Color(0.42, 1.0, 0.81),
	Color(1.0, 0.55, 0.42), Color(1.0, 0.85, 0.4),
	Color(0.5, 0.7, 1.0), Color(1.0, 0.5, 0.7),
]
const ENEMY_COLOR := Color(0.85, 0.30, 0.32)
const BOSS_COLOR := Color(0.95, 0.20, 0.45)
const FLOOR_COLOR := Color(0.12, 0.10, 0.16)
const CORRIDOR_COLOR := Color(0.10, 0.085, 0.135)
const SPAWN_TINT := Color(0.10, 0.14, 0.14)
const EXIT_TINT := Color(0.15, 0.10, 0.19)

# --- The shared board (identical on every peer, derived from the run seed)
var layout: Dictionary

# --- Server-authoritative state (meaningful only on the host)
var positions: Dictionary = {}     # peer_id -> Vector2
var inputs: Dictionary = {}        # peer_id -> Vector2 (steering intent)
var player_hp: Dictionary = {}     # peer_id -> float
var player_max: Dictionary = {}    # peer_id -> float
var player_respawn: Dictionary = {} # peer_id -> float (countdown; >0 = dead)
var cooldowns: Dictionary = {}     # peer_id -> { ability_name: seconds_left }
var enemies: Dictionary = {}       # eid -> { pos, hp, max, alive, atk, dmg, depth, room, boss }
var ground_loot: Dictionary = {}   # loot_id -> { item, pos }
var portal_active: bool = false    # true once the exit room is cleared
var _next_loot_id: int = 0

# --- Client render state (all peers)
var targets: Dictionary = {}       # peer_id -> Vector2 (position snapshot)
var c_players: Dictionary = {}     # peer_id -> { hp, max, dead }
var c_enemies: Dictionary = {}     # eid -> { pos, hp, max, boss }
var c_loot: Dictionary = {}        # loot_id -> { pos, rarity }
var c_portal: bool = false
var avatars: Dictionary = {}       # peer_id -> Token
var enemy_tokens: Dictionary = {}  # eid -> Token
var loot_tokens: Dictionary = {}   # loot_id -> Token
var loot_log: Label

var _last_sent_input := Vector2.ZERO
var _broadcast_accum := 0.0
var _combat_accum := 0.0
var _run_over := false
var _local_cd: Dictionary = {}     # client-side predicted cooldowns for UI
var joystick: Control
var world: Node2D
var camera: Camera2D
var minimap: Minimap
var portal_token: Token
var hotbar: HBoxContainer
var status_label: Label
var banner_label: Label
var xp_label: Label
var levelup_button: Button
var levelup_panel: Control
var levelup_options: VBoxContainer
var levelup_header: Label

func _ready() -> void:
	if not NetworkManager.is_active():
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	# Every peer derives the same board from the host-rolled seed (v0.5).
	layout = DungeonGenerator.generate(NetworkManager.run_seed)

	var view := get_viewport_rect().size
	_build_world()
	_build_ui(view)

	if NetworkManager.is_server():
		var i := 0
		for id in NetworkManager.players.keys():
			_spawn_player(id, i)
			i += 1
		_spawn_enemies()
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		# Builds can change mid-run now (in-run level-ups, v0.6) — refresh the
		# server's derived stats whenever the roster re-syncs.
		NetworkManager.lobby_updated.connect(_on_roster_updated)

# ================================================================ build
func _build_world() -> void:
	# Backdrop lives on its own layer so it fills the screen wherever the
	# camera goes; the floor itself is world-space geometry.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)
	add_child(bg_layer)

	# Floors: corridors first (under), then rooms; spawn/exit rooms are tinted.
	for c in layout["corridors"]:
		add_child(_floor_rect(c, CORRIDOR_COLOR))
	for room in layout["rooms"]:
		var col := FLOOR_COLOR
		match room["kind"]:
			"spawn": col = SPAWN_TINT
			"exit": col = EXIT_TINT
		add_child(_floor_rect(room["rect"], col))

	world = Node2D.new()
	add_child(world)

	# Exit portal — sealed until the deepest room is cleared.
	portal_token = Token.new()
	portal_token.radius = 30.0
	portal_token.color = Color(0.35, 0.3, 0.45)
	portal_token.position = layout["portal_pos"]
	portal_token.set_label("Portal (sealed)")
	world.add_child(portal_token)

	camera = Camera2D.new()
	camera.position = _spawn_room_center()
	add_child(camera)
	camera.make_current()

func _floor_rect(r: Rect2, col: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = col
	cr.position = r.position
	cr.size = r.size
	return cr

func _build_ui(view: Vector2) -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var banner := Label.new()
	banner.text = "Dungeon — clear the deepest room to open the portal"
	banner.position = Vector2(20, 14)
	banner.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	ui.add_child(banner)

	status_label = Label.new()
	status_label.position = Vector2(20, 38)
	status_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	ui.add_child(status_label)

	xp_label = Label.new()
	xp_label.position = Vector2(20, 62)
	xp_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	ui.add_child(xp_label)

	loot_log = Label.new()
	loot_log.position = Vector2(20, 86)
	ui.add_child(loot_log)

	# Big center announcement (used when the run completes).
	banner_label = Label.new()
	banner_label.text = ""
	banner_label.add_theme_font_size_override("font_size", 34)
	banner_label.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.position = Vector2(0, view.y * 0.32)
	banner_label.size = Vector2(view.x, 90)
	ui.add_child(banner_label)

	minimap = Minimap.new(layout)
	minimap.position = Vector2(view.x - Minimap.MAP_SIZE.x - 16, 92)
	ui.add_child(minimap)

	joystick = preload("res://scenes/game/VirtualJoystick.gd").new()
	joystick.position = Vector2(40, view.y - 40 - 180)
	ui.add_child(joystick)

	# Hotbar from the local player's loadout (or known abilities if none equipped).
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 8)
	hotbar.position = Vector2(view.x * 0.5 - 150, view.y - 70)
	ui.add_child(hotbar)
	for ability_name in _local_hotbar_abilities():
		hotbar.add_child(_make_ability_button(ability_name))

	# The signature moment, surfaced mid-run (v0.6): lights up when banked XP
	# covers the next level; opens the deepen-vs-mix fork. The dungeon does NOT
	# pause — choosing under pressure is part of the flavor.
	levelup_button = Button.new()
	levelup_button.text = "▲ LEVEL UP!"
	levelup_button.visible = false
	levelup_button.position = Vector2(view.x - 170, view.y - 140)
	levelup_button.custom_minimum_size = Vector2(150, 52)
	levelup_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	levelup_button.pressed.connect(_open_levelup)
	ui.add_child(levelup_button)

	_build_levelup_panel(ui, view)

	var leave := Button.new()
	leave.text = "Leave"
	leave.position = Vector2(view.x - 130, 24)
	leave.custom_minimum_size = Vector2(100, 44)
	leave.pressed.connect(func():
		NetworkManager.leave()
		get_tree().change_scene_to_file(MAIN_MENU))
	ui.add_child(leave)

func _local_hotbar_abilities() -> Array:
	var build: CharacterBuild = GameState.player_build
	if build == null:
		return []
	if not build.loadout.is_empty():
		return build.loadout
	# Fallback so there's something to test even if nothing was equipped.
	var known := ClassSystem.known_ability_names(build)
	return known.slice(0, min(4, known.size()))

func _make_ability_button(ability_name: String) -> Button:
	var b := Button.new()
	b.set_meta("ability", ability_name)
	b.text = ability_name
	b.custom_minimum_size = Vector2(96, 48)
	b.pressed.connect(func(): _try_cast(ability_name))
	return b

# ================================================================ level-up (v0.6)
## The deepen-vs-mix fork, in-run. Same engine as character creation
## (ClassSystem.preview_invest); here it spends XP banked from kills.
func _build_levelup_panel(ui: CanvasLayer, view: Vector2) -> void:
	levelup_panel = Control.new()
	levelup_panel.visible = false
	levelup_panel.size = view
	ui.add_child(levelup_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_panel.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(view.x * 0.5 - 310, view.y * 0.16)
	panel.custom_minimum_size = Vector2(620, 0)
	levelup_panel.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "LEVEL UP — invest your point"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	col.add_child(title)

	levelup_header = Label.new()
	levelup_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	levelup_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	col.add_child(levelup_header)

	levelup_options = VBoxContainer.new()
	levelup_options.add_theme_constant_override("separation", 8)
	col.add_child(levelup_options)

	var later := Button.new()
	later.text = "Later (keep fighting)"
	later.custom_minimum_size = Vector2(0, 48)
	later.pressed.connect(func(): levelup_panel.visible = false)
	col.add_child(later)

func _open_levelup() -> void:
	var build: CharacterBuild = GameState.player_build
	if build == null or not build.can_level_up():
		return
	var c := ClassSystem.resolve(build)
	levelup_header.text = "%s the %s (Lv %d)   ·   XP banked: %d (next level costs %d)\nThe dungeon does not wait — choose your road." % [
		build.character_name, c.get("title", "Wanderer"), build.total_level(),
		build.xp, build.xp_to_next()]
	for child in levelup_options.get_children():
		child.queue_free()
	for id in ClassSystem.all_aspect_ids():
		var preview := ClassSystem.preview_invest(build, id)
		var verb := "Mix in" if preview.get("is_new_aspect", true) else "Deepen"
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 52)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s %s  →  %s" % [verb, ClassSystem.aspect_display(id), preview["title"]]
		if not preview.get("is_known", false):
			btn.text += "  (uncharted)"
		btn.pressed.connect(func(): _choose_level_up(id))
		levelup_options.add_child(btn)
	levelup_panel.visible = true

func _choose_level_up(aspect_id: String) -> void:
	var build: CharacterBuild = GameState.player_build
	if build == null or not build.level_up(aspect_id):
		levelup_panel.visible = false
		return
	GameState.save()
	# Tell the authoritative server: its combat math (and our max HP) must
	# reflect the new build immediately — same path gear changes use.
	NetworkManager.push_local_update()
	_refresh_hotbar()
	_fx_levelup()
	# More banked levels? Re-open with fresh previews; otherwise close.
	if build.can_level_up():
		_open_levelup()
	else:
		levelup_panel.visible = false

## Known pool may have grown (a mix can unlock a whole new tree). The equipped
## loadout is untouched, but the fallback hotbar can widen.
func _refresh_hotbar() -> void:
	for child in hotbar.get_children():
		child.queue_free()
	for ability_name in _local_hotbar_abilities():
		hotbar.add_child(_make_ability_button(ability_name))

## Local celebratory flash on our own avatar (cosmetic only).
func _fx_levelup() -> void:
	var me: Token = avatars.get(NetworkManager.local_id())
	if me == null:
		return
	var l := Label.new()
	l.text = "LEVEL UP"
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	l.position = me.position + Vector2(-46, -AVATAR_RADIUS - 58)
	world.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", l.position + Vector2(0, -50), 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)

# ================================================================ spawning (server)
func _spawn_room_center() -> Vector2:
	return (layout["rooms"][layout["spawn"]]["rect"] as Rect2).get_center()

func _spawn_player(id: int, index: int) -> void:
	positions[id] = _spawn_point(index)
	inputs[id] = Vector2.ZERO
	var build := _build_for(id)
	player_max[id] = _max_hp(build)
	player_hp[id] = player_max[id]
	player_respawn[id] = 0.0
	cooldowns[id] = {}

## Enemies come from the generated layout: deeper rooms hold more and meaner
## husks, and the exit room adds a boss guarding the portal.
func _spawn_enemies() -> void:
	var eid := 0
	for spawn in layout["enemies"]:
		var depth: int = spawn["depth"]
		var boss: bool = spawn["boss"]
		var hp := ENEMY_HP * (1.0 + ENEMY_DEPTH_HP * float(depth - 1))
		var dmg := ENEMY_ATTACK_DAMAGE * (1.0 + ENEMY_DEPTH_DMG * float(depth - 1))
		if boss:
			hp *= BOSS_HP_MULT
			dmg *= BOSS_DMG_MULT
		enemies[eid] = {
			"pos": spawn["pos"], "hp": hp, "max": hp, "alive": true,
			"atk": ENEMY_ATTACK_INTERVAL, "dmg": dmg,
			"depth": depth, "room": spawn["room"], "boss": boss,
		}
		eid += 1

func _spawn_point(index: int) -> Vector2:
	var angle := float(index) * (TAU / float(NetworkManager.MAX_PLAYERS))
	return _spawn_room_center() + Vector2(cos(angle), sin(angle)) * 110.0

func _on_player_joined(peer_id: int, _info: Dictionary) -> void:
	if NetworkManager.is_server() and not positions.has(peer_id):
		_spawn_player(peer_id, positions.size())

func _on_player_left(peer_id: int) -> void:
	for d in [positions, inputs, player_hp, player_max, player_respawn, cooldowns]:
		d.erase(peer_id)

## A peer's build changed mid-run (level-up or gear). Recompute max HP; when it
## grew, grant the difference as an immediate heal — leveling should feel good.
func _on_roster_updated(_players: Dictionary) -> void:
	if not NetworkManager.is_server():
		return
	for id in player_max.keys():
		var new_max := _max_hp(_build_for(id))
		var diff: float = new_max - player_max[id]
		if diff == 0.0:
			continue
		player_max[id] = new_max
		if diff > 0.0 and not _is_dead(id):
			player_hp[id] = min(new_max, player_hp[id] + diff)
		else:
			player_hp[id] = min(player_hp[id], new_max)

func _build_for(peer_id: int) -> CharacterBuild:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	return CharacterBuild.from_dict(info.get("build", {}))

func _max_hp(build: CharacterBuild) -> float:
	return PLAYER_BASE_HP + build.level_power() + float(build.equipped_stats().get("max_hp", 0.0))

# ================================================================ main loop
func _physics_process(delta: float) -> void:
	if not NetworkManager.is_active():
		return
	_tick_local_cd(delta)
	_handle_local_input()
	if NetworkManager.is_server() and not _run_over:
		_server_step(delta)
		_broadcast_accum += delta
		if _broadcast_accum >= 1.0 / BROADCAST_HZ:
			_broadcast_accum = 0.0
			_sync_positions.rpc(positions)
		_combat_accum += delta
		if _combat_accum >= 1.0 / COMBAT_HZ:
			_combat_accum = 0.0
			_sync_combat.rpc(_pack_players(), _pack_enemies(), _pack_loot(), portal_active)
	_render(delta)
	_update_status()

# ---- movement intent
func _input_vector() -> Vector2:
	var v := Vector2.ZERO
	if joystick:
		v += joystick.get_vector()
	v += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	return v.limit_length(1.0)

func _handle_local_input() -> void:
	if _is_local_dead() or _run_over:
		return
	var v := _input_vector()
	if v.distance_to(_last_sent_input) <= 0.04:
		return
	_last_sent_input = v
	if NetworkManager.is_server():
		inputs[1] = v
	else:
		_submit_input.rpc_id(1, v)

# ---- server simulation
func _server_step(delta: float) -> void:
	# cooldowns
	for id in cooldowns.keys():
		for ab in cooldowns[id].keys():
			cooldowns[id][ab] = max(0.0, cooldowns[id][ab] - delta)
	# player respawns — back at the entrance; the walk back is the price.
	for id in player_respawn.keys():
		if player_respawn[id] > 0.0:
			player_respawn[id] -= delta
			if player_respawn[id] <= 0.0:
				player_hp[id] = player_max[id]
				positions[id] = _spawn_point(0)
	# movement (only the living move) — walls are real now (v0.5)
	for id in positions.keys():
		if _is_dead(id):
			continue
		var intent: Vector2 = inputs.get(id, Vector2.ZERO)
		if intent != Vector2.ZERO:
			positions[id] = _slide_move(positions[id],
				intent.limit_length(1.0) * SPEED * delta, AVATAR_RADIUS)
	# enemies: dead stay dead (you *clear* a dungeon); the living chase & bite
	for eid in enemies.keys():
		var e: Dictionary = enemies[eid]
		if not e["alive"]:
			continue
		var radius: float = BOSS_RADIUS if e["boss"] else ENEMY_RADIUS
		var prey := _nearest_player(e["pos"], ENEMY_AGGRO_RANGE)
		if prey != -1:
			var to: Vector2 = positions[prey] - e["pos"]
			if to.length() > ENEMY_ATTACK_RANGE * 0.6:
				e["pos"] = _slide_move(e["pos"], to.normalized() * ENEMY_SPEED * delta, radius)
		e["atk"] -= delta
		if e["atk"] <= 0.0:
			e["atk"] = ENEMY_ATTACK_INTERVAL
			_enemy_attack(e["pos"], e["dmg"])
	# portal: any living player standing in the open portal extracts the party
	if portal_active:
		for id in positions.keys():
			if not _is_dead(id) and positions[id].distance_to(layout["portal_pos"]) <= PORTAL_RADIUS:
				_finish_run()
				break
	# Auto-pickup: hand each ground item to the nearest living player in range.
	for lid in ground_loot.keys():
		var loot: Dictionary = ground_loot[lid]
		var who := _nearest_player(loot["pos"], PICKUP_RADIUS)
		if who != -1:
			ground_loot.erase(lid)
			_award_loot(who, loot["item"])

## Move with axis-sliding collision against the dungeon floor plan: try the
## full motion, then each axis alone, so walls feel like walls, not glue.
func _slide_move(from: Vector2, motion: Vector2, radius: float) -> Vector2:
	var dest := from + motion
	if DungeonGenerator.walkable(layout, dest, radius):
		return dest
	dest = from + Vector2(motion.x, 0.0)
	if motion.x != 0.0 and DungeonGenerator.walkable(layout, dest, radius):
		return dest
	dest = from + Vector2(0.0, motion.y)
	if motion.y != 0.0 and DungeonGenerator.walkable(layout, dest, radius):
		return dest
	return from

func _nearest_player(from: Vector2, rng: float) -> int:
	var best := -1
	var best_d := rng
	for id in positions.keys():
		if _is_dead(id):
			continue
		var d: float = from.distance_to(positions[id])
		if d <= best_d:
			best_d = d
			best = id
	return best

func _award_loot(peer_id: int, item: Dictionary) -> void:
	# Server is the sole loot authority; deliver to the owning client (or apply
	# locally when the host wins it) so they bag + persist it.
	if peer_id == 1:
		_apply_grant(item)
	else:
		_grant_loot.rpc_id(peer_id, item)

func _enemy_attack(from: Vector2, dmg: float) -> void:
	for id in positions.keys():
		if _is_dead(id):
			continue
		if positions[id].distance_to(from) <= ENEMY_ATTACK_RANGE:
			_damage_player(id, dmg)

# ================================================================ casting (server-authoritative)
func _try_cast(ability_name: String) -> void:
	if _is_local_dead() or _run_over:
		return
	var def := ClassSystem.ability_def(ability_name)
	# Client-side cooldown prediction for snappy UI; server is the real gate.
	if _local_cd.get(ability_name, 0.0) > 0.0:
		return
	_local_cd[ability_name] = def.get("cooldown", 1.0)
	if NetworkManager.is_server():
		_resolve_cast(1, ability_name)
	else:
		_cast.rpc_id(1, ability_name)

@rpc("any_peer", "call_remote", "reliable")
func _cast(ability_name: String) -> void:
	if NetworkManager.is_server():
		_resolve_cast(multiplayer.get_remote_sender_id(), ability_name)

func _resolve_cast(peer_id: int, ability_name: String) -> void:
	if _run_over or _is_dead(peer_id) or not positions.has(peer_id):
		return
	var build := _build_for(peer_id)
	# Anti-cheat: you can only cast abilities you actually know.
	if not ClassSystem.known_ability_names(build).has(ability_name):
		return
	var cd: Dictionary = cooldowns.get(peer_id, {})
	if cd.get(ability_name, 0.0) > 0.0:
		return
	var def := ClassSystem.ability_def(ability_name)
	cd[ability_name] = def.get("cooldown", 1.0)
	cooldowns[peer_id] = cd

	var origin: Vector2 = positions[peer_id]
	var kind: String = def.get("kind", "projectile")
	var base := float(def.get("power", 8.0))
	var dmg := _amp(build, ability_name, base, false)   # affinity + gear damage
	var heal := _amp(build, ability_name, base, true)    # affinity + gear healing
	var rng := float(def.get("range", 300.0))

	match kind:
		"heal":
			_heal_player(peer_id, heal)
			_fx_number.rpc(origin, heal, true)
		"nova":
			var radius := float(def.get("radius", 140.0))
			for eid in enemies.keys():
				var e: Dictionary = enemies[eid]
				if e["alive"] and origin.distance_to(e["pos"]) <= radius:
					_damage_enemy(eid, dmg)
		"drain":
			var t := _nearest_enemy(origin, rng)
			if t != -1:
				_damage_enemy(t, dmg)
				_heal_player(peer_id, dmg * 0.5)
				_fx_line.rpc(origin, enemies[t]["pos"], false)
		_:  # projectile / melee
			var target := _nearest_enemy(origin, rng)
			if target != -1:
				_damage_enemy(target, dmg)
				_fx_line.rpc(origin, enemies[target]["pos"], true)

## Amplify a base amount by identity affinity (DESIGN.md 3.3) and equipped gear
## (the lateral power axis, DESIGN.md 3.7). is_heal picks heal_pct vs damage_pct.
func _amp(build: CharacterBuild, ability_name: String, amount: float, is_heal: bool) -> float:
	var src := ClassSystem.ability_source_key(ability_name)
	if src != "" and ClassSystem.ability_gets_affinity(build, src):
		var pct := float(ClassSystem.identity_affinity(build).get("bonus_pct", 0))
		amount *= 1.0 + pct / 100.0
	var gear := build.equipped_stats()
	var stat := "heal_pct" if is_heal else "damage_pct"
	return amount * (1.0 + float(gear.get(stat, 0.0)) / 100.0)

func _nearest_enemy(from: Vector2, rng: float) -> int:
	var best := -1
	var best_d := rng if rng > 0.0 else 1.0e20
	for eid in enemies.keys():
		var e: Dictionary = enemies[eid]
		if not e["alive"]:
			continue
		var d: float = from.distance_to(e["pos"])
		if d <= best_d:
			best_d = d
			best = eid
	return best

func _damage_enemy(eid: int, dmg: float) -> void:
	var e: Dictionary = enemies[eid]
	e["hp"] -= dmg
	_fx_number.rpc(e["pos"], dmg, false)
	if e["hp"] <= 0.0:
		e["hp"] = 0.0
		e["alive"] = false
		_award_xp_party(_kill_xp(e["depth"], e["boss"]))
		_maybe_drop(e["pos"], e["depth"], e["boss"])
		_check_portal(e["room"])

## XP for a kill, scaled by room depth; bosses pay a fat premium.
func _kill_xp(depth: int, boss: bool) -> int:
	var amount := XP_PER_KILL * (1.0 + XP_DEPTH_BONUS * float(depth - 1))
	if boss:
		amount *= XP_BOSS_MULT
	return int(round(amount))

## Party-shared XP (server): every member banks the full amount — co-op should
## never devolve into kill-stealing. Delivery mirrors the loot-grant path.
func _award_xp_party(amount: int) -> void:
	if amount <= 0:
		return
	for id in NetworkManager.players.keys():
		if id == 1:
			_apply_xp(amount)
		else:
			_grant_xp.rpc_id(id, amount)

## The portal opens the moment the exit room is cleared.
func _check_portal(room_idx: int) -> void:
	if portal_active or room_idx != int(layout["exit"]):
		return
	for eid in enemies.keys():
		var e: Dictionary = enemies[eid]
		if e["room"] == room_idx and e["alive"]:
			return
	portal_active = true

## Depth is the loot dial (v0.5): deeper rooms roll higher item levels, and
## bosses always drop.
func _maybe_drop(pos: Vector2, depth: int, boss: bool) -> void:
	if not boss and randf() > DROP_CHANCE:
		return
	var ilvl := clampi(randi_range(1 + depth, 2 + depth * 2), 1, LOOT_MAX_ILVL)
	var item := LootSystem.roll_drop(ilvl)
	ground_loot[_next_loot_id] = {"item": item, "pos": pos}
	_next_loot_id += 1

## Extraction (server): bonus reward + completion XP for every party member,
## then send everyone back to the lobby together.
func _finish_run() -> void:
	if _run_over:
		return
	var exit_depth: int = layout["rooms"][layout["exit"]]["depth"]
	_award_xp_party(XP_EXTRACT_BASE + XP_EXTRACT_PER_DEPTH * exit_depth)
	for id in NetworkManager.players.keys():
		var bonus := LootSystem.roll_drop(clampi(2 + exit_depth * 2, 1, LOOT_MAX_ILVL))
		_award_loot(id, bonus)
	_complete_run.rpc()

func _damage_player(peer_id: int, dmg: float) -> void:
	if not player_hp.has(peer_id):
		return
	player_hp[peer_id] = max(0.0, player_hp[peer_id] - dmg)
	_fx_number.rpc(positions[peer_id], dmg, false)
	if player_hp[peer_id] <= 0.0 and player_respawn.get(peer_id, 0.0) <= 0.0:
		player_respawn[peer_id] = PLAYER_RESPAWN

func _heal_player(peer_id: int, amount: float) -> void:
	if not player_hp.has(peer_id) or _is_dead(peer_id):
		return
	player_hp[peer_id] = min(player_max[peer_id], player_hp[peer_id] + amount)

func _is_dead(peer_id: int) -> bool:
	return player_respawn.get(peer_id, 0.0) > 0.0 or player_hp.get(peer_id, 1.0) <= 0.0

func _is_local_dead() -> bool:
	var me := c_players.get(NetworkManager.local_id(), {})
	return me.get("dead", false)

# ================================================================ networking
@rpc("any_peer", "call_remote", "reliable")
func _submit_input(v: Vector2) -> void:
	if not NetworkManager.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if positions.has(sender):
		inputs[sender] = v

@rpc("authority", "call_local", "unreliable_ordered")
func _sync_positions(snapshot: Dictionary) -> void:
	targets = snapshot.duplicate(true)

@rpc("authority", "call_local", "unreliable_ordered")
func _sync_combat(players: Dictionary, mobs: Dictionary, loot: Dictionary, portal: bool) -> void:
	c_players = players
	c_enemies = mobs
	c_loot = loot
	c_portal = portal

## Server -> owning client: "you picked this up." Bag it and persist.
@rpc("authority", "call_remote", "reliable")
func _grant_loot(item: Dictionary) -> void:
	_apply_grant(item)

## Server -> owning client: "you earned this XP." Bank it and persist (v0.6).
@rpc("authority", "call_remote", "reliable")
func _grant_xp(amount: int) -> void:
	_apply_xp(amount)

func _apply_xp(amount: int) -> void:
	GameState.receive_xp(amount)

func _apply_grant(item: Dictionary) -> void:
	GameState.receive_loot(item)
	if loot_log:
		var col := LootSystem.rarity_color(item.get("rarity", "common"))
		loot_log.add_theme_color_override("font_color", col)
		loot_log.text = "Looted: %s" % item.get("name", "item")

## Server -> all peers: run complete. Celebrate, then extract to the lobby
## together (the party stays connected for the next run).
@rpc("authority", "call_local", "reliable")
func _complete_run() -> void:
	_run_over = true
	levelup_panel.visible = false
	banner_label.text = "DUNGEON CLEARED!\nExtracting…"
	# Capture the tree, not self: if this peer bails to the menu during the
	# delay, the node is freed but the timer still fires safely — and
	# is_active() is false by then, so nothing happens.
	var tree := get_tree()
	tree.create_timer(EXTRACT_DELAY).timeout.connect(func():
		if NetworkManager.is_active():
			tree.change_scene_to_file(LOBBY))

func _pack_players() -> Dictionary:
	var out := {}
	for id in player_hp.keys():
		out[id] = {"hp": player_hp[id], "max": player_max[id], "dead": _is_dead(id)}
	return out

func _pack_enemies() -> Dictionary:
	var out := {}
	for eid in enemies.keys():
		if enemies[eid]["alive"]:
			out[eid] = {"pos": enemies[eid]["pos"], "hp": enemies[eid]["hp"],
				"max": enemies[eid]["max"], "boss": enemies[eid]["boss"]}
	return out

func _pack_loot() -> Dictionary:
	var out := {}
	for lid in ground_loot.keys():
		out[lid] = {"pos": ground_loot[lid]["pos"], "rarity": ground_loot[lid]["item"].get("rarity", "common")}
	return out

# ================================================================ rendering
func _render(delta: float) -> void:
	# Players
	for id in targets.keys():
		var tok: Token = avatars.get(id)
		if tok == null:
			tok = _make_player_token(id)
			avatars[id] = tok
			world.add_child(tok)
			tok.position = targets[id]
		else:
			tok.position = tok.position.lerp(targets[id], clamp(delta * 14.0, 0.0, 1.0))
		var pstate: Dictionary = c_players.get(id, {})
		tok.set_hp(pstate.get("hp", -1.0), pstate.get("max", 1.0))
		tok.set_dead(pstate.get("dead", false))
	for id in avatars.keys():
		if not targets.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	# Camera + minimap follow the local avatar
	var me: Token = avatars.get(NetworkManager.local_id())
	if me != null:
		camera.position = camera.position.lerp(me.position, clamp(delta * 8.0, 0.0, 1.0))
		minimap.player_pos = me.position
	minimap.exit_open = c_portal
	minimap.queue_redraw()
	# Exit portal state
	if c_portal and not portal_token.is_open:
		portal_token.is_open = true
		portal_token.color = Color(0.61, 0.42, 1.0)
		portal_token.set_label("PORTAL — step in!")
		portal_token.queue_redraw()
	# Enemies
	for eid in c_enemies.keys():
		var et: Token = enemy_tokens.get(eid)
		if et == null:
			et = _make_enemy_token(c_enemies[eid].get("boss", false))
			enemy_tokens[eid] = et
			world.add_child(et)
		et.position = c_enemies[eid]["pos"]
		et.set_hp(c_enemies[eid]["hp"], c_enemies[eid]["max"])
	for eid in enemy_tokens.keys():
		if not c_enemies.has(eid):
			enemy_tokens[eid].queue_free()
			enemy_tokens.erase(eid)
	# Ground loot (small rarity-colored diamonds)
	for lid in c_loot.keys():
		var lt: Token = loot_tokens.get(lid)
		if lt == null:
			lt = Token.new()
			lt.radius = 9.0
			lt.is_square = true
			lt.color = LootSystem.rarity_color(c_loot[lid].get("rarity", "common"))
			loot_tokens[lid] = lt
			world.add_child(lt)
		lt.position = c_loot[lid]["pos"]
	for lid in loot_tokens.keys():
		if not c_loot.has(lid):
			loot_tokens[lid].queue_free()
			loot_tokens.erase(lid)

func _make_player_token(peer_id: int) -> Token:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var tok := Token.new()
	tok.radius = AVATAR_RADIUS
	tok.color = PALETTE[abs(peer_id) % PALETTE.size()]
	tok.is_local = peer_id == NetworkManager.local_id()
	tok.set_label("%s\n%s" % [info.get("name", "Player %d" % peer_id), info.get("class_title", "")])
	return tok

func _make_enemy_token(boss: bool) -> Token:
	var tok := Token.new()
	tok.radius = BOSS_RADIUS if boss else ENEMY_RADIUS
	tok.color = BOSS_COLOR if boss else ENEMY_COLOR
	tok.is_square = true
	tok.set_label("Dread Husk" if boss else "Husk")
	return tok

func _tick_local_cd(delta: float) -> void:
	for ab in _local_cd.keys():
		_local_cd[ab] = max(0.0, _local_cd[ab] - delta)
	if hotbar:
		for btn in hotbar.get_children():
			var ab: String = btn.get_meta("ability", "")
			var left: float = _local_cd.get(ab, 0.0)
			btn.disabled = left > 0.0 or _is_local_dead() or _run_over
			btn.text = ("%s\n%.1fs" % [ab, left]) if left > 0.0 else ab

func _update_status() -> void:
	var role := "HOST" if NetworkManager.is_server() else "client #%d" % NetworkManager.local_id()
	var me: Dictionary = c_players.get(NetworkManager.local_id(), {})
	var hp_txt := ""
	if me.has("hp"):
		hp_txt = "   HP %d/%d" % [int(me["hp"]), int(me["max"])]
		if me.get("dead", false):
			hp_txt += "  (down — respawning)"
	var hunt := "   PORTAL OPEN!" if c_portal else "   Husks left: %d" % c_enemies.size()
	status_label.text = "%s%s%s" % [role, hp_txt, hunt]
	# XP readout + the fork prompt (v0.6) — read straight off the local build,
	# which is the one true owner of banked XP.
	var build: CharacterBuild = GameState.player_build
	if build != null:
		xp_label.text = "Lv %d   ·   XP %d / %d" % [build.total_level(), build.xp, build.xp_to_next()]
		levelup_button.visible = build.can_level_up() and not _run_over
	else:
		levelup_button.visible = false

# ---- floating numbers / projectile lines (cosmetic, all peers)
@rpc("authority", "call_local", "unreliable")
func _fx_number(pos: Vector2, amount: float, is_heal: bool) -> void:
	var l := Label.new()
	l.text = ("+%d" % int(round(amount))) if is_heal else str(int(round(amount)))
	l.position = pos + Vector2(-8, -AVATAR_RADIUS - 10)
	l.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if is_heal else Color(1.0, 0.5, 0.4))
	world.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", l.position + Vector2(0, -42), 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

@rpc("authority", "call_local", "unreliable")
func _fx_line(from: Vector2, to: Vector2, is_attack: bool) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 4.0
	line.default_color = Color(0.7, 0.6, 1.0) if is_attack else Color(0.5, 1.0, 0.7)
	world.add_child(line)
	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)

# ================================================================ minimap
## Screen-space overview of the generated layout: rooms, corridors, the exit,
## and you. Everyone has the same map (it's derived from the shared seed), so
## there's nothing to sync — it's pure presentation.
class Minimap extends Control:
	const MAP_SIZE := Vector2(190, 190)
	const PAD := 8.0
	var layout: Dictionary
	var player_pos: Vector2 = Vector2.INF
	var exit_open := false
	var _scale: float
	var _offset: Vector2

	func _init(l: Dictionary) -> void:
		layout = l
		custom_minimum_size = MAP_SIZE
		size = MAP_SIZE
		var b: Rect2 = layout["bounds"]
		var inner := MAP_SIZE - Vector2(PAD, PAD) * 2.0
		_scale = minf(inner.x / b.size.x, inner.y / b.size.y)
		_offset = Vector2(PAD, PAD) + (inner - b.size * _scale) * 0.5 - b.position * _scale

	func _map(r: Rect2) -> Rect2:
		return Rect2(r.position * _scale + _offset, r.size * _scale)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.0, 0.0, 0.0, 0.5))
		for c in layout["corridors"]:
			draw_rect(_map(c), Color(0.45, 0.42, 0.55, 0.6))
		for i in layout["rooms"].size():
			var room: Dictionary = layout["rooms"][i]
			var col := Color(0.5, 0.48, 0.6)
			if i == int(layout["spawn"]):
				col = Color(0.32, 0.7, 0.6)
			elif i == int(layout["exit"]):
				col = Color(0.61, 0.42, 1.0) if exit_open else Color(0.4, 0.28, 0.55)
			draw_rect(_map(room["rect"]), col)
		if player_pos != Vector2.INF:
			draw_circle(player_pos * _scale + _offset, 4.0, Color.WHITE)

# ================================================================ token visual
## A drawn token (player circle, enemy square, loot diamond, or the portal)
## with a name label and HP bar. No art assets needed yet.
class Token extends Node2D:
	var radius: float = 22.0
	var color: Color = Color.WHITE
	var is_local: bool = false
	var is_square: bool = false
	var is_open: bool = false    # portal only: draw an inviting ring
	var hp_ratio: float = -1.0   # <0 hides the bar
	var dead: bool = false
	var _label: Label

	func set_label(text: String) -> void:
		if _label == null:
			_label = Label.new()
			_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_label.position = Vector2(-60, -radius - 38)
			_label.custom_minimum_size = Vector2(120, 0)
			add_child(_label)
		_label.text = text

	func set_hp(hp: float, maxhp: float) -> void:
		var r := -1.0 if hp < 0.0 or maxhp <= 0.0 else clamp(hp / maxhp, 0.0, 1.0)
		if r != hp_ratio:
			hp_ratio = r
			queue_redraw()

	func set_dead(value: bool) -> void:
		if value != dead:
			dead = value
			queue_redraw()

	func _draw() -> void:
		var c := color
		c.a = 0.35 if dead else 1.0
		if is_square:
			var s := radius
			draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), c)
		else:
			draw_circle(Vector2.ZERO, radius, c)
		if is_local and not dead:
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color.WHITE, 2.5, true)
		if is_open:
			draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 40, Color(0.85, 0.75, 1.0), 3.0, true)
		if hp_ratio >= 0.0:
			var w := radius * 2.0
			var y := -radius - 12.0
			draw_rect(Rect2(-radius, y, w, 5.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-radius, y, w * hp_ratio, 5.0), Color(0.35, 0.85, 0.4))
