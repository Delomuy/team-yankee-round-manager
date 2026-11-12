class_name FormationData
extends RefCounted
## One formation of a nation, read from data/formations/<prefix>_formation_data.json (see FormationDB):
## an HQ card and the slots of the formation diagram. Each slot holds one unit chosen from its `units` (the OR
## choices); `compulsory` slots must be filled to field the formation. `exclusive` lists groups of slot ids of
## which only one may be filled. `division` is the division the formation belongs to (e.g. "228th Guards").
## Formations are created and edited in the Formations section (FormationEditor) and saved by FormationDB.

var id: String = ""
var name: String = ""
var division: String = ""               ## "" = no division
var nation: String = ""
var hq: String = ""                     ## card id of the HQ unit
## [{"id": String, "group": String, "compulsory": bool, "units": PackedStringArray}]
var slots: Array = []
## [PackedStringArray of slot ids], only one slot of each group may be filled
var exclusive: Array = []
## Fields of the file entry starting with "_" (notes such as "_source"); kept when the file is saved again.
var notes: Dictionary = {}


static func from_dict(d: Dictionary, p_nation: String) -> FormationData:
	var f: FormationData = FormationData.new()
	f.id = str(d.get("id", ""))
	f.name = str(d.get("name", f.id))
	f.division = str(d.get("division", "")).strip_edges()
	f.nation = p_nation
	f.hq = str(d.get("hq", ""))
	var n: int = 0
	for s in d.get("slots", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		n += 1
		f.slots.append({
			"id": str(s.get("id", "slot_%d" % n)),
			"group": str(s.get("group", "")),
			"compulsory": bool(s.get("compulsory", false)),
			"units": PackedStringArray(s.get("units", [])),
		})
	for g in d.get("exclusive", []):
		if typeof(g) == TYPE_ARRAY and (g as Array).size() > 1:
			f.exclusive.append(PackedStringArray(g))
	for k in d:
		if str(k).begins_with("_"):
			f.notes[str(k)] = d[k]
	return f


## The dictionary written to the formation file (the reverse of from_dict).
func to_dict() -> Dictionary:
	var out_slots: Array = []
	for s in slots:
		out_slots.append({
			"id": str(s["id"]),
			"group": str(s["group"]),
			"compulsory": bool(s["compulsory"]),
			"units": Array(PackedStringArray(s["units"])),
		})
	var out_ex: Array = []
	for g: PackedStringArray in exclusive:
		out_ex.append(Array(g))
	var d: Dictionary = {"id": id, "name": name}
	if division != "":
		d["division"] = division
	d["hq"] = hq
	d["slots"] = out_slots
	d["exclusive"] = out_ex
	for k in notes:
		d[k] = notes[k]
	return d


## A deep copy (the editor works on copies of the slots).
func duplicate_formation() -> FormationData:
	return FormationData.from_dict(to_dict(), nation)


## "228th Guards - BTR-60 Motor Rifle Battalion", or just the name when there is no division.
func full_name() -> String:
	return name if division == "" else "%s - %s" % [division, name]


## A slot id not used yet in this formation ("slot_1", "slot_2" ...).
func new_slot_id() -> String:
	var n: int = slots.size() + 1
	while not slot("slot_%d" % n).is_empty():
		n += 1
	return "slot_%d" % n


## Removes a slot and every mention of it in the exclusive groups (groups left with one slot are dropped).
func remove_slot(slot_id: String) -> void:
	for i in range(slots.size() - 1, -1, -1):
		if str(slots[i]["id"]) == slot_id:
			slots.remove_at(i)
	var kept: Array = []
	for g: PackedStringArray in exclusive:
		var ng: PackedStringArray = []
		for sid in g:
			if sid != slot_id:
				ng.append(sid)
		if ng.size() > 1:
			kept.append(ng)
	exclusive = kept


## What is wrong or missing (shown in the editor; the formation is still saved).
func problems() -> PackedStringArray:
	var out: PackedStringArray = []
	if name.strip_edges() == "":
		out.append("no name")
	if hq == "":
		out.append("no HQ card")
	elif hq_unit() == null:
		out.append("HQ card %s is not in the unit data" % hq)
	if slots.is_empty():
		out.append("no slots")
	var has_compulsory: bool = false
	for s in slots:
		if bool(s["compulsory"]):
			has_compulsory = true
		if (s["units"] as PackedStringArray).is_empty():
			out.append("slot '%s' has no cards" % str(s["group"]))
		for uid in s["units"]:
			var msg: String = "card %s is not in the unit data" % uid
			if UnitDatabase.get_unit(StringName(uid)) == null and not out.has(msg):
				out.append(msg)
	if not slots.is_empty() and not has_compulsory:
		out.append("no compulsory slot")
	return out


func slot(slot_id: String) -> Dictionary:
	for s in slots:
		if str(s["id"]) == slot_id:
			return s
	return {}


## The other slots that cannot be filled together with `slot_id`.
func exclusive_partners(slot_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for g: PackedStringArray in exclusive:
		if g.has(slot_id):
			for other in g:
				if other != slot_id and not out.has(other):
					out.append(other)
	return out


## The HQ card, or null when the id is not in the unit data.
func hq_unit() -> UnitData:
	return UnitDatabase.get_unit(StringName(hq))
