class_name Army
extends Resource
## A player's army list: support units (ArmyEntry.formation == "") and, when `use_formations` is on, formations
## (FormationData from data/formations) whose HQ and slots are filled with entries of their own.
## Limits (Settings > "Limit unit quantities", UnitData.max_copies / exclusive_with) only count support units;
## inside a formation the slots are the limit.

@export var army_name: String = "Army"
@export var nation: String = ""          ## the main army (nation) of this player
@export var points_limit: int = 0         ## 0 = no limit
@export var owner_id: int = 0
@export var entries: Array[ArmyEntry] = []
## This army uses a formation ("Uses a formation" on the Armies set-up page; edited on the FormationScreen).
@export var use_formations: bool = false
## The formations taken: [{"key": "f1", "formation_id": String}] in the order they were added.
@export var formations: Array = []
@export var _next_formation: int = 1
## The saved_army file this army was last saved to or loaded from ("" = never saved) and its contents at that moment
## (to_json), so is_saved() can tell whether it changed since (ArmyFiles).
var saved_path: String = ""
var saved_json: String = ""


func add_unit(unit_id: StringName, option_index: int, formation: String = "", upgrades: Dictionary = {}) -> ArmyEntry:
	var u := UnitDatabase.get_unit(unit_id)
	if u == null:
		push_error("Unknown unit id: %s" % unit_id)
		return null
	if u.get_option(option_index) == null:
		push_error("Unit %s has no option %d" % [unit_id, option_index])
		return null
	var e := ArmyEntry.new()
	e.unit_id = unit_id
	e.option_index = option_index
	e.formation = formation
	e.upgrades = upgrades.duplicate()
	entries.append(e)
	return e


func remove_entry(index: int) -> void:
	if index >= 0 and index < entries.size():
		entries.remove_at(index)


func total_points() -> int:
	var total := 0
	for e in entries:
		total += e.get_points()
	return total


## The support entries (outside formations) merged by unit, size and ticked upgrades, in the order they were first
## bought: [{"unit_id": id, "option_index": i, "upgrades": {idx: qty}, "key": String, "count": n}, ...]
func groups() -> Array:
	var out: Array = []
	var where: Dictionary = {}
	for e in entries:
		if e.in_formation():
			continue
		var k: String = e.key()
		if where.has(k):
			var g: Dictionary = out[where[k]]
			g["count"] = int(g["count"]) + 1
		else:
			where[k] = out.size()
			out.append({"unit_id": e.unit_id, "option_index": e.option_index, "upgrades": e.upgrades, "key": k, "count": 1})
	return out


## Support copies bought with exactly these upgrades (none by default).
func count_of(unit_id: StringName, option_index: int, upgrades: Dictionary = {}) -> int:
	var k: String = ArmyEntry.make_key(unit_id, option_index, upgrades)
	var n: int = 0
	for e in entries:
		if not e.in_formation() and e.key() == k:
			n += 1
	return n


## Removes up to `n` support copies of a unit bought at that size with those upgrades (the newest ones). Returns
## how many were removed. Formation entries are never touched (use clear_slot / remove_formation).
func remove_copies(unit_id: StringName, option_index: int, n: int, upgrades: Dictionary = {}) -> int:
	var k: String = ArmyEntry.make_key(unit_id, option_index, upgrades)
	var removed: int = 0
	var i: int = entries.size() - 1
	while i >= 0 and removed < n:
		if not entries[i].in_formation() and entries[i].key() == k:
			entries.remove_at(i)
			removed += 1
		i -= 1
	return removed


## Units per category: [armored, ground, air].
func category_counts() -> Array:
	var out: Array = [0, 0, 0]
	for e in entries:
		var u: UnitData = e.get_unit()
		if u != null:
			out[clampi(u.category, 0, 2)] += 1
	return out


## Points per category: [armored, ground, air].
func category_points() -> Array:
	var out: Array = [0, 0, 0]
	for e in entries:
		var u: UnitData = e.get_unit()
		if u != null:
			out[clampi(u.category, 0, 2)] += e.get_points()
	return out


