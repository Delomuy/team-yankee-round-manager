class_name UnitSheet
extends PanelContainer
## A unit card laid out like the Team Yankee force-builder page:
##   - a coloured title bar,
##   - on the left the purchase options (points badges) and the upgrades,
##   - on the right the unit-type line, the picture, the red Courage / Skill pills, Is Hit On and the save
##     (or the Front / Side / Top armour box), the movement table and the weapons table.
## Special rules are clickable (see RulePopup). On a narrow window the options move under the card.
##
## Every box sits on the parchment picture (see Paper). With `selectable` the purchase options are radio rows
## (clicking one selects that unit size and emits option_chosen) and every upgrade is a check box with its points
## (a "+N each" upgrade also has an "x n" box; upgrades_changed is emitted). The army editor uses this.
##
## Use:  var sheet := UnitSheet.new().setup(unit, ArmyManager.use_dynamic_points)

signal option_chosen(index: int)
signal upgrades_changed

const RED := Color(0.745, 0.122, 0.141)
const PAPER := Color(1, 1, 1)
const ZEBRA := Color(0.933, 0.933, 0.933)
const INK := Color(0.07, 0.07, 0.07)
const GOLD := Color(0.88, 0.66, 0.05)
const CLEAR := Color(0, 0, 0, 0)
const NARROW_BELOW := 760.0

var unit: UnitData
var _color: Color = Color(0.4, 0.4, 0.4)
var _dynamic: bool = false
var _root: VBoxContainer
var _body: BoxContainer
var _options: Control
var _card: Control
var _narrow: bool = false
var _selectable: bool = false
var _selected_option: int = 0
var _option_rows: Array = []             # the frame of each option row
var _radios: Array = []
var _up_checks: Array = []               # selectable sheet: one CheckBox per upgrade
var _up_spins: Array = []                # ... and its "x n" SpinBox (null for one-off upgrades)
var _group: ButtonGroup = ButtonGroup.new()

static var _bold_font: FontVariation


## Colour of a nation's cards (the same as its tile in the grid; American green is the web page's).
static func color_for(nation: String) -> Color:
	return CardTile.nation_color_for(nation)


static func _bold() -> Font:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = ThemeDB.fallback_font
		_bold_font.variation_embolden = 0.9
	return _bold_font


func setup(u: UnitData, dynamic: bool = false, selectable: bool = false, option_index: int = 0) -> UnitSheet:
	unit = u
	_dynamic = dynamic
	_selectable = selectable and not u.options.is_empty()
	_selected_option = clampi(option_index, 0, maxi(u.options.size() - 1, 0))
	_color = color_for(u.nation)
	var page: MarginContainer = UIUtil.round_holder(self, 10, 10, 10, Color(0.97, 0.96, 0.93))     # rounded parchment page
	_root = UIUtil.vbox(8)
	page.add_child(_root)
	_root.add_child(_heading())
	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_root.add_child(_body)
	_options = _options_panel()
	_card = _card_column()
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_options.size_flags_stretch_ratio = 4.0
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_stretch_ratio = 6.0
	_body.add_child(_options)
	_body.add_child(_card)
	resized.connect(func() -> void: set_narrow(size.x < NARROW_BELOW))
	_apply_option_styles()
	return self


## Index of the highlighted option (0 when the sheet is not selectable).
func selected_option() -> int:
	return _selected_option


func select_option(index: int) -> void:
	if index < 0 or index >= _option_rows.size():
		return
	_selected_option = index
	_apply_option_styles()
	_update_upgrade_limits()


## {upgrade index: how many} of the ticked upgrades (selectable sheets only).
func chosen_upgrades() -> Dictionary:
	var out: Dictionary = {}
	for i in _up_checks.size():
		if (_up_checks[i] as CheckBox).button_pressed:
			var spin: SpinBox = _up_spins[i]
			out[i] = int(spin.value) if spin != null else 1
	return out


