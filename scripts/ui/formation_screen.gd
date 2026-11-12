class_name FormationScreen
extends VBoxContainer
## The formation screen of one army (Armies > overview > Edit formation), laid out like the FowList force diagram.
## Also the formation preview of the Formations section (open_preview: a scratch army, "Edit formation" button).
## Only one card per choice is shown in full (see _featured): the chosen card, else the last one picked, else the
## first that can be taken; all OR alternatives and exclusive slots are folded to one-line CardStrips, also before
## anything is chosen. Click a strip to take that card, double-click to read it.
##   top bar:  "Formation:" drop-down (the formations of the army's main army; changing it replaces the formation)
##   top:      the HQ and the compulsory slots, always in the formation
##   bottom:   the additional (optional) slots
## Every slot is a column of cards; the cards of one slot are OR choices with a red OR between them. A chosen card has
## a gold outline; cards that cannot be taken now are greyed out: the other cards of a slot whose card is chosen,
## the cards of a slot that is exclusive with a filled slot, and cards exclusive (unit file) with a unit in the army.
## Click a card to choose it; click a chosen card to set its size and upgrades (and, for an additional unit, to
## remove it). Clicking a greyed OR alternative of the same slot swaps the choice.

signal back_requested
## Preview mode (Formations section): "Edit formation" was pressed.
signal edit_requested(formation_id: String)

const CARD := Vector2(165, 232)

