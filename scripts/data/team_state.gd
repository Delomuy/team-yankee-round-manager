class_name TeamState
extends RefCounted
## One model on the table: a single vehicle, aircraft, gun or infantry team.
## Every model has a code such as "IA3": I = the type of its unit (I infantry, T tanks, A artillery, C carriers /
## transports, H helicopters, P planes), A = which unit of that type (A, B, C ...), 3 = the third model of that unit.

enum Status { OK, BAILED_OUT, DESTROYED }
const RIDERS_ON_TOP := 3                 # infantry models that can ride on top of one ground vehicle

var team_name: String = ""               # "IA3 FAL rifle team" (code + kind), used in the log
var code: String = ""                    # "IA3"
var kind: String = ""                    # what the model is: "FAL rifle team", "BMP-1" ...
var status: int = Status.OK
var weapons: Array = []                  # indexes into the unit's weapons this model can fire (see ModelWeapons)
var is_vehicle: bool = false             # can carry infantry
var is_aircraft: bool = false            # nobody rides on top of a helicopter
var capacity: int = 0                    # infantry models that fit inside ("Passengers N" on the card)
var carrier: TeamState = null            # the vehicle this infantry model is in / on (null = on foot)
var on_top: bool = false                 # true = riding on top of `carrier`, false = inside it
var fired: Dictionary = {}               # weapon index -> true: what this model has fired this turn
var mounted_this_turn: bool = false      # "A Team cannot Mount and Dismount in the same turn" (rules p.36)
var dismounted_this_turn: bool = false
var rides_on_top_ok: bool = false        # an Armoured Tank Team: up to three Infantry Teams can ride on top of it
var in_building: bool = false            # infantry occupying a building
# --- how this model moved in its own last Movement step (UnitInstance.MoveMode)
var move_mode: int = 0
var move_distance: int = 0
var cross_failed: bool = false           # Bogged Down: failed a Cross Check, cannot Move, Shoot or Assault until its next turn


func _init(p_name: String = "") -> void:
	team_name = p_name
	kind = p_name


## An OK team can move, shoot and assault. Bailed-out teams can do none of these.
func is_active() -> bool:
	return status == Status.OK


func is_alive() -> bool:
	return status != Status.DESTROYED


## Carried by a vehicle that is still alive (a model whose vehicle was destroyed is back on foot).
## Bogged Down in Difficult Going (frees itself at the start of its next turn).
func bogged() -> bool:
	return cross_failed and is_alive()


func mounted() -> bool:
	return carrier != null and carrier.is_alive() and is_alive()


func dismount() -> void:
	carrier = null
	on_top = false


func place_text() -> String:
	if not mounted():
		return "in a building" if in_building else ""
	return ("on top of %s" if on_top else "inside %s") % carrier.code


func status_text() -> String:
	match status:
		Status.BAILED_OUT:
			return "Bailed out"
		Status.DESTROYED:
			return "Destroyed"
	return "OK"
