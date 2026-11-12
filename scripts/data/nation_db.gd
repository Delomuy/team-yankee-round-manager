class_name NationDB
extends RefCounted
## The nations the program knows: the ones in the unit files plus the ones added in the program ("New nation...",
## NationDialog). An added nation is kept in data/custom/nations.json (user://custom_units/nations.json exported):
##   {"nations": [{"name": "French", "label": "France", "prefix": "france", "color": "#2a4f9a"}]}
## name   = the nation as written in unit files ("American", "WestGerman" ...)
## label  = how it is shown (RulesDB.nation_label falls back to it)
## prefix = file prefix of its unit / custom / formation files (france_units.json ...)
## color  = the colour of its cards (CardTile.nation_color_for falls back to it)

const FILE_NAME := "nations.json"

static var _loaded: bool = false
static var _added: Dictionary = {}          # name -> {"name", "label", "prefix", "color"}


## nations.json lives next to the custom card files (UnitDatabase.custom_dir(); the smoke test redirects that folder
## with UnitDatabase.custom_dir_override).
static func _path() -> String:
	return UnitDatabase.custom_dir().path_join(FILE_NAME)


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_added.clear()
	var paths: Array = [_path()]
	if UnitDatabase.custom_dir_override == "":
		paths = [UnitDatabase.CUSTOM_DIR.path_join(FILE_NAME), UnitDatabase.CUSTOM_USER_DIR.path_join(FILE_NAME)]
		if not OS.has_feature("editor"):
			paths.reverse()                       # exported: the user:// copy wins
	for p: String in paths:
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for n in parsed.get("nations", []):
			var d: Dictionary = n
			var nm: String = str(d.get("name", "")).strip_edges()
			if nm != "" and not _added.has(nm):
				_added[nm] = {"name": nm, "label": str(d.get("label", nm)), "prefix": str(d.get("prefix", prefix_for_name(nm))),
						"color": str(d.get("color", ""))}
		break
	for nm in _added:
		if not UnitDatabase.nation_prefix.has(nm):
			UnitDatabase.nation_prefix[nm] = str(_added[nm]["prefix"])


## Forgets the added nations and reads the file again on the next call.
static func reload() -> void:
	_loaded = false


## Every nation: the ones with cards and the added ones, sorted.
static func all() -> Array:
	_ensure()
	var out: Array = []
	for u: UnitData in UnitDatabase.units.values():
		if u.nation != "" and not out.has(u.nation):
			out.append(u.nation)
	for nm in _added:
		if not out.has(nm):
			out.append(nm)
	out.sort()
	return out


## True for a nation added in the program.
static func is_added(nation: String) -> bool:
	_ensure()
	return _added.has(nation)


## The added nation's label, or "" (RulesDB.nation_label uses it for nations it does not know).
static func label(nation: String) -> String:
	_ensure()
	return str((_added.get(nation, {}) as Dictionary).get("label", ""))


## The added nation's colour; `ok` false when the nation was not added or has none.
static func color(nation: String) -> Dictionary:
	_ensure()
	var c: String = str((_added.get(nation, {}) as Dictionary).get("color", ""))
	if c == "" or not Color.html_is_valid(c):
		return {"ok": false}
	return {"ok": true, "color": Color.html(c)}


## "New Zealand" -> "newzealand": lower case letters and digits only.
static func prefix_for_name(name: String) -> String:
	var out: String = ""
	for ch in name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out if out != "" else "nation"


## Why a nation cannot be added with these values ("" = it can).
static func add_problem(name: String, prefix: String) -> String:
	_ensure()
	var nm: String = name.strip_edges()
	if nm == "":
		return "Type the nation's name."
	if all().has(nm):
		return "There is already a nation called %s." % nm
	if prefix_for_name(prefix) != prefix or prefix == "":
		return "The file prefix may only hold lower-case letters and digits."
	for other in UnitDatabase.nation_prefix:
		if str(UnitDatabase.nation_prefix[other]) == prefix:
			return "The file prefix %s is used by %s." % [prefix, other]
	return ""


## Adds a nation and saves nations.json. Returns "" or the error text.
static func add(name: String, shown: String, prefix: String, col: Color) -> String:
	var p: String = add_problem(name, prefix)
	if p != "":
		return p
	var nm: String = name.strip_edges()
	_added[nm] = {"name": nm, "label": shown.strip_edges() if shown.strip_edges() != "" else nm, "prefix": prefix,
			"color": "#" + col.to_html(false)}
	UnitDatabase.nation_prefix[nm] = prefix
	return _save()


## Removes an added nation that has no cards left. Returns "" or why not.
static func remove(name: String) -> String:
	_ensure()
	if not _added.has(name):
		return "%s was not added in the program." % name
	for u: UnitData in UnitDatabase.units.values():
		if u.nation == name:
			return "%s still has cards; delete them first." % name
	_added.erase(name)
	UnitDatabase.nation_prefix.erase(name)
	return _save()


static func _save() -> String:
	var path: String = _path()
	if not DirAccess.dir_exists_absolute(path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var list: Array = []
	var names: Array = _added.keys()
	names.sort()
	for nm in names:
		list.append(_added[nm])
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not write %s (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify({"_help": "Nations added in the program (Cards > Nations ... / New nation). "
			+ "name = as in the unit files, label = shown, prefix = file prefix, color = card colour.", "nations": list}, "  ", false) + "\n")
	f.close()
	return ""
