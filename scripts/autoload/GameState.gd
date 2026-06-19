extends Node
## Autoload. Holds the local player's session state and the active character.
## Deliberately thin — gameplay-authoritative state lives on the server
## (NetworkManager); this is the local client's view.

signal character_changed(build: CharacterBuild)
signal loot_received(item: Dictionary)

var player_build: CharacterBuild = null

func set_character(build: CharacterBuild) -> void:
	player_build = build
	character_changed.emit(build)
	save()

## Persist the active character. Called on every meaningful change.
func save() -> void:
	if player_build != null:
		SaveSystem.save(player_build)

## Add a looted item to the active character's bag and persist (called when the
## authoritative server grants a drop). See DungeonRoom._grant_loot.
func receive_loot(item: Dictionary) -> void:
	if player_build == null:
		return
	player_build.inventory.append(item)
	save()
	loot_received.emit(item)

func has_character() -> bool:
	return player_build != null

## Convenience: current resolved class identity, or empty if no character yet.
func current_class() -> Dictionary:
	if player_build == null:
		return {}
	return ClassSystem.resolve(player_build)
