extends Node
## Autoload. Multiplayer core. Player-hosted, server-authoritative lobby over
## ENet (DESIGN.md section 4). The host peer (id 1) is the authority; clients
## send intents and the server validates + broadcasts canonical state.
##
## Structured so the host can later become a headless dedicated server with no
## gameplay rewrite: all authority checks go through `is_server()`.

signal lobby_updated(players: Dictionary)
signal connection_succeeded()
signal connection_failed(reason: String)
signal server_started(port: int)
signal player_joined(peer_id: int, info: Dictionary)
signal player_left(peer_id: int)
signal game_started()

const DEFAULT_PORT := 8910
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/game/DungeonRoom.tscn"

## peer_id -> { name, race, class_title, aspect_set, ready }
var players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ---------------------------------------------------------------- helpers
func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func is_active() -> bool:
	return multiplayer.has_multiplayer_peer()

func local_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 0

func _local_info() -> Dictionary:
	var build: CharacterBuild = GameState.player_build
	if build == null:
		return { "name": "Guest", "race": "Human", "class_title": "Wanderer", "aspect_set": [], "ready": false }
	var c := ClassSystem.resolve(build)
	return {
		"name": build.character_name,
		"race": build.race,
		"class_title": c.get("title", "Wanderer"),
		"aspect_set": c.get("aspect_set", []),
		"ready": false,
		# Full build so the authoritative server can resolve combat (DESIGN.md 4).
		"build": build.to_dict(),
	}

# ---------------------------------------------------------------- host / join
func host_game(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("Could not create server (err %d)." % err)
		return false
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[1] = _local_info()
	server_started.emit(port)
	lobby_updated.emit(players)
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("Could not reach %s:%d (err %d)." % [address, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	return true

## Re-send our character info (e.g. after equipping gear) so the authoritative
## server's combat math reflects the change.
func push_local_update() -> void:
	if not is_active():
		return
	if is_server():
		players[1] = _local_info()
		_sync_roster.rpc(players)
	else:
		_register_player.rpc_id(1, local_id(), _local_info())

func leave() -> void:
	if is_active():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	lobby_updated.emit(players)

# ---------------------------------------------------------------- signals
func _on_peer_connected(_id: int) -> void:
	# A transport-level peer connected. Registration is driven by the client's
	# connected_to_server handler, which RPCs its character info to the server;
	# the server then broadcasts the full roster. Nothing to do here for v0.
	pass

func _on_peer_disconnected(id: int) -> void:
	if is_server():
		players.erase(id)
		_sync_roster.rpc(players)
	player_left.emit(id)

func _on_connected_to_server() -> void:
	# Client successfully connected; announce our character to the server.
	_register_player.rpc_id(1, local_id(), _local_info())
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit("Connection failed.")

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	lobby_updated.emit(players)
	connection_failed.emit("Host closed the lobby.")

# ---------------------------------------------------------------- RPCs
## A peer registers its character with the authority. Server records and
## re-broadcasts the full roster so every client converges on the same truth.
@rpc("any_peer", "call_remote", "reliable")
func _register_player(peer_id: int, info: Dictionary) -> void:
	if is_server():
		players[peer_id] = info
		player_joined.emit(peer_id, info)
		_sync_roster.rpc(players)

## Authority pushes the canonical roster to all clients.
@rpc("authority", "call_local", "reliable")
func _sync_roster(roster: Dictionary) -> void:
	players = roster
	lobby_updated.emit(players)

## A peer toggles ready; the server is the only authority that mutates the
## roster. The host applies its own change directly; clients ask the server.
func set_ready(value: bool) -> void:
	if not is_active():
		return
	if is_server():
		_apply_ready(local_id(), value)
	else:
		_request_ready.rpc_id(1, local_id(), value)

# ---------------------------------------------------------------- start game
## Host launches the party into the shared room; every peer loads it in lockstep.
func start_game() -> void:
	if is_server():
		_load_game.rpc()

@rpc("authority", "call_local", "reliable")
func _load_game() -> void:
	game_started.emit()
	get_tree().change_scene_to_file(GAME_SCENE)

@rpc("any_peer", "call_remote", "reliable")
func _request_ready(peer_id: int, value: bool) -> void:
	# Only meaningful on the server. (TODO v0.x: trust get_remote_sender_id()
	# over the passed peer_id to prevent spoofing.)
	if is_server():
		_apply_ready(peer_id, value)

func _apply_ready(peer_id: int, value: bool) -> void:
	if is_server() and players.has(peer_id):
		players[peer_id]["ready"] = value
		_sync_roster.rpc(players)