## Fighting models plus their transports.
func total_models() -> int:
	var n: int = 0
	for e in entries:
		var o: UnitOption = e.get_option()
		if o != null:
			n += o.models + o.transport_models
	return n


# ------------------------------------------------------------------ support units: limits and exclusions

## Support entries (outside formations).
func support_entries() -> Array[ArmyEntry]:
	var out: Array[ArmyEntry] = []
	for e in entries:
		if not e.in_formation():
			out.append(e)
	return out


## Support copies of a card, any size and upgrades.
func support_copies(unit_id: StringName) -> int:
	var n: int = 0
	for e in entries:
		if not e.in_formation() and e.unit_id == unit_id:
			n += 1
	return n


## How many more support copies of `u` may be taken (999 = no limit). Formation units do not count.
func room_for(u: UnitData) -> int:
	if not AppSettings.limit_units():
		return 999
	return maxi(u.max_copies - support_copies(u.id), 0)


## Why `count` more copies of `u` cannot be taken as support units ("" = they can).
func support_problem(u: UnitData, count: int = 1) -> String:
	if u == null:
		return "Unknown card."
	if u.options.is_empty():
		return "%s is an attachment (it comes with its parent unit) and cannot be bought on its own." % u.display_name
	if u.formation_only:
		if use_formations:
			return "%s can only be taken inside a formation (Armies overview > Edit formation)." % u.display_name
		return "%s can only be taken inside a formation, and this army does not use one (tick 'Uses a formation' on the Armies set-up page)." % u.display_name
	if use_formations and u.is_hq():
		return "%s is an HQ: with a formation it only leads its formation (Armies overview > Edit formation)." % u.display_name
	if AppSettings.limit_units() and support_copies(u.id) + count > u.max_copies:
		return "%s can be taken %d time(s) outside formations (Settings > Limit unit quantities); the army already has %d." % [
				u.display_name, u.max_copies, support_copies(u.id)]
	var clash: String = exclusive_clash(u)
	if clash != "":
		return clash
	return ""


## A support unit already in the army that excludes `u` (or that `u` excludes): the message, or "".
func exclusive_clash(u: UnitData, ignore: ArmyEntry = null) -> String:
	for e in entries:
		if e == ignore or e.in_formation() or e.unit_id == u.id:
			continue
		var other: UnitData = e.get_unit()
		if other == null:
			continue
		if u.exclusive_with.has(String(other.id)) or other.exclusive_with.has(String(u.id)):
			return "%s cannot be taken together with %s (exclusive units)." % [u.display_name, other.display_name]
	return ""


# ------------------------------------------------------------------ formations

## Adds an empty formation (HQ and slots still to fill). Returns its key ("" = unknown formation id).
func add_formation(formation_id: String) -> String:
	if FormationDB.get_formation(formation_id) == null:
		return ""
	var key: String = "f%d" % _next_formation
	_next_formation += 1
	formations.append({"key": key, "formation_id": formation_id})
	return key


## Removes a formation and every unit in it.
func remove_formation(key: String) -> void:
	for i in range(formations.size() - 1, -1, -1):
		if str(formations[i]["key"]) == key:
			formations.remove_at(i)
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].formation == key:
			entries.remove_at(i)


func formation_data(key: String) -> FormationData:
	for f in formations:
		if str(f["key"]) == key:
			return FormationDB.get_formation(str(f["formation_id"]))
	return null


## The entry in a formation slot ("hq" for the HQ), or null when the slot is empty.
func slot_entry(key: String, slot_id: String) -> ArmyEntry:
	for e in entries:
		if e.formation == key and e.slot == slot_id:
			return e
	return null


