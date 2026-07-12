extends Node2D
## v0.9 — the PvP Arena prototype: the second social loop (DESIGN.md 4).
##
## Same authority model as the dungeon: the SERVER owns positions, HP,
## cooldowns and every damage roll; clients send intent and render snapshots.
## The same server-authoritative spine that stops PvE cheating is exactly what
## makes fair PvP possible.
##
## Format: free-for-all rounds on a symmetric ring map (one central pillar).
## Last one standing takes the round; first to MATCH_TARGET rounds takes the
## match. This is the live test of the design's core bet — capped loadout
## slots (3.5) + the soft-cap power curve (3.7) should make fights about
## build and skill, not grind.

const LOBBY := "res://scenes/lobby/Lobby.tscn"
const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"

# --- Map: a ring — four overlapping bands around a central pillar. Walkable is
# the union of the bands, so the pillar is a real wall to orbit and juke around.
const WORLD := 1100.0
const PILLAR_MIN := 430.0
const PILLAR_MAX := 670.0
const SPAWN_INSET := 150.0

# --- Movement / combat (player stats mirror the dungeon's)
const SPEED := 240.0
const BROADCAST_HZ := 20.0
const COMBAT_HZ := 10.0
const AVATAR_RADIUS := 22.0
const PLAYER_BASE_HP := 80.0

# --- Round / match flow
const MATCH_TARGET := 3        # round wins to take the match
const MAX_ROUNDS := 9          # safety valve so a match always ends
const COUNTDOWN := 3.0
const ROUNDOVER_DELAY := 2.5
const MATCHOVER_DELAY := 5.0

# --- Rewards: modest by design — the arena is for glory, the dungeon for
# wealth. PvP must never become the optimal farm.
const WIN_GOLD := 120
const WIN_XP := 80
const CONSOLATION_GOLD := 30
const CONSOLATION_XP := 25

const PALETTE := [
	Color(0.61, 0.42, 1.0), Color(0.42, 1.0, 0.81),
	Color(1.0, 0.55, 0.42), Color(1.0, 0.85, 0.4),
	Color(0.5, 0.7, 1.0), Color(1.0, 0.5, 0.7),
]

# --- Server-authoritative state (meaningful only on the host)
var positions: Dictionary = {}   # peer_id -> Vector2
var inputs: Dictionary = {}      # peer_id -> Vector2
var player_hp: Dictionary = {}   # peer_id -> float
var player_max: Dictionary = {}  # peer_id -> float
var cooldowns: Dictionary = {}   # peer_id -> { ability: seconds_left }
var scores: Dictionary = {}      # peer_id -> round wins
var phase: String = "countdown"  # countdown | fight | roundover | matchover
var phase_t: float = COUNTDOWN
var round_num: int = 1
var last_winner: int = 0         # peer id of last round/match winner (0 = draw)
var _walk_rects: Array = []

# --- Client render state (all peers)
var targets: Dictionary = {}
var c_players: Dictionary = {}   # peer_id -> { hp, max, dead }
var c_meta: Dictionary = {}      # { phase, t, round, scores, winner }
var avatars: Dictionary = {}     # peer_id -> Token

var _last_sent_input := Vector2.ZERO
var _broadcast_accum := 0.0
var _combat_accum := 0.0
var _local_cd: Dictionary = {}
var joystick: Control
var world: Node2D
var hotbar: HBoxContainer
var status_label: Label
var score_label: Label
var banner_label: Label

func _ready() -> void:
	if not NetworkManager.is_active():
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	_walk_rects = [
		Rect2(0, 0, WORLD, PILLAR_MIN),                    # top band
		Rect2(0, PILLAR_MAX, WORLD, WORLD - PILLAR_MAX),   # bottom band
		Rect2(0, 0, PILLAR_MIN, WORLD),                    # left band
		Rect2(PILLAR_MAX, 0, WORLD - PILLAR_MAX, WORLD),   # right band
	]

	var view := get_viewport_rect().size
	_build_world()
	_build_ui(view)

	if NetworkManager.is_server():
		var i := 0
		for id in NetworkManager.players.keys():
			_init_player(id, i)
			i += 1
		NetworkManager.player_left.connect(_on_player_left)
		_start_round()

