class_name ArmyEntry
extends Resource
## One line of an army list: a unit type, which size/composition option was bought, which upgrades were ticked
## and which formation it belongs to.

@export var unit_id: StringName
@export var option_index: int = 0
## Ticked upgrades: upgrade index (into UnitData.upgrades) -> how many were bought (1 for a one-off upgrade).
@export var upgrades: Dictionary = {}
## Key of the formation in Army.formations ("" = a support unit, outside every formation).
@export var formation: String = ""
## Inside a formation: "hq" for the HQ, otherwise the slot id from the formation file.
@export var slot: String = ""


func in_formation() -> bool:
	return formation != ""


func get_unit() -> UnitData:
	return UnitDatabase.get_unit(unit_id)


func get_option() -> UnitOption:
	var u := get_unit()
	return u.get_option(option_index) if u else null


func get_models() -> int:
	var o := get_option()
	return o.models if o else 0


## Points of the ticked upgrades.
func upgrade_points() -> int:
	var u: UnitData = get_unit()
	if u == null:
		return 0
	var total: int = 0
	var o: UnitOption = get_option()
	for idx in upgrades:
		total += u.upgrade_cost(int(idx), int(upgrades[idx]), o)
	return total


## Size cost plus upgrades.
func get_points() -> int:
	var o := get_option()
	return (o.cost(ArmyManager.use_dynamic_points) if o else 0) + upgrade_points()


## The ticked upgrades as text lines ("Add 1x Milan ... (x2)").
func upgrade_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var u: UnitData = get_unit()
	if u == null:
		return out
	var idxs: Array = upgrades.keys()
	idxs.sort()
	var o: UnitOption = get_option()
	for idx in idxs:
		var up: Dictionary = u.upgrades[int(idx)] if int(idx) < u.upgrades.size() else {}
		var q: int = u.upgrade_units(int(idx), o) if u.upgrade_kind(int(idx)) == "model" else int(upgrades[idx])
		out.append("%s%s  (+%d pts)" % [str(up.get("text", "?")), (" x%d" % q) if q > 1 else "", u.upgrade_cost(int(idx), int(upgrades[idx]), o)])
	return out


## "2:1,5:2" - identical upgrade choices give identical keys ("" = none).
static func upgrade_key(ups: Dictionary) -> String:
	var idxs: Array = ups.keys()
	idxs.sort()
	var parts: PackedStringArray = []
	for idx in idxs:
		parts.append("%d:%d" % [int(idx), int(ups[idx])])
	return ",".join(parts)


## Entries with the same key are the same card ("id|size", plus "|upgrades" when some are ticked).
static func make_key(p_unit_id: Variant, p_option_index: int, ups: Dictionary = {}) -> String:
	var k: String = "%s|%d" % [p_unit_id, p_option_index]
	if not ups.is_empty():
		k += "|" + upgrade_key(ups)
	return k


func key() -> String:
	return make_key(unit_id, option_index, upgrades)
