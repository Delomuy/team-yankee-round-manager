class_name BattleState
extends RefCounted
## The whole battle: 2 to 4 players grouped into teams (1v1, 2v2, 3v1, 2v1, 1v1v1, 2v1v1, a free-for-all ...),
## every player's units, which team's turn it is, which step we are in, and the event log.
##
## A turn belongs to a TEAM: all the players of the team play their Starting, Movement, Shooting, Artillery and
## Assault steps together, then the next team plays. Every other team is the enemy. A round ends when every team
## has had its turn.

signal log_added(bbcode: String)
signal state_changed()      # something about a unit changed (refresh status displays)
signal phase_changed()      # the step or the active team changed (rebuild the step panel)

enum Phase { STARTING, MOVEMENT, SHOOTING, ARTILLERY, ASSAULT }
const PHASE_NAMES := ["Starting Step", "Movement Step", "Shooting Step", "Artillery Step", "Assault Step"]
const MAX_PLAYERS := 4
const PLAYER_COLORS := ["#1f4f9a", "#a82a1a", "#1d7a3a", "#7a3d94"]
const TEAM_NAMES := ["Team A", "Team B", "Team C", "Team D"]
## First letter of a unit / model code (see type_letter).
const TYPE_NAMES := {"I": "Infantry", "T": "Tanks", "A": "Artillery", "C": "Carriers / transports", "H": "Helicopters", "P": "Planes"}

var round_number: int = 0            # 0 = the set-up round (who rides in / on which vehicle), then 1, 2, 3 ...
var phase: int = Phase.STARTING
var player_names: Array = ["Player 1", "Player 2"]
var player_colors: Array = []        # [player] -> "#rrggbb": the colour of the player's card in the Armies tab (its nation)
var player_team: Array = [0, 1]      # [player] -> team id (index into TEAM_NAMES)
var turn_order: Array = [0, 1]       # the team ids that play, in turn order
var turn_index: int = 0              # index into turn_order of the team whose turn it is
var units: Array = [[], []]          # [player] -> Array of UnitInstance
var log_history: Array = []


## `names[i]` is the name of the player whose army is ArmyManager.armies[i]; `teams[i]` is that player's team id
## (0-3). Leave `teams` empty for "everyone against everyone" (with two players: the normal 1v1).
func setup(names: Array, teams: Array = []) -> void:
	var lists: Array = []
	var colors: Array = []
	for p in names.size():
		var army: Army = ArmyManager.armies.get(p)
		colors.append("#" + CardTile.nation_color_for(army.nation).to_html(false) if army != null and army.nation != "" else "")
		lists.append(ArmyManager.spawn_units(p))
	setup_units(names, teams, lists, colors)


## Starts a battle with ready-made units: `lists[p]` = the UnitInstances of player p (the Test range uses this with
## its two configurable test units). `colors[p]` = "#rrggbb" or "" for a default colour.
func setup_units(names: Array, teams: Array, lists: Array, colors: Array = []) -> void:
	player_names = names.duplicate()
	player_team = []
	for i in names.size():
		player_team.append(int(teams[i]) if i < teams.size() else i)
	turn_order = []
	for t in player_team:
		if not turn_order.has(t):
			turn_order.append(t)
	turn_order.sort()
	units = []
	player_colors = []
	for p in names.size():
		var given: String = str(colors[p]) if p < colors.size() else ""
		player_colors.append(given if given != "" else PLAYER_COLORS[p % PLAYER_COLORS.size()])
	for p in names.size():
		var list: Array = lists[p]
		_assign_codes(list, p, names.size() > 2)
		if names.size() > 2:                          # with several armies on the table, say whose unit it is
			for u: UnitInstance in list:
				u.label = "%s: %s" % [str(names[p]), u.label]
		for u: UnitInstance in list:
			u.begin_turn()
		units.append(list)
	round_number = 0
	turn_index = 0
	phase = Phase.STARTING
	log_history.clear()
	var sides: PackedStringArray = []
	for t in turn_order:
		sides.append(team_tag(t))
	log_line("[b]Battle:[/b] %s." % "  vs  ".join(sides))
	log_line("[b]Round 0[/b] - set-up: drag the infantry into or onto the vehicles that carry them, then start round 1.")


