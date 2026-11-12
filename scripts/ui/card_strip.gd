class_name CardStrip
extends PanelContainer
## A card folded to one line: name and id on a greyed strip in the nation's colour. Used in the formation screens for
## cards that cannot be taken now (the OR alternatives of a chosen card, cards of an exclusive slot that is blocked),
## so the chosen cards stand out and the columns stay short. Click = the same as clicking the full card;
## double-click = read the full card.

signal clicked(unit: UnitData)
signal activated(unit: UnitData)

var unit: UnitData


func setup(u: UnitData, width: float, reason: String = "") -> CardStrip:
	unit = u
	var col: Color = CardTile.nation_color_for(u.nation)
	add_theme_stylebox_override("panel", AppTheme.box(Color(0.90, 0.89, 0.86), col.lerp(Color(0.6, 0.6, 0.6), 0.5), 2, 6, 8, 3))
	custom_minimum_size = Vector2(width, 0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v: VBoxContainer = UIUtil.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl: Label = UIUtil.bold_label(u.display_name, 12, Color(0.32, 0.32, 0.32), HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.clip_text = true
	name_lbl.custom_minimum_size = Vector2(width - 20.0, 0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)
	var id_lbl: Label = UIUtil.label("%s  -  %s" % [String(u.id), "not available" if reason != "" else "not chosen"], Color(0.45, 0.45, 0.45))
	id_lbl.add_theme_font_size_override("font_size", 11)
	id_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(id_lbl)
	add_child(v)
	tooltip_text = ("NOT AVAILABLE: %s\n\n" % reason if reason != "" else "") + "%s (%s)\nDouble-click to read the card." % [u.display_name, String(u.id)]
	return self


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.double_click:
		activated.emit(unit)
	else:
		clicked.emit(unit)
