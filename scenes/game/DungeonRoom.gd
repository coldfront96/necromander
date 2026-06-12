extends Node2D
## v0.2 + v0.3 — a shared, server-authoritative room with combat.
##
## Authority model (DESIGN.md 4): the SERVER owns all truth — positions, HP,
## cooldowns, enemy state, and every damage/heal roll. Clients send only intent
## (steer here / cast this) and render the snapshots the server broadcasts. No
## client can move itself, hurt an enemy, or heal itself directly — it can only
## ask, and the server decides. Identity affinity (DESIGN.md 3.3) is applied
## server-side so build choices actually change your numbers.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"

# --- Movement
const SPEED := 240.0
const BROADCAST_HZ := 20.0
const ROOM_MARGIN := 80.0
const AVATAR_RADIUS := 22.0

# --- Combat
const COMBAT_HZ := 10.0
const ENEMY_RADIUS := 24.0
const ENEMY_HP := 70.0
const ENEMY_ATTACK_INTERVAL := 1.5
const ENEMY_ATTACK_RANGE := 90.0
const ENEMY_ATTACK_DAMAGE := 6.0
const ENEMY_RESPAWN := 4.0
const PLAYER_BASE_HP := 80.0
const PLAYER_RESPAWN := 3.0

const PALETTE := [
	Color(0.61, 0.42, 1.0), Color(0.42, 1.0, 0.81),
	Color(1.0, 0.55, 0.42), Color(1.0, 0.85, 0.4),
	Color(0.5, 0.7, 1.0), Color(1.0, 0.5, 0.7),
]
const ENEMY_COLOR := Color(0.85, 0.30, 0.32)

# --- Server-authoritative state (meaningful only on the host)
var positions: Dictionary = {}     # peer_id -> Vector2
var inputs: Dictionary = {}        # peer_id -> Vector2 (steering intent)
var player_hp: Dictionary = {}     # peer_id -> float
var player_max: Dictionary = {}    # peer_id -> float
var player_respawn: Dictionary = {} # peer_id -> float (countdown; >0 = dead)
var cooldowns: Dictionary = {}     # peer_id -> { ability_name: seconds_left }
var enemies: Dictionary = {}       # eid -> { pos, hp, max, alive, respawn, atk }

# --- Client render state (all peers)
var targets: Dictionary = {}       # peer_id -> Vector2 (position snapshot)
var c_players: Dictionary = {}     # peer_id -> { hp, max, dead }
var c_enemies: Dictionary = {}     # eid -> { pos, hp, max }
var avatars: Dictionary = {}       # peer_id -> Token
var enemy_tokens: Dictionary = {}  # eid -> Token

var _last_sent_input := Vector2.ZERO
var _broadcast_accum := 0.0
var _combat_accum := 0.0
var _room_rect: Rect2
var _local_cd: Dictionary = {}     # client-side predicted cooldowns for UI
var joystick: Control
var world: Node2D
var hotbar: HBoxContainer
var status_label: Label

func _ready() -> void:
	if not NetworkManager.is_active():
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	var view := get_viewport_rect().size
	_room_rect = Rect2(ROOM_MARGIN, ROOM_MARGIN,
		view.x - ROOM_MARGIN * 2.0, view.y - ROOM_MARGIN * 2.0)

	_build_room(view)
	_build_ui(view)

	if NetworkManager.is_server():
		var i := 0
		for id in NetworkManager.players.keys():
			_spawn_player(id, i)
			i += 1
		_spawn_enemies()
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)

# ================================================================ build
func _build_room(view: Vector2) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.10)
	bg.size = view
	add_child(bg)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.12, 0.10, 0.16)
	floor_rect.position = _room_rect.position
	floor_rect.size = _room_rect.size
	add_child(floor_rect)

	world = Node2D.new()
	add_child(world)

func _build_ui(view: Vector2) -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var banner := Label.new()
	banner.text = "Dungeon Room — move with the stick, tap an ability to cast"
	banner.position = Vector2(20, 14)
	banner.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	ui.add_child(banner)

	status_label = Label.new()
	status_label.position = Vector2(20, 38)
	status_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	ui.add_child(status_label)

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

