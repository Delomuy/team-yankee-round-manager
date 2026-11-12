class_name PlayerBlock
extends PanelContainer
## One player's summary on the Armies overview: name, main army, number of units, points, models and
## the split between Armored / Ground / Air. Click the block to open that player's army list.

signal opened(index: int)

const CATEGORY_NAMES := ["Armored", "Ground", "Air"]

var index: int = 0
var _army: Army
var _root: VBoxContainer


func setup(player_index: int, army: Army) -> PlayerBlock:
	index = player_index
	_army = army
	custom_minimum_size = Vector2(330, 0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _root == null:
		_root = UIUtil.vbox(6)
		add_child(_root)
	UIUtil.clear_children(_root)
	_build()
	_pass_mouse(self)
	return self


func _build() -> void:
	var color: Color = UnitSheet.color_for(_army.nation) if _army.nation != "" else Color(0.4, 0.4, 0.4)
	_root.add_child(UIUtil.title_bar(_army.army_name, "PLAYER %d" % (index + 1), color, 24))

	var body: VBoxContainer = UIUtil.vbox(4)
	var total: int = _army.total_points()
	var groups: int = _army.groups().size()
	body.add_child(_row("Main army", RulesDB.nation_label(_army.nation) if _army.nation != "" else "not chosen"))
	if _army.use_formations:
		var support: int = _army.support_entries().size()
		body.add_child(_row("Units", "%d  (formation %d, support %d)" % [_army.entries.size(), _army.entries.size() - support, support]))
	else:
		body.add_child(_row("Units", "%d  (%d different)" % [_army.entries.size(), groups]))
	var pts: String = "%d" % total
	var pts_color: Color = UIUtil.INK
	if _army.points_limit > 0:
		pts += " / %d" % _army.points_limit
		pts_color = UIUtil.GOOD if total <= _army.points_limit else UIUtil.BAD
	body.add_child(_row("Points", pts, pts_color))
	if _army.points_limit > 0:
		var left: int = _army.points_limit - total
		body.add_child(_row("", ("%d left" % left) if left >= 0 else ("%d over the limit" % -left), pts_color, 12))
	body.add_child(_row("Models", str(_army.total_models())))
	body.add_child(UIUtil.bold_label("UNIT TYPES", 12, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	body.add_child(_division_bar())
	body.add_child(_legend())
	var hint: Label = UIUtil.label("Click to build this army", Color(0.4, 0.4, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)
	_root.add_child(UIUtil.paper_frame(body, color, 10, 8, 6, 2))


func _row(title: String, value: String, value_color: Color = UIUtil.INK, size: int = 14) -> Control:
	var h: HBoxContainer = UIUtil.hbox(6)
	var t: Label = UIUtil.label(title, Color(0.3, 0.3, 0.3))
	t.custom_minimum_size = Vector2(90, 0)
	h.add_child(t)
	var v: Label = UIUtil.bold_label(value, size, value_color, HORIZONTAL_ALIGNMENT_LEFT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	return h


## A bar split by the number of units of each type.
func _division_bar() -> Control:
	var counts: Array = _army.category_counts()
	var bar: HBoxContainer = UIUtil.hbox(1)
	bar.custom_minimum_size = Vector2(0, 16)
	var any: bool = false
	for i in 3:
		if int(counts[i]) > 0:
			any = true
			var seg: ColorRect = ColorRect.new()
			seg.color = UIUtil.CATEGORY_COLORS[i]
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seg.size_flags_stretch_ratio = float(counts[i])
			bar.add_child(seg)
	if not any:
		var empty: ColorRect = ColorRect.new()
		empty.color = Color(0.6, 0.58, 0.54, 0.5)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(empty)
	return bar


func _legend() -> Control:
	var counts: Array = _army.category_counts()
	var points: Array = _army.category_points()
	var h: HBoxContainer = UIUtil.hbox(10)
	for i in 3:
		var col: VBoxContainer = UIUtil.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIUtil.bold_label(String(CATEGORY_NAMES[i]).to_upper(), 11, UIUtil.CATEGORY_COLORS[i], HORIZONTAL_ALIGNMENT_LEFT))
		col.add_child(UIUtil.label("%d unit(s)" % int(counts[i])))
		col.add_child(UIUtil.label("%d pts" % int(points[i]), Color(0.3, 0.3, 0.3)))
		h.add_child(col)
	return h


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		opened.emit(index)


## Everything inside the block lets the click through to the block itself.
func _pass_mouse(node: Node) -> void:
	for c in node.get_children():
		var ctl: Control = c as Control
		if ctl != null:
			ctl.mouse_filter = Control.MOUSE_FILTER_PASS
		_pass_mouse(c)