# ------------------------------------------------------------------ model codes

## "A", "B" ... "Z", "AA", "AB" ...
static func unit_letters(n: int) -> String:
	var s: String = ""
	n += 1
	while n > 0:
		n -= 1
		s = char(65 + n % 26) + s
		n = int(n / 26.0)
	return s


## I infantry, T tanks, A artillery, C carriers / transports, H helicopters, P planes.
static func type_letter(u: UnitInstance) -> String:
	if u.is_air():
		return "H" if u.is_helicopter() else "P"
	if u.transport_of != null or u.data.is_attachment:
		return "C"
	if not u.data.weapons.is_empty() and TYRules.is_bombardment(u.data.weapons[0]):
		return "A"                                   # its main weapon is a bombardment
	if u.is_armored() and u.data.unit_type.to_lower().contains("artillery"):
		return "A"
	return "T" if u.is_armored() else "I"


## Every unit gets a code: type letter + unit letter ("IA" = infantry unit A, "TB" = tank unit B), and every model
## the code of its unit + its number ("IA3"). With more than two players the player number comes first ("2IA3").
func _assign_codes(list: Array, player: int, with_player: bool) -> void:
	var seen: Dictionary = {}
	for u: UnitInstance in list:
		var letter: String = type_letter(u)
		var c: String = "%s%s" % [letter, unit_letters(int(seen.get(letter, 0)))]
		seen[letter] = int(seen.get(letter, 0)) + 1
		if with_player:
			c = "%d%s" % [player + 1, c]
		u.set_code(c)
		u.label = "%s %s" % [c, u.label]


## Re-reads which weapons every model can fire (after "Weapons per model..." was changed during a battle).
func refresh_model_weapons() -> void:
	for list in units:
		for u: UnitInstance in list:
			u.apply_model_weapons()
	state_changed.emit()


## Every model with this code (codes are unique, so 0 or 1).
func find_model(code: String) -> TeamState:
	for list in units:
		for u: UnitInstance in list:
			for t in u.teams:
				if t.code == code:
					return t
	return null


# ------------------------------------------------------------------ transports

## Infantry models riding in / on vehicle model `carrier`.
func passengers(carrier: TeamState, on_top: bool) -> Array:
	var out: Array = []
	for list in units:
		for u: UnitInstance in list:
			for t in u.teams:
				if t.carrier == carrier and t.on_top == on_top and t.mounted():
					out.append(t)
	return out


## Free places inside (`on_top` false: "Passengers N" of the card) or on top (up to 3, Armoured Tank Teams only).
func free_places(carrier: TeamState, on_top: bool) -> int:
	if not carrier.is_vehicle or not carrier.is_alive():
		return 0
	var room: int = carrier.capacity
	if on_top:
		room = TeamState.RIDERS_ON_TOP if (carrier.rides_on_top_ok and not carrier.is_aircraft) else 0
	return maxi(room - passengers(carrier, on_top).size(), 0)


