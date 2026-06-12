extends Node
## Autoload. Holds the local player's session state and the active character.
## Deliberately thin — gameplay-authoritative state lives on the server
## (NetworkManager); this is the local client's view.

signal character_changed(build: CharacterBuild)

var player_build: CharacterBuild = null

func set_character(build: CharacterBuild) -> void:
	player_build = build
	character_changed.emit(build)

func has_character() -> bool:
	return player_build != null

## Convenience: current resolved class identity, or empty if no character yet.
func current_class() -> Dictionary:
	if player_build == null:
		return {}
	return ClassSystem.resolve(player_build)
