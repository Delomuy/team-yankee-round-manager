class_name FormationEditor
extends VBoxContainer
## The Formations section: create, change and delete the formations every army can use (FormationDB).
##   top bar:  nation, formation drop-down ("Division - Name"), New, Duplicate, Delete
##   left:     the card selector (the same card grid as the Cards tab, every card of every nation; HQ cards are
##             shown even when Settings > Hide HQ units is on)
##   right:    the formation: name, division, the HQ box, the slots (one column each), the exclusive groups
## Drag a card from the selector onto the HQ box or onto a slot to add it; a slot with several cards is an OR choice.
## A single click on a card in the selector selects it; "+ Selected card" on a slot adds that card without dragging.
## Every change is saved at once to the nation's formation file (FormationDB.save_nation).

signal formations_changed
## "< Back" was pressed (the owner shows the page it came from).
signal back_requested

const SLOT_CARD := Vector2(150, 211)
const GROUPS := ["Headquarters", "Infantry", "Armour", "Tanks", "Artillery", "Anti-aircraft", "Anti-tank", "Recon",
		"Support", "Red Banner", "Aircraft"]

var _nations: Array = []                 # nation names, same order as _nation_opt
var _nation_opt: OptionButton
var _form_opt: OptionButton
var _form_ids: Array = []
var _status: Label
var _browser: CardBrowser
var _body: VBoxContainer                 # the right pane's content, rebuilt by refresh()
var _f: FormationData = null             # the formation being edited (the copy stored in FormationDB)
var _save_timer: Timer
var _name_edit: LineEdit
var _div_edit: LineEdit
var _problems: Label
var _back_btn: Button


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var top: HBoxContainer = UIUtil.hbox(8)
	_back_btn = UIUtil.button("< Back", func() -> void:
		_flush()
		back_requested.emit())
	top.add_child(_back_btn)
	top.add_child(UIUtil.heading("Edit formations"))
	top.add_child(UIUtil.label("Nation:"))
	_nation_opt = OptionButton.new()
	_nation_opt.custom_minimum_size = Vector2(170, 0)
	_nation_opt.item_selected.connect(_on_nation_chosen)
	top.add_child(_nation_opt)
	top.add_child(UIUtil.label("Formation:"))
	_form_opt = UIUtil.narrow(OptionButton.new(), 400)
	_form_opt.item_selected.connect(_on_formation_chosen)
	top.add_child(_form_opt)
	top.add_child(UIUtil.button("New", _on_new))
	top.add_child(UIUtil.button("Duplicate", _on_duplicate))
	top.add_child(UIUtil.button("Delete", _on_delete))
	add_child(top)
	_status = UIUtil.note("")
	add_child(_status)

	_browser = CardBrowser.new()
	_browser.drag_cards = true
	_browser.obey_hide_hq = false                      # HQ cards are always shown here: every formation needs one
	_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_browser.add_child(_build_pane())
	add_child(_browser)

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)


func _ready() -> void:
	_fill_nations("Soviet")
	if not _nations.is_empty():
		_fill_formations("")
		_browser.set_nation.call_deferred(nation())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			reload())


## The nation drop-down, with `select` picked (new nations may have been added since).
func _fill_nations(select: String) -> void:
	_nations = Array(UnitDatabase.get_nations())
	_nation_opt.clear()
	for n: String in _nations:
		_nation_opt.add_item(RulesDB.nation_label(n))
	var at: int = maxi(0, _nations.find(select))
	if not _nations.is_empty():
		_nation_opt.select(at)


## Reads the lists again (the other formation editor, or the Formations pages, may have changed formations).
func reload() -> void:
	var keep_nation: String = nation()
	var keep_id: String = _f.id if _f != null else ""
	_fill_nations(keep_nation)
	_fill_formations(keep_id)


## Shows the editor on `nation`, with formation `formation_id` open ("" = the first one of the nation).
func open_for(p_nation: String, formation_id: String = "") -> void:
	_flush()
	_fill_nations(p_nation)
	_fill_formations(formation_id)
	_browser.set_nation(nation())


