class_name ModelWeapons
extends RefCounted
## Which weapons can each kind of model fire?
##
## A unit card lists every weapon of the unit, but a model only fires its own: in an infantry platoon the rifle
## teams, the anti-tank team and the transport each have different weapons. This class answers
## weapons_for(card, kind of model) -> weapon indexes.
##
## 1. What you specified in the program (card window -> "Weapons per model...", or a unit in the Battle tab) is
##    stored in model_weapons.json: { "<card id>": { "<kind of model>": ["<weapon name>", ...] } }.
##    You can also edit that file by hand.
## 2. Otherwise a guess: weapons whose name shares a distinctive word with the model's name ("Blindicide anti-tank
##    team" -> "Blindicide anti-tank team"); a model that names another card ("AIFV-B-C25 (TBE105)") gets the
##    weapons of that card; anything left gets the weapons nobody else claimed.

const RES_FILE := "res://data/model_weapons.json"
const USER_FILE := "user://model_weapons.json"
## Words that say nothing about which weapon it is.
const GENERIC: Array[String] = ["team", "teams", "anti", "tank", "missile", "missiles", "gun", "guns", "with", "and",
		"the", "mg", "aa", "at", "cal", "rifle", "launcher", "mm", "light", "heavy"]

static var _loaded: bool = false
static var _overrides: Dictionary = {}       # card id -> { kind -> Array of weapon names }
static var _re_ref: RegEx


static func save_path() -> String:
	return RES_FILE if OS.has_feature("editor") else USER_FILE


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_overrides = {}
	_re_ref = RegEx.create_from_string(r"\((T[A-Za-z0-9]+)\)")
	for path in [RES_FILE, USER_FILE]:               # the user file wins
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed
		for id in d:
			if typeof(d[id]) == TYPE_DICTIONARY:
				_overrides[str(id)] = d[id]


static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func save() -> Error:
	_ensure_loaded()
	var f: FileAccess = FileAccess.open(save_path(), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(_overrides, " "))
	f.close()
	return OK


# ------------------------------------------------------------------ kinds of model

## Every kind of model the card can contain (over all its sizes). Transports with their own card are not listed:
## they are a unit of their own in battle.
static func kinds(u: UnitData) -> PackedStringArray:
	var out: PackedStringArray = []
	for o in u.options:
		for item in o.composition:
			if str(item.get("unit_id", "")) != "":
				continue
			var k: String = str(item.get("name", u.display_name))
			if not out.has(k):
				out.append(k)
	if out.is_empty():
		out.append(u.display_name)
	return out


## The other card a model names, e.g. "AIFV-B-C25 (TBE105)" -> card TBE105 (null when it names none).
static func ref_card(kind: String) -> UnitData:
	_ensure_loaded()
	var m: RegExMatch = _re_ref.search(kind)
	if m == null:
		return null
	return UnitDatabase.get_unit(StringName(m.get_string(1)))


## A vehicle or aircraft (it can carry infantry), as opposed to an infantry or gun team.
static func is_vehicle(u: UnitData, kind: String) -> bool:
	if u.category != UnitData.Category.GROUND:
		return true
	var ref: UnitData = ref_card(kind)
	return ref != null and ref.category != UnitData.Category.GROUND


static func is_aircraft(u: UnitData, kind: String) -> bool:
	var ref: UnitData = ref_card(kind)
	if ref != null:
		return ref.category == UnitData.Category.AIR
	return u.category == UnitData.Category.AIR


## Infantry models that fit inside: the N of "Passengers N" on the model's card (0 = it carries nobody inside).
static func capacity(u: UnitData, kind: String) -> int:
	if not is_vehicle(u, kind):
		return 0
	var ref: UnitData = ref_card(kind)
	var card: UnitData = ref if ref != null else u
	for r in card.special_rules:
		var s: String = str(r).strip_edges()
		if s.to_lower().begins_with("passengers"):
			return maxi(int(s.get_slice(" ", 1)), 0)
	return 0


# ------------------------------------------------------------------ weapons

static func _tokens(s: String) -> Array:
	var out: Array = []
	var cur: String = ""
	for ch in s.to_lower() + " ":
		var c: String = ch
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			cur += c
		else:
			if cur.length() >= 2 and not GENERIC.has(cur) and not out.has(cur):
				out.append(cur)
			cur = ""
	return out


static func _name_matches(u: UnitData, kind: String) -> Array:
	var kt: Array = _tokens(kind)
	var out: Array = []
	for i in u.weapons.size():
		for t in _tokens(u.weapons[i].weapon_name):
			if kt.has(t):
				out.append(i)
				break
	return out


## The guess used when nothing was specified.
static func default_for(u: UnitData, kind: String) -> Array:
	var out: Array = _name_matches(u, kind)
	if not out.is_empty():
		return out
	var ref: UnitData = ref_card(kind)
	if ref != null:                                   # the weapons of the card the model names
		for i in u.weapons.size():
			for rw in ref.weapons:
				if rw.weapon_name.to_lower() == u.weapons[i].weapon_name.to_lower():
					out.append(i)
					break
		if not out.is_empty():
			return out
	var claimed: Dictionary = {}                      # weapons that clearly belong to another kind of model
	for other in kinds(u):
		if other != kind:
			for i in _name_matches(u, other):
				claimed[i] = true
	for i in u.weapons.size():
		if not claimed.has(i):
			out.append(i)
	if out.is_empty():
		for i in u.weapons.size():
			out.append(i)
	return out


static func has_override(u: UnitData, kind: String) -> bool:
	_ensure_loaded()
	return _overrides.has(String(u.id)) and (_overrides[String(u.id)] as Dictionary).has(kind)


## Weapon indexes (into u.weapons) a model of this kind can fire.
static func weapons_for(u: UnitData, kind: String) -> Array:
	_ensure_loaded()
	if has_override(u, kind):
		var names: Array = (_overrides[String(u.id)] as Dictionary)[kind]
		var out: Array = []
		for i in u.weapons.size():
			if names.has(u.weapons[i].weapon_name):
				out.append(i)
		return out
	return default_for(u, kind)


## Stores what you specified (call save() afterwards).
static func set_override(u: UnitData, kind: String, weapon_indexes: Array) -> void:
	_ensure_loaded()
	var id: String = String(u.id)
	if not _overrides.has(id):
		_overrides[id] = {}
	var names: Array = []
	for i in weapon_indexes:
		if int(i) >= 0 and int(i) < u.weapons.size():
			names.append(u.weapons[int(i)].weapon_name)
	(_overrides[id] as Dictionary)[kind] = names


## Back to the automatic guess for the whole card.
static func clear_override(u: UnitData) -> void:
	_ensure_loaded()
	_overrides.erase(String(u.id))