# ================================================================ build
func _build_world() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)
	add_child(bg_layer)

	# Floor, then the pillar drawn on top as an obstacle.
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.13, 0.10, 0.14)
	floor_rect.size = Vector2(WORLD, WORLD)
	add_child(floor_rect)

	var pillar := ColorRect.new()
	pillar.color = Color(0.06, 0.05, 0.09)
	pillar.position = Vector2(PILLAR_MIN, PILLAR_MIN)
	pillar.size = Vector2(PILLAR_MAX - PILLAR_MIN, PILLAR_MAX - PILLAR_MIN)
	add_child(pillar)

	world = Node2D.new()
	add_child(world)

	# Fixed camera framing the whole arena — in PvP, information is fairness.
	var camera := Camera2D.new()
	camera.position = Vector2(WORLD, WORLD) * 0.5
	camera.zoom = Vector2(0.6, 0.6)
	add_child(camera)
	camera.make_current()

func _build_ui(view: Vector2) -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var banner := Label.new()
	banner.text = "Arena — free-for-all, first to %d rounds" % MATCH_TARGET
	banner.position = Vector2(20, 14)
	banner.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	ui.add_child(banner)

	status_label = Label.new()
	status_label.position = Vector2(20, 38)
	status_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	ui.add_child(status_label)

	score_label = Label.new()
	score_label.position = Vector2(20, 62)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	score_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_label.custom_minimum_size = Vector2(view.x - 160, 0)
	ui.add_child(score_label)

	banner_label = Label.new()
	banner_label.add_theme_font_size_override("font_size", 34)
	banner_label.add_theme_color_override("font_color", Color(0.61, 0.42, 1.0))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.position = Vector2(0, view.y * 0.30)
	banner_label.size = Vector2(view.x, 90)
	ui.add_child(banner_label)

	joystick = preload("res://scenes/game/VirtualJoystick.gd").new()
	joystick.position = Vector2(40, view.y - 40 - 180)
	ui.add_child(joystick)

	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 8)
	hotbar.position = Vector2(view.x * 0.5 - 150, view.y - 70)
	ui.add_child(hotbar)
	for ability_name in _local_hotbar_abilities():
		hotbar.add_child(_make_ability_button(ability_name))

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
	var known := ClassSystem.known_ability_names(build)
	return known.slice(0, min(4, known.size()))

func _make_ability_button(ability_name: String) -> Button:
	var b := Button.new()
	b.set_meta("ability", ability_name)
	b.text = ability_name
	b.custom_minimum_size = Vector2(96, 48)
	b.pressed.connect(func(): _try_cast(ability_name))
	return b

# ================================================================ round flow (server)
func _init_player(id: int, index: int) -> void:
	positions[id] = _spawn_point(index)
	inputs[id] = Vector2.ZERO
	var build := _build_for(id)
	player_max[id] = PLAYER_BASE_HP + build.level_power() + float(build.equipped_stats().get("max_hp", 0.0))
	player_hp[id] = player_max[id]
	cooldowns[id] = {}
	scores[id] = int(scores.get(id, 0))

func _spawn_point(index: int) -> Vector2:
	var corners := [
		Vector2(SPAWN_INSET, SPAWN_INSET),
		Vector2(WORLD - SPAWN_INSET, WORLD - SPAWN_INSET),
		Vector2(SPAWN_INSET, WORLD - SPAWN_INSET),
		Vector2(WORLD - SPAWN_INSET, SPAWN_INSET),
	]
	return corners[index % corners.size()]

func _start_round() -> void:
	var i := 0
	for id in positions.keys():
		positions[id] = _spawn_point(i)
		player_hp[id] = player_max[id]
		inputs[id] = Vector2.ZERO
		cooldowns[id] = {}
		i += 1
	phase = "countdown"
	phase_t = COUNTDOWN
	last_winner = 0