# ================================================================ spawning (server)
func _spawn_player(id: int, index: int) -> void:
	positions[id] = _spawn_point(index)
	inputs[id] = Vector2.ZERO
	var build := _build_for(id)
	player_max[id] = _max_hp(build)
	player_hp[id] = player_max[id]
	player_respawn[id] = 0.0
	cooldowns[id] = {}

func _spawn_enemies() -> void:
	var center := _room_rect.position + _room_rect.size * 0.5
	var spots := [center + Vector2(0, -180), center + Vector2(-160, 120), center + Vector2(160, 120)]
	var eid := 0
	for spot in spots:
		enemies[eid] = {"pos": spot, "hp": ENEMY_HP, "max": ENEMY_HP, "alive": true, "respawn": 0.0, "atk": ENEMY_ATTACK_INTERVAL}
		eid += 1

func _spawn_point(index: int) -> Vector2:
	var center := _room_rect.position + _room_rect.size * 0.5
	var angle := float(index) * (TAU / float(NetworkManager.MAX_PLAYERS))
	return center + Vector2(cos(angle), sin(angle)) * 110.0

func _on_player_joined(peer_id: int, _info: Dictionary) -> void:
	if NetworkManager.is_server() and not positions.has(peer_id):
		_spawn_player(peer_id, positions.size())

func _on_player_left(peer_id: int) -> void:
	for d in [positions, inputs, player_hp, player_max, player_respawn, cooldowns]:
		d.erase(peer_id)

func _build_for(peer_id: int) -> CharacterBuild:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	return CharacterBuild.from_dict(info.get("build", {}))

func _max_hp(build: CharacterBuild) -> float:
	return PLAYER_BASE_HP + build.level_power()

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
			_sync_combat.rpc(_pack_players(), _pack_enemies())
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
	if _is_local_dead():
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
	# player respawns
	for id in player_respawn.keys():
		if player_respawn[id] > 0.0:
			player_respawn[id] -= delta
			if player_respawn[id] <= 0.0:
				player_hp[id] = player_max[id]
				positions[id] = _spawn_point(0)
	# movement (only the living move)
	for id in positions.keys():
		if _is_dead(id):
			continue
		var intent: Vector2 = inputs.get(id, Vector2.ZERO)
		if intent != Vector2.ZERO:
			positions[id] = _clamp_to_room(positions[id] + intent.limit_length(1.0) * SPEED * delta)
	# enemies
	for eid in enemies.keys():
		var e: Dictionary = enemies[eid]
		if not e["alive"]:
			e["respawn"] -= delta
			if e["respawn"] <= 0.0:
				e["alive"] = true
				e["hp"] = e["max"]
			continue
		e["atk"] -= delta
		if e["atk"] <= 0.0:
			e["atk"] = ENEMY_ATTACK_INTERVAL
			_enemy_attack(e["pos"])

func _enemy_attack(from: Vector2) -> void:
	for id in positions.keys():
		if _is_dead(id):
			continue
		if positions[id].distance_to(from) <= ENEMY_ATTACK_RANGE:
			_damage_player(id, ENEMY_ATTACK_DAMAGE)

func _clamp_to_room(p: Vector2) -> Vector2:
	return Vector2(
		clamp(p.x, _room_rect.position.x + AVATAR_RADIUS, _room_rect.end.x - AVATAR_RADIUS),
		clamp(p.y, _room_rect.position.y + AVATAR_RADIUS, _room_rect.end.y - AVATAR_RADIUS))

# ================================================================ casting (server-authoritative)
func _try_cast(ability_name: String) -> void:
	if _is_local_dead():
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
	if _is_dead(peer_id) or not positions.has(peer_id):
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
	var power := _with_affinity(build, ability_name, float(def.get("power", 8.0)))
	var rng := float(def.get("range", 300.0))

	match kind:
		"heal":
			_heal_player(peer_id, power)
			_fx_number.rpc(origin, power, true)
		"nova":
			var radius := float(def.get("radius", 140.0))
			for eid in enemies.keys():
				var e: Dictionary = enemies[eid]
				if e["alive"] and origin.distance_to(e["pos"]) <= radius:
					_damage_enemy(eid, power)
		"drain":
			var t := _nearest_enemy(origin, rng)
			if t != -1:
				_damage_enemy(t, power)
				_heal_player(peer_id, power * 0.5)
				_fx_line.rpc(origin, enemies[t]["pos"], false)
		_:  # projectile / melee
			var target := _nearest_enemy(origin, rng)
			if target != -1:
				_damage_enemy(target, power)
				_fx_line.rpc(origin, enemies[target]["pos"], true)

