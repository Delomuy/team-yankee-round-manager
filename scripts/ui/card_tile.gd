class_name CardTile
extends PanelContainer
## One unit drawn like a real card: nation-coloured title strip, picture, type line and key stats.

signal clicked(unit: UnitData)
signal activated(unit: UnitData)      # double click
signal right_clicked(unit: UnitData)

var unit: UnitData
var _nation_color: Color = Color(0.4, 0.4, 0.4)
var _selected: bool = false
var _img: TextureRect
var _holder: PanelContainer
var _paper_bg: TextureRect
var _holder_flat: StyleBoxFlat           # the coloured placeholder background (used while there is no picture)
var _placeholder: Label
var _footer: Label
var _footer_override: String = ""
var _count_badge: PanelContainer
var _count_lbl: Label
var _remove_badge: PanelContainer
var _remove_lbl: Label
## Set to {"kind": ..., ...} to make the card draggable (see DropZone). Empty = not draggable.
var drag_payload: Dictionary = {}


static func nation_color_for(nation: String) -> Color:
	match nation:
		"American":
			return Color.html("#396826")      # the green of the web card page
		"Soviet":
			return Color.html("#9a2f2f")
		"British":
			return Color.html("#6a4a8a")
		"WestGerman":
			return Color.html("#7a7a40")
		"EastGerman":
			return Color.html("#3f7a4a")
		"Belgian":
			return Color.html("#a0802a")
		"Israeli":
			return Color.html("#2f7a9a")
		"Swedish":
			return Color.html("#3a6fb0")
	var added: Dictionary = NationDB.color(nation)     # a nation added in the program
	if bool(added["ok"]):
		return added["color"]
	return Color.from_hsv(float(absi(nation.hash()) % 360) / 360.0, 0.45, 0.55)


static func _cm(v: int) -> String:
	return "unl." if v == UnitData.AUTO else str(maxi(v, 0))


static func _plus(v: int) -> String:
	if v == UnitData.AUTO:
		return "Auto"
	return "-" if v <= 0 else "%d+" % v


func setup(u: UnitData, p_size: Vector2) -> void:
	unit = u
	custom_minimum_size = p_size
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_PASS         # lets drops and the mouse wheel reach the container behind
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_nation_color = nation_color_for(u.nation)
	_apply_style()

	var compact: bool = p_size.x < 200.0
	var fs: int = 10 if compact else 11
	var inner_w: float = p_size.x - 22.0
	var box: VBoxContainer = UIUtil.vbox(4)
	add_child(box)

	# ---- title strip
	var strip: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _nation_color
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	strip.add_theme_stylebox_override("panel", sb)
	var tbox: VBoxContainer = UIUtil.vbox(0)
	var name_lbl: Label = Label.new()
	name_lbl.text = u.display_name
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.max_lines_visible = 2
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	name_lbl.custom_minimum_size = Vector2(inner_w - 14.0, 36)
	tbox.add_child(name_lbl)
	var id_lbl: Label = Label.new()
	id_lbl.text = "%s  -  %s" % [String(u.id), u.nation]
	id_lbl.add_theme_font_size_override("font_size", 10)
	id_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	id_lbl.clip_text = true
	id_lbl.custom_minimum_size = Vector2(inner_w - 14.0, 14)
	tbox.add_child(id_lbl)
	strip.add_child(tbox)
	box.add_child(strip)

	# ---- picture (or a coloured placeholder)
	var holder: PanelContainer = PanelContainer.new()
	var hb: StyleBoxFlat = StyleBoxFlat.new()
	hb.bg_color = UIUtil.CATEGORY_COLORS[clampi(u.category, 0, 2)]
	hb.set_corner_radius_all(4)
	holder.add_theme_stylebox_override("panel", hb)
	_holder = holder
	_holder_flat = hb
	holder.custom_minimum_size = Vector2(inner_w, int(p_size.y * 0.37))
	holder.clip_contents = true
	if Paper.texture() != null:                                  # parchment behind a picture (shown only when there is one)
		_paper_bg = TextureRect.new()
		_paper_bg.texture = Paper.texture()
		_paper_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_paper_bg.stretch_mode = TextureRect.STRETCH_SCALE
		_paper_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paper_bg.visible = false
		UIUtil.round_texture(_paper_bg, 4.0)
		holder.add_child(_paper_bg)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.clip_contents = true
	UIUtil.round_texture(_img, 4.0)
	holder.add_child(_img)
	_placeholder = Label.new()
	_placeholder.text = u.category_name().to_upper()
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.add_theme_font_size_override("font_size", 20)
	_placeholder.add_theme_color_override("font_color", Color(1, 1, 1, 0.28))
	holder.add_child(_placeholder)
	box.add_child(holder)

	# ---- type line
	var kind: String = u.unit_type
	if not u.special_rules.is_empty():
		kind += ", " + ", ".join(u.special_rules)
	var type_lbl: Label = _small(kind, fs, Color(0.32, 0.27, 0.12), inner_w)
	box.add_child(type_lbl)

	# ---- stats
	var move: String = "Move unlimited"
	if u.tactical != UnitData.AUTO:
		move = "Move %s/%s/%s/%scm" % [_cm(u.tactical), _cm(u.terrain_dash), _cm(u.cross_dash), _cm(u.road_dash)]
	box.add_child(_small(move, fs, Color(0.12, 0.12, 0.12), inner_w))
	var prot: String = ""
	if u.get("armour_front") != null and not u.unit_type.to_lower().contains("unarmoured"):
		prot = "Armour %s/%s/%s" % [str(u.get("armour_front")), str(u.get("armour_side")), str(u.get("armour_top"))]
	else:
		prot = "Save %s" % _plus(u.save)
	box.add_child(_small("%s   Hit on %s" % [prot, _plus(u.is_hit_on)], fs, Color(0.12, 0.12, 0.12), inner_w))
	box.add_child(_small("Skill %s  Courage %s  Cross %s" % [_plus(u.skill), _plus(u.courage), _plus(u.cross_skill)], fs, Color(0.12, 0.12, 0.12), inner_w))

	# ---- footer
	_footer = _small("", fs, Color(0.50, 0.30, 0.0), inner_w)
	box.add_child(_footer)

	tooltip_text = _tooltip()
	_add_badges()
	_ignore_mouse(self)
	refresh_points()
	refresh_image()