## Why `unit_id` cannot go into that slot ("" = it can).
func slot_problem(key: String, slot_id: String, unit_id: StringName) -> String:
	var f: FormationData = formation_data(key)
	if f == null:
		return "This formation is not in the formation files any more."
	var u: UnitData = UnitDatabase.get_unit(unit_id)
	if u == null:
		return "Card %s is not in the unit data." % unit_id
	if u.options.is_empty():
		return "%s has no sizes to buy." % u.display_name
	if slot_id == "hq":
		return "" if String(unit_id) == f.hq else "Only %s can lead this formation." % f.hq
	var s: Dictionary = f.slot(slot_id)
	if s.is_empty():
		return "The formation has no slot %s." % slot_id
	if not (s["units"] as PackedStringArray).has(String(unit_id)):
		return "%s cannot fill this slot." % u.display_name
	for other in f.exclusive_partners(slot_id):
		if slot_entry(key, other) != null:
			var os: Dictionary = f.slot(other)
			return "This slot is exclusive with the %s slot (%s), which is already filled." % [str(os.get("group", other)), other]
	return ""


## Puts a unit into a formation slot (replacing what was there). Returns the entry, or null if not allowed.
func set_slot(key: String, slot_id: String, unit_id: StringName, option_index: int, upgrades: Dictionary = {}) -> ArmyEntry:
	var old: ArmyEntry = slot_entry(key, slot_id)
	if old != null:
		entries.erase(old)
	if slot_problem(key, slot_id, unit_id) != "":
		if old != null:
			entries.append(old)
		return null
	var e: ArmyEntry = add_unit(unit_id, option_index, key, upgrades)
	if e != null:
		e.slot = slot_id
	return e


func clear_slot(key: String, slot_id: String) -> void:
	var e: ArmyEntry = slot_entry(key, slot_id)
	if e != null:
		entries.erase(e)


func formation_points(key: String) -> int:
	var total: int = 0
	for e in entries:
		if e.formation == key:
			total += e.get_points()
	return total


