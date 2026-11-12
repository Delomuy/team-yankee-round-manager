extends Node
## Autoload as "ArmyManager". Holds each player's Army and the live UnitInstances built from it.

signal army_registered(owner_id: int, army: Army)
signal units_spawned(owner_id: int, instances: Array)
## Armies were added to or taken out of the roster from outside the Armies screen (Settings > Use formations).
signal roster_changed

## true = price units with their "dynamic points" figure instead of the standard one.
var use_dynamic_points: bool = false

var armies: Dictionary = {}      # battle slot (0 .. 3) -> Army that is fighting
## Team id (0-3) of each battle slot; players with the same id fight together. Empty = everyone on their own.
var battle_teams: Array = []
## Every player's army as set up on the Armies screen (2 to MAX_PLAYERS). A battle uses 2 to 4 of them.
var roster: Array[Army] = []
const MAX_PLAYERS := 8
## Main army of the first players when the roster is created: player 1 American, player 2 Soviet.
const DEFAULT_NATIONS := ["American", "Soviet"]
var _instances: Dictionary = {}  # owner_id -> Array of UnitInstance


## Makes the roster exactly `count` armies long (new ones are empty, extra ones are dropped). The first two new
## armies get DEFAULT_NATIONS as their main army. With Settings > Use formations on, a new army gets the first
## formation of its nation.
func set_player_count(count: int) -> void:
	count = clampi(count, 2, MAX_PLAYERS)
	while roster.size() < count:
		var a: Army = Army.new()
		a.army_name = "Player %d" % (roster.size() + 1)
		if roster.size() < DEFAULT_NATIONS.size() and UnitDatabase.get_nations().has(DEFAULT_NATIONS[roster.size()]):
			a.nation = DEFAULT_NATIONS[roster.size()]
		elif not UnitDatabase.get_nations().is_empty():
			a.nation = UnitDatabase.get_nations()[roster.size() % UnitDatabase.get_nations().size()]
		a.require_formation()
		roster.append(a)
	while roster.size() > count:
		roster.pop_back()


## The armies that stand in the way of Settings > Use formations: armies without a formation that have units which
## are not saved. Turning the setting on is refused while there are any.
func armies_blocking_formations() -> Array:
	var out: Array = []
	for a: Army in roster:
		if not a.has_formation() and not a.entries.is_empty() and not a.is_saved():
			out.append(a)
	return out


## Turns Settings > Use formations on: closes every army without a formation (they are saved or empty, see
## armies_blocking_formations), refills the roster to two players and gives every army a formation.
## Returns the names of the closed armies.
func apply_use_formations() -> PackedStringArray:
	var closed: PackedStringArray = []
	for i in range(roster.size() - 1, -1, -1):
		var a: Army = roster[i]
		if not a.has_formation():
			closed.insert(0, a.army_name)
			roster.remove_at(i)
	set_player_count(maxi(roster.size(), 2))
	for a: Army in roster:
		a.require_formation()
	roster_changed.emit()
	return closed


func register_army(owner_id: int, army: Army) -> void:
	army.owner_id = owner_id
	armies[owner_id] = army
	army_registered.emit(owner_id, army)


## Turns the army list into runtime unit instances (one per entry). Units bought more than once
## are numbered ("M1A1 Abrams Platoon #2") so they can be told apart.
func spawn_units(owner_id: int) -> Array:
	var list: Array = []
	var army: Army = armies.get(owner_id)
	if army:
		var totals: Dictionary = {}
		for e in army.entries:
			totals[e.unit_id] = int(totals.get(e.unit_id, 0)) + 1
		var seen: Dictionary = {}
		for e in army.entries:
			var data: UnitData = e.get_unit()
			var opt: UnitOption = e.get_option()
			if data == null or opt == null:
				continue
			var inst: UnitInstance = UnitInstance.new(data, opt, owner_id)
			inst.upgrade_points = e.upgrade_points()
			inst.upgrade_lines = e.upgrade_lines()
			inst.formation = e.formation
			inst.formation_slot = e.slot
			if int(totals[e.unit_id]) > 1:
				seen[e.unit_id] = int(seen.get(e.unit_id, 0)) + 1
				inst.label = "%s #%d" % [data.display_name, seen[e.unit_id]]
			list.append(inst)
			for item in opt.composition:                 # transports with their own card become a unit of their own
				var tid: String = str(item.get("unit_id", ""))
				var tdata: UnitData = UnitDatabase.get_unit(StringName(tid)) if tid != "" else null
				if tdata == null:
					continue
				var carrier: UnitInstance = UnitInstance.new(tdata, null, owner_id, int(item.get("count", 1)))
				carrier.transport_of = inst
				carrier.label = "%s (transport of %s)" % [tdata.display_name, inst.label]
				list.append(carrier)
	_instances[owner_id] = list
	units_spawned.emit(owner_id, list)
	return list


## category = -1 returns every unit; otherwise pass UnitData.Category.ARMORED / GROUND / AIR.
func get_units(owner_id: int, category: int = -1) -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	for inst in _instances.get(owner_id, []):
		if category == -1 or inst.data.category == category:
			out.append(inst)
	return out


func save_army(army: Army, path: String) -> Error:
	return ResourceSaver.save(army, path)   # e.g. "user://my_army.tres"


func load_army(path: String) -> Army:
	return load(path) as Army


func clear() -> void:
	armies.clear()
	_instances.clear()