# ------------------------------------------------------------------ badges (army list)

func _add_badges() -> void:
	var overlay: Control = Control.new()                 # fills the tile; the two circles are anchored in its corners
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_count_badge = _circle(Color(0.03, 0.03, 0.03), true)
	_count_lbl = _count_badge.get_child(0) as Label
	overlay.add_child(_count_badge)
	_remove_badge = _circle(Color(0.80, 0.08, 0.08), false)
	_remove_lbl = _remove_badge.get_child(0) as Label
	overlay.add_child(_remove_badge)


func _circle(bg: Color, right: bool) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", AppTheme.box(bg, Color.WHITE, 2, 16, 4, 0))
	p.custom_minimum_size = Vector2(32, 32)
	p.visible = false
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = UIUtil.bold_label("", 14, Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	if right:                                            # top right corner
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -38.0
		p.offset_right = -6.0
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:                                                # top left corner
		p.offset_left = 6.0
		p.offset_right = 38.0
	p.offset_top = 6.0
	p.offset_bottom = 38.0
	return p


## "x3" in a black circle at the top right (shown from 2 copies up): the same card bought several times.
func set_count(n: int) -> void:
	_count_lbl.text = "x%d" % n
	_count_badge.visible = n >= 2


## Red circle at the top left with the number of copies marked for removal (hidden at 0).
func set_remove_count(k: int) -> void:
	_remove_lbl.text = str(k)
	_remove_badge.visible = k > 0


## Replaces the "from N pts" line (used by the army list to show the size that was bought).
func set_footer(text: String, extra_tooltip: String = "") -> void:
	_footer_override = text
	_footer.text = text
	if extra_tooltip != "":
		tooltip_text = _tooltip() + "\n" + extra_tooltip


func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty():
		return null
	var copy: CardTile = CardTile.new()                 # the whole card follows the mouse, slightly see-through
	copy.setup(unit, custom_minimum_size)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.modulate = Color(1, 1, 1, 0.85)
	copy.position = -custom_minimum_size * 0.5
	var preview: Control = Control.new()
	preview.add_child(copy)
	set_drag_preview(preview)
	return drag_payload


func _small(text: String, font_size: int, color: Color, width: float) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.clip_text = true
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _tooltip() -> String:
	var t: String = "%s (%s)\n%s" % [unit.display_name, String(unit.id), unit.unit_type]
	for w in unit.weapons:
		t += "\n- %s  AT %d  FP %s" % [w.weapon_name, w.anti_tank, _plus(w.firepower)]
	return t


func _ignore_mouse(n: Node) -> void:
	for c in n.get_children():
		var ctl: Control = c as Control
		if ctl != null:
			ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)


func _apply_style() -> void:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.96, 0.94, 0.89)
	var w: int = 4 if _selected else 2
	s.set_border_width_all(w)
	s.border_color = Color(1.0, 0.85, 0.3) if _selected else _nation_color
	s.set_corner_radius_all(9)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	add_theme_stylebox_override("panel", s)


## Gold outline: the card is chosen (card selector highlight, a filled formation slot).
func set_selected(on: bool) -> void:
	_selected = on
	_apply_style()


## Greyed out: the card cannot be taken now (exclusive with a chosen card, limit reached ...). `reason` heads the
## tooltip. The card still receives clicks; the screen decides what a click does.
func set_greyed(on: bool, reason: String = "") -> void:
	modulate = Color(0.55, 0.55, 0.55, 0.65) if on else Color.WHITE
	tooltip_text = ("NOT AVAILABLE: %s\n\n" % reason if on and reason != "" else "") + _tooltip()


func refresh_image() -> void:
	var tex: Texture2D = CardImages.get_thumbnail(String(unit.id))
	_img.texture = tex
	_placeholder.visible = tex == null
	UIUtil.fit_round_texture(_img)
	if _paper_bg != null:
		_paper_bg.visible = tex != null


## Points text follows the standard / dynamic points switch.
func refresh_points() -> void:
	if _footer_override != "":
		return
	var best_at: int = 0
	for w in unit.weapons:
		best_at = maxi(best_at, w.anti_tank)
	var pts: String = "attachment" if unit.is_attachment else "from %d pts" % unit.min_points(ArmyManager.use_dynamic_points)
	_footer.text = pts if best_at <= 0 else "%s  |  best AT %d" % [pts, best_at]


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click:
			activated.emit(unit)
		else:
			clicked.emit(unit)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(unit)
