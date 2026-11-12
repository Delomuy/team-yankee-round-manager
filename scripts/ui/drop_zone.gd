class_name DropZone
extends PanelContainer
## A panel that accepts dragged cards. Cards carry a payload dictionary {"kind": "catalog" | "army", ...}
## (CardTile.drag_payload); the zone only accepts the kind it was made for and emits `dropped`.
## While a matching card is being dragged the zone is tinted so you can see where to drop it.

signal dropped(payload: Dictionary)

## "catalog" = a card taken from the card selector, "army" = a card taken from an army list.
var accepts: String = ""
var _lit: bool = false


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String((data as Dictionary).get("kind", "")) == accepts


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(data as Dictionary)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if typeof(data) == TYPE_DICTIONARY and String((data as Dictionary).get("kind", "")) == accepts:
			_lit = true
			modulate = Color(1.0, 0.9, 0.55)
	elif what == NOTIFICATION_DRAG_END and _lit:
		_lit = false
		modulate = Color(1, 1, 1)
