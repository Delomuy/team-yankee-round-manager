class_name ArmyFiles
extends RefCounted
## Saved armies: one JSON file per army in the saved_army folder, named NAME_NATION_army.json
## (e.g. "Red Guard_Soviet_army.json"). Run from the Godot editor the folder is res://saved_army (inside the
## project); in an exported program it is user://saved_army. The format is Army.to_dict (with or without a
## formation). Used by the Saved armies page of the Armies section (SavedArmiesPage).

const DIR := "res://saved_army"
const USER_DIR := "user://saved_army"
const SUFFIX := "_army.json"
## Characters a file name cannot hold (Windows); they become "-".
const BAD_CHARS := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", "_"]

## When set, armies are saved here instead (the smoke test uses it).
static var dir_override: String = ""


static func folder() -> String:
	if dir_override != "":
		return dir_override
	return DIR if OS.has_feature("editor") else USER_DIR


## The folder as a path the system understands (to open it in the file explorer).
static func folder_global() -> String:
	return ProjectSettings.globalize_path(folder())


## A name or nation made safe for a file name. "_" separates the parts, so it is replaced too.
static func _safe(text: String) -> String:
	var out: String = text.strip_edges()
	for c in BAD_CHARS:
		out = out.replace(c, "-")
	return out if out != "" else "Army"


## "NAME_NATION_army.json" for an army.
static func file_name(army: Army) -> String:
	return "%s_%s%s" % [_safe(army.army_name), _safe(army.nation), SUFFIX]


static func path_for(army: Army) -> String:
	return folder().path_join(file_name(army))


## True when saving `army` would replace a file of another army (same name and nation).
static func would_replace_other(army: Army) -> bool:
	var path: String = path_for(army)
	return FileAccess.file_exists(path) and path != army.saved_path


## Saves the army to the saved_army folder. When the army was saved before under another name, that old file is
## removed (it is the same army, renamed). Returns "" or the error text.
static func save(army: Army) -> String:
	var dir: String = folder()
	if not DirAccess.dir_exists_absolute(dir):
		var e: Error = DirAccess.make_dir_recursive_absolute(dir)
		if e != OK:
			return "Could not make the folder %s (error %d)" % [dir, e]
	var path: String = path_for(army)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not write %s (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(army.to_json() + "\n")
	f.close()
	if army.saved_path != "" and army.saved_path != path and FileAccess.file_exists(army.saved_path) \
			and army.saved_path.get_base_dir() == dir:
		DirAccess.remove_absolute(army.saved_path)
	army.mark_saved(path)
	return ""


## Reads a saved army file. Returns {"army": Army or null, "warnings": PackedStringArray, "error": String}.
## With Settings > Use formations on, an army without a formation is refused.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"army": null, "warnings": PackedStringArray(), "error": "File not found: %s" % path}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"army": null, "warnings": PackedStringArray(), "error": "%s is not valid JSON." % path.get_file()}
	var res: Dictionary = Army.from_dict(parsed)
	var a: Army = res["army"]
	if a == null:
		return res
	if AppSettings.use_formations() and not a.has_formation():
		return {"army": null, "warnings": res["warnings"],
				"error": "%s has no formation, and Settings > Use formations is on." % a.army_name}
	if path.get_base_dir() == folder() and (res["warnings"] as PackedStringArray).is_empty():
		a.mark_saved(path)                   # loaded unchanged from the folder: it counts as saved
	return res


## A short description of every saved army, newest first:
## [{"path", "file", "name", "nation", "points", "formation", "units", "modified", "error"}]
static func list() -> Array:
	var out: Array = []
	var dir: String = folder()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(SUFFIX):
			continue
		var path: String = dir.path_join(file)
		var info: Dictionary = {"path": path, "file": file, "name": file.trim_suffix(SUFFIX), "nation": "", "points": 0,
				"formation": "", "units": 0, "modified": FileAccess.get_modified_time(path), "error": ""}
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("format", "")) != "TY helper army":
			info["error"] = "not a saved army file"
		else:
			info["name"] = str(parsed.get("army_name", info["name"]))
			info["nation"] = str(parsed.get("nation", ""))
			info["points"] = int(parsed.get("total_points", 0))
			info["units"] = (parsed.get("entries", []) as Array).size()
			var forms: Array = parsed.get("formations", [])
			if bool(parsed.get("use_formations", false)) and not forms.is_empty():
				info["formation"] = str((forms[0] as Dictionary).get("name", (forms[0] as Dictionary).get("formation_id", "")))
		out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["modified"]) > int(b["modified"]))
	return out


## Copies a saved army file from anywhere into the saved_army folder (named after the army inside it).
## Returns {"path": the new path or "", "error": String}.
static func import_file(source: String) -> Dictionary:
	var res: Dictionary = load_file(source)
	var a: Army = res["army"]
	if a == null:
		return {"path": "", "error": str(res["error"])}
	if not DirAccess.dir_exists_absolute(folder()):
		DirAccess.make_dir_recursive_absolute(folder())
	var path: String = path_for(a)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"path": "", "error": "Could not write %s" % path}
	f.store_string(FileAccess.get_file_as_string(source))
	f.close()
	return {"path": path, "error": ""}


static func delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
