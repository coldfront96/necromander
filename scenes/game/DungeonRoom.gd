extends Node2D
## v0.2 — a shared, server-authoritative room. Players see each other move.
##
## Authority model (DESIGN.md 4): the SERVER owns every avatar's position. Clients
## send only their steering intent; the server integrates movement and broadcasts
## the canonical positions. No client can teleport itself — it can only ask to
## move. Clients render by interpolating toward the latest server snapshot.
##
## This is intentionally a simple snapshot model (no prediction/interpolation
## buffer yet) — clients feel a little input latency; the host is instant. Good
## enough to prove the shared world; we can add client prediction in v0.3.

const MAIN_MENU := "res://scenes/main_menu/MainMenu.tscn"
const SPEED := 240.0                # px/sec
const BROADCAST_HZ := 20.0         # server position snapshots per second
const ROOM_MARGIN := 80.0
const AVATAR_RADIUS := 22.0

# Server-authoritative state (authoritative only on the host)
var positions: Dictionary = {}     # peer_id -> Vector2 (canonical, server-owned)
var inputs: Dictionary = {}        # peer_id -> Vector2 (last steering intent)

# Client-side render state (all peers)
var targets: Dictionary = {}       # peer_id -> Vector2 (latest snapshot)
var avatars: Dictionary = {}       # peer_id -> Node2D

var _last_sent_input := Vector2.ZERO
var _broadcast_accum := 0.0
var _room_rect: Rect2
var joystick: Control
var world: Node2D

const PALETTE := [
	Color(0.61, 0.42, 1.0), Color(0.42, 1.0, 0.81),
	Color(1.0, 0.55, 0.42), Color(1.0, 0.85, 0.4),
	Color(0.5, 0.7, 1.0), Color(1.0, 0.5, 0.7),
]

func _ready() -> void:
	if not NetworkManager.is_active():
		# Reached here without a session (e.g. opened scene directly) — bail out.
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	var view := get_viewport_rect().size
	_room_rect = Rect2(ROOM_MARGIN, ROOM_MARGIN,
		view.x - ROOM_MARGIN * 2.0, view.y - ROOM_MARGIN * 2.0)

	_build_room(view)
	_build_ui(view)

	if NetworkManager.is_server():
		# Seed authoritative positions for everyone already in the lobby.
		var i := 0
		for id in NetworkManager.players.keys():
			positions[id] = _spawn_point(i)
			inputs[id] = Vector2.ZERO
			i += 1
		targets = positions.duplicate(true)
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)

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

	# Avatars live in a world layer drawn above the floor.
	world = Node2D.new()
	add_child(world)

func _build_ui(view: Vector2) -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var banner := Label.new()
	banner.text = "Dungeon Room — move with the stick (or arrow keys)"
	banner.position = Vector2(20, 16)
	banner.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	ui.add_child(banner)

	var role := Label.new()
	role.text = "You are the HOST (server)" if NetworkManager.is_server() else "Connected as client #%d" % NetworkManager.local_id()
	role.position = Vector2(20, 40)
	role.add_theme_color_override("font_color", Color(0.42, 1.0, 0.81))
	ui.add_child(role)

	joystick = preload("res://scenes/game/VirtualJoystick.gd").new()
	joystick.position = Vector2(40, view.y - 40 - 180)
	ui.add_child(joystick)

	var leave := Button.new()
	leave.text = "Leave"
	leave.position = Vector2(view.x - 130, 24)
	leave.custom_minimum_size = Vector2(100, 44)
	leave.pressed.connect(func():
		NetworkManager.leave()
		get_tree().change_scene_to_file(MAIN_MENU))
	ui.add_child(leave)

# ---------------------------------------------------------------- spawn helpers
func _spawn_point(index: int) -> Vector2:
	# Spread spawns around the room center.
	var center := _room_rect.position + _room_rect.size * 0.5
	var angle := float(index) * (TAU / float(NetworkManager.MAX_PLAYERS))
	return center + Vector2(cos(angle), sin(angle)) * 90.0