## Shows the editor on `nation` and makes a new formation there.
func start_new(p_nation: String) -> void:
	open_for(p_nation)
	_on_new()


## The text of the back button ("< Back", "< Cards" ...).
func set_back_text(text: String) -> void:
	_back_btn.text = text


func _build_pane() -> Control:
	var pane: PanelContainer = PanelContainer.new()
	pane.add_theme_stylebox_override("panel", AppTheme.box(Color(0.30, 0.235, 0.153), AppTheme.CLEAR, 0, 8, 6, 6))
	pane.custom_minimum_size = Vector2(560, 0)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_stretch_ratio = 2.0
	var paper: PanelContainer = PanelContainer.new()
	var holder: MarginContainer = UIUtil.round_holder(paper, 8, 8, 8, Color(0.95, 0.94, 0.91))
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = UIUtil.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	holder.add_child(scroll)
	pane.add_child(paper)
	return pane


## The nation picked in the top bar ("" when there is none).
func nation() -> String:
	var i: int = _nation_opt.selected
	return str(_nations[i]) if i >= 0 and i < _nations.size() else ""


## The formation being edited (null = none).
func current() -> FormationData:
	return _f


## Fills the formation drop-down of the nation and opens `select_id` (or the first formation).
func _fill_formations(select_id: String) -> void:
	_form_opt.clear()
	_form_ids.clear()
	var list: Array = FormationDB.for_nation(nation())
	list.sort_custom(func(a: FormationData, b: FormationData) -> bool: return a.full_name().naturalnocasecmp_to(b.full_name()) < 0)
	for f: FormationData in list:
		_form_opt.add_item(f.full_name())
		_form_ids.append(f.id)
	var at: int = _form_ids.find(select_id)
	if at < 0 and not _form_ids.is_empty():
		at = 0
	if at >= 0:
		_form_opt.select(at)
		open_formation(str(_form_ids[at]))
	else:
		_f = null
		refresh()


## Opens a formation for editing.
func open_formation(id: String) -> void:
	_flush()
	_f = FormationDB.get_formation(id)
	var at: int = _form_ids.find(id)
	if at >= 0 and _form_opt.selected != at:
		_form_opt.select(at)
	refresh()


# ------------------------------------------------------------------ the right pane