## Why model `t` cannot get into / onto `carrier` right now ("" = it can). carrier null = why it cannot get out.
## Rules p.36: an Infantry Team dismounts before its Transport moves, and cannot Mount and Dismount in the same turn.
func mount_problem(t: TeamState, carrier: TeamState, on_top: bool = false) -> String:
	if carrier == null:
		if not t.mounted() or in_setup():
			return ""
		if t.mounted_this_turn:
			return "%s mounted this turn: a Team cannot Mount and Dismount in the same turn." % t.code
		if t.carrier.move_mode != UnitInstance.MoveMode.HALTED:
			return "%s cannot Dismount: its Transport %s has already moved (Dismount before the Transport moves)." % [t.code, t.carrier.code]
		return ""
	if t.is_vehicle or t == carrier:
		return "%s cannot be carried." % t.code
	if t.carrier == carrier and t.on_top == on_top and t.mounted():
		return ""
	if not in_setup() and t.dismounted_this_turn:
		return "%s dismounted this turn: a Team cannot Mount and Dismount in the same turn." % t.code
	if t.mounted() and not in_setup():
		var out: String = mount_problem(t, null)
		if out != "":
			return out
	if on_top and not carrier.rides_on_top_ok:
		return "Infantry can only ride on top of an Armoured Tank Team (%s is not one)." % carrier.code
	if free_places(carrier, on_top) <= 0:
		return "No room %s %s." % ["on top of" if on_top else "inside", carrier.code]
	return ""


## Puts infantry model `t` inside or on top of `carrier` (null = back on foot). Returns false when it is not allowed
## (see mount_problem).
func mount(t: TeamState, carrier: TeamState, on_top: bool = false) -> bool:
	var problem: String = mount_problem(t, carrier, on_top)
	if problem != "":
		log_line("[color=#b35a00](!) %s[/color]" % TYRules.esc(problem))
		return false
	if carrier == null:
		if t.carrier != null:
			log_line("%s dismounts from %s." % [TYRules.esc(t.team_name), TYRules.esc(t.carrier.code)])
			if not in_setup():
				t.dismounted_this_turn = true
		t.dismount()
		state_changed.emit()
		return true
	if t.carrier == carrier and t.on_top == on_top and t.mounted():
		return true
	t.carrier = carrier
	t.on_top = on_top
	t.in_building = false
	if not in_setup():
		t.mounted_this_turn = true
	log_line("%s mounts: %s %s%s." % [TYRules.esc(t.team_name), "rides on top of" if on_top else "is carried inside", TYRules.esc(carrier.team_name),
			"" if on_top else " (special rule Passengers %d)" % carrier.capacity])
	state_changed.emit()
	return true


## Infantry model `t` goes into a building (or comes out of it). Getting out of a vehicle to do so counts as dismounting.
func set_in_building(t: TeamState, inside: bool) -> bool:
	if t.is_vehicle:
		return false
	if inside and t.mounted() and not mount(t, null):
		return false
	if t.in_building != inside:
		t.in_building = inside
		log_line("%s %s a building." % [TYRules.esc(t.team_name), "occupies" if inside else "leaves"])
		state_changed.emit()
	return true


# ------------------------------------------------------------------ teams

func player_count() -> int:
	return player_names.size()


func active_team() -> int:
	return int(turn_order[turn_index])


func next_team() -> int:
	return int(turn_order[(turn_index + 1) % turn_order.size()])


func team_of(player: int) -> int:
	return int(player_team[player])


func team_players(team: int) -> Array:
	var out: Array = []
	for p in player_team.size():
		if int(player_team[p]) == team:
			out.append(p)
	return out


## The players whose turn it is.
func active_players() -> Array:
	return team_players(active_team())


func is_active(player: int) -> bool:
	return team_of(player) == active_team()


func are_enemies(a: int, b: int) -> bool:
	return team_of(a) != team_of(b)


## "Team A (Anna + Ben)"; a team of one is just the player's name.
func team_label(team: int) -> String:
	var names: PackedStringArray = []
	for p in team_players(team):
		names.append(str(player_names[p]))
	if names.size() == 1:
		return names[0]
	return "%s (%s)" % [TEAM_NAMES[team], " + ".join(names)]


func team_tag(team: int) -> String:
	var parts: PackedStringArray = []
	for p in team_players(team):
		parts.append(player_tag(p))
	if parts.size() == 1:
		return parts[0]
	return "[b]%s[/b] (%s)" % [TEAM_NAMES[team], " + ".join(parts)]


## Name of the side whose turn it is.
func active_name() -> String:
	return team_label(active_team())


