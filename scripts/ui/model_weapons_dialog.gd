class_name ModelWeaponsDialog
extends AcceptDialog
## "Weapons per model": one row per kind of model on the card, one check box per weapon of the card. Tick the
## weapons that kind of model can fire. Saved in model_weapons.json (see ModelWeapons) and used in every battle.

signal saved

var unit: UnitData
var _checks: Dictionary = {}          # kind -> Array of CheckBox (one per weapon)
var _note: Label


func setup(u: UnitData) -> ModelWeaponsDialog:
	unit = u
	title = "Weapons per model - %s" % u.display_name
	ok_button_text = "Save"
	add_cancel_button("Cancel")
	add_button("Back to the automatic guess", false, "auto")
	custom_action.connect(_on_custom_action)
	var v: VBoxContainer = UIUtil.vbox(8)
	v.add_child(UIUtil.heading(u.display_name))
	_note = UIUtil.note("Tick the weapons each kind of model can fire. In battle a weapon is fired only by the models that have it. "
			+ "Saved in %s." % ModelWeapons.save_path())
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(600, 0)
	v.add_child(_note)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 1 + u.weapons.size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_child(UIUtil.bold_label("MODEL", 12, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	for w in u.weapons:
		var head: Label = UIUtil.bold_label(w.weapon_name, 11, AppTheme.BROWN)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.custom_minimum_size = Vector2(92, 0)
		grid.add_child(head)
	for kind in ModelWeapons.kinds(u):
		var name_lbl: Label = UIUtil.bold_label(kind, 13, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.custom_minimum_size = Vector2(220, 0)
		grid.add_child(name_lbl)
		var row: Array = []
		for i in u.weapons.size():
			var cb: CheckBox = CheckBox.new()
			cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			grid.add_child(cb)
			row.append(cb)
		_checks[kind] = row
	if u.weapons.is_empty():
		v.add_child(UIUtil.note("This card has no weapons."))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(260.0 + 104.0 * u.weapons.size(), 1100.0), minf(90.0 + 40.0 * _checks.size(), 420.0))
	scroll.add_child(grid)
	v.add_child(scroll)
	add_child(UIUtil.paper_frame(v, AppTheme.EDGE, 6, 12, 10, 2))
	confirmed.connect(_on_confirmed)
	_fill()
	about_to_popup.connect(func() -> void: UIUtil.fit_popup.call_deferred(self, scroll, grid, 420.0))
	return self


func _fill() -> void:
	for kind in _checks:
		var have: Array = ModelWeapons.weapons_for(unit, String(kind))
		var row: Array = _checks[kind]
		for i in row.size():
			(row[i] as CheckBox).button_pressed = have.has(i)


## The ticked weapon indexes of one kind of model.
func chosen(kind: String) -> Array:
	var out: Array = []
	var row: Array = _checks.get(kind, [])
	for i in row.size():
		if (row[i] as CheckBox).button_pressed:
			out.append(i)
	return out


func _on_custom_action(action: StringName) -> void:
	if action == &"auto":
		ModelWeapons.clear_override(unit)
		ModelWeapons.save()
		_fill()
		saved.emit()


func _on_confirmed() -> void:
	for kind in _checks:
		ModelWeapons.set_override(unit, String(kind), chosen(String(kind)))
	var err: Error = ModelWeapons.save()
	if err != OK:
		push_warning("Could not save %s (error %d)" % [ModelWeapons.save_path(), err])
	saved.emit()