func _on_player_joined(peer_id: int, _info: Dictionary) -> void:
	if NetworkManager.is_server() and not positions.has(peer_id):
		positions[peer_id] = _spawn_point(positions.size())
		inputs[peer_id] = Vector2.ZERO

func _on_player_left(peer_id: int) -> void:
	positions.erase(peer_id)
	inputs.erase(peer_id)

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if not NetworkManager.is_active():
		return
	_handle_local_input()
	if NetworkManager.is_server():
		_server_integrate(delta)
		_broadcast_accum += delta
		if _broadcast_accum >= 1.0 / BROADCAST_HZ:
			_broadcast_accum = 0.0
			_sync_positions.rpc(positions)
	_render_avatars(delta)

func _input_vector() -> Vector2:
	var v := Vector2.ZERO
	if joystick:
		v += joystick.get_vector()
	v += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	return v.limit_length(1.0)

func _handle_local_input() -> void:
	var v := _input_vector()
	# Only emit when intent meaningfully changes — keeps the wire quiet.
	if v.distance_to(_last_sent_input) <= 0.04:
		return
	_last_sent_input = v
	if NetworkManager.is_server():
		inputs[1] = v
	else:
		_submit_input.rpc_id(1, v)

func _server_integrate(delta: float) -> void:
	for id in positions.keys():
		var intent: Vector2 = inputs.get(id, Vector2.ZERO)
		if intent == Vector2.ZERO:
			continue
		var moved: Vector2 = positions[id] + intent.limit_length(1.0) * SPEED * delta
		positions[id] = _clamp_to_room(moved)

func _clamp_to_room(p: Vector2) -> Vector2:
	return Vector2(
		clamp(p.x, _room_rect.position.x + AVATAR_RADIUS, _room_rect.end.x - AVATAR_RADIUS),
		clamp(p.y, _room_rect.position.y + AVATAR_RADIUS, _room_rect.end.y - AVATAR_RADIUS))

# ---------------------------------------------------------------- networking
## Client -> server: "I want to steer this way." Server is the only integrator.
@rpc("any_peer", "call_remote", "reliable")
func _submit_input(v: Vector2) -> void:
	if not NetworkManager.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if positions.has(sender):
		inputs[sender] = v

## Server -> everyone: the canonical position snapshot.
@rpc("authority", "call_local", "unreliable_ordered")
func _sync_positions(snapshot: Dictionary) -> void:
	targets = snapshot.duplicate(true)

# ---------------------------------------------------------------- rendering
func _render_avatars(delta: float) -> void:
	# Add/move avatars for everyone in the latest snapshot.
	for id in targets.keys():
		if not avatars.has(id):
			avatars[id] = _make_avatar(id)
			world.add_child(avatars[id])
			avatars[id].position = targets[id]  # snap on first appearance
		else:
			# Smoothly chase the server's truth.
			avatars[id].position = avatars[id].position.lerp(targets[id], clamp(delta * 14.0, 0.0, 1.0))
	# Remove avatars no longer present.
	for id in avatars.keys():
		if not targets.has(id):
			avatars[id].queue_free()
			avatars.erase(id)

func _make_avatar(peer_id: int) -> Node2D:
	var node := Node2D.new()

	var body := _Avatar.new()
	body.radius = AVATAR_RADIUS
	body.color = PALETTE[abs(peer_id) % PALETTE.size()]
	body.is_local = peer_id == NetworkManager.local_id()
	node.add_child(body)

	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var label := Label.new()
	var who := "%s\n%s" % [info.get("name", "Player %d" % peer_id), info.get("class_title", "")]
	label.text = who
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-60, -AVATAR_RADIUS - 36)
	label.custom_minimum_size = Vector2(120, 0)
	node.add_child(label)
	return node

## Tiny drawn token so we need no art assets yet.
class _Avatar extends Node2D:
	var radius: float = 22.0
	var color: Color = Color.WHITE
	var is_local: bool = false

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)
		if is_local:
			draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 32, Color.WHITE, 2.5, true)
