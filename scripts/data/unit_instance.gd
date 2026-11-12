class_name UnitInstance
extends RefCounted
## Runtime state of one unit on the table. Static stats stay in `data`; everything that changes
## during the battle (teams, movement, pinned, what has fired ...) lives here.

enum MoveMode { HALTED, TACTICAL, TERRAIN_DASH, CROSS_DASH, ROAD_DASH }
const MOVE_NAMES := ["Halted", "Tactical", "Terrain Dash", "Cross-Country Dash", "Road Dash"]

var data: UnitData
var option: UnitOption
var owner_id: int = 0
var label: String = ""
var code: String = ""               # "IA": type letter (see BattleState.type_letter) + unit letter
var transport_of: UnitInstance = null   # set on a transport unit: the unit it came with
var upgrade_points: int = 0         # points of the upgrades bought for this unit
var upgrade_lines: PackedStringArray = []
## Key of the formation the unit belongs to (Army.formations, "" = support unit) and its slot ("hq" for the HQ).
## Not used by the rules yet: Formation Command will need it.
var formation: String = ""
var formation_slot: String = ""
var teams: Array[TeamState] = []

# --- per-turn state: reset when the owner's turn begins, so the enemy can still see how this
# --- unit moved during its own last turn (needed for "stationary", "Gone to Ground" ...)
var move_mode: int = MoveMode.HALTED
var move_distance: int = 0
var cross_failed: bool = false
var order: String = ""              # "", "blitz", "follow_me", "cross_here", "dig_in"
var order_failed: bool = false
var shot_this_turn: bool = false
var assaulted_this_turn: bool = false
var bombarded_this_turn: bool = false
var air_arrived: bool = false       # Strike Aircraft: arrived this turn
var spotted_this_turn: bool = false # a Spotting Team spots for one Bombardment each turn
var foxholes: bool = false          # Dig In succeeded: Bulletproof Cover until the unit moves
var fired_weapons: Dictionary = {}  # weapon index -> true

# --- persists between turns
var pinned: bool = false
var hits_taken: int = 0
var used_once: Dictionary = {}      # weapon index -> true ("One Shot", "Smoke Bombardment")


## `p_models` > 0 sets the number of models for a card without sizes (a transport that came with another unit).
func _init(p_data: UnitData, p_option: UnitOption, p_owner: int, p_models: int = 0) -> void:
	data = p_data
	option = p_option
	owner_id = p_owner
	label = p_data.display_name
	_build_teams(p_models)


## One TeamState per model. Models are separate even when they are the same kind.
func _build_teams(p_models: int = 0) -> void:
	teams.clear()
	var comp: Array = []
	if option != null:
		comp = option.composition
	for item in comp:
		if str(item.get("unit_id", "")) != "":
			continue                    # a transport with its own card: it is a unit of its own (see ArmyManager.spawn_units)
		var count: int = int(item.get("count", 1))
		var item_name: String = str(item.get("name", data.display_name))
		for i in count:
			teams.append(TeamState.new(item_name))
	if teams.is_empty():
		var models: int = maxi(p_models, 1)
		if option != null:
			models = maxi(option.models, 1)
		for i in models:
			teams.append(TeamState.new(data.display_name))
	for t in teams:
		var ref: UnitData = ModelWeapons.ref_card(t.kind)
		var card: UnitData = ref if ref != null else data
		t.rides_on_top_ok = card.category == UnitData.Category.ARMORED and card.get("armour_front") != null \
				and not card.unit_type.to_lower().contains("unarmoured")
		t.is_vehicle = ModelWeapons.is_vehicle(data, t.kind)
		t.is_aircraft = ModelWeapons.is_aircraft(data, t.kind)
		t.capacity = ModelWeapons.capacity(data, t.kind)
	apply_model_weapons()
	set_code(code)


## Gives the unit its code ("IA") and numbers its models ("IA1", "IA2" ...).
func set_code(p_code: String) -> void:
	code = p_code
	for i in teams.size():
		teams[i].code = "%s%d" % [code, i + 1]
		teams[i].team_name = ("%s %s" % [teams[i].code, teams[i].kind]).strip_edges()


## (Re)reads which weapons each model can fire (after "Weapons per model..." was changed).
func apply_model_weapons() -> void:
	for t in teams:
		t.weapons = ModelWeapons.weapons_for(data, t.kind)


## Models that can fire weapon `widx` right now (OK and not carried).
func teams_with_weapon(widx: int) -> Array[TeamState]:
	var out: Array[TeamState] = []
	for t in active_teams():
		if t.weapons.has(widx):
			out.append(t)
	return out


## Infantry / gun models (the ones that can be carried).
func foot_teams() -> Array[TeamState]:
	var out: Array[TeamState] = []
	for t in teams:
		if t.is_alive() and not t.is_vehicle:
			out.append(t)
	return out


# ------------------------------------------------------------------ team queries

func total_teams() -> int:
	return teams.size()


func count_status(s: int) -> int:
	var c: int = 0
	for t in teams:
		if t.status == s:
			c += 1
	return c


## Models that can be hit: alive and not carried by a vehicle. (If the whole unit is being carried this returns
## every living model, so nothing breaks when it is picked as a target by mistake.)
func alive_teams() -> Array[TeamState]:
	var out: Array[TeamState] = []
	var all_alive: Array[TeamState] = []
	for t in teams:
		if t.is_alive():
			all_alive.append(t)
			if not t.mounted():
				out.append(t)
	return all_alive if out.is_empty() else out


