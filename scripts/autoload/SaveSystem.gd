extends Node
## Autoload. Local character persistence to user:// as JSON. Designed so the same
## CharacterBuild.to_dict()/from_dict() round-trip can later be sent to a server
## for cloud saves with no model changes (DESIGN.md roadmap v0.4).

const SAVE_PATH := "user://savegame.json"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save(build: CharacterBuild) -> void:
	if build == null:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(build.to_dict(), "\t"))

func load_build() -> CharacterBuild:
	if not has_save():
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: save file is corrupt")
		return null
	return CharacterBuild.from_dict(parsed)

func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
