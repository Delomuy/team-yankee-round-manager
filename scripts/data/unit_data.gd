class_name UnitData
extends Resource
## Base class for every unit type. Holds what is common to armored, ground and air units.

enum Category { ARMORED, GROUND, AIR }

## Stored in movement / cross_skill fields when the source says "AUTO" or "Unlimited".
const AUTO := -1

@export var id: StringName
@export var display_name: String = ""
@export var nation: String = ""
@export var category: Category = Category.GROUND
@export var unit_type: String = ""          ## original label, e.g. "Tank Unit", "Strike Aircraft Unit"
## Transports and similar units that are not bought on their own (they have no options).
@export var is_attachment: bool = false
@export var passengers: int = 0
## HQ formations are several stat cards: the first is the unit, the rest are attachments.
@export var part_of: StringName
@export var attached_ids: PackedStringArray = []

## Army-list limits, edited by hand in the unit JSON (tools/convert_units.py keeps them when it converts again).
## How many times the unit may be taken outside formations when Settings > "Limit unit quantities" is on.
@export var max_copies: int = 1
## Ids of units that cannot be in the same army as this one (outside formations).
@export var exclusive_with: PackedStringArray = []
## true = the unit can only be taken inside a formation (an army that does not use formations cannot take it).
@export var formation_only: bool = false

## Ways this unit can be bought (size or composition), each with its own points cost.
@export var options: Array[UnitOption] = []
## Optional extras (the "options" under the sizes on the card): [{ "text": "...", "cost": 1, "per_model": false }, ...]
## How the cost is paid (upgrade_kind):
##   once      (per_model false)  - "for +1 point": once for the unit
##   choice    (per_model true)   - "+1 point each" for the ones the player picks ("any or all", "up to two")
##   model     ("per": "model")   - "+1 point per tank" / "all ... +1 point each": for every model it covers,
##              counted from the chosen size. Optional: "count_models": "Milan" (only rows whose name has that word),
##              "count": 2 (a fixed number, e.g. teams added by another option), "group": 2 ("per two aircraft",
##              "for every eight teams": one cost per started group).
@export var upgrades: Array = []
## Free-text rules from the source that aren't prices.
@export var notes: PackedStringArray = []

# Morale / skill.  0 means "not applicable" (e.g. a unit that cannot assault).
@export var courage: int = 0
@export var morale: int = 0
@export var rally: int = 0       ## infantry
@export var remount: int = 0     ## vehicles
@export var skill: int = 0
@export var assault: int = 0
@export var counterattack: int = 0
@export var is_hit_on: int = 4
@export var save: int = 0        ## infantry / aircraft / unarmoured-vehicle save ("n+" stored as n)

# Movement (cm). AUTO (-1) means unlimited / automatic.
@export var tactical: int = 0
@export var terrain_dash: int = 0
@export var cross_dash: int = 0
@export var road_dash: int = 0
@export var cross_skill: int = 0

@export var weapons: Array[WeaponData] = []
@export var special_rules: PackedStringArray = []


## An HQ (commander) card: the card type is "Tank Formation" / "Infantry Formation" (also the extra stat cards of
## an HQ), or the name ends in "HQ".
func is_hq() -> bool:
	var t: String = unit_type.strip_edges().to_lower()
	return t.ends_with("formation") or display_name.strip_edges().ends_with(" HQ") or display_name.contains(" HQ:")


func get_option(index: int) -> UnitOption:
	if index >= 0 and index < options.size():
		return options[index]
	return null


func get_points(option_index: int, dynamic: bool = false) -> int:
	var o := get_option(option_index)
	return o.cost(dynamic) if o else 0


## "once", "choice" or "model" - how upgrade `index` is paid (see `upgrades`).
func upgrade_kind(index: int) -> String:
	if index < 0 or index >= upgrades.size():
		return "once"
	var up: Dictionary = upgrades[index]
	if str(up.get("per", "")) == "model":
		return "model"
	return "choice" if bool(up.get("per_model", false)) else "once"


## How many times the cost of a "model" upgrade is paid for size `option` (1 for the other kinds).
func upgrade_units(index: int, option: UnitOption) -> int:
	if upgrade_kind(index) != "model":
		return 1
	var up: Dictionary = upgrades[index]
	var n: int = 1
	if up.has("count"):
		n = int(up["count"])
	elif option != null:
		var word: String = str(up.get("count_models", "")).strip_edges().to_lower()
		if word == "":
			n = option.models
		else:
			n = 0
			for item in option.composition:
				if str((item as Dictionary).get("name", "")).to_lower().contains(word):
					n += int((item as Dictionary).get("count", 1))
	var group: int = maxi(int(up.get("group", 1)), 1)
	return ceili(float(maxi(n, 0)) / float(group))


## How many times upgrade `index` can be bought for an option with `models` models: the "up to N" of its text or one
## per model for a "choice" upgrade; 1 for the others (a "model" upgrade is ticked once and counts the models itself).
func upgrade_limit(index: int, models: int) -> int:
	if upgrade_kind(index) != "choice":
		return 1
	var up: Dictionary = upgrades[index]
	var re: RegEx = RegEx.create_from_string(r"(?i)up to (\d+)")
	var m: RegExMatch = re.search(str(up.get("text", "")))
	if m != null:
		return maxi(int(m.get_string(1)), 1)
	re = RegEx.create_from_string(r"(?i)up to (one|two|three|four|five|six)\b")
	m = re.search(str(up.get("text", "")))
	if m != null:
		return ["one", "two", "three", "four", "five", "six"].find(m.get_string(1).to_lower()) + 1
	return maxi(models, 1)


## Points of upgrade `index` bought `qty` times for size `option` (upgrades cost the same in standard and dynamic
## points). A "model" upgrade ignores `qty` and pays for every model it covers in that size.
func upgrade_cost(index: int, qty: int = 1, option: UnitOption = null) -> int:
	if index < 0 or index >= upgrades.size():
		return 0
	var cost: int = int((upgrades[index] as Dictionary).get("cost", 0))
	if upgrade_kind(index) == "model":
		return cost * upgrade_units(index, option)
	return cost * maxi(qty, 0)


## The price as shown on the card: "free", "+1 pt", "+1 pt each", "+1 pt per model", "+3 pts per 2 models",
## "+1 pt per Milan model".
func upgrade_price_text(index: int) -> String:
	if index < 0 or index >= upgrades.size():
		return ""
	var up: Dictionary = upgrades[index]
	var cost: int = int(up.get("cost", 0))
	if cost == 0:
		return "free"
	var pts: String = "+%d pt%s" % [cost, "" if absi(cost) == 1 else "s"]
	match upgrade_kind(index):
		"choice":
			return pts + " each"
		"model":
			var what: String = "model"
			var word: String = str(up.get("count_models", "")).strip_edges()
			if word != "":
				what = "%s model" % word
			var group: int = maxi(int(up.get("group", 1)), 1)
			var text: String = "%s per %s" % [pts, what] if group == 1 else "%s per %d %ss" % [pts, group, what]
			if up.has("count"):
				text += " (%d)" % int(up["count"])
			return text
	return pts


func min_points(dynamic: bool = false) -> int:
	var best := -1
	for o in options:
		var c := o.cost(dynamic)
		if best < 0 or c < best:
			best = c
	return maxi(best, 0)


func has_rule(rule: String) -> bool:
	return special_rules.has(rule)


func category_name() -> String:
	return Category.keys()[category].capitalize()
