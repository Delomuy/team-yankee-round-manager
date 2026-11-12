class_name UnitOption
extends Resource
## One purchasable size/composition of a unit, e.g. "3x M1A1 Abrams" for 29 pts,
## or "infantry teams + their transports" for an infantry company.

@export var label: String = ""
@export var models: int = 1              ## fighting models (transports are counted separately)
@export var transport_models: int = 0    ## how many transport vehicles come with this option
@export var points: int = 0              ## standard points
@export var points_dynamic: int = 0      ## "dynamic points" cost (equals points if the source gave none)
## [{ "count": 4, "name": "BMP-2", "unit_id": "TS107" }, ...] ("unit_id" only on transports)
@export var composition: Array = []


func cost(dynamic: bool = false) -> int:
	return points_dynamic if dynamic else points


static func from_dict(d: Dictionary) -> UnitOption:
	var o := UnitOption.new()
	o.label = str(d.get("label", ""))
	o.models = int(d.get("models", 1))
	o.transport_models = int(d.get("transport_models", 0))
	o.points = int(d.get("points", 0))
	o.points_dynamic = int(d.get("points_dynamic", o.points))
	o.composition = d.get("composition", [])
	return o
