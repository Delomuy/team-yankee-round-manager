class_name AirUnitData
extends UnitData
## Helicopters and fixed-wing aircraft.

@export var aircraft_type: String = "helicopter"   ## "helicopter" or "jet"


func _init() -> void:
	category = Category.AIR
