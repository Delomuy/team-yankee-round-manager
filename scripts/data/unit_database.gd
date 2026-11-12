extends Node
## Autoload as "UnitDatabase". Loads every nation file (data/*_units.json) into typed UnitData resources.
## Create those files from the .txt copies with:  python tools/convert_units.py --all
##
## Cards made, copied or changed in the program (Cards > New card / Edit / Copy, see UnitEditor) are kept apart in
## data/custom/<prefix>_units.json (user://custom_units in an exported program). They are read after the main files
## and replace a main card with the same id, so converting the cards again never loses them, and a changed main card
## can be restored (remove_custom).

## A card was made, changed, restored or deleted in the program (the card grids update that card).
signal cards_changed(id: String)

const DATA_DIR := "res://data"
const CUSTOM_DIR := "res://data/custom"
const CUSTOM_USER_DIR := "user://custom_units"

var units: Dictionary = {}   # StringName -> UnitData
## Nation -> file prefix of its unit file ("Soviet" -> "ussr" from ussr_units.json). FormationDB uses it to name
## a nation's formation file.
var nation_prefix: Dictionary = {}
## Ids of the cards saved in the custom files (new, copied or changed cards) -> true.
var custom_ids: Dictionary = {}
## When set, the custom files are written here instead (the smoke test uses it).
var custom_dir_override: String = ""
var _base: Dictionary = {}           # id -> the card's dictionary from the main files (for "Restore original")
var _custom_nations: Dictionary = {} # nations that have a custom file -> true (rewritten even when emptied)


func _ready() -> void:
	load_all()


## Loads every .json file in res://data (or, if there is none, anywhere under res://), then the custom cards.
## Returns the file count.
func load_all() -> int:
	var files: Array[String] = []
	_collect_json(DATA_DIR, files, false)
	if files.is_empty():
		_collect_json("res://", files, true)
	var count: int = 0
	for f in files:
		if load_from_file(f):
			count += 1
	if count == 0:
		push_error("No unit .json files found. Run: python tools/convert_units.py --all")
	load_custom()
	return count


## Reads the custom card files (see the class comment). In an exported program the user:// copy of a file wins.
func load_custom(dir_path: String = "") -> void:
	var dirs: Array = [dir_path] if dir_path != "" else [CUSTOM_DIR, CUSTOM_USER_DIR]
	var names: Array = []
	for d: String in dirs:
		if DirAccess.dir_exists_absolute(d):
			for file in DirAccess.get_files_at(d):
				if file.ends_with("_units.json") and not names.has(file):
					names.append(file)
	names.sort()
	for file: String in names:
		var path: String = str(dirs[0]).path_join(file)
		if dir_path == "":
			var user_path: String = CUSTOM_USER_DIR.path_join(file)
			if not OS.has_feature("editor") and FileAccess.file_exists(user_path):
				path = user_path
			elif not FileAccess.file_exists(path):
				path = user_path
		load_from_file(path, true)


func _collect_json(dir_path: String, out: Array[String], recursive: bool) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension().to_lower() == "json":
			out.append(dir_path.path_join(file))
	if recursive:
		for sub in DirAccess.get_directories_at(dir_path):
			if not sub.begins_with("."):
				_collect_json(dir_path.path_join(sub), out, true)