func _on_player_left(peer_id: int) -> void:
	for d in [positions, inputs, player_hp, player_max, cooldowns, scores]:
		d.erase(peer_id)

# ================================================================ main loop
func _physics_process(delta: float) -> void:
	if not NetworkManager.is_active():
		return
	_tick_local_cd(delta)
	_handle_local_input()
	if NetworkManager.is_server():
		_server_step(delta)
		_broadcast_accum += delta
		if _broadcast_accum >= 1.0 / BROADCAST_HZ:
			_broadcast_accum = 0.0
			_sync_positions.rpc(positions)
		_combat_accum += delta
		if _combat_accum >= 1.0 / COMBAT_HZ:
			_combat_accum = 0.0
			_sync_arena.rpc(_pack_players(), _pack_meta())
	_render(delta)
	_update_hud()

func _input_vector() -> Vector2:
	var v := Vector2.ZERO
	if joystick:
		v += joystick.get_vector()
	v += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	return v.limit_length(1.0)

func _handle_local_input() -> void:
	var fighting: bool = c_meta.get("phase", "") == "fight" and not _is_local_dead()
	var v := _input_vector() if fighting else Vector2.ZERO
	if v.distance_to(_last_sent_input) <= 0.04:
		return
	_last_sent_input = v
	if NetworkManager.is_server():
		inputs[1] = v
	else:
		_submit_input.rpc_id(1, v)

# ---- server simulation
func _server_step(delta: float) -> void:
	match phase:
		"countdown":
			phase_t -= delta
			if phase_t <= 0.0:
				phase = "fight"
		"fight":
			_step_fight(delta)
		"roundover":
			phase_t -= delta
			if phase_t <= 0.0:
				if _match_decided():
					_end_match()
				else:
					round_num += 1
					_start_round()
		"matchover":
			phase_t -= delta
			if phase_t <= 0.0:
				_return_to_lobby.rpc()

func _step_fight(delta: float) -> void:
	# cooldowns
	for id in cooldowns.keys():
		for ab in cooldowns[id].keys():
			cooldowns[id][ab] = max(0.0, cooldowns[id][ab] - delta)
	# movement (living only)
	for id in positions.keys():
		if _is_dead(id):
			continue
		var intent: Vector2 = inputs.get(id, Vector2.ZERO)
		if intent != Vector2.ZERO:
			positions[id] = _slide_move(positions[id], intent.limit_length(1.0) * SPEED * delta)
	# round end: last one standing (or a mutual-KO draw)
	var alive: Array = []
	for id in positions.keys():
		if not _is_dead(id):
			alive.append(id)
	if positions.size() >= 2 and alive.size() <= 1:
		last_winner = alive[0] if alive.size() == 1 else 0
		if last_winner != 0:
			scores[last_winner] = int(scores.get(last_winner, 0)) + 1
		phase = "roundover"
		phase_t = ROUNDOVER_DELAY
	elif positions.size() < 2:
		# Everyone else left: whoever remains wins the match by default.
		last_winner = alive[0] if alive.size() == 1 else 0
		_end_match()

func _match_decided() -> bool:
	if round_num >= MAX_ROUNDS:
		return true
	for id in scores.keys():
		if int(scores[id]) >= MATCH_TARGET:
			return true
	return false

func _end_match() -> void:
	phase = "matchover"
	phase_t = MATCHOVER_DELAY
	# Match winner = most round wins (last_winner breaks a tie implicitly:
	# the final round's victor sorts first among equals below).
	var best := last_winner
	var best_wins := -1
	for id in scores.keys():
		if int(scores[id]) > best_wins:
			best_wins = int(scores[id])
			best = id
	last_winner = best
	for id in positions.keys():
		var win: bool = id == last_winner
		_award(id, WIN_GOLD if win else CONSOLATION_GOLD, WIN_XP if win else CONSOLATION_XP)