var _army: Army
var _preview: bool = false
var _last_pick: Dictionary = {}          # "formation id|slot id" -> card id last picked there (see _featured)
var _last_slot: Dictionary = {}          # "formation id|slot ids of an exclusive group" -> slot last picked from
var _back_btn: Button
var _edit_btn: Button
var _clear_btn: Button
var _title: Label
var _form_opt: OptionButton
var _form_ids: Array = []
var _points: Label
var _status: Label
var _problems: Label
var _top_flow: HFlowContainer
var _bottom_flow: HFlowContainer


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var top: HBoxContainer = UIUtil.hbox(10)
	_back_btn = UIUtil.button("< Back to armies", _on_back)
	top.add_child(_back_btn)
	_title = UIUtil.heading("")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_clear_btn = UIUtil.button("Clear choices", func() -> void:
		var f: FormationData = _army.main_formation() if _army != null else null
		if f != null:
			_army.set_main_formation("")
			_army.set_main_formation(f.id)
			refresh())
	_clear_btn.visible = false
	top.add_child(_clear_btn)
	_edit_btn = UIUtil.button("Edit formation", func() -> void:
		var f: FormationData = _army.main_formation() if _army != null else null
		if f != null:
			edit_requested.emit(f.id))
	_edit_btn.visible = false
	top.add_child(_edit_btn)
	top.add_child(UIUtil.label("Formation:"))
	_form_opt = UIUtil.narrow(OptionButton.new(), 400)
	_form_opt.item_selected.connect(_on_formation_chosen)
	top.add_child(_form_opt)
	_points = UIUtil.bold_label("", 15, UIUtil.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_points.custom_minimum_size = Vector2(200, 0)
	top.add_child(_points)
	add_child(top)
	_status = UIUtil.note("")
	add_child(_status)
	_problems = UIUtil.label("", UIUtil.BAD)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_problems)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body: VBoxContainer = UIUtil.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(UIUtil.bold_label("HEADQUARTERS AND COMPULSORY UNITS", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	body.add_child(UIUtil.note("Always part of the formation. Click a card to set its size and upgrades; where a slot offers "
			+ "several cards (OR), click another card to swap."))
	_top_flow = _flow()
	body.add_child(_top_flow)
	body.add_child(UIUtil.bold_label("ADDITIONAL UNITS", 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	body.add_child(UIUtil.note("Optional units that scale the formation up. Click a card to take it (gold outline), click it "
			+ "again to change its size and upgrades or remove it. Greyed-out cards are exclusive with a chosen one."))
	_bottom_flow = _flow()
	body.add_child(_bottom_flow)
	scroll.add_child(body)
	add_child(scroll)


func _flow() -> HFlowContainer:
	var f: HFlowContainer = HFlowContainer.new()
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_theme_constant_override("h_separation", 12)
	f.add_theme_constant_override("v_separation", 12)
	return f


## Shows the formation of roster player `index`.
func open_player(index: int) -> void:
	open_army(ArmyManager.roster[index], false)


## Preview of a formation (Formations section): a scratch army of the formation's nation, so cards can be clicked to
## try out choices and see the points; nothing is kept. "Edit formation" asks to open the formation editor.
func open_preview(formation_id: String) -> void:
	var f: FormationData = FormationDB.get_formation(formation_id)
	if f == null:
		return
	var a: Army = Army.new()
	a.army_name = "Preview"
	a.nation = f.nation
	a.use_formations = true
	a.set_main_formation(formation_id)
	open_army(a, true)


## Shows `army`'s formation. `preview` = a scratch army of the Formations section (see open_preview).
func open_army(army: Army, preview: bool) -> void:
	_army = army
	_preview = preview
	_back_btn.text = "< Back" if preview else "< Back to armies"
	_edit_btn.visible = preview
	_clear_btn.visible = preview
	_army.use_formations = true
	_status.text = "Preview: click cards to try out choices and see the points. Nothing is saved." if preview else ""
	_form_opt.clear()
	_form_ids.clear()
	for f: FormationData in FormationDB.for_nation(_army.nation):
		_form_opt.add_item(f.full_name())
		_form_ids.append(f.id)
	var current: FormationData = _army.main_formation()
	if current == null and not _form_ids.is_empty():
		_army.set_main_formation(str(_form_ids[0]))
		current = _army.main_formation()
	var at: int = _form_ids.find(current.id) if current != null else -1
	if at >= 0:
		_form_opt.select(at)
	if current != null:                          # empty compulsory slots get their first card (also older armies)
		_army.autofill_formation(_army.main_formation_key())
	refresh()


func refresh() -> void:
	UIUtil.clear_children(_top_flow)
	UIUtil.clear_children(_bottom_flow)
	if _army == null:
		return
	var f: FormationData = _army.main_formation()
	var key: String = _army.main_formation_key()
	_title.text = ("%s  -  formation preview" % RulesDB.nation_label(_army.nation)) if _preview else "%s  -  formation" % _army.army_name
	if f == null:
		_points.text = ""
		_problems.text = "There are no formations for %s yet (data/formations)." % RulesDB.nation_label(_army.nation)
		return
	_points.text = ("Chosen: %d pts" % _army.formation_points(key)) if _preview else \
			"Formation %d pts   Army %d pts" % [_army.formation_points(key), _army.total_points()]
	var problems: PackedStringArray = _army.formation_problems(key)
	_problems.text = "" if problems.is_empty() else "Missing: " + "; ".join(problems)
	_problems.visible = not problems.is_empty()
	_top_flow.add_child(_slot_column(key, "hq", "Headquarters", PackedStringArray([f.hq]), true, "HQ"))
	for s in f.slots:
		var compulsory: bool = bool(s["compulsory"])
		var col: Control = _slot_column(key, str(s["id"]), str(s["group"]), s["units"], compulsory,
				"Compulsory" if compulsory else "Optional")
		(_top_flow if compulsory else _bottom_flow).add_child(col)
	if _bottom_flow.get_child_count() == 0:
		_bottom_flow.add_child(UIUtil.note("This formation has no additional units."))


# ------------------------------------------------------------------ one slot = one column of OR choices

func _slot_column(key: String, slot_id: String, group: String, choices: PackedStringArray, compulsory: bool, tag: String) -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	v.add_child(UIUtil.bold_label(group.to_upper(), 12, UIUtil.INK))
	v.add_child(UIUtil.label(tag, Color(0.35, 0.35, 0.35)))
	var e: ArmyEntry = _army.slot_entry(key, slot_id)
	var featured: String = _featured(key, slot_id, choices, e)
	for i in choices.size():
		if i > 0:
			v.add_child(_or_tag())
		var u: UnitData = UnitDatabase.get_unit(StringName(choices[i]))
		if u == null:
			v.add_child(_missing_card(choices[i]))
			continue
		var chosen: bool = e != null and e.unit_id == u.id
		var why: String = "" if chosen else _grey_reason(key, slot_id, u, e)
		if String(u.id) != featured:
			# every card but the featured one is folded to one line (OR alternatives, exclusive slots ...);
			# a folded card that can be taken still takes it when clicked
			var strip: CardStrip = CardStrip.new().setup(u, CARD.x, why)
			strip.clicked.connect(_on_card_clicked.bind(key, slot_id, compulsory))
			strip.activated.connect(func(cu: UnitData) -> void: CardView.popup(cu, self))
			v.add_child(strip)
			continue
		var tile: CardTile = CardTile.new()
		tile.setup(u, CARD)
		tile.set_selected(chosen)
		if chosen:
			var o: UnitOption = e.get_option()
			tile.set_footer("%s  -  %d pts" % [o.label if o != null else "?", e.get_points()],
					"Chosen. Click to change the size and upgrades%s." % ("" if compulsory else " or to remove it"))
		tile.clicked.connect(_on_card_clicked.bind(key, slot_id, compulsory))
		tile.activated.connect(func(cu: UnitData) -> void: CardView.popup(cu, self))
		v.add_child(tile)
	var frame_color: Color = Color(0.05, 0.05, 0.05) if compulsory else Color(0.55, 0.55, 0.55)
	return UIUtil.paper_frame(v, frame_color, 10, 6, 6, 2)


## The one card of a slot shown in full ("" = none, the whole slot is folded):
##   - the chosen card;
##   - nothing when an exclusive partner slot is filled (the slot cannot be used);
##   - in an "only one of" group with no slot filled, only one slot shows a card: the slot last picked from, else the
##     group's first slot;
##   - in that slot: the card last picked there if it can still be taken, else the first card that can be taken.
func _featured(key: String, slot_id: String, choices: PackedStringArray, e: ArmyEntry) -> String:
	if e != null:
		return String(e.unit_id)
	var f: FormationData = _army.formation_data(key)
	if f != null and slot_id != "hq":
		var group: Array = _exclusive_group(f, slot_id)
		if group.size() > 1:
			for sid in group:
				if _army.slot_entry(key, str(sid)) != null:
					return ""
			var lead: String = str(_last_slot.get("%s|%s" % [f.id, ",".join(group)], ""))
			if not group.has(lead):
				lead = str(group[0])
			if lead != slot_id:
				return ""
	var fid: String = f.id if f != null else ""
	var last: String = str(_last_pick.get("%s|%s" % [fid, slot_id], ""))
	var first_free: String = ""
	for uid in choices:
		var u: UnitData = UnitDatabase.get_unit(StringName(uid))
		if u == null or _grey_reason(key, slot_id, u, null) != "":
			continue
		if uid == last:
			return uid
		if first_free == "":
			first_free = uid
	return first_free


## Every slot that is "only one of" with `slot_id` (and the slot itself), in the formation's slot order.
func _exclusive_group(f: FormationData, slot_id: String) -> Array:
	var members: Dictionary = {slot_id: true}
	var grew: bool = true
	while grew:                              # partners of partners belong to the same choice too
		grew = false
		for sid in members.keys():
			for p in f.exclusive_partners(str(sid)):
				if not members.has(p):
					members[p] = true
					grew = true
	var out: Array = []
	for s in f.slots:
		if members.has(str(s["id"])):
			out.append(str(s["id"]))
	return out


## Remembers the card picked in a slot (and the slot picked in its exclusive group), so that card stays the one shown
## in full when the slot is emptied again.
func _remember_pick(key: String, slot_id: String, u: UnitData) -> void:
	var f: FormationData = _army.formation_data(key)
	if f == null or slot_id == "hq":
		return
	_last_pick["%s|%s" % [f.id, slot_id]] = String(u.id)
	var group: Array = _exclusive_group(f, slot_id)
	if group.size() > 1:
		_last_slot["%s|%s" % [f.id, ",".join(group)]] = slot_id


## Why an unchosen card is greyed out ("" = it can be taken).
func _grey_reason(key: String, slot_id: String, u: UnitData, e: ArmyEntry) -> String:
	if e != null:
		return "another card of this slot is chosen (OR). Click to take this one instead."
	if slot_id != "hq":
		var p: String = _army.slot_problem(key, slot_id, u.id)
		if p != "":
			return p
	return _army.army_clash(u)


## The red OR between two choices of a slot.
func _or_tag() -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", AppTheme.box(AppTheme.RED, Color.WHITE, 2, 6, 6, 1))
	p.custom_minimum_size = Vector2(90, 0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(UIUtil.bold_label("OR", 15, Color.WHITE))
	return p


## A card id named in the formation file that is not in the unit data.
func _missing_card(uid: String) -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", AppTheme.box(Color(0.85, 0.84, 0.80), Color(0.6, 0.6, 0.6), 2, 9, 8, 8))
	p.custom_minimum_size = CARD
	var l: Label = UIUtil.label("%s\n\nno card in the unit data yet" % uid, Color(0.4, 0.4, 0.4))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	p.tooltip_text = "Card %s is named in the formation file but is not in data/*_units.json." % uid
	return p


# ------------------------------------------------------------------ clicks

func _on_card_clicked(u: UnitData, key: String, slot_id: String, compulsory: bool) -> void:
	var e: ArmyEntry = _army.slot_entry(key, slot_id)
	if e != null and e.unit_id == u.id:
		_open_card(key, slot_id, u, e.option_index, e.upgrades, not compulsory)
		return
	if e == null:                                  # an empty slot: anything blocking it?
		var why: String = _grey_reason(key, slot_id, u, null)
		if why != "":
			_status.text = why
			return
	else:                                          # an OR alternative of a filled slot: swap, unless the new card clashes
		var clash: String = _army.army_clash(u, e)
		if clash != "":
			_status.text = clash
			return
	if _army.set_slot(key, slot_id, u.id, 0) == null:
		_status.text = _army.slot_problem(key, slot_id, u.id)
	else:
		_status.text = "%s added to the formation." % u.display_name
		_remember_pick(key, slot_id, u)
	refresh()


## The card window for a chosen card: size and upgrades (one copy); additional units can also be removed here.
func _open_card(key: String, slot_id: String, u: UnitData, option_index: int, upgrades: Dictionary, removable: bool) -> void:
	var dlg: UnitEditDialog = UnitEditDialog.new().setup(u, option_index, upgrades, 1, false)
	dlg.set_max_copies(1)
	dlg.ok_button_text = "Apply"
	if removable:
		dlg.add_button("Remove from formation", true, "remove")
		dlg.custom_action.connect(_on_card_action.bind(dlg, key, slot_id, u))
	add_child(dlg)
	dlg.applied.connect(_on_card_applied.bind(key, slot_id, u))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_card_applied(option_index: int, upgrades: Dictionary, _count: int, key: String, slot_id: String, u: UnitData) -> void:
	_army.set_slot(key, slot_id, u.id, option_index, upgrades)
	_status.text = "%s changed." % u.display_name
	refresh()


func _on_card_action(action: StringName, dlg: UnitEditDialog, key: String, slot_id: String, u: UnitData) -> void:
	if action == &"remove":
		_army.clear_slot(key, slot_id)
		_status.text = "%s removed from the formation." % u.display_name
		dlg.hide()
		dlg.queue_free()
		refresh()


func _on_formation_chosen(idx: int) -> void:
	if _army == null or idx < 0 or idx >= _form_ids.size():
		return
	var fid: String = str(_form_ids[idx])
	var old: FormationData = _army.main_formation()
	if old != null and old.id == fid:
		return
	_army.set_main_formation(fid)
	_status.text = "Formation changed to %s (the units of the old formation were removed)." % _form_opt.get_item_text(idx)
	refresh()


func _on_back() -> void:
	back_requested.emit()