## Ticks the given upgrades ({index: how many}) and un-ticks the others.
func set_upgrades(ups: Dictionary) -> void:
	_update_upgrade_limits()
	for i in _up_checks.size():
		var on: bool = ups.has(i)
		(_up_checks[i] as CheckBox).set_pressed_no_signal(on)
		var spin: SpinBox = _up_spins[i]
		if spin != null and on:
			spin.set_value_no_signal(clampf(float(ups[i]), spin.min_value, spin.max_value))


## The "x n" boxes cannot go above what the chosen size allows ("up to 2", or one per model).
func _update_upgrade_limits() -> void:
	var o: UnitOption = unit.get_option(_selected_option)
	var models: int = o.models if o != null else 1
	for i in _up_spins.size():
		var spin: SpinBox = _up_spins[i]
		if spin == null:
			continue
		var was_max: bool = spin.value >= spin.max_value
		spin.max_value = unit.upgrade_limit(i, models)
		spin.set_value_no_signal(spin.max_value if was_max else minf(spin.value, spin.max_value))


## Narrow: the card first, the options underneath it. Wide: options left, card right (as on the web page).
func set_narrow(narrow: bool) -> void:
	if narrow == _narrow or _body == null:
		return
	_narrow = narrow
	_body.vertical = narrow
	_body.move_child(_card, 0 if narrow else 1)


# ------------------------------------------------------------------ small builders

func _style(bg: Color, border: Color = CLEAR, border_w: int = 0, radius: int = 6, margin_h: int = 4, margin_v: int = 2) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h + border_w
	s.content_margin_right = margin_h + border_w
	s.content_margin_top = margin_v + border_w
	s.content_margin_bottom = margin_v + border_w
	return s


func _panel(style: StyleBox, child: Control = null) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	if child != null:
		p.add_child(child)
	return p


## Parchment box with a nation-coloured frame.
## Its content is cut to the rounded shape, so pictures and tables get rounded corners too.
func _framed(child: Control, radius: int = 8, margin_h: int = 4, margin_v: int = 2, border: int = 2) -> PanelContainer:
	return UIUtil.paper_frame(child, _color, radius, margin_h, margin_v, border)