func _award(peer_id: int, gold: int, xp: int) -> void:
	if peer_id == 1:
		_apply_reward(gold, xp)
	else:
		_grant_reward.rpc_id(peer_id, gold, xp)

## Axis-sliding collision against the arena bands (the pillar is the "wall").
func _slide_move(from: Vector2, motion: Vector2) -> Vector2:
	var dest := from + motion
	if _walkable(dest):
		return dest
	dest = from + Vector2(motion.x, 0.0)
	if motion.x != 0.0 and _walkable(dest):
		return dest
	dest = from + Vector2(0.0, motion.y)
	if motion.y != 0.0 and _walkable(dest):
		return dest
	return from

func _walkable(p: Vector2) -> bool:
	for r in _walk_rects:
		if (r as Rect2).grow(-AVATAR_RADIUS).has_point(p):
			return true
	return false

# ================================================================ casting (server-authoritative, players as targets)
func _try_cast(ability_name: String) -> void:
	if c_meta.get("phase", "") != "fight" or _is_local_dead():
		return
	var def := ClassSystem.ability_def(ability_name)
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
	if phase != "fight" or _is_dead(peer_id) or not positions.has(peer_id):
		return
	var build := _build_for(peer_id)
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
	var dmg := _amp(build, ability_name, base, false)
	var heal := _amp(build, ability_name, base, true)
	var rng := float(def.get("range", 300.0))

	match kind:
		"heal":
			_heal_player(peer_id, heal)
			_fx_number.rpc(origin, heal, true)
		"nova":
			var radius := float(def.get("radius", 140.0))
			for id in positions.keys():
				if id != peer_id and not _is_dead(id) and origin.distance_to(positions[id]) <= radius:
					_damage_player(id, dmg)
		"drain":
			var t := _nearest_foe(peer_id, origin, rng)
			if t != -1:
				_damage_player(t, dmg)
				_heal_player(peer_id, dmg * 0.5)
				_fx_line.rpc(origin, positions[t], false)
		_:
			var target := _nearest_foe(peer_id, origin, rng)
			if target != -1:
				_damage_player(target, dmg)
				_fx_line.rpc(origin, positions[target], true)

## Same affinity + gear math as PvE — your build IS your weapon here.
func _amp(build: CharacterBuild, ability_name: String, amount: float, is_heal: bool) -> float:
	var src := ClassSystem.ability_source_key(ability_name)
	if src != "" and ClassSystem.ability_gets_affinity(build, src):
		var pct := float(ClassSystem.identity_affinity(build).get("bonus_pct", 0))
		amount *= 1.0 + pct / 100.0
	var gear := build.equipped_stats()
	var stat := "heal_pct" if is_heal else "damage_pct"
	return amount * (1.0 + float(gear.get(stat, 0.0)) / 100.0)

func _nearest_foe(peer_id: int, from: Vector2, rng: float) -> int:
	var best := -1
	var best_d := rng if rng > 0.0 else 1.0e20
	for id in positions.keys():
		if id == peer_id or _is_dead(id):
			continue
		var d: float = from.distance_to(positions[id])
		if d <= best_d:
			best_d = d
			best = id
	return best

func _damage_player(peer_id: int, dmg: float) -> void:
	if not player_hp.has(peer_id) or _is_dead(peer_id):
		return
	player_hp[peer_id] = max(0.0, player_hp[peer_id] - dmg)
	_fx_number.rpc(positions[peer_id], dmg, false)

func _heal_player(peer_id: int, amount: float) -> void:
	if not player_hp.has(peer_id) or _is_dead(peer_id):
		return
	player_hp[peer_id] = min(player_max[peer_id], player_hp[peer_id] + amount)

func _is_dead(peer_id: int) -> bool:
	return player_hp.get(peer_id, 1.0) <= 0.0

func _is_local_dead() -> bool:
	var me := c_players.get(NetworkManager.local_id(), {})
	return me.get("dead", false)

