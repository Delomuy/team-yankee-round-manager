class_name GroundUnitData
extends UnitData
## Infantry, gun teams, command teams, other unarmored dismounts.

## The vehicle unit this company rides in (as listed in the source data).
@export var transport_name: String = ""
@export var transport_id: StringName
## Every vehicle it can ride in (some formations offer several).
@export var transport_ids: PackedStringArray = []


func _init() -> void:
	category = Category.GROUND