## What is still missing or wrong in a formation (empty = it can be fielded).
func formation_problems(key: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var f: FormationData = formation_data(key)
	if f == null:
		out.append("formation not found in the formation files")
		return out
	if slot_entry(key, "hq") == null:
		out.append("no HQ (%s)" % f.hq)
	for s in f.slots:
		if bool(s["compulsory"]) and slot_entry(key, str(s["id"])) == null:
			out.append("compulsory %s slot empty" % str(s["group"]))
	for g: PackedStringArray in f.exclusive:
		var filled: int = 0
		for sid in g:
			if slot_entry(key, sid) != null:
				filled += 1
		if filled > 1:
			out.append("only one of %s may be filled" % ", ".join(g))
	return out


## Every problem of the army list (formations and support units), for the editor and before a battle.
func list_problems() -> PackedStringArray:
	var out: PackedStringArray = []
	if AppSettings.use_formations() and not has_formation():
		out.append("no formation (Settings > Use formations is on)")
	if use_formations:
		for f in formations:
			var fd: FormationData = formation_data(str(f["key"]))
			for p in formation_problems(str(f["key"])):
				out.append("%s: %s" % [fd.name if fd != null else str(f["formation_id"]), p])
	var counted: Dictionary = {}
	for e in support_entries():
		var u: UnitData = e.get_unit()
		if u == null or counted.has(u.id):
			continue
		counted[u.id] = true
		if u.formation_only:
			out.append("%s can only be taken inside a formation" % u.display_name)
		if use_formations and u.is_hq():
			out.append("%s is an HQ: with formations it must lead a formation" % u.display_name)
		if AppSettings.limit_units() and support_copies(u.id) > u.max_copies:
			out.append("%s: %d copies, at most %d" % [u.display_name, support_copies(u.id), u.max_copies])
		var clash: String = exclusive_clash(u)
		if clash != "":
			out.append(clash)
	return out


## Key of the army's main formation (the one chosen on the Armies set-up page), "" = none.
func main_formation_key() -> String:
	return str(formations[0]["key"]) if not formations.is_empty() else ""


func main_formation() -> FormationData:
	return formation_data(main_formation_key())


## Makes `formation_id` the army's formation ("" = no formation). A different formation replaces the old one with
## its units; the same one is kept as it is. The HQ and the compulsory slots with only one card are filled at once
## (first size, no upgrades). Returns the formation key ("" when there is none).
func set_main_formation(formation_id: String) -> String:
	var f: FormationData = main_formation()
	if f != null and f.id == formation_id:
		return main_formation_key()
	while not formations.is_empty():
		remove_formation(str(formations[0]["key"]))
	if formation_id == "":
		return ""
	var key: String = add_formation(formation_id)
	if key != "":
		autofill_formation(key)
	return key


## Fills the HQ and every empty compulsory slot (first size, no upgrades). A slot with several cards (OR) gets its
## first card that can be taken: in the unit data, with sizes, not blocked by an exclusive slot and not clashing with a
## unit already in the army. The player swaps it on the formation screen. Slots already filled are kept.
func autofill_formation(key: String) -> void:
	var f: FormationData = formation_data(key)
	if f == null:
		return
	if slot_entry(key, "hq") == null and UnitDatabase.get_unit(StringName(f.hq)) != null:
		set_slot(key, "hq", StringName(f.hq), 0)
	for s in f.slots:
		var sid: String = str(s["id"])
		if not bool(s["compulsory"]) or slot_entry(key, sid) != null:
			continue
		for uid in (s["units"] as PackedStringArray):
			var u: UnitData = UnitDatabase.get_unit(StringName(uid))
			if u == null or army_clash(u) != "":
				continue
			if set_slot(key, sid, u.id, 0) != null:
				break


## A unit anywhere in the army (support or formation, except `ignore`) that `u` is exclusive with: the message, or "".
## Used to grey out cards in the formation screen and the card selector.
func army_clash(u: UnitData, ignore: ArmyEntry = null) -> String:
	for e in entries:
		if e == ignore or e.unit_id == u.id:
			continue
		var other: UnitData = e.get_unit()
		if other != null and (u.exclusive_with.has(String(other.id)) or other.exclusive_with.has(String(u.id))):
			return "%s is exclusive with %s, which is in the army." % [u.display_name, other.display_name]
	return ""


## Turns formations on or off for this army. Returns "" or why it was refused (formations still in the army).
func set_use_formations(on: bool) -> String:
	if not on and not formations.is_empty():
		return "Remove the %d formation(s) first: their units would be left without a formation." % formations.size()
	use_formations = on
	return ""


## true when the army has a formation (its main formation is known).
func has_formation() -> bool:
	return use_formations and main_formation() != null


## Settings > Use formations is on: gives an army without a formation the first formation of its nation.
## Returns "" or why it could not (the nation has no formations).
func require_formation() -> String:
	if not AppSettings.use_formations() or has_formation():
		return ""
	var list: Array = FormationDB.for_nation(nation)
	if list.is_empty():
		return "%s has no formations, and Settings > Use formations is on." % RulesDB.nation_label(nation)
	use_formations = true
	set_main_formation((list[0] as FormationData).id)
	return ""


# ------------------------------------------------------------------ saving (ArmyFiles)

## The army in the saved_army file format. Besides what is needed to load it again, every entry carries the card
## name, the size and its points so the file can be read by people.
func to_dict() -> Dictionary:
	var out_entries: Array = []
	for e in entries:
		var ups: Dictionary = {}
		for idx in e.upgrades:
			ups[str(idx)] = int(e.upgrades[idx])
		var u: UnitData = e.get_unit()
		var o: UnitOption = e.get_option()
		var d: Dictionary = {"unit_id": String(e.unit_id), "option_index": e.option_index, "upgrades": ups,
				"formation": e.formation, "slot": e.slot}
		d["card"] = u.display_name if u != null else "?"
		d["size"] = o.label if o != null else "?"
		d["points"] = e.get_points()
		out_entries.append(d)
	var out_forms: Array = []
	for f in formations:
		var fd: FormationData = FormationDB.get_formation(str(f["formation_id"]))
		out_forms.append({"key": str(f["key"]), "formation_id": str(f["formation_id"]),
				"name": fd.full_name() if fd != null else "?"})
	return {
		"format": "TY helper army",
		"version": 1,
		"army_name": army_name,
		"nation": nation,
		"points_limit": points_limit,
		"use_formations": use_formations,
		"formations": out_forms,
		"next_formation": _next_formation,
		"entries": out_entries,
		"total_points": total_points(),
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ", false)


## What makes the army what it is (no names or points that only describe it), to compare with the saved file.
func state_key() -> String:
	var d: Dictionary = to_dict()
	d.erase("total_points")
	for e in d["entries"]:
		for k in ["card", "size", "points"]:
			(e as Dictionary).erase(k)
	for f in d["formations"]:
		(f as Dictionary).erase("name")
	return JSON.stringify(d, "", true)


## true when the army is unchanged since it was saved to (or loaded from) its saved_army file.
func is_saved() -> bool:
	return saved_path != "" and state_key() == saved_json


## Remembers that the army is now the same as the file `path`.
func mark_saved(path: String) -> void:
	saved_path = path
	saved_json = state_key()


## Builds an army from a saved_army dictionary. Returns {"army": Army or null, "warnings": PackedStringArray,
## "error": String}. Cards and formations that are not in the data any more are left out and named in the warnings.
static func from_dict(d: Dictionary) -> Dictionary:
	var warnings: PackedStringArray = []
	if str(d.get("format", "")) != "TY helper army" or not d.has("entries"):
		return {"army": null, "warnings": warnings, "error": "This is not a saved army file."}
	var a: Army = Army.new()
	a.army_name = str(d.get("army_name", "Army"))
	a.nation = str(d.get("nation", ""))
	a.points_limit = int(d.get("points_limit", 0))
	a.use_formations = bool(d.get("use_formations", false))
	a._next_formation = maxi(int(d.get("next_formation", 1)), 1)
	var dropped_forms: Dictionary = {}
	for f in d.get("formations", []):
		var fid: String = str((f as Dictionary).get("formation_id", ""))
		var key: String = str((f as Dictionary).get("key", ""))
		if FormationDB.get_formation(fid) == null:
			dropped_forms[key] = true
			warnings.append("Formation '%s' (%s) is not in the formation files any more: it and its units were left out."
					% [str((f as Dictionary).get("name", fid)), fid])
			continue
		a.formations.append({"key": key, "formation_id": fid})
	if a.formations.is_empty() and not a.use_formations:
		a.use_formations = false
	for ed in d.get("entries", []):
		var e: Dictionary = ed
		var fkey: String = str(e.get("formation", ""))
		if dropped_forms.has(fkey):
			continue
		var uid: StringName = StringName(str(e.get("unit_id", "")))
		var u: UnitData = UnitDatabase.get_unit(uid)
		if u == null:
			warnings.append("Card %s (%s) is not in the unit data: left out." % [uid, str(e.get("card", "?"))])
			continue
		var oi: int = int(e.get("option_index", 0))
		if u.get_option(oi) == null:
			warnings.append("%s has no size %d any more: the first size was used." % [u.display_name, oi + 1])
			oi = 0
			if u.get_option(0) == null:
				continue
		var ups: Dictionary = {}
		var raw: Dictionary = e.get("upgrades", {})
		for k in raw:
			if int(k) < u.upgrades.size():
				ups[int(k)] = int(raw[k])
		var entry: ArmyEntry = a.add_unit(uid, oi, fkey, ups)
		if entry != null:
			entry.slot = str(e.get("slot", ""))
	return {"army": a, "warnings": warnings, "error": ""}


func entries_in_category(category: int) -> Array[ArmyEntry]:
	var out: Array[ArmyEntry] = []
	for e in entries:
		var u := e.get_unit()
		if u and u.category == category:
			out.append(e)
	return out