# ------------------------------------------------------------------ units

func living(player: int) -> Array:
	var out: Array = []
	for u in units[player]:
		if not u.is_destroyed():
			out.append(u)
	return out


## Living units of the team whose turn it is (all its players).
func friendly_living() -> Array:
	var out: Array = []
	for p in active_players():
		out.append_array(living(p))
	return out


## Living units of every other team.
func enemy_living() -> Array:
	var out: Array = []
	for p in player_count():
		if not is_active(p):
			out.append_array(living(p))
	return out


## "#rrggbb" of a player: the colour of the player's card in the Armies tab.
func color_hex(p: int) -> String:
	if p >= 0 and p < player_colors.size():
		return String(player_colors[p])
	return PLAYER_COLORS[p % PLAYER_COLORS.size()]


func player_color(p: int) -> Color:
	return Color.html(color_hex(p))


func player_tag(p: int) -> String:
	return "[color=%s][b]%s[/b][/color]" % [color_hex(p), TYRules.esc(str(player_names[p]))]


## Coloured unit name for log lines.
func tag(u: UnitInstance) -> String:
	return "[color=%s]%s[/color]" % [color_hex(u.owner_id), TYRules.esc(u.label)]


## The unit a model belongs to.
func unit_of(model: TeamState) -> UnitInstance:
	for list in units:
		for u: UnitInstance in list:
			if u.teams.has(model):
				return u
	return null


## True during round 0 (the transport set-up before the first turn).
func in_setup() -> bool:
	return round_number == 0


func phase_name() -> String:
	return PHASE_NAMES[phase]


func log_line(bbcode: String) -> void:
	log_history.append(bbcode)
	log_added.emit(bbcode)


func touch() -> void:
	state_changed.emit()


# ------------------------------------------------------------------ turn sequence

func next_phase() -> void:
	if in_setup():                                   # round 0 is over: the first team starts round 1
		round_number = 1
		turn_index = 0
		phase = Phase.STARTING
		for p in active_players():
			for u in units[p]:
				u.begin_turn()
		log_line("")
		log_line("[b]Round 1[/b] - %s's turn" % team_tag(active_team()))
		phase_changed.emit()
		state_changed.emit()
		return
	if phase < Phase.ASSAULT:
		phase += 1
		if phase == Phase.SHOOTING:                 # hits only Pin Down when they are scored in one Shooting Step
			for list in units:
				for u: UnitInstance in list:
					u.hits_taken = 0
		log_line("[color=#6b6b6b]-- %s: %s --[/color]" % [TYRules.esc(active_name()), phase_name()])
	else:
		_end_turn()
		return
	phase_changed.emit()
	state_changed.emit()


func _end_turn() -> void:
	turn_index = (turn_index + 1) % turn_order.size()
	if turn_index == 0:
		round_number += 1
	phase = Phase.STARTING
	for p in active_players():
		for u in units[p]:
			u.begin_turn()
	log_line("")
	log_line("[b]Round %d[/b] - %s's turn" % [round_number, team_tag(active_team())])
	phase_changed.emit()
	state_changed.emit()


# ------------------------------------------------------------------ points

func points_total(player: int) -> int:
	var total: int = 0
	for u in units[player]:
		total += (u.option.cost(ArmyManager.use_dynamic_points) if u.option != null else 0) + u.upgrade_points
	return total


## Points value of the units a player has lost so far (whole units only).
func points_lost(player: int) -> int:
	var total: int = 0
	for u in units[player]:
		if u.is_destroyed():
			total += (u.option.cost(ArmyManager.use_dynamic_points) if u.option != null else 0) + u.upgrade_points
	return total


func team_points_total(team: int) -> int:
	var total: int = 0
	for p in team_players(team):
		total += points_total(p)
	return total


func team_points_lost(team: int) -> int:
	var total: int = 0
	for p in team_players(team):
		total += points_lost(p)
	return total