func _with_affinity(build: CharacterBuild, ability_name: String, amount: float) -> float:
	var src := ClassSystem.ability_source_key(ability_name)
	if src != "" and ClassSystem.ability_gets_affinity(build, src):
		var pct := float(ClassSystem.identity_affinity(build).get("bonus_pct", 0))
		return amount * (1.0 + pct / 100.0)
	return amount

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
		e["respawn"] = ENEMY_RESPAWN

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
func _sync_combat(players: Dictionary, mobs: Dictionary) -> void:
	c_players = players
	c_enemies = mobs

func _pack_players() -> Dictionary:
	var out := {}
	for id in player_hp.keys():
		out[id] = {"hp": player_hp[id], "max": player_max[id], "dead": _is_dead(id)}
	return out

func _pack_enemies() -> Dictionary:
	var out := {}
	for eid in enemies.keys():
		if enemies[eid]["alive"]:
			out[eid] = {"pos": enemies[eid]["pos"], "hp": enemies[eid]["hp"], "max": enemies[eid]["max"]}
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
	# Enemies
	for eid in c_enemies.keys():
		var et: Token = enemy_tokens.get(eid)
		if et == null:
			et = _make_enemy_token()
			enemy_tokens[eid] = et
			world.add_child(et)
		et.position = c_enemies[eid]["pos"]
		et.set_hp(c_enemies[eid]["hp"], c_enemies[eid]["max"])
	for eid in enemy_tokens.keys():
		if not c_enemies.has(eid):
			enemy_tokens[eid].queue_free()
			enemy_tokens.erase(eid)

func _make_player_token(peer_id: int) -> Token:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var tok := Token.new()
	tok.radius = AVATAR_RADIUS
	tok.color = PALETTE[abs(peer_id) % PALETTE.size()]
	tok.is_local = peer_id == NetworkManager.local_id()
	tok.set_label("%s\n%s" % [info.get("name", "Player %d" % peer_id), info.get("class_title", "")])
	return tok

func _make_enemy_token() -> Token:
	var tok := Token.new()
	tok.radius = ENEMY_RADIUS
	tok.color = ENEMY_COLOR
	tok.is_square = true
	tok.set_label("Dummy")
	return tok

func _tick_local_cd(delta: float) -> void:
	for ab in _local_cd.keys():
		_local_cd[ab] = max(0.0, _local_cd[ab] - delta)
	if hotbar:
		for btn in hotbar.get_children():
			var ab: String = btn.get_meta("ability", "")
			var left: float = _local_cd.get(ab, 0.0)
			btn.disabled = left > 0.0 or _is_local_dead()
			btn.text = ("%s\n%.1fs" % [ab, left]) if left > 0.0 else ab

func _update_status() -> void:
	var role := "HOST" if NetworkManager.is_server() else "client #%d" % NetworkManager.local_id()
	var me: Dictionary = c_players.get(NetworkManager.local_id(), {})
	var hp_txt := ""
	if me.has("hp"):
		hp_txt = "   HP %d/%d" % [int(me["hp"]), int(me["max"])]
		if me.get("dead", false):
			hp_txt += "  (down — respawning)"
	status_label.text = "%s%s" % [role, hp_txt]

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

# ================================================================ token visual
## A drawn token (player circle or enemy square) with a name label and HP bar.
## No art assets needed yet.
class Token extends Node2D:
	var radius: float = 22.0
	var color: Color = Color.WHITE
	var is_local: bool = false
	var is_square: bool = false
	var hp_ratio: float = -1.0   # <0 hides the bar
	var dead: bool = false
	var _label: Label

	func set_label(text: String) -> void:
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.position = Vector2(-60, -radius - 38)
		_label.custom_minimum_size = Vector2(120, 0)
		add_child(_label)

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
		if hp_ratio >= 0.0:
			var w := radius * 2.0
			var y := -radius - 12.0
			draw_rect(Rect2(-radius, y, w, 5.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-radius, y, w * hp_ratio, 5.0), Color(0.35, 0.85, 0.4))