## Models that can move, shoot and assault: OK and not carried by a vehicle.
func active_teams() -> Array[TeamState]:
	var out: Array[TeamState] = []
	for t in teams:
		if t.is_active() and not t.mounted():
			out.append(t)
	return out


func mounted_count() -> int:
	var n: int = 0
	for t in teams:
		if t.mounted():
			n += 1
	return n


func is_destroyed() -> bool:
	return count_status(TeamState.Status.DESTROYED) >= teams.size()


# ------------------------------------------------------------------ classification

func is_air() -> bool:
	return data.category == UnitData.Category.AIR


func is_armored() -> bool:
	return data.category == UnitData.Category.ARMORED


func is_ground() -> bool:
	return data.category == UnitData.Category.GROUND


func is_unarmoured() -> bool:
	return is_armored() and data.unit_type.to_lower().contains("unarmoured")


func is_helicopter() -> bool:
	return is_air() and str(data.get("aircraft_type")) == "helicopter"


func is_strike_aircraft() -> bool:
	return is_air() and not is_helicopter()


## True for fully armoured tank teams (they use Armour ratings instead of Saves).
func uses_armour() -> bool:
	return is_armored() and not is_unarmoured() and data.get("armour_front") != null


func armour(facing: String) -> int:
	var v = data.get("armour_" + facing)
	return int(v) if v != null else 0


func save_value() -> int:
	var v = data.get("save")
	return int(v) if v != null else 0


func can_be_pinned() -> bool:
	return not is_air() and not uses_armour()


# ------------------------------------------------------------------ movement

## Distance limit in cm for a movement mode. -1 means unlimited, 0 means no movement.
func movement_limit(mode: int) -> int:
	match mode:
		MoveMode.TACTICAL:
			return data.tactical
		MoveMode.TERRAIN_DASH:
			return data.terrain_dash
		MoveMode.CROSS_DASH:
			return data.cross_dash
		MoveMode.ROAD_DASH:
			return data.road_dash
	return 0


func moved() -> bool:
	return move_mode != MoveMode.HALTED


func is_dash() -> bool:
	return move_mode >= MoveMode.TERRAIN_DASH


## Shoots with Moving ROF (moved, Pinned Down, or digging in).
func fires_as_moving() -> bool:
	return moved() or pinned or order == "dig_in"


## Teams that did not Move, Shoot or Assault are Gone to Ground (Scouts and Hunter-Killers may move).
func is_gone_to_ground() -> bool:
	if shot_this_turn or assaulted_this_turn:
		return false
	if moved():
		return data.has_rule("Scout") or data.has_rule("Hunter-Killer")
	return true


# ------------------------------------------------------------------ turn flow

func begin_turn() -> void:
	move_mode = MoveMode.HALTED
	move_distance = 0
	cross_failed = false
	order = ""
	order_failed = false
	shot_this_turn = false
	assaulted_this_turn = false
	bombarded_this_turn = false
	air_arrived = false
	spotted_this_turn = false
	fired_weapons.clear()
	for t in teams:
		t.fired.clear()
		t.mounted_this_turn = false
		t.dismounted_this_turn = false
		t.move_mode = MoveMode.HALTED
		t.move_distance = 0
		t.cross_failed = false
	hits_taken = 0


## Movement is recorded per model. The unit as a whole counts as having moved as much as its fastest model
## (used for Gone to Ground, "stationary target" and the like); a shot uses the movement of the models that fire.
func sync_movement() -> void:
	var mode: int = MoveMode.HALTED
	var dist: int = 0
	var failed: bool = false
	for t in teams:
		if not t.is_alive():
			continue
		mode = maxi(mode, t.move_mode)
		dist = maxi(dist, t.move_distance)
		failed = failed or t.cross_failed
	move_mode = mode
	move_distance = dist
	cross_failed = failed
	if mode != MoveMode.HALTED:
		foxholes = false                    # Foxholes only protect until the teams Move


## Slider maximum for a movement mode: the card's distance, or `unlimited` cm when the card has no limit.
func slider_limit(mode: int, unlimited: int = 200) -> int:
	var limit: int = movement_limit(mode)
	return unlimited if limit < 0 else limit


## Counts hits towards Pinned Down (5 hits, or 8 for units of 12+ teams). Returns true if newly pinned.
func register_hits(n: int) -> bool:
	hits_taken += n
	if pinned or not can_be_pinned():
		return false
	var threshold: int = 8 if teams.size() >= 12 else 5
	if hits_taken >= threshold:
		pinned = true
		return true
	return false


func status_text() -> String:
	var s: String = "%d/%d models" % [total_teams() - count_status(TeamState.Status.DESTROYED), total_teams()]
	if mounted_count() > 0:
		s += ", %d carried" % mounted_count()
	var bailed: int = count_status(TeamState.Status.BAILED_OUT)
	if bailed > 0:
		s += ", %d bailed out" % bailed
	if pinned:
		s += ", PINNED"
	if foxholes:
		s += ", in Foxholes"
	if is_destroyed():
		s = "DESTROYED"
	return s
