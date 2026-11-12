class_name FormationDB
extends RefCounted
## The formations of every nation, loaded on first use from res://data/formations/*_formation_data.json
## (one file per nation, same prefix as the unit file: us_formation_data.json, ussr_formation_data.json ...).
## The file format is explained in the "_help" list of data/formations/ussr_formation_data.json.
## The Formations section (FormationEditor) changes formations with put() / remove() and writes a nation's file with
## save_nation(). Run from the editor the file in res://data/formations is rewritten; in an exported program the
## copy goes to user://formations, which is then read instead of the res:// file of the same name.

const DIR := "res://data/formations"
const USER_DIR := "user://formations"
const SUFFIX := "_formation_data.json"

static var _loaded: bool = false
static var _by_id: Dictionary = {}       # formation id -> FormationData
static var _order: Array = []            # FormationData in file order
static var _files: Dictionary = {}       # nation -> file name ("ussr_formation_data.json")
static var _help: Dictionary = {}        # file name -> its "_help" list (kept when saving)
## When set, save_nation writes here instead (the smoke test uses it so the real files are not touched).
static var save_dir_override: String = ""


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var names: Array = []
	for d: String in [DIR, USER_DIR]:
		if DirAccess.dir_exists_absolute(d):
			for file in DirAccess.get_files_at(d):
				if file.ends_with(SUFFIX) and not names.has(file):
					names.append(file)
	names.sort()
	for file: String in names:
		var user_path: String = USER_DIR.path_join(file)
		var use_user: bool = not OS.has_feature("editor") and FileAccess.file_exists(user_path)
		load_file(user_path if use_user else DIR.path_join(file))
	add_hq_formations()


## Every HQ card leads its own formation: for each HQ card (UnitData.is_hq, not attachments) that no formation uses
## as its HQ yet, a blank formation is made - no division, no slots, named after the card without "HQ"
## ("T-80 Shock Tank Company HQ" -> "T-80 Shock Tank Company"). The nations that got new ones are saved, so this
## happens once per card. Returns how many were made.
static func add_hq_formations() -> int:
	var used: Dictionary = {}
	for f: FormationData in _order:
		used[f.hq] = true
	var cards: Array = []
	for u: UnitData in UnitDatabase.units.values():
		if u.is_hq() and not u.is_attachment and not used.has(String(u.id)):
			cards.append(u)
	cards.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		return a.nation < b.nation if a.nation != b.nation else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	var nations: Array = []
	for u: UnitData in cards:
		var f: FormationData = FormationData.new()
		f.nation = u.nation
		f.name = name_from_hq(u.display_name)
		f.hq = String(u.id)
		f.id = new_id(f.nation, f.name)
		_by_id[f.id] = f
		_order.append(f)
		if not nations.has(u.nation):
			nations.append(u.nation)
	for n: String in nations:
		var err: String = save_nation(n)
		if err != "":
			push_warning(err)
	return cards.size()


## The formation name for an HQ card: its name without the word "HQ".
static func name_from_hq(card_name: String) -> String:
	var words: PackedStringArray = []
	for w in card_name.strip_edges().split(" ", false):
		if w != "HQ":
			words.append(w)
	var out: String = " ".join(words).trim_suffix(":").strip_edges()
	return out if out != "" else card_name.strip_edges()


## Forgets everything and reads the files again on the next call.
static func reload() -> void:
	_loaded = false
	_by_id.clear()
	_order.clear()
	_files.clear()
	_help.clear()


## Reads one formation file. Returns how many formations it added.
static func load_file(path: String) -> int:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Formation file %s is not valid JSON" % path)
		return 0
	var nation: String = str(parsed.get("nation", ""))
	if nation != "" and not _files.has(nation):
		_files[nation] = path.get_file()
	if parsed.has("_help"):
		_help[path.get_file()] = parsed["_help"]
	var n: int = 0
	for d in parsed.get("formations", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var f: FormationData = FormationData.from_dict(d, nation)
		if f.id == "":
			push_warning("%s: a formation has no id" % path.get_file())
			continue
		if _by_id.has(f.id):
			push_warning("%s: formation id %s is used twice; the later one wins" % [path.get_file(), f.id])
			_order.erase(_by_id[f.id])
		_by_id[f.id] = f
		_order.append(f)
		n += 1
	return n


static func get_formation(id: String) -> FormationData:
	_ensure()
	return _by_id.get(id)


## Formations of one nation ("" = every nation), in file order.
static func for_nation(nation: String) -> Array:
	_ensure()
	var out: Array = []
	for f: FormationData in _order:
		if nation == "" or f.nation == nation:
			out.append(f)
	return out


## The division names used by a nation's formations, sorted.
static func divisions(nation: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f: FormationData in for_nation(nation):
		if f.division != "" and not out.has(f.division):
			out.append(f.division)
	out.sort()
	return out


## Card ids that are named in some formation (HQs and slot units) - for checks and reports.
static func card_ids() -> Dictionary:
	_ensure()
	var out: Dictionary = {}
	for f: FormationData in _order:
		out[f.hq] = true
		for s in f.slots:
			for uid in s["units"]:
				out[str(uid)] = true
	return out


# ------------------------------------------------------------------ editing (FormationEditor)

## A formation id not used yet, made from the nation and the name ("soviet_btr_60_motor_rifle_battalion").
static func new_id(nation: String, fname: String) -> String:
	_ensure()
	var base: String = ""
	for c in ("%s_%s" % [nation, fname]).to_lower():
		base += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while base.contains("__"):
		base = base.replace("__", "_")
	base = base.strip_edges().trim_prefix("_").trim_suffix("_")
	if base == "":
		base = "formation"
	var id: String = base
	var n: int = 2
	while _by_id.has(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id


## Adds a formation or replaces the one with the same id (keeping its place in the list).
static func put(f: FormationData) -> void:
	_ensure()
	var old: FormationData = _by_id.get(f.id)
	if old != null:
		_order[_order.find(old)] = f
	else:
		_order.append(f)
	_by_id[f.id] = f


static func remove(id: String) -> void:
	_ensure()
	var f: FormationData = _by_id.get(id)
	if f != null:
		_order.erase(f)
		_by_id.erase(id)


## The file name of a nation's formations: the one it was read from, else <unit file prefix>_formation_data.json.
static func file_name(nation: String) -> String:
	_ensure()
	if _files.has(nation):
		return str(_files[nation])
	var prefix: String = str(UnitDatabase.nation_prefix.get(nation, nation.to_lower().replace(" ", "")))
	return prefix + SUFFIX


## Where save_nation writes: res:// when run from the Godot editor, user:// in an exported program.
static func save_path(nation: String) -> String:
	var dir: String = DIR if OS.has_feature("editor") else USER_DIR
	if save_dir_override != "":
		dir = save_dir_override
	return dir.path_join(file_name(nation))


## Writes every formation of `nation` to its file. Returns "" or the error text.
static func save_nation(nation: String) -> String:
	_ensure()
	var path: String = save_path(nation)
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var fname: String = path.get_file()
	var data: Dictionary = {}
	if not _help.has(fname) and not _help.is_empty():
		_help[fname] = _help.values()[0]            # a new nation file gets the same explanation as the others
	if _help.has(fname):
		data["_help"] = _help[fname]
	data["nation"] = nation
	var list: Array = []
	for f: FormationData in for_nation(nation):
		list.append(f.to_dict())
	data["formations"] = list
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write %s (error %d)" % [path, FileAccess.get_open_error()]
	file.store_string(JSON.stringify(data, "  ", false) + "\n")
	file.close()
	_files[nation] = fname
	return ""