func _label(text: String, font_size: int = 13, color: Color = INK, bold: bool = false,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", _bold())
	return l


func _wrap(l: Label, min_width: float = 80.0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_width, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _rich(bbcode: String, font_size: int, centered: bool) -> RichTextLabel:
	var r: RichTextLabel = RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(70, 0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_color_override("default_color", INK)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		r.add_theme_font_size_override(key, font_size)
	r.text = ("[center]%s[/center]" % bbcode) if centered else bbcode
	RulePopup.connect_label(r)
	return r


## A cell of a table: the grid behind the cells is the nation colour, so a 1px gap draws the coloured lines.
func _cell(content: Control, bg: Color, expand: bool = false) -> PanelContainer:
	var style: StyleBox = _style(bg, CLEAR, 0, 0, 4, 2)
	if bg == PAPER:
		style = Paper.style(Color.WHITE, 4, 2)
	elif bg == ZEBRA:
		style = Paper.style(Color(0.88, 0.87, 0.84), 4, 2)
	var p: PanelContainer = _panel(style, content)
	if expand:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _table_frame(grid: GridContainer) -> PanelContainer:
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	return UIUtil.paper_frame(grid, _color, 8, 2, 2, 2, Color.WHITE, _color)      # the colour shows through the 1px gaps; the margin keeps the square cells inside the rounded corners


func _head(text: String, expand: bool) -> PanelContainer:
	return _cell(_label(text.to_upper(), 11, Color.WHITE, true), _color, expand)


# ------------------------------------------------------------------ title bar

func _heading() -> Control:
	var v: VBoxContainer = UIUtil.vbox(0)
	v.add_child(_label("TEAM YANKEE", 12, Color(1, 1, 1, 0.85)))
	v.add_child(_label(unit.display_name.to_upper(), 26, Color.WHITE, true))
	v.add_child(_label("%s  -  %s" % [String(unit.id), RulesDB.nation_label(unit.nation)], 12, Color(1, 1, 1, 0.7)))
	return _panel(_style(_color, CLEAR, 0, 10, 8, 6), v)


# ------------------------------------------------------------------ left: options

func _options_panel() -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	var outer: PanelContainer = _framed(v, 10, 4, 4)
	v.add_child(_label(unit.display_name.to_upper(), 16, INK, true))
	if unit.is_attachment:
		v.add_child(_wrap(_label("Attachment: not bought on its own.", 12, Color(0.5, 0.3, 0.0), false)))
	elif _selectable:
		v.add_child(_wrap(_label("Click the size you want and tick the upgrades you want.", 11, Color(0.35, 0.35, 0.35), false)))
	for i in unit.options.size():
		v.add_child(_option_row(unit.options[i], i))
	if not unit.upgrades.is_empty():
		v.add_child(_label("OPTIONS", 14, INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		for i in unit.upgrades.size():
			var up: Dictionary = unit.upgrades[i]
			var suffix: String = "  (%s)" % unit.upgrade_price_text(i)
			var text: Label = _wrap(_label("%s%s%s" % ["" if _selectable else "- ", str(up.get("text", "")), suffix], 12, INK, false, HORIZONTAL_ALIGNMENT_LEFT), 120.0)
			if _selectable:
				v.add_child(_upgrade_row(i, text, unit.upgrade_kind(i) == "choice"))
			else:
				v.add_child(text)
		_update_upgrade_limits()
	if not unit.notes.is_empty():
		v.add_child(_label("NOTES", 14, INK, true, HORIZONTAL_ALIGNMENT_LEFT))
		for n in unit.notes:
			v.add_child(_wrap(_label("- " + str(n), 12, INK, false, HORIZONTAL_ALIGNMENT_LEFT), 120.0))
	return outer


func _upgrade_row(index: int, text: Label, per_model: bool) -> Control:
	var row: HBoxContainer = UIUtil.hbox(6)
	var cb: CheckBox = CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cb.toggled.connect(_on_upgrade_toggled)
	_up_checks.append(cb)
	row.add_child(cb)
	row.add_child(text)
	var spin: SpinBox = null
	if per_model:
		spin = UIUtil.spin(1, 1, 1)
		spin.prefix = "x "
		spin.tooltip_text = "How many of them"
		spin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		spin.value_changed.connect(_on_upgrade_qty_changed)
		row.add_child(spin)
	_up_spins.append(spin)
	return row


func _on_upgrade_toggled(_on: bool) -> void:
	upgrades_changed.emit()


func _on_upgrade_qty_changed(_v: float) -> void:
	upgrades_changed.emit()


func _option_row(o: UnitOption, index: int) -> Control:
	var lines: PackedStringArray = []
	if o.composition.is_empty():
		lines = o.label.split(" + ")
	else:
		for c in o.composition:
			var part: Dictionary = c
			lines.append("%dx %s" % [int(part.get("count", 1)), str(part.get("name", ""))])
	var row: HBoxContainer = UIUtil.hbox(6)
	if _selectable:
		var radio: CheckBox = CheckBox.new()
		radio.button_group = _group
		radio.focus_mode = Control.FOCUS_NONE
		radio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		radio.toggled.connect(_on_radio_toggled.bind(index))
		_radios.append(radio)
		row.add_child(radio)
	row.add_child(_wrap(_label("\n".join(lines), 13, INK, true, HORIZONTAL_ALIGNMENT_LEFT), 120.0))
	var badge: PanelContainer = _panel(_style(_color, CLEAR, 0, 6, 8, 2),
			_label("%d POINTS" % o.cost(_dynamic), 12, Color.WHITE, true))
	badge.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(badge)
	var frame: PanelContainer = _framed(row, 7, 4, 3)
	if _selectable:
		frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		frame.gui_input.connect(_on_row_input.bind(index))
	_option_rows.append(frame)
	return frame


func _on_radio_toggled(on: bool, index: int) -> void:
	if on:
		_choose(index)


func _on_row_input(event: InputEvent, index: int) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_choose(index)


func _choose(index: int) -> void:
	_selected_option = index
	_apply_option_styles()
	_update_upgrade_limits()
	option_chosen.emit(index)


## Gold, thicker frame and a ticked radio button on the chosen row.
func _apply_option_styles() -> void:
	for i in _option_rows.size():
		var chosen: bool = _selectable and i == _selected_option
		var frame: PanelContainer = _option_rows[i]
		var outline: Panel = frame.get_meta("border") as Panel
		outline.add_theme_stylebox_override("panel", UIUtil.border_style(GOLD if chosen else _color, 4 if chosen else 2, 7))
		if i < _radios.size():
			(_radios[i] as CheckBox).set_pressed_no_signal(chosen)


# ------------------------------------------------------------------ right: the card

func _card_column() -> Control:
	var v: VBoxContainer = UIUtil.vbox(8)
	var parts: PackedStringArray = [unit.unit_type.to_upper()]
	parts.append_array(_rule_links())
	v.add_child(_rich("[b]• %s •[/b]" % " • ".join(parts), 12, true))
	var top: HBoxContainer = UIUtil.hbox(8)
	top.add_child(_picture())
	var stats: VBoxContainer = UIUtil.vbox(6)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(_pills())
	stats.add_child(_armour_box() if unit.get("armour_front") != null else _hit_save_boxes())
	top.add_child(stats)
	v.add_child(top)
	v.add_child(_movement_table())
	v.add_child(_weapons_table())
	return v


func _rule_links() -> PackedStringArray:
	var out: PackedStringArray = []
	for r in unit.special_rules:
		out.append(RulesDB.link(r, unit.nation, true, true))
	return out


func _picture() -> Control:
	var content: Control
	var tex: Texture2D = CardImages.get_texture(String(unit.id))
	if tex != null:
		var pic: TextureRect = TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		UIUtil.round_texture(pic, 6.0)
		content = pic
	else:
		content = _wrap(_label("No picture yet", 12, Color(0.45, 0.45, 0.45)), 60.0)
	var holder: PanelContainer = _framed(content, 8, 2, 2)      # the parchment shows behind the picture
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(120, 150)
	return holder


func _pill_column(title: String, value: int, lines: Array) -> Control:
	var v: VBoxContainer = UIUtil.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_panel(_style(RED, CLEAR, 0, 8, 4, 2), _label("%s %s" % [title, CardView._stat(value)], 14, Color.WHITE, true)))
	for pair in lines:
		var p: Array = pair
		v.add_child(_label("%s %s" % [String(p[0]), CardView._stat(int(p[1]))], 11, INK, true))
	return v


func _pills() -> Control:
	var left_lines: Array = [["MORALE", unit.morale]]
	if unit.rally > 0:
		left_lines.append(["RALLY", unit.rally])
	if unit.remount > 0:
		left_lines.append(["REMOUNT", unit.remount])
	var h: HBoxContainer = UIUtil.hbox(2)
	h.add_child(_pill_column("COURAGE", unit.courage, left_lines))
	var skill_lines: Array = []
	if unit.category != UnitData.Category.AIR:           # aircraft and helicopters do not assault; ground units always show them
		skill_lines = [["ASSAULT", unit.assault], ["COUNTERATTACK", unit.counterattack]]
	h.add_child(_pill_column("SKILL", unit.skill, skill_lines))
	return _framed(h, 8, 2, 2)


func _stat_box(title: String, value: String) -> Control:
	var v: VBoxContainer = UIUtil.vbox(0)
	v.add_child(_panel(_style(_color, CLEAR, 0, 7, 2, 2), _label(title.to_upper(), 11, Color.WHITE, true)))
	v.add_child(_label(value, 22, INK, true))
	var box: PanelContainer = _framed(v, 8, 2, 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


func _hit_save_boxes() -> Control:
	var h: HBoxContainer = UIUtil.hbox(4)
	h.add_child(_stat_box("Is hit on", CardView._stat(unit.is_hit_on)))
	var save: Variant = unit.get("save")
	if save != null and int(save) > 0:
		var title: String = "Save"
		if unit.category == UnitData.Category.AIR:
			title = "Aircraft Save"
		elif unit.category == UnitData.Category.GROUND:
			title = "Infantry Save"
		h.add_child(_stat_box(title, CardView._stat(int(save))))
	return h


func _armour_box() -> Control:
	var v: VBoxContainer = UIUtil.vbox(3)
	var pill: PanelContainer = UIUtil.paper_frame(_label("IS HIT ON %s" % CardView._stat(unit.is_hit_on), 13, INK, true),
			CLEAR, 10, 10, 2, 0)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pill)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for h in ["Front", "Side", "Top"]:
		grid.add_child(_cell(_label(String(h).to_upper(), 11, Color.WHITE, true), _color, true))
	for a in [unit.get("armour_front"), unit.get("armour_side"), unit.get("armour_top")]:
		grid.add_child(_cell(_label(str(a), 16, INK, true), PAPER, true))
	v.add_child(grid)
	return _panel(_style(_color, _color, 2, 10, 4, 4), v)


# ------------------------------------------------------------------ tables

func _movement_table() -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	for h in ["Tactical", "Terrain Dash", "Cross Country Dash", "Road Dash", "Cross"]:
		var head: PanelContainer = _head(String(h), true)
		grid.add_child(head)
	var cross: String = CardView._stat(unit.cross_skill).to_upper()
	for v in [CardView._move(unit.tactical), CardView._move(unit.terrain_dash), CardView._move(unit.cross_dash),
			CardView._move(unit.road_dash), cross]:
		grid.add_child(_cell(_label(String(v), 14, INK, true), PAPER, true))
	return _table_frame(grid)


static func _range_text(w: WeaponData) -> String:
	var far: String = CardView._move(w.range_cm)
	if w.range_cm_min > 0:
		return "%s-\n%s" % [CardView._move(w.range_cm_min), far]
	return far


func _weapons_table() -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 7
	var heads: Array = ["Weapon", "Range", "ROF Halted", "ROF Moving", "Anti-tank", "Firepower", "Notes"]
	for i in heads.size():
		grid.add_child(_head(String(heads[i]), i == 0 or i == 6))
	var odd: bool = false
	for w: WeaponData in unit.weapons:
		var bg: Color = ZEBRA if odd else PAPER
		odd = not odd
		grid.add_child(_cell(_wrap(_label(w.weapon_name, 13, INK, true, HORIZONTAL_ALIGNMENT_LEFT), 90.0), bg, true))
		grid.add_child(_cell(_label(_range_text(w), 13, INK, true), bg))
		grid.add_child(_cell(_label(CardView._rof(w, false), 13, INK, true), bg))
		grid.add_child(_cell(_label(CardView._rof(w, true), 13, INK, true), bg))
		grid.add_child(_cell(_label(str(w.anti_tank) if w.anti_tank > 0 else "-", 13, INK, true), bg))
		grid.add_child(_cell(_label(CardView._stat(w.firepower), 13, INK, true), bg))
		var notes: String = ""
		if not w.rules.is_empty():
			notes = "[i]%s[/i]" % RulesDB.links(w.rules, unit.nation, true)
		grid.add_child(_cell(_rich(notes, 12, false), bg, true))
	return _table_frame(grid)
