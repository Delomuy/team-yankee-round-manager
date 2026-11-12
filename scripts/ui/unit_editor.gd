class_name UnitEditor
extends ConfirmationDialog
## The card editor (Cards > New card, and Edit card / Copy card in a card's window). It edits a dictionary in the unit
## file format (UnitDatabase.unit_to_dict) and saves it with UnitDatabase.save_custom into data/custom/.
##   Card:        id (new and copied cards only; a copy gets a free id such as TS123c), name, nation, kind of unit
##                (Armored / Ground / Air, which decides the fields below), card type, aircraft type, "transport card"
##   Ratings:     Is hit on, Skill, Courage, Morale, Rally / Remount, Assault, Counterattack, Save, Armour
##   Movement:    Tactical, Terrain, Cross-country, Road, Cross (-1 = Auto)
##   Rules:       special rules, army-list limits (copies, exclusive with, formation only)
##   Upgrades: text, points and how they are paid (once / each one picked / for every model, with what to count).
##   Weapons, Sizes and points (each size lists its models; a row linked to a transport card brings that transport
##   into the battle as its own unit), Upgrades, and the transport links.
## Changing a card from the main files keeps the original: "Restore original" in the card window brings it back.

signal saved(id: String)

enum Mode { NEW, EDIT, COPY }

const KINDS := ["Armored", "Ground", "Air"]
const KIND_KEYS := ["armored", "ground", "air"]
const TYPES := {
	"armored": ["Tank Unit", "Unarmoured Tank Unit", "Tank Formation", "Tank Attachment", "Independent Tank Unit"],
	"ground": ["Infantry Unit", "Infantry Formation", "Infantry Attachment", "Gun Unit"],
	"air": ["Helicopter Aircraft Unit", "Strike Aircraft Unit"],
}

var edit_mode: int = Mode.EDIT
var _d: Dictionary = {}                 # the card being edited (unit file format)
var _original_id: String = ""
var _body: VBoxContainer
var _status: Label
var _nations: Array = []
var _transports: Array = []             # UnitData of every card that can carry passengers
var _link_units: PackedStringArray = [] # cards to give this transport when saving (transport cards only)