func refresh() -> void:
	UIUtil.clear_children(_body)
	_name_edit = null
	_div_edit = null
	if _f == null:
		_body.add_child(UIUtil.bold_label("No formations for %s yet." % RulesDB.nation_label(nation()), 18, UIUtil.INK))
		_body.add_child(UIUtil.note("Press New in the top bar to make one."))
		return

	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_child(UIUtil.label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.text = _f.name
	_name_edit.placeholder_text = "BTR-60 Motor Rifle Battalion"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	grid.add_child(_name_edit)
	grid.add_child(UIUtil.label("Division:"))
	var div_row: HBoxContainer = UIUtil.hbox(4)
	_div_edit = LineEdit.new()
	_div_edit.text = _f.division
	_div_edit.placeholder_text = "228th Guards"
	_div_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_div_edit.text_changed.connect(_on_division_changed)
	div_row.add_child(_div_edit)
	var pick: MenuButton = MenuButton.new()
	pick.text = "Pick..."
	pick.tooltip_text = "Divisions already used by this nation's formations"
	pick.flat = false
	for d: String in FormationDB.divisions(nation()):
		pick.get_popup().add_item(d)
	pick.disabled = pick.get_popup().item_count == 0
	pick.get_popup().index_pressed.connect(_on_division_picked.bind(pick))
	div_row.add_child(pick)
	grid.add_child(div_row)
	_body.add_child(grid)
	_body.add_child(UIUtil.note("Id: %s   (used inside saved armies; it does not change when the name changes)" % _f.id))
	_problems = UIUtil.label("", UIUtil.BAD)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_problems)
	_update_problems()

	# ---- HQ
	_body.add_child(UIUtil.bold_label("HEADQUARTERS", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	_body.add_child(_hq_box())

	# ---- slots
	var head: HBoxContainer = UIUtil.hbox(8)
	var sl: Label = UIUtil.bold_label("SLOTS", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sl)
	head.add_child(UIUtil.button("+ Add slot", _on_add_slot))
	_body.add_child(head)
	_body.add_child(UIUtil.note("One slot holds ONE unit. Several cards in a slot are the OR choices. A unit that may be taken "
			+ "three times needs three slots. Black frame = compulsory, grey = optional (additional units)."))
	var flow: HFlowContainer = HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	for i in _f.slots.size():
		flow.add_child(_slot_box(i))
	if _f.slots.is_empty():
		flow.add_child(UIUtil.note("No slots yet. Press + Add slot."))
	_body.add_child(flow)

	# ---- exclusive groups
	var ehead: HBoxContainer = UIUtil.hbox(8)
	var el: Label = UIUtil.bold_label("ONLY ONE OF (exclusive slots)", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT)
	el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ehead.add_child(el)
	var add_ex: Button = UIUtil.button("+ Add group", _on_add_exclusive)
	add_ex.disabled = _f.slots.size() < 2
	ehead.add_child(add_ex)
	_body.add_child(ehead)
	_body.add_child(UIUtil.note("Tick the slots of which only one may be filled (e.g. Recon OR Anti-tank). A group needs at least two slots."))
	for gi in _f.exclusive.size():
		_body.add_child(_exclusive_row(gi))


func _update_problems() -> void:
	if _problems == null or _f == null:
		return
	var p: PackedStringArray = _f.problems()
	_problems.text = "" if p.is_empty() else "To check: " + "; ".join(p)
	_problems.visible = not p.is_empty()


## The HQ box: one card, dropped from the selector.
func _hq_box() -> Control:
	var zone: DropZone = DropZone.new()
	zone.accepts = "catalog"
	zone.dropped.connect(_on_hq_dropped)
	zone.add_theme_stylebox_override("panel", AppTheme.box(Color(1, 1, 1, 0.35), Color(0.05, 0.05, 0.05), 2, 10, 8, 6))
	zone.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var v: VBoxContainer = UIUtil.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	if _f.hq == "":
		var l: Label = UIUtil.label("Drop the HQ card here", Color(0.35, 0.35, 0.35))
		l.custom_minimum_size = Vector2(SLOT_CARD.x, 60)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	else:
		v.add_child(_card(_f.hq))
		v.add_child(UIUtil.button("Remove", _on_hq_cleared))
	var b: Button = UIUtil.button("+ Selected card", _on_hq_selected)
	b.tooltip_text = "Make the card selected on the left the HQ"
	v.add_child(b)
	zone.add_child(v)
	return zone


## One slot: group name, compulsory tick, move / delete buttons, its cards (OR) and the drop area.
func _slot_box(i: int) -> Control:
	var s: Dictionary = _f.slots[i]
	var compulsory: bool = bool(s["compulsory"])
	var zone: DropZone = DropZone.new()
	zone.accepts = "catalog"
	zone.dropped.connect(_on_slot_dropped.bind(i))
	var border: Color = Color(0.05, 0.05, 0.05) if compulsory else Color(0.55, 0.55, 0.55)
	zone.add_theme_stylebox_override("panel", AppTheme.box(Color(1, 1, 1, 0.35), border, 2, 10, 8, 6))
	var v: VBoxContainer = UIUtil.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.custom_minimum_size = Vector2(SLOT_CARD.x, 0)

	var bar: HBoxContainer = UIUtil.hbox(2)
	bar.add_child(UIUtil.bold_label("%d." % (i + 1), 14, UIUtil.INK))
	var left: Button = UIUtil.button("<", _on_move_slot.bind(i, -1))
	left.tooltip_text = "Move this slot left"
	left.disabled = i == 0
	bar.add_child(left)
	var right: Button = UIUtil.button(">", _on_move_slot.bind(i, 1))
	right.tooltip_text = "Move this slot right"
	right.disabled = i == _f.slots.size() - 1
	bar.add_child(right)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	var del: Button = UIUtil.button("X", _on_delete_slot.bind(i))
	del.tooltip_text = "Delete this slot"
	bar.add_child(del)
	v.add_child(bar)

	var group_row: HBoxContainer = UIUtil.hbox(2)
	var group: LineEdit = LineEdit.new()
	group.text = str(s["group"])
	group.placeholder_text = "Group (Infantry ...)"
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.text_changed.connect(_on_group_changed.bind(i))
	group_row.add_child(group)
	var gpick: MenuButton = MenuButton.new()
	gpick.text = "v"
	gpick.flat = false
	gpick.tooltip_text = "Common group names"
	for g: String in GROUPS:
		gpick.get_popup().add_item(g)
	gpick.get_popup().index_pressed.connect(_on_group_picked.bind(i))
	group_row.add_child(gpick)
	v.add_child(group_row)
	var comp: CheckBox = UIUtil.check("Compulsory", compulsory)
	comp.toggled.connect(_on_compulsory_toggled.bind(i))
	v.add_child(comp)

	var units: PackedStringArray = s["units"]
	for k in units.size():
		if k > 0:
			v.add_child(_or_tag())
		v.add_child(_card(units[k]))
		var rm: Button = UIUtil.button("Remove", _on_remove_card.bind(i, k))
		rm.tooltip_text = "Take %s out of this slot" % units[k]
		v.add_child(rm)
	var hint: Label = UIUtil.label("Drop a card here" if units.is_empty() else "Drop another card here for OR", Color(0.35, 0.35, 0.35))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(SLOT_CARD.x, 40)
	v.add_child(hint)
	var add: Button = UIUtil.button("+ Selected card", _on_slot_selected.bind(i))
	add.tooltip_text = "Add the card selected on the left to this slot"
	v.add_child(add)
	zone.add_child(v)
	return zone


## A card of the formation (small), or a grey box when the id is not in the unit data.
func _card(uid: String) -> Control:
	var u: UnitData = UnitDatabase.get_unit(StringName(uid))
	if u == null:
		var p: PanelContainer = PanelContainer.new()
		p.add_theme_stylebox_override("panel", AppTheme.box(Color(0.85, 0.84, 0.80), Color(0.6, 0.6, 0.6), 2, 9, 8, 8))
		p.custom_minimum_size = SLOT_CARD
		var l: Label = UIUtil.label("%s\n\nno card in the unit data" % uid, Color(0.4, 0.4, 0.4))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.add_child(l)
		return p
	var tile: CardTile = CardTile.new()
	tile.setup(u, SLOT_CARD)
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.activated.connect(_browser.open_card)
	return tile


func _or_tag() -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.RED, Color.WHITE, 2, 6, 6, 1))
	p.custom_minimum_size = Vector2(70, 0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(UIUtil.bold_label("OR", 13, Color.WHITE))
	return p


## One exclusive group: a tick box per slot and a delete button.
func _exclusive_row(gi: int) -> Control:
	var g: PackedStringArray = _f.exclusive[gi]
	var row: HFlowContainer = HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(UIUtil.bold_label("Group %d:" % (gi + 1), 14, UIUtil.INK))
	for i in _f.slots.size():
		var sid: String = str(_f.slots[i]["id"])
		var c: CheckBox = UIUtil.check(_slot_label(i), g.has(sid))
		c.toggled.connect(_on_exclusive_toggled.bind(gi, sid))
		row.add_child(c)
	row.add_child(UIUtil.button("Delete group", _on_delete_exclusive.bind(gi)))
	if g.size() < 2:
		row.add_child(UIUtil.label("tick at least two", UIUtil.WARN))
	return UIUtil.paper_frame(row, AppTheme.EDGE, 6, 8, 4, 1)


## "3. Red Banner (TS111 / TS110)" - how a slot is named in the exclusive groups.
func _slot_label(i: int) -> String:
	var s: Dictionary = _f.slots[i]
	var group: String = str(s["group"]) if str(s["group"]) != "" else "slot"
	var units: PackedStringArray = s["units"]
	var names: PackedStringArray = []
	for uid in units:
		var u: UnitData = UnitDatabase.get_unit(StringName(uid))
		names.append(u.display_name if u != null else uid)
	var cards: String = "" if names.is_empty() else " (%s)" % " / ".join(names)
	if cards.length() > 50:
		cards = cards.substr(0, 47) + "...)"
	return "%d. %s%s" % [i + 1, group, cards]


# ------------------------------------------------------------------ saving

## Saves at once (structure changes) and tells the other screens.
func _save() -> void:
	_save_timer.stop()
	if _f == null:
		return
	FormationDB.put(_f)
	var err: String = FormationDB.save_nation(_f.nation)
	_status.text = err if err != "" else "Saved to %s" % FormationDB.save_path(_f.nation)
	UIUtil.set_color(_status, UIUtil.BAD if err != "" else Color(0.35, 0.35, 0.35))
	formations_changed.emit()


## Saves a pending typed change before switching formation or nation.
func _flush() -> void:
	if not _save_timer.is_stopped():
		_save()


## A structure change: save, redraw.
func _changed() -> void:
	_save()
	refresh()


## Text typed in a field: save a moment later, keep the focus where it is.
func _typed() -> void:
	_save_timer.start()
	_update_problems()


func _relabel_current() -> void:
	var at: int = _form_ids.find(_f.id)
	if at >= 0:
		_form_opt.set_item_text(at, _f.full_name())


# ------------------------------------------------------------------ top bar

func _on_nation_chosen(_idx: int) -> void:
	_flush()
	_fill_formations("")
	_browser.set_nation(nation())


func _on_formation_chosen(idx: int) -> void:
	if idx >= 0 and idx < _form_ids.size():
		open_formation(str(_form_ids[idx]))


## A new, empty formation of the nation in the top bar (the division of the formation being edited is kept).
func _on_new() -> void:
	_flush()
	if nation() == "":
		return
	var f: FormationData = FormationData.new()
	f.nation = nation()
	f.name = "New formation"
	f.division = _f.division if _f != null else ""
	f.id = FormationDB.new_id(f.nation, "formation")
	f.slots.append({"id": "slot_1", "group": "", "compulsory": true, "units": PackedStringArray()})
	FormationDB.put(f)
	_f = f
	_save()
	_fill_formations(f.id)
	_status.text = "New formation made. Type its name and division, then drop the HQ and the slot cards."
	if _name_edit != null:
		_name_edit.grab_focus.call_deferred()
		_name_edit.select_all.call_deferred()


func _on_duplicate() -> void:
	_flush()
	if _f == null:
		return
	var f: FormationData = _f.duplicate_formation()
	f.name = _f.name + " (copy)"
	f.id = FormationDB.new_id(f.nation, f.name)
	FormationDB.put(f)
	_f = f
	_save()
	_fill_formations(f.id)
	_status.text = "Copy made: %s" % f.full_name()


func _on_delete() -> void:
	if _f == null:
		return
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "Delete formation"
	dlg.dialog_text = "Delete the formation \"%s\"?\nArmies that use it lose their formation." % _f.full_name()
	dlg.ok_button_text = "Delete"
	dlg.confirmed.connect(_delete_current)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _delete_current() -> void:
	if _f == null:
		return
	_save_timer.stop()
	var gone: String = _f.full_name()
	var nat: String = _f.nation
	FormationDB.remove(_f.id)
	_f = null
	var err: String = FormationDB.save_nation(nat)
	formations_changed.emit()
	_fill_formations("")
	_status.text = err if err != "" else "Deleted: %s" % gone


# ------------------------------------------------------------------ fields

func _on_name_changed(text: String) -> void:
	_f.name = text.strip_edges()
	_relabel_current()
	_typed()


func _on_division_changed(text: String) -> void:
	_f.division = text.strip_edges()
	_relabel_current()
	_typed()


func _on_division_picked(idx: int, pick: MenuButton) -> void:
	_f.division = pick.get_popup().get_item_text(idx)
	_relabel_current()
	_changed()


func _on_group_changed(text: String, i: int) -> void:
	_f.slots[i]["group"] = text.strip_edges()
	_typed()


func _on_group_picked(idx: int, i: int) -> void:
	_f.slots[i]["group"] = str(GROUPS[idx])
	_changed()


func _on_compulsory_toggled(on: bool, i: int) -> void:
	_f.slots[i]["compulsory"] = on
	_changed()


# ------------------------------------------------------------------ HQ and slots

func _on_hq_dropped(payload: Dictionary) -> void:
	set_hq(str(payload.get("unit_id", "")))


func _on_hq_selected() -> void:
	if _browser.selected == null:
		_status.text = "Click a card on the left first."
		return
	set_hq(String(_browser.selected.id))


func _on_hq_cleared() -> void:
	_f.hq = ""
	_changed()


## Makes `uid` the HQ card.
func set_hq(uid: String) -> void:
	if _f == null or uid == "":
		return
	_f.hq = uid
	_changed()
	_status.text = "HQ set to %s." % _card_name(uid)


func _on_add_slot() -> void:
	var group: String = str(_f.slots[-1]["group"]) if not _f.slots.is_empty() else ""
	_f.slots.append({"id": _f.new_slot_id(), "group": group, "compulsory": false, "units": PackedStringArray()})
	_changed()


func _on_delete_slot(i: int) -> void:
	_f.remove_slot(str(_f.slots[i]["id"]))
	_changed()


func _on_move_slot(i: int, delta: int) -> void:
	var j: int = i + delta
	if j < 0 or j >= _f.slots.size():
		return
	var s: Dictionary = _f.slots[i]
	_f.slots[i] = _f.slots[j]
	_f.slots[j] = s
	_changed()


func _on_slot_dropped(payload: Dictionary, i: int) -> void:
	add_to_slot(i, str(payload.get("unit_id", "")))


func _on_slot_selected(i: int) -> void:
	if _browser.selected == null:
		_status.text = "Click a card on the left first."
		return
	add_to_slot(i, String(_browser.selected.id))


## Adds card `uid` to slot `i` as one more OR choice.
func add_to_slot(i: int, uid: String) -> void:
	if _f == null or uid == "" or i < 0 or i >= _f.slots.size():
		return
	var units: PackedStringArray = _f.slots[i]["units"]
	if units.has(uid):
		_status.text = "%s is already in this slot." % _card_name(uid)
		return
	units.append(uid)
	_f.slots[i]["units"] = units
	_changed()
	_status.text = "%s added to slot %d." % [_card_name(uid), i + 1]


func _on_remove_card(i: int, k: int) -> void:
	var units: PackedStringArray = _f.slots[i]["units"]
	units.remove_at(k)
	_f.slots[i]["units"] = units
	_changed()


func _card_name(uid: String) -> String:
	var u: UnitData = UnitDatabase.get_unit(StringName(uid))
	return u.display_name if u != null else uid


# ------------------------------------------------------------------ exclusive groups

func _on_add_exclusive() -> void:
	_f.exclusive.append(PackedStringArray())
	refresh()          # not saved until it has two slots (a group of fewer is dropped when the file is read)


func _on_delete_exclusive(gi: int) -> void:
	_f.exclusive.remove_at(gi)
	_changed()


func _on_exclusive_toggled(on: bool, gi: int, sid: String) -> void:
	var g: PackedStringArray = _f.exclusive[gi]
	if on and not g.has(sid):
		g.append(sid)
	elif not on and g.has(sid):
		g.remove_at(g.find(sid))
	_f.exclusive[gi] = g
	_changed()
