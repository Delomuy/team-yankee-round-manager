class_name ArmoredUnitData
extends UnitData
## Tanks, IFVs, APCs, self-propelled guns, armored recon.

@export var armour_front: int = 0
@export var armour_side: int = 0
@export var armour_top: int = 0


func _init() -> void:
	category = Category.ARMORED