func _build_for(peer_id: int) -> CharacterBuild:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	return CharacterBuild.from_dict(info.get("build", {}))

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
func _sync_arena(players: Dictionary, meta: Dictionary) -> void:
	c_players = players
	c_meta = meta

## Server -> owning client: match payout (gold + XP over the usual local bank).
@rpc("authority", "call_remote", "reliable")
func _grant_reward(gold: int, xp: int) -> void:
	_apply_reward(gold, xp)

func _apply_reward(gold: int, xp: int) -> void:
	GameState.receive_gold(gold)
	GameState.receive_xp(xp)

## Server -> all peers: match finished, everyone back to the lobby together.
@rpc("authority", "call_local", "reliable")
func _return_to_lobby() -> void:
	if NetworkManager.is_active():
		get_tree().change_scene_to_file(LOBBY)

func _pack_players() -> Dictionary:
	var out := {}
	for id in player_hp.keys():
		out[id] = {"hp": player_hp[id], "max": player_max[id], "dead": _is_dead(id)}
	return out

func _pack_meta() -> Dictionary:
	return {"phase": phase, "t": phase_t, "round": round_num,
		"scores": scores.duplicate(), "winner": last_winner}

# ================================================================ rendering
func _render(delta: float) -> void:
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

func _make_player_token(peer_id: int) -> Token:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var tok := Token.new()
	tok.radius = AVATAR_RADIUS
	tok.color = PALETTE[abs(peer_id) % PALETTE.size()]
	tok.is_local = peer_id == NetworkManager.local_id()
	tok.set_label("%s\n%s" % [info.get("name", "Player %d" % peer_id), info.get("class_title", "")])
	return tok

func _tick_local_cd(delta: float) -> void:
	for ab in _local_cd.keys():
		_local_cd[ab] = max(0.0, _local_cd[ab] - delta)
	if hotbar:
		var fighting: bool = c_meta.get("phase", "") == "fight"
		for btn in hotbar.get_children():
			var ab: String = btn.get_meta("ability", "")
			var left: float = _local_cd.get(ab, 0.0)
			btn.disabled = left > 0.0 or _is_local_dead() or not fighting
			btn.text = ("%s\n%.1fs" % [ab, left]) if left > 0.0 else ab

func _update_hud() -> void:
	var meta_phase: String = c_meta.get("phase", "countdown")
	var t := float(c_meta.get("t", 0.0))
	var rnd := int(c_meta.get("round", 1))
	match meta_phase:
		"countdown":
			banner_label.text = "Round %d\n%d…" % [rnd, int(ceil(t))]
		"fight":
			banner_label.text = ""
		"roundover":
			var w := int(c_meta.get("winner", 0))
			if w == 0:
				banner_label.text = "Mutual destruction — draw!"
			else:
				banner_label.text = "%s takes the round!" % _name_of(w)
		"matchover":
			banner_label.text = "%s WINS THE MATCH!" % _name_of(int(c_meta.get("winner", 0)))
	var me: Dictionary = c_players.get(NetworkManager.local_id(), {})
	var hp_txt := ""
	if me.has("hp"):
		hp_txt = "HP %d/%d" % [int(me["hp"]), int(me["max"])]
		if me.get("dead", false):
			hp_txt += "  (down — spectating until next round)"
	status_label.text = hp_txt
	# Scoreboard from synced scores + the roster for names.
	var parts: Array = []
	var meta_scores: Dictionary = c_meta.get("scores", {})
	var ids := meta_scores.keys()
	ids.sort()
	for id in ids:
		parts.append("%s: %d" % [_name_of(int(id)), int(meta_scores[id])])
	score_label.text = ("Round wins — " + "   ".join(parts)) if not parts.is_empty() else ""

func _name_of(peer_id: int) -> String:
	if peer_id == 0:
		return "Nobody"
	return NetworkManager.players.get(peer_id, {}).get("name", "Player %d" % peer_id)

# ---- cosmetic fx (all peers)
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
