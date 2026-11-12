class_name ModelTile
extends PanelContainer
## One model as a small, nearly square tile: its icon (ModelIcons, or a drawn symbol), its code ("IA3") and its name
## ("M16 rifle team"), plus its state. Used in the model grids of the Battle tab. It can be clicked (shooting) and,
## when `drag_payload` is set, dragged (round 0: into or onto a carrier).

signal clicked(model: TeamState)
signal shots_changed(model: TeamState, delta: int)       # the + / - buttons of a chosen target

const SIZE := Vector2(104, 100)
enum Mark { NONE, SHOOTER, TARGET }
const MARK_COLORS := [Color(0, 0, 0, 0), Color(0.86, 0.62, 0.04), Color(0.78, 0.12, 0.10)]

var model: TeamState
var unit: UnitInstance
var drag_payload: Dictionary = {}
var _color: Color = Color(0.3, 0.3, 0.3)
var _letter: String = "I"
var _mark: int = Mark.NONE
var _shots_row: HBoxContainer
var _shots_lbl: Label


## `color` = the player's colour, `letter` = the unit's type letter (for the icon).
func setup(u: UnitInstance, m: TeamState, color: Color) -> ModelTile:
	unit = u
	model = m
	_color = color
	var letters: String = u.code.lstrip("0123456789")
	_letter = letters.substr(0, 1) if letters != "" else "I"
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v: VBoxContainer = UIUtil.vbox(1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_BEGIN

	# + / - and the number of shots at this model: only shown once it is chosen as a target (set_shots)
	_shots_row = UIUtil.hbox(3)
	_shots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shots_row.visible = false
	var minus: Button = _small_button("-", -1)
	_shots_lbl = UIUtil.bold_label("x1", 13, UIUtil.BAD)
	_shots_lbl.custom_minimum_size = Vector2(30, 0)
	_shots_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plus: Button = _small_button("+", 1)
	_shots_row.add_child(minus)
	_shots_row.add_child(_shots_lbl)
	_shots_row.add_child(plus)
	v.add_child(_shots_row)

	var icon_holder: CenterContainer = CenterContainer.new()
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = ModelIcons.get_icon(String(u.data.id), _letter)
	if tex != null:
		var pic: TextureRect = TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(44, 34)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_holder.add_child(pic)
	else:
		var sym: ModelSymbol = ModelSymbol.new(_letter, color.darkened(0.2))
		sym.custom_minimum_size = Vector2(44, 34)
		icon_holder.add_child(sym)
	v.add_child(icon_holder)

	var code_lbl: Label = UIUtil.bold_label(m.code, 14, UIUtil.INK)
	code_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(code_lbl)
	var name_lbl: Label = UIUtil.label(m.kind, UIUtil.INK)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.max_lines_visible = 2
	name_lbl.clip_text = true
	name_lbl.custom_minimum_size = Vector2(SIZE.x - 12, 0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)
	var state_text: String = ""
	var state_color: Color = UIUtil.INK
	if not m.is_alive():
		state_text = "DESTROYED"
		state_color = UIUtil.BAD
	elif m.status == TeamState.Status.BAILED_OUT:
		state_text = "BAILED OUT"
		state_color = UIUtil.WARN
	elif m.mounted():
		state_text = ("on %s" if m.on_top else "in %s") % m.carrier.code
		state_color = Color(0.10, 0.37, 0.66)
	elif m.in_building:
		state_text = "in building"
		state_color = Color(0.10, 0.37, 0.66)
	if state_text != "":
		var st: Label = UIUtil.bold_label(state_text, 9, state_color)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(st)
	add_child(v)

	var names: PackedStringArray = []
	for wi in m.weapons:
		if int(wi) < u.data.weapons.size():
			names.append(u.data.weapons[int(wi)].weapon_name)
	var lines: PackedStringArray = ["%s  %s" % [m.code, m.kind], u.label]
	lines.append("To hit this model: %s  (Is Hit On)" % TYRules.needed_text(u.data.is_hit_on))
	if u.uses_armour():
		lines.append("Armour: front %d / side %d / top %d" % [u.armour("front"), u.armour("side"), u.armour("top")])
	else:
		lines.append("Save: %s" % TYRules.needed_text(u.save_value()))
	if m.status != TeamState.Status.OK:
		lines.append(m.status_text().to_upper())
	if m.place_text() != "":
		lines.append("It is %s" % m.place_text())
	lines.append("Fires: %s" % (", ".join(names) if not names.is_empty() else "nothing"))
	tooltip_text = "\n".join(lines)
	if not m.is_alive():
		modulate = Color(1, 1, 1, 0.45)
	_restyle()
	return self


func _small_button(text: String, delta: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(24, 22)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(_on_shots_pressed.bind(delta))
	return b


func _on_shots_pressed(delta: int) -> void:
	shots_changed.emit(model, delta)


## Shows "- xN +" on the tile (n = shots aimed at this model); 0 hides it.
func set_shots(n: int) -> void:
	_shots_row.visible = n > 0
	_shots_lbl.text = "x%d" % n


## Gold frame = chosen to shoot, red frame = chosen as target.
func set_mark(mark: int) -> void:
	_mark = mark
	_restyle()


func _restyle() -> void:
	var marked: bool = _mark != Mark.NONE
	var fill: Color = Color(0.96, 0.94, 0.88)
	if _mark == Mark.SHOOTER:
		fill = Color(1.0, 0.93, 0.68)
	elif _mark == Mark.TARGET:
		fill = Color(1.0, 0.84, 0.80)
	add_theme_stylebox_override("panel", AppTheme.box(fill, MARK_COLORS[_mark] if marked else _color, 4 if marked else 2, 8, 4, 3))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			clicked.emit(model)


## The whole tile follows the mouse.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty():
		return null
	var copy: ModelTile = ModelTile.new().setup(unit, model, _color)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.modulate = Color(1, 1, 1, 0.85)
	copy.position = -SIZE * 0.5
	var preview: Control = Control.new()
	preview.add_child(copy)
	set_drag_preview(preview)
	return drag_payload