## Opens `u` for editing (Mode.EDIT), as a copy (Mode.COPY) or, with u = null, a new card of `nation`.
func setup(u: UnitData, p_mode: int, nation: String = "") -> UnitEditor:
	edit_mode = p_mode
	if u != null:
		_d = UnitDatabase.unit_to_dict(u).duplicate(true)
		_original_id = String(u.id)
	else:
		_d = _blank(nation)
	if edit_mode == Mode.COPY:
		_d["id"] = UnitDatabase.free_id(_original_id)
		_d["name"] = str(_d["name"]) + " (copy)"
	title = {Mode.NEW: "New card", Mode.EDIT: "Edit card %s" % _original_id, Mode.COPY: "Copy of card %s" % _original_id}[edit_mode]
	ok_button_text = "Save card"
	_nations = Array(UnitDatabase.get_nations())
	_transports = UnitDatabase.transport_cards()

	var room: Vector2 = Vector2(1600, 900)
	var paper: PanelContainer = PanelContainer.new()       # parchment behind everything: dark text stays readable
	paper.add_theme_stylebox_override("panel", Paper.style(Color(0.97, 0.96, 0.93), 12, 8))
	var v: VBoxContainer = UIUtil.vbox(6)
	_status = UIUtil.label("", UIUtil.BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(room.x - 180.0, room.y - 190.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = UIUtil.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	v.add_child(scroll)
	paper.add_child(v)
	add_child(paper)
	get_ok_button().pressed.connect(_on_save_pressed)
	dialog_hide_on_ok = false
	rebuild()
	return self


func _blank(nation: String) -> Dictionary:
	return {
		"id": "", "name": "New unit", "nation": nation, "category": "armored", "unit_type": "Tank Unit",
		"special_rules": [], "tactical": 25, "terrain_dash": 35, "cross_dash": 50, "road_dash": 60, "cross_skill": 3,
		"courage": 4, "morale": 3, "rally": 0, "remount": 3, "skill": 4, "assault": 4, "counterattack": 4,
		"is_hit_on": 4, "save": 0, "armour_front": 0, "armour_side": 0, "armour_top": 0,
		"options": [{"label": "", "models": 1, "transport_models": 0, "points": 1, "points_dynamic": 1,
				"composition": [{"count": 1, "name": ""}]}],
		"weapons": [], "max_copies": 1, "exclusive_with": [], "formation_only": false,
	}


## The card as it would be saved now (for the smoke test and the save button).
func card() -> Dictionary:
	return _d


# ------------------------------------------------------------------ drawing

func rebuild() -> void:
	UIUtil.clear_children(_body)
	var cat: String = str(_d["category"])
	_body.add_child(_section("CARD"))
	_body.add_child(_card_grid())
	_body.add_child(_section("RATINGS"))
	_body.add_child(_ratings(cat))
	_body.add_child(_section("MOVEMENT"))
	_body.add_child(_movement())
	_body.add_child(_section("SPECIAL RULES AND ARMY LIST"))
	_body.add_child(_rules_box())
	_body.add_child(_section("WEAPONS", "+ Add weapon", _on_add_weapon))
	_body.add_child(_weapons_box())
	if bool(_d.get("is_attachment", false)):
		_body.add_child(_section("UNITS THAT RIDE IN THIS TRANSPORT"))
		_body.add_child(_carried_box())
	else:
		_body.add_child(_section("SIZES AND POINTS", "+ Add size", _on_add_option))
		_body.add_child(UIUtil.note("Each size lists its models. A row linked to a transport card is the unit's transport: "
				+ "in a battle those vehicles become a unit of their own that the infantry can mount."))
		for i in (_d["options"] as Array).size():
			_body.add_child(_option_box(i))
		_body.add_child(_section("TRANSPORT"))
		_body.add_child(_transport_box())
		_body.add_child(_section("UPGRADES", "+ Add upgrade", _on_add_upgrade))
		_body.add_child(_upgrades_box())
	_check()


func _section(text: String, button: String = "", handler: Callable = Callable()) -> Control:
	var h: HBoxContainer = UIUtil.hbox(8)
	var l: Label = UIUtil.bold_label(text, 18, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if button != "":
		h.add_child(UIUtil.button(button, handler))
	return h


func _card_grid() -> Control:
	var g: GridContainer = GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	# id
	g.add_child(UIUtil.label("Card id:"))
	var id_edit: LineEdit = _line("id", 160)
	if edit_mode == Mode.EDIT:
		id_edit.editable = false
		id_edit.tooltip_text = "The id of an existing card cannot change (armies and formations use it). Use Copy card for a card with another id."
	else:
		id_edit.tooltip_text = "A unique code, e.g. TS123c. Armies and formations refer to the card by it."
	g.add_child(id_edit)
	g.add_child(UIUtil.label("Name:"))
	g.add_child(_line("name", 360))
	# nation
	g.add_child(UIUtil.label("Nation:"))
	var nat: OptionButton = OptionButton.new()
	for n: String in _nations:
		nat.add_item(RulesDB.nation_label(n))
	var at: int = _nations.find(str(_d["nation"]))
	if at < 0:
		nat.add_item(str(_d["nation"]))
		_nations.append(str(_d["nation"]))
		at = _nations.size() - 1
	nat.select(at)
	nat.item_selected.connect(func(i: int) -> void: _d["nation"] = str(_nations[i]); _check())
	var nrow: HBoxContainer = UIUtil.hbox(4)
	nat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(nat)
	var add_nat: Button = UIUtil.button("New...", func() -> void: NationDialog.open(self, _on_nation_created))
	add_nat.tooltip_text = "Add a nation (name, file prefix, card colour)"
	nrow.add_child(add_nat)
	g.add_child(nrow)
	# kind of unit
	g.add_child(UIUtil.label("Kind of unit:"))
	var kind: OptionButton = UIUtil.option(KINDS)
	kind.select(KIND_KEYS.find(str(_d["category"])))
	kind.item_selected.connect(_on_kind_chosen)
	kind.tooltip_text = "Armored: has armour (tanks, APCs, SP guns). Ground: infantry and guns (save, rally). Air: helicopters and planes."
	g.add_child(kind)
	# card type
	g.add_child(UIUtil.label("Card type:"))
	var trow: HBoxContainer = UIUtil.hbox(2)
	var tl: LineEdit = _line("unit_type", 220)
	trow.add_child(tl)
	var pick: MenuButton = MenuButton.new()
	pick.text = "v"
	pick.flat = false
	pick.tooltip_text = "Card types used on the cards"
	for t: String in TYPES[str(_d["category"])]:
		pick.get_popup().add_item(t)
	pick.get_popup().index_pressed.connect(func(i: int) -> void:
		_d["unit_type"] = pick.get_popup().get_item_text(i)
		tl.text = str(_d["unit_type"]))
	trow.add_child(pick)
	g.add_child(trow)
	if str(_d["category"]) == "air":
		g.add_child(UIUtil.label("Aircraft:"))
		var air: OptionButton = UIUtil.option(["helicopter", "jet"])
		air.select(1 if str(_d.get("aircraft_type", "helicopter")) == "jet" else 0)
		air.item_selected.connect(func(i: int) -> void: _d["aircraft_type"] = ["helicopter", "jet"][i])
		g.add_child(air)
	else:
		g.add_child(Control.new())
		g.add_child(Control.new())
	# transport card: its own line, so the long tick box text does not widen the first column of the grid
	var box: VBoxContainer = UIUtil.vbox(6)
	box.add_child(g)
	var row: HBoxContainer = UIUtil.hbox(10)
	var att: CheckBox = UIUtil.check("Transport / attachment card (not bought on its own)", bool(_d.get("is_attachment", false)))
	att.tooltip_text = "Transports (BTR-60 Transport, M113 ...) come with the unit that rides in them and have no sizes of their own."
	att.toggled.connect(_on_attachment_toggled)
	row.add_child(att)
	row.add_child(UIUtil.label("Passengers:"))
	var pas: SpinBox = _spin("passengers", 0, 20)
	pas.tooltip_text = "How many infantry teams fit inside (the 'Passengers N' rule). 0 = carries nobody."
	row.add_child(pas)
	box.add_child(row)
	return box


func _ratings(cat: String) -> Control:
	var fields: Array = [["is_hit_on", "Is hit on", 1, 7], ["skill", "Skill", 0, 7], ["courage", "Courage", 0, 7],
			["morale", "Morale", 0, 7]]
	if cat == "ground":
		fields.append(["rally", "Rally", 0, 7])
	else:
		fields.append(["remount", "Remount", 0, 7])
	fields.append_array([["assault", "Assault", 0, 7], ["counterattack", "Counterattack", 0, 7], ["save", "Save", 0, 7]])
	if cat == "armored":
		fields.append_array([["armour_front", "Armour front", 0, 30], ["armour_side", "Armour side", 0, 30],
				["armour_top", "Armour top", 0, 30]])
	var box: VBoxContainer = UIUtil.vbox(4)
	box.add_child(_spin_flow(fields))
	box.add_child(UIUtil.note("Ratings are the 'n+' numbers of the card (Skill 4+ = 4). 0 = the card does not have it. "
			+ "Save: infantry, aircraft and unarmoured vehicles."))
	return box


func _movement() -> Control:
	var box: VBoxContainer = UIUtil.vbox(4)
	box.add_child(_spin_flow([["tactical", "Tactical cm", -1, 300], ["terrain_dash", "Terrain dash cm", -1, 300],
			["cross_dash", "Cross-country dash cm", -1, 300], ["road_dash", "Road dash cm", -1, 300],
			["cross_skill", "Cross", -1, 7]]))
	box.add_child(UIUtil.note("-1 = Auto / unlimited (aircraft, or a Cross the unit passes automatically)."))
	return box


func _rules_box() -> Control:
	var g: GridContainer = GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_child(UIUtil.label("Special rules:"))
	var rules: LineEdit = LineEdit.new()
	rules.text = ", ".join(PackedStringArray(_d.get("special_rules", [])))
	rules.placeholder_text = "Thermal Imaging, Chobham Armour  (comma separated)"
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.text_changed.connect(func(t: String) -> void: _d["special_rules"] = _split(t))
	g.add_child(rules)
	g.add_child(UIUtil.label("Army list:"))
	var row: HBoxContainer = UIUtil.hbox(8)
	row.add_child(UIUtil.label("Copies allowed"))
	row.add_child(_spin("max_copies", 0, 9))
	row.add_child(UIUtil.label("Exclusive with ids"))
	var ex: LineEdit = LineEdit.new()
	ex.text = ", ".join(PackedStringArray(_d.get("exclusive_with", [])))
	ex.placeholder_text = "TS102, TS138"
	ex.custom_minimum_size = Vector2(220, 0)
	ex.text_changed.connect(func(t: String) -> void: _d["exclusive_with"] = _split(t))
	row.add_child(ex)
	var fo: CheckBox = UIUtil.check("Formation only", bool(_d.get("formation_only", false)))
	fo.toggled.connect(func(on: bool) -> void: _d["formation_only"] = on)
	row.add_child(fo)
	g.add_child(row)
	return g


# ---- weapons

const W_COLS := [["name", "Weapon", 0], ["range_cm_min", "Min cm", 1], ["range_cm", "Range cm", 1],
		["rof_static", "ROF halted", 1], ["rof_moving", "ROF moving", 1], ["salvo", "Salvo", 2],
		["artillery", "Artillery", 2], ["anti_tank", "AT", 1], ["firepower", "FP", 1], ["rules", "Rules (comma separated)", 3]]


func _weapons_box() -> Control:
	var weapons: Array = _d["weapons"]
	if weapons.is_empty():
		return UIUtil.note("No weapons. Press + Add weapon.")
	var g: GridContainer = GridContainer.new()
	g.columns = W_COLS.size() + 1
	g.add_theme_constant_override("h_separation", 6)
	for c in W_COLS:
		g.add_child(UIUtil.bold_label(str(c[1]), 13, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	g.add_child(Control.new())
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		for c in W_COLS:
			var key: String = str(c[0])
			match int(c[2]):
				0:
					var l: LineEdit = LineEdit.new()
					l.text = str(w.get(key, ""))
					l.custom_minimum_size = Vector2(230, 0)
					l.text_changed.connect(func(t: String) -> void: w[key] = t.strip_edges(); _check())
					g.add_child(l)
				1:
					var s: SpinBox = UIUtil.small_spin(0, 300, float(w.get(key, 0)))
					s.value_changed.connect(func(v: float) -> void: w[key] = int(v))
					g.add_child(s)
				2:
					var cb: CheckBox = UIUtil.check("", bool(w.get(key, false)))
					cb.toggled.connect(func(on: bool) -> void: w[key] = on)
					g.add_child(cb)
				3:
					var r: LineEdit = LineEdit.new()
					r.text = ", ".join(PackedStringArray(w.get(key, [])))
					r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					r.custom_minimum_size = Vector2(240, 0)
					r.text_changed.connect(func(t: String) -> void: w[key] = _split(t))
					g.add_child(r)
		g.add_child(UIUtil.button("X", _on_remove_row.bind("weapons", i)))
	var box: VBoxContainer = UIUtil.vbox(4)
	box.add_child(g)
	box.add_child(UIUtil.note("ROF 0 = cannot fire in that state. FP is the 'n+' number (FP 3+ = 3). Salvo / Artillery: "
			+ "the card says SALVO or ARTILLERY instead of a ROF."))
	return box


# ---- sizes

func _option_box(i: int) -> Control:
	var o: Dictionary = _d["options"][i]
	var v: VBoxContainer = UIUtil.vbox(4)
	var top: HBoxContainer = UIUtil.hbox(6)
	top.add_child(UIUtil.bold_label("Size %d" % (i + 1), 15, UIUtil.INK))
	top.add_child(UIUtil.label("Label:"))
	var lab: LineEdit = LineEdit.new()
	lab.text = str(o.get("label", ""))
	lab.placeholder_text = "made from the models when empty"
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.text_changed.connect(func(t: String) -> void: o["label"] = t.strip_edges())
	top.add_child(lab)
	top.add_child(UIUtil.label("Points"))
	var pts: SpinBox = UIUtil.spin(0, 999, float(o.get("points", 0)))
	pts.value_changed.connect(func(val: float) -> void: o["points"] = int(val))
	top.add_child(pts)
	top.add_child(UIUtil.label("Dynamic points"))
	var dyn: SpinBox = UIUtil.spin(0, 999, float(o.get("points_dynamic", o.get("points", 0))))
	dyn.value_changed.connect(func(val: float) -> void: o["points_dynamic"] = int(val))
	top.add_child(dyn)
	var del: Button = UIUtil.button("Delete size", _on_remove_row.bind("options", i))
	del.disabled = (_d["options"] as Array).size() <= 1
	top.add_child(del)
	v.add_child(top)

	var comp: Array = o["composition"]
	var g: GridContainer = GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 6)
	for k in comp.size():
		var item: Dictionary = comp[k]
		var cnt: SpinBox = UIUtil.small_spin(1, 99, float(item.get("count", 1)))
		cnt.value_changed.connect(func(val: float) -> void: item["count"] = int(val))
		g.add_child(cnt)
		var nm: LineEdit = LineEdit.new()
		nm.text = str(item.get("name", ""))
		nm.placeholder_text = "model, e.g. M1A1 Abrams or AK-74 team"
		nm.custom_minimum_size = Vector2(320, 0)
		nm.text_changed.connect(func(t: String) -> void: item["name"] = t.strip_edges())
		g.add_child(nm)
		g.add_child(_transport_picker(item, nm))
		g.add_child(UIUtil.button("X", _on_remove_model.bind(i, k)))
	v.add_child(g)
	var btns: HBoxContainer = UIUtil.hbox(6)
	btns.add_child(UIUtil.button("+ Models", _on_add_model.bind(i, false)))
	btns.add_child(UIUtil.button("+ Transport vehicles", _on_add_model.bind(i, true)))
	v.add_child(btns)
	return UIUtil.paper_frame(v, AppTheme.EDGE, 8, 8, 6, 1)


## The "Transport card" drop-down of one model row: none = models of this unit, else the transport card they are.
func _transport_picker(item: Dictionary, name_edit: LineEdit) -> OptionButton:
	var opt: OptionButton = OptionButton.new()
	opt.add_item("models of this unit")
	var ids: Array = [""]
	var cur: String = str(item.get("unit_id", ""))
	for t: UnitData in _transports:
		opt.add_item("transport: %s (%s, %s)" % [t.display_name, String(t.id), RulesDB.nation_label(t.nation)])
		ids.append(String(t.id))
	if cur != "" and not ids.has(cur):
		opt.add_item("transport: %s (not a known card)" % cur)
		ids.append(cur)
	opt.select(ids.find(cur))
	UIUtil.narrow(opt, 360)
	opt.tooltip_text = "Link the row to a transport card: those vehicles come into the battle as the unit's transport."
	opt.item_selected.connect(func(idx: int) -> void:
		var tid: String = str(ids[idx])
		if tid == "":
			item.erase("unit_id")
		else:
			item["unit_id"] = tid
			var t: UnitData = UnitDatabase.get_unit(StringName(tid))
			if t != null and name_edit.text.strip_edges() == "":
				item["name"] = t.display_name.trim_suffix(" Transport")
				name_edit.text = str(item["name"])
		_check())
	return opt


## The default transport: shows which transport cards the sizes use and adds one to every size.
func _transport_box() -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	var used: PackedStringArray = _used_transports()
	var names: PackedStringArray = []
	for tid in used:
		var t: UnitData = UnitDatabase.get_unit(StringName(tid))
		names.append("%s (%s)" % [t.display_name if t != null else "?", tid])
	v.add_child(UIUtil.label("Rides in: " + (", ".join(names) if not names.is_empty() else "no transport linked")))
	var row: HBoxContainer = UIUtil.hbox(6)
	row.add_child(UIUtil.label("Link transport card"))
	var opt: OptionButton = OptionButton.new()
	var ids: Array = []
	for t: UnitData in _transports:
		if t.nation == str(_d["nation"]):            # own nation first
			opt.add_item("%s (%s)" % [t.display_name, String(t.id)])
			ids.append(String(t.id))
	for t: UnitData in _transports:
		if t.nation != str(_d["nation"]):
			opt.add_item("%s (%s, %s)" % [t.display_name, String(t.id), RulesDB.nation_label(t.nation)])
			ids.append(String(t.id))
	UIUtil.narrow(opt, 360)
	row.add_child(opt)
	row.add_child(UIUtil.label("vehicles per size"))
	var cnt: SpinBox = UIUtil.spin(1, 99, 1)
	row.add_child(cnt)
	var b: Button = UIUtil.button("Add to every size", func() -> void:
		if opt.selected >= 0:
			_link_transport(str(ids[opt.selected]), int(cnt.value)))
	b.disabled = ids.is_empty()
	row.add_child(b)
	v.add_child(row)
	v.add_child(UIUtil.note("Adds a row of that transport to every size that has none yet; set the number of vehicles of each "
			+ "size in its rows above. Remove a transport by deleting its rows."))
	return v


## Transport cards: which units ride in it, and a way to link more.
func _carried_box() -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	var users: PackedStringArray = UnitDatabase.users_of_transport(str(_d["id"])) if edit_mode == Mode.EDIT else PackedStringArray()
	var names: PackedStringArray = []
	for uid in users:
		var u: UnitData = UnitDatabase.get_unit(StringName(uid))
		names.append("%s (%s)" % [u.display_name if u != null else "?", uid])
	v.add_child(UIUtil.label("Used by: " + (", ".join(names) if not names.is_empty() else "no unit yet")))
	for uid in _link_units:
		v.add_child(UIUtil.label("Will be linked when you save: %s" % uid, UIUtil.GOOD))
	var row: HBoxContainer = UIUtil.hbox(6)
	row.add_child(UIUtil.label("Link to unit"))
	var opt: OptionButton = OptionButton.new()
	var ids: Array = []
	var cards: Array = UnitDatabase.query(str(_d["nation"]), -1, false)
	for u: UnitData in cards:
		if not users.has(String(u.id)) and not _link_units.has(String(u.id)) and String(u.id) != str(_d["id"]):
			opt.add_item("%s (%s)" % [u.display_name, String(u.id)])
			ids.append(String(u.id))
	UIUtil.narrow(opt, 400)
	row.add_child(opt)
	var b: Button = UIUtil.button("Link", func() -> void:
		if opt.selected >= 0:
			_link_units.append(str(ids[opt.selected]))
			rebuild())
	b.disabled = ids.is_empty()
	row.add_child(b)
	v.add_child(row)
	v.add_child(UIUtil.note("Linking adds one vehicle of this transport to every size of that unit (that unit's card is "
			+ "saved as changed). Set the right number of vehicles afterwards in that unit's card."))
	return v


# ---- upgrades

func _upgrades_box() -> Control:
	var ups: Array = _d.get("upgrades", [])
	if ups.is_empty():
		return UIUtil.note("No upgrades.")
	var box: VBoxContainer = UIUtil.vbox(6)
	for i in ups.size():
		var up: Dictionary = ups[i]
		var v: VBoxContainer = UIUtil.vbox(4)
		var row: HBoxContainer = UIUtil.hbox(6)
		var t: LineEdit = LineEdit.new()
		t.text = str(up.get("text", ""))
		t.placeholder_text = "Add AT-11 Sniper missile for +1 point."
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.text_changed.connect(func(s: String) -> void: up["text"] = s.strip_edges())
		row.add_child(t)
		row.add_child(UIUtil.label("Points"))
		var c: SpinBox = UIUtil.spin(-99, 99, float(up.get("cost", 0)))
		c.value_changed.connect(func(val: float) -> void: up["cost"] = int(val))
		row.add_child(c)
		var kind: OptionButton = UIUtil.option(UPGRADE_KINDS)
		kind.select(_upgrade_kind_index(up))
		kind.tooltip_text = "Once: '+1 point'.  Each one picked: '+1 point each' for 'any or all' / 'up to two' (the player sets how many).\n" \
				+ "For every model: '+1 point per tank', 'all M109 ... +1 point each', 'per two aircraft' (counted from the size)."
		kind.item_selected.connect(_on_upgrade_kind_chosen.bind(up))
		row.add_child(kind)
		row.add_child(UIUtil.button("X", _on_remove_row.bind("upgrades", i)))
		v.add_child(row)
		if str(up.get("per", "")) == "model":
			var cnt: HBoxContainer = UIUtil.hbox(6)
			cnt.add_child(UIUtil.label("   Count only models named"))
			var word: LineEdit = LineEdit.new()
			word.text = str(up.get("count_models", ""))
			word.placeholder_text = "empty = every model of the size (e.g. Milan)"
			word.custom_minimum_size = Vector2(300, 0)
			word.text_changed.connect(func(s: String) -> void:
				if s.strip_edges() == "":
					up.erase("count_models")
				else:
					up["count_models"] = s.strip_edges())
			cnt.add_child(word)
			cnt.add_child(UIUtil.label("or a fixed number"))
			var fixed: SpinBox = UIUtil.spin(0, 99, float(up.get("count", 0)))
			fixed.tooltip_text = "0 = count the models of the size. Use a number when the models come from another option."
			fixed.value_changed.connect(func(val: float) -> void:
				if int(val) <= 0:
					up.erase("count")
				else:
					up["count"] = int(val))
			cnt.add_child(fixed)
			cnt.add_child(UIUtil.label("one cost per"))
			var group: SpinBox = UIUtil.spin(1, 20, float(up.get("group", 1)))
			group.suffix = "models"
			group.tooltip_text = "2 = '+3 points per two aircraft'; 8 = 'for every eight (or part thereof) teams'."
			group.value_changed.connect(func(val: float) -> void:
				if int(val) <= 1:
					up.erase("group")
				else:
					up["group"] = int(val))
			cnt.add_child(group)
			v.add_child(cnt)
		box.add_child(v)
	return box


const UPGRADE_KINDS := ["once for the unit", "each one picked", "for every model"]


static func _upgrade_kind_index(up: Dictionary) -> int:
	if str(up.get("per", "")) == "model":
		return 2
	return 1 if bool(up.get("per_model", false)) else 0


func _on_upgrade_kind_chosen(idx: int, up: Dictionary) -> void:
	up["per_model"] = idx == 1
	if idx == 2:
		up["per"] = "model"
	else:
		for k in ["per", "count_models", "count", "group"]:
			up.erase(k)
	rebuild()


# ---- small builders

func _line(key: String, width: float) -> LineEdit:
	var l: LineEdit = LineEdit.new()
	l.text = str(_d.get(key, ""))
	l.custom_minimum_size = Vector2(width, 0)
	l.text_changed.connect(func(t: String) -> void: _d[key] = t.strip_edges(); _check())
	return l


func _spin(key: String, lo: int, hi: int) -> SpinBox:
	var s: SpinBox = UIUtil.small_spin(lo, hi, float(_d.get(key, 0)))
	s.value_changed.connect(func(v: float) -> void: _d[key] = int(v))
	return s


## A wrapping row of "Label [spin]" pairs: [key, label, min, max].
func _spin_flow(fields: Array) -> Control:
	var f: HFlowContainer = HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 14)
	f.add_theme_constant_override("v_separation", 6)
	for fd in fields:
		var h: HBoxContainer = UIUtil.hbox(4)
		h.add_child(UIUtil.label(str(fd[1])))
		h.add_child(_spin(str(fd[0]), int(fd[2]), int(fd[3])))
		f.add_child(h)
	return f


static func _split(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var p: String = part.strip_edges()
		if p != "":
			out.append(p)
	return out


# ------------------------------------------------------------------ changes

## A nation was added from the card editor: the card belongs to it now.
func _on_nation_created(nation: String) -> void:
	_nations = Array(UnitDatabase.get_nations())
	_d["nation"] = nation
	rebuild()


func _on_kind_chosen(idx: int) -> void:
	var cat: String = str(KIND_KEYS[idx])
	if cat == str(_d["category"]):
		return
	_d["category"] = cat
	var types: Array = TYPES[cat]
	if not types.has(str(_d["unit_type"])):
		_d["unit_type"] = str(types[0])
	if cat == "air":
		_d["aircraft_type"] = str(_d.get("aircraft_type", "helicopter"))
		for k in ["tactical", "terrain_dash", "cross_dash", "road_dash", "cross_skill"]:
			_d[k] = UnitData.AUTO
	rebuild()


func _on_attachment_toggled(on: bool) -> void:
	_d["is_attachment"] = on
	if on:
		_d["options"] = []
		if TYPES.has(str(_d["category"])) and str(_d["category"]) != "air":
			_d["unit_type"] = "Tank Attachment" if str(_d["category"]) == "armored" else "Infantry Attachment"
	elif (_d["options"] as Array).is_empty():
		_d["options"] = [{"label": "", "models": 1, "transport_models": 0, "points": 1, "points_dynamic": 1,
				"composition": [{"count": 1, "name": ""}]}]
	rebuild()


func _on_add_weapon() -> void:
	(_d["weapons"] as Array).append({"name": "", "range_cm_min": 0, "range_cm": 40, "rof_static": 1, "rof_moving": 1,
			"salvo": false, "artillery": false, "anti_tank": 0, "firepower": 6, "rules": []})
	rebuild()


func _on_add_option() -> void:
	var opts: Array = _d["options"]
	var o: Dictionary = (opts[-1] as Dictionary).duplicate(true) if not opts.is_empty() else \
			{"label": "", "models": 1, "transport_models": 0, "points": 1, "points_dynamic": 1, "composition": [{"count": 1, "name": ""}]}
	o["label"] = ""
	opts.append(o)
	rebuild()


func _on_add_model(i: int, transport: bool) -> void:
	var item: Dictionary = {"count": 1, "name": ""}
	if transport and not _transports.is_empty():
		var used: PackedStringArray = _used_transports()
		var tid: String = used[0] if not used.is_empty() else _first_transport_of_nation()
		var t: UnitData = UnitDatabase.get_unit(StringName(tid))
		item["unit_id"] = tid
		item["name"] = t.display_name.trim_suffix(" Transport") if t != null else ""
	(_d["options"][i]["composition"] as Array).append(item)
	rebuild()


func _on_remove_model(i: int, k: int) -> void:
	(_d["options"][i]["composition"] as Array).remove_at(k)
	rebuild()


func _on_add_upgrade() -> void:
	if not _d.has("upgrades"):
		_d["upgrades"] = []
	(_d["upgrades"] as Array).append({"text": "", "cost": 1, "per_model": false})
	rebuild()


func _on_remove_row(key: String, i: int) -> void:
	(_d[key] as Array).remove_at(i)
	rebuild()


func _first_transport_of_nation() -> String:
	for t: UnitData in _transports:
		if t.nation == str(_d["nation"]):
			return String(t.id)
	return String((_transports[0] as UnitData).id)


func _used_transports() -> PackedStringArray:
	var out: PackedStringArray = []
	for o in _d.get("options", []):
		for item in o["composition"]:
			var tid: String = str((item as Dictionary).get("unit_id", ""))
			if tid != "" and not out.has(tid):
				out.append(tid)
	return out


## Adds `count` vehicles of transport `tid` to every size that has no row of it yet.
func _link_transport(tid: String, count: int) -> void:
	var t: UnitData = UnitDatabase.get_unit(StringName(tid))
	for o in _d["options"]:
		var has: bool = false
		for item in o["composition"]:
			if str((item as Dictionary).get("unit_id", "")) == tid:
				has = true
		if not has:
			(o["composition"] as Array).append({"count": count, "name": t.display_name.trim_suffix(" Transport") if t != null else tid,
					"unit_id": tid})
	rebuild()


# ------------------------------------------------------------------ checking and saving

## What stops the card from being saved ("" = nothing).
func problem() -> String:
	var id: String = str(_d.get("id", ""))
	if id == "":
		return "Type a card id."
	if id.contains(" ") or id.contains("\""):
		return "The card id cannot contain spaces or quotes."
	if edit_mode != Mode.EDIT and UnitDatabase.get_unit(StringName(id)) != null:
		return "Card id %s is already used by %s. Choose another id." % [id, UnitDatabase.get_unit(StringName(id)).display_name]
	if str(_d.get("name", "")) == "":
		return "Type a name."
	if not bool(_d.get("is_attachment", false)) and (_d["options"] as Array).is_empty():
		return "Add at least one size (or tick 'Transport / attachment card')."
	for o in _d.get("options", []):
		if (o["composition"] as Array).is_empty():
			return "Every size needs at least one row of models."
		for item in o["composition"]:
			if str((item as Dictionary).get("name", "")) == "":
				return "Every row of models needs a name."
	for w in _d["weapons"]:
		if str((w as Dictionary).get("name", "")) == "":
			return "Every weapon needs a name."
	return ""


func _check() -> void:
	var p: String = problem()
	_status.text = p
	get_ok_button().disabled = p != ""


## Fills in what follows from the rest: model counts and labels of the sizes, the card's transport fields and the
## Passengers rule.
func finish() -> void:
	for o in _d.get("options", []):
		var models: int = 0
		var vehicles: int = 0
		var parts: PackedStringArray = []
		for item in o["composition"]:
			var it: Dictionary = item
			if str(it.get("unit_id", "")) != "":
				vehicles += int(it.get("count", 1))
			else:
				models += int(it.get("count", 1))
			parts.append("%dx %s" % [int(it.get("count", 1)), str(it.get("name", ""))])
		o["models"] = maxi(models, 1)
		o["transport_models"] = vehicles
		if str(o.get("label", "")) == "":
			o["label"] = " + ".join(parts)
	var used: PackedStringArray = _used_transports()
	if used.is_empty():
		for k in ["transport_id", "transport_name", "transport_ids"]:
			_d.erase(k)
	else:
		var t: UnitData = UnitDatabase.get_unit(StringName(used[0]))
		_d["transport_id"] = used[0]
		_d["transport_name"] = t.display_name.trim_suffix(" Transport") if t != null else used[0]
		_d["transport_ids"] = Array(used)
	var rules: Array = []
	for r in _d.get("special_rules", []):
		if not str(r).begins_with("Passengers"):
			rules.append(r)
	var pas: int = int(_d.get("passengers", 0))
	if pas > 0:
		rules.append("Passengers %d" % pas)
	else:
		_d.erase("passengers")
	_d["special_rules"] = rules
	if not bool(_d.get("is_attachment", false)):
		_d.erase("is_attachment")


## Saves the card (and the units linked to a transport card). Returns "" or the error text.
func save() -> String:
	var p: String = problem()
	if p != "":
		return p
	finish()
	var err: String = UnitDatabase.save_custom(_d)
	if err != "":
		return err
	var id: String = str(_d["id"])
	if edit_mode == Mode.COPY and CardImages.find_path(_original_id) != "" and CardImages.find_path(id) == "":
		CardImages.set_image(id, ProjectSettings.globalize_path(CardImages.find_path(_original_id)))
	for uid in _link_units:
		var u: UnitData = UnitDatabase.get_unit(StringName(uid))
		if u == null:
			continue
		var other: UnitEditor = UnitEditor.new().setup(u, Mode.EDIT)
		other._link_transport(id, 1)
		var e2: String = other.save()
		other.free()
		if e2 != "":
			return "%s saved, but linking %s failed: %s" % [id, uid, e2]
	saved.emit(id)
	return ""


func _on_save_pressed() -> void:
	var err: String = save()
	if err != "":
		_status.text = err
		return
	hide()
	queue_free()
