class_name WeaponData
extends Resource
## One weapon profile (gun, ATGM, MG, rocket pod...).
## A ROF of 0 means the weapon cannot fire in that state ("-" in the source).

@export var weapon_name: String = ""
@export var range_cm_min: int = 0
@export var range_cm: int = 0
@export var rof_static: int = 1     ## ROF when stationary
@export var rof_moving: int = 1     ## ROF when moving
@export var salvo: bool = false     ## source ROF was "SALVO"
@export var artillery: bool = false ## source ROF was "ARTILLERY" (bombardment rules)
@export var anti_tank: int = 0
@export var firepower: int = 0      ## the "n+" value, stored as n
@export var rules: PackedStringArray = []


static func from_dict(d: Dictionary) -> WeaponData:
	var w := WeaponData.new()
	w.weapon_name = str(d.get("name", ""))
	w.range_cm_min = int(d.get("range_cm_min", 0))
	w.range_cm = int(d.get("range_cm", 0))
	w.rof_static = int(d.get("rof_static", 1))
	w.rof_moving = int(d.get("rof_moving", w.rof_static))
	w.salvo = bool(d.get("salvo", false))
	w.artillery = bool(d.get("artillery", false))
	w.anti_tank = int(d.get("anti_tank", 0))
	w.firepower = int(d.get("firepower", 0))
	w.rules = PackedStringArray(d.get("rules", []))
	return w


func has_rule(rule: String) -> bool:
	return rules.has(rule)