## Reads one unit file. `custom` = a file of cards made in the program (they replace main cards silently).
func load_from_file(path: String, custom: bool = false) -> bool:
	if not FileAccess.file_exists(path):
		push_error("Unit data not found: %s" % path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("units"):
		push_warning("Skipped %s: no \"units\" list (run tools/convert_units.py on it?)" % path)
		return false
	if custom:
		_custom_nations[str(parsed.get("nation", ""))] = true
	for d in parsed["units"]:
		var u := _build(d)
		if u:
			if units.has(u.id) and not custom:
				push_warning("Unit id %s from %s replaces an earlier one" % [u.id, path.get_file()])
			units[u.id] = u
			if custom:
				custom_ids[String(u.id)] = true
				_custom_nations[u.nation] = true
			else:
				_base[String(u.id)] = d
			if path.get_file().ends_with("_units.json") and not nation_prefix.has(u.nation):
				nation_prefix[u.nation] = path.get_file().trim_suffix("_units.json")
	_custom_nations.erase("")
	return true


# ------------------------------------------------------------------ cards made in the program (UnitEditor)

## True for a card saved in the custom files (new, copied or changed).
func is_custom(id: String) -> bool:
	return custom_ids.has(id)


## True when the card comes from the main files (a changed one can be restored).
func has_original(id: String) -> bool:
	return _base.has(id)


## A card id not used yet, made from `id`: "TS123" -> "TS123c", "TS123c2" ...
func free_id(id: String) -> String:
	var base: String = id.strip_edges()
	if base == "":
		base = "NEW"
	var n: int = 1
	var out: String = base + "c"
	while units.has(StringName(out)):
		n += 1
		out = "%sc%d" % [base, n]
	return out


## Builds a card from a dictionary in the unit file format (see unit_to_dict). Null when the category is unknown.
func build_unit(d: Dictionary) -> UnitData:
	return _build(d)


## Adds or replaces a card made or changed in the program and writes the custom files.
## Returns "" or the error text.
func save_custom(d: Dictionary) -> String:
	var u: UnitData = _build(d)
	if u == null:
		return "Unknown category"
	if String(u.id) == "":
		return "The card has no id"
	units[u.id] = u
	custom_ids[String(u.id)] = true
	_custom_nations[u.nation] = true
	var err: String = write_custom()
	cards_changed.emit(String(u.id))
	return err


## Adds or replaces several cards at once (the card import) and writes the custom files once.
## Returns "" or the error text.
func save_custom_many(dicts: Array) -> String:
	var ids: PackedStringArray = []
	for d: Dictionary in dicts:
		var u: UnitData = _build(d)
		if u == null or String(u.id) == "":
			continue
		units[u.id] = u
		custom_ids[String(u.id)] = true
		_custom_nations[u.nation] = true
		ids.append(String(u.id))
	var err: String = write_custom()
	for id in ids:
		cards_changed.emit(id)
	return err


## Takes a card out of the custom files: a changed main card goes back to its original, a new card is removed.
## Returns "" or the error text.
func remove_custom(id: String) -> String:
	if not custom_ids.has(id):
		return ""
	custom_ids.erase(id)
	if _base.has(id):
		var u: UnitData = _build(_base[id])
		if u != null:
			units[u.id] = u
	else:
		units.erase(StringName(id))
	var err: String = write_custom()
	cards_changed.emit(id)
	return err


## Where the custom card files go: res://data/custom from the Godot editor, user://custom_units exported.
func custom_dir() -> String:
	if custom_dir_override != "":
		return custom_dir_override
	return CUSTOM_DIR if OS.has_feature("editor") else CUSTOM_USER_DIR


## Rewrites the custom file of every nation that has (or had) custom cards. Returns "" or the error text.
func write_custom() -> String:
	var dir: String = custom_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var by_nation: Dictionary = {}
	for n in _custom_nations:
		by_nation[n] = []
	var ids: Array = custom_ids.keys()
	ids.sort()
	for id in ids:
		var u: UnitData = units.get(StringName(id))
		if u == null:
			continue
		if not by_nation.has(u.nation):
			by_nation[u.nation] = []
		(by_nation[u.nation] as Array).append(unit_to_dict(u))
	for n: String in by_nation:
		var prefix: String = str(nation_prefix.get(n, n.to_lower().replace(" ", "")))
		var path: String = dir.path_join(prefix + "_units.json")
		var data: Dictionary = {
			"_help": "Cards made, copied or changed in the program (Cards > New card / Edit / Copy). They replace the "
					+ "card with the same id in data/" + prefix + "_units.json. Remove one with 'Restore original' or 'Delete card'.",
			"nation": n,
			"units": by_nation[n],
		}
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return "Could not write %s (error %d)" % [path, FileAccess.get_open_error()]
		f.store_string(JSON.stringify(data, "  ", false) + "\n")
		f.close()
	return ""


## The card as a dictionary in the unit file format (the reverse of _build).
func unit_to_dict(u: UnitData) -> Dictionary:
	var d: Dictionary = {
		"id": String(u.id),
		"name": u.display_name,
		"nation": u.nation,
		"category": ["armored", "ground", "air"][u.category],
		"unit_type": u.unit_type,
		"special_rules": Array(u.special_rules),
		"tactical": u.tactical, "terrain_dash": u.terrain_dash, "cross_dash": u.cross_dash,
		"road_dash": u.road_dash, "cross_skill": u.cross_skill,
		"courage": u.courage, "morale": u.morale, "rally": u.rally, "remount": u.remount, "skill": u.skill,
		"assault": u.assault, "counterattack": u.counterattack, "is_hit_on": u.is_hit_on, "save": u.save,
	}
	if u is ArmoredUnitData:
		var a: ArmoredUnitData = u
		d["armour_front"] = a.armour_front
		d["armour_side"] = a.armour_side
		d["armour_top"] = a.armour_top
	if u is GroundUnitData:
		var g: GroundUnitData = u
		if not g.transport_ids.is_empty():
			d["transport_id"] = String(g.transport_id)
			d["transport_name"] = g.transport_name
			d["transport_ids"] = Array(g.transport_ids)
	if u is AirUnitData:
		d["aircraft_type"] = (u as AirUnitData).aircraft_type
	if u.is_attachment:
		d["is_attachment"] = true
	if u.passengers > 0:
		d["passengers"] = u.passengers
	if String(u.part_of) != "":
		d["part_of"] = String(u.part_of)
	if not u.attached_ids.is_empty():
		d["attached_ids"] = Array(u.attached_ids)
	var opts: Array = []
	for o: UnitOption in u.options:
		var comp: Array = []
		for item in o.composition:
			comp.append((item as Dictionary).duplicate())
		opts.append({"label": o.label, "models": o.models, "transport_models": o.transport_models,
				"points": o.points, "points_dynamic": o.points_dynamic, "composition": comp})
	d["options"] = opts
	if not u.upgrades.is_empty():
		var ups: Array = []
		for up in u.upgrades:
			ups.append((up as Dictionary).duplicate())
		d["upgrades"] = ups
	if not u.notes.is_empty():
		d["notes"] = Array(u.notes)
	var ws: Array = []
	for w: WeaponData in u.weapons:
		ws.append({"name": w.weapon_name, "range_cm_min": w.range_cm_min, "range_cm": w.range_cm,
				"rof_static": w.rof_static, "rof_moving": w.rof_moving, "salvo": w.salvo, "artillery": w.artillery,
				"anti_tank": w.anti_tank, "firepower": w.firepower, "rules": Array(w.rules)})
	d["weapons"] = ws
	d["max_copies"] = u.max_copies
	d["exclusive_with"] = Array(u.exclusive_with)
	d["formation_only"] = u.formation_only
	return d


## Card ids that use `transport_id` as their transport (in a size's models or in transport_ids).
func users_of_transport(transport_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for u: UnitData in units.values():
		var uses: bool = u is GroundUnitData and (u as GroundUnitData).transport_ids.has(transport_id)
		for o: UnitOption in u.options:
			for item in o.composition:
				if str((item as Dictionary).get("unit_id", "")) == transport_id:
					uses = true
		if uses:
			out.append(String(u.id))
	out.sort()
	return out


## Cards that can carry others: attachments with a Passengers rule or a passenger number, sorted by nation and name.
func transport_cards() -> Array:
	var out: Array = []
	for u: UnitData in units.values():
		var carries: bool = u.passengers > 0
		for r in u.special_rules:
			if r.begins_with("Passengers"):
				carries = true
		if carries:
			out.append(u)
	out.sort_custom(func(a: UnitData, b: UnitData) -> bool:
		return a.nation < b.nation if a.nation != b.nation else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return out


func get_unit(id: StringName) -> UnitData:
	return units.get(id)


## Attachments (transports etc.) are hidden unless include_attachments is true.
func query(nation: String = "", category: int = -1, include_attachments: bool = false) -> Array[UnitData]:
	var out: Array[UnitData] = []
	for u in units.values():
		if u.is_attachment and not include_attachments:
			continue
		if nation != "" and u.nation != nation:
			continue
		if category != -1 and u.category != category:
			continue
		out.append(u)
	out.sort_custom(func(a, b): return a.display_name < b.display_name)
	return out


## Every nation: the ones with cards and the ones added in the program (NationDB), sorted.
func get_nations() -> Array[String]:
	var out: Array[String] = []
	for n in NationDB.all():
		out.append(str(n))
	return out


# ---------------------------------------------------------------------------

func _build(d: Dictionary) -> UnitData:
	var u: UnitData
	match str(d.get("category", "")).to_lower():
		"armored": u = ArmoredUnitData.new()
		"ground": u = GroundUnitData.new()
		"air": u = AirUnitData.new()
		_:
			push_error("Unit '%s' has unknown category" % d.get("id", "?"))
			return null

	u.display_name = str(d.get("name", ""))
	_assign(u, d)

	for o in d.get("options", []):
		u.options.append(UnitOption.from_dict(o))
	for w in d.get("weapons", []):
		u.weapons.append(WeaponData.from_dict(w))
	return u


## Copies matching JSON keys onto the resource, fixing JSON's float/array types.
## Keys the resource doesn't have are ignored.
func _assign(u: UnitData, d: Dictionary) -> void:
	for key in d:
		if key in ["category", "weapons", "options"] or not (key in u):
			continue
		match typeof(u.get(key)):
			TYPE_INT: u.set(key, int(d[key]))
			TYPE_STRING_NAME: u.set(key, StringName(d[key]))
			TYPE_PACKED_STRING_ARRAY: u.set(key, PackedStringArray(d[key]))
			_: u.set(key, d[key])
