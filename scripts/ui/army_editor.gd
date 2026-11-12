class_name ArmyEditor
extends VBoxContainer
## One player's army list. On the left the card selector (the same card grid as the Cards tab), on the right
## the army as small cards. Drag a card from the selector onto the list to add one copy (the whole card follows the
## mouse) and drag a card from the list back onto the selector to take one copy out. Double-click a card (in the
## selector or in the list) to open the full card, where the size, the upgrades and the number of copies are chosen.
## The same unit bought several times is one card with "xN" in a black circle.
## "Remove selected" is a mode: click cards to mark copies (red circle top left), then press Accept.
## The list holds the support units (outside the formation; the formation is edited on the FormationScreen). They
## obey Army.support_problem (Settings > Limit unit quantities, exclusive units, formation-only and HQ cards); the
## cards the army cannot take are greyed out in the selector.

signal back_requested
signal changed

const SMALL_TILE := Vector2(165, 232)

var _army: Army
var _pane: DropZone
var _browser: CardBrowser
var _title: Label
var _name_edit: LineEdit
var _limit: SpinBox
var _totals: Label
var _status: Label
var _list: HFlowContainer
var _empty_hint: Label
var _accept_btn: Button
var _remove_btn: Button
var _mode_hint: Label
var _removing: bool = false
var _remove_counts: Dictionary = {}      # card key (ArmyEntry.make_key) -> copies marked for removal
var _groups_by_key: Dictionary = {}      # card key -> {"unit_id", "option_index", "upgrades", "key", "count"}
var _tiles: Dictionary = {}              # card key -> CardTile
var _problems: Label


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	# ---- top bar
	var top: HBoxContainer = UIUtil.hbox(10)
	top.add_child(UIUtil.button("< Back to armies", _on_back))
	_title = UIUtil.heading("")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(UIUtil.label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(180, 0)
	_name_edit.text_changed.connect(_on_name_changed)
	top.add_child(_name_edit)
	top.add_child(UIUtil.label("Points limit (0 = none):"))
	_limit = UIUtil.spin(0, 5000, 0)
	_limit.value_changed.connect(_on_limit_changed)
	top.add_child(_limit)
	add_child(top)
	_status = UIUtil.note("")
	add_child(_status)

	# ---- body: card selector | army list
	_browser = CardBrowser.new()
	_browser.drag_cards = true
	_browser.open_on_activate = false                  # double-click opens the army editor's own window (no picture buttons)
	_browser.unit_activated.connect(_on_catalog_activated)
	_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_browser.army_card_returned.connect(_on_army_card_returned)
	_browser.add_child(_build_army_pane())
	add_child(_browser)


func _build_army_pane() -> Control:
	var pane: DropZone = DropZone.new()
	_pane = pane
	pane.accepts = "catalog"
	pane.dropped.connect(_on_catalog_dropped)
	pane.add_theme_stylebox_override("panel", AppTheme.box(Color(0.30, 0.235, 0.153), AppTheme.CLEAR, 0, 8, 6, 6))
	pane.custom_minimum_size = Vector2(380, 0)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.size_flags_stretch_ratio = 2.0
	var v: VBoxContainer = UIUtil.vbox(6)
	pane.add_child(v)

	_totals = UIUtil.bold_label("", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # the formation name can be long
	_totals.custom_minimum_size = Vector2(200, 0)
	v.add_child(_totals)
	_problems = UIUtil.label("", Color(1, 0.8, 0.7))
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_problems)

	var paper: PanelContainer = PanelContainer.new()
	var paper_holder: MarginContainer = UIUtil.round_holder(paper, 8, 6, 6, Color(0.95, 0.94, 0.91))
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	paper.mouse_filter = Control.MOUSE_FILTER_PASS         # a drop on the paper still reaches the drop zone
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner: VBoxContainer = UIUtil.vbox(6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_hint = UIUtil.note("Drag cards here from the card selector on the left.")
	inner.add_child(_empty_hint)
	_list = HFlowContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 8)
	inner.add_child(_list)
	scroll.add_child(inner)
	paper_holder.add_child(scroll)
	v.add_child(paper)

	_mode_hint = UIUtil.label("Remove mode: click a card to mark another copy (right-click: one less), then press Accept.", Color(1, 0.9, 0.6))
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.visible = false
	v.add_child(_mode_hint)

	var btns: HBoxContainer = UIUtil.hbox(6)
	_accept_btn = UIUtil.button("Accept", _on_accept)
	_accept_btn.visible = false
	btns.add_child(_accept_btn)
	_remove_btn = Button.new()
	_remove_btn.text = "Remove selected"
	_remove_btn.toggle_mode = true
	_remove_btn.toggled.connect(_on_remove_toggled)
	btns.add_child(_remove_btn)
	btns.add_child(UIUtil.button("Clear army", _on_clear))
	v.add_child(btns)
	return pane


## Shows the army of roster player `index` (the card selector starts on that player's main army).
func open_player(index: int) -> void:
	_army = ArmyManager.roster[index]
	_leave_remove_mode()
	_name_edit.set_text(_army.army_name)
	_limit.set_value_no_signal(_army.points_limit)
	_status.text = ""
	_browser.set_nation(_army.nation)
	var frame: Color = UnitSheet.color_for(_army.nation) if _army.nation != "" else AppTheme.BROWN
	_pane.add_theme_stylebox_override("panel", AppTheme.box(frame, AppTheme.CLEAR, 0, 8, 6, 6))
	_refresh()


# ------------------------------------------------------------------ the list

func _refresh() -> void:
	UIUtil.clear_children(_list)
	_tiles.clear()
	_groups_by_key.clear()
	var groups: Array = _army.groups()
	_empty_hint.visible = groups.is_empty()
	for item in groups:
		var g: Dictionary = item
		var tile: CardTile = _make_tile(g)
		if tile != null:
			_list.add_child(tile)
	_update_header()
	_update_unavailable()


## Greys out in the card selector every card this army cannot take now (exclusive with a unit in the army, limit
## reached, formation-only, an HQ while the army uses a formation). Attachments are left alone.
func _update_unavailable() -> void:
	var reasons: Dictionary = {}
	for u: UnitData in UnitDatabase.units.values():
		if u.options.is_empty():
			continue
		var why: String = _army.support_problem(u, 1)
		if why == "":
			why = _army.army_clash(u)                 # also units exclusive with one in the formation
		if why != "":
			reasons[u.id] = why
	_browser.set_unavailable(reasons)


func _make_tile(g: Dictionary) -> CardTile:
	var u: UnitData = UnitDatabase.get_unit(StringName(g["unit_id"]))
	var oi: int = int(g["option_index"])
	if u == null or u.get_option(oi) == null:
		return null
	var o: UnitOption = u.get_option(oi)
	var count: int = int(g["count"])
	var ups: Dictionary = g["upgrades"]
	var key: String = String(g["key"])
	_groups_by_key[key] = g
	var tile: CardTile = CardTile.new()
	tile.setup(u, SMALL_TILE)
	tile.set_count(count)
	var each: int = o.cost(ArmyManager.use_dynamic_points)
	var tip: String = "Size: " + o.label
	var up_lines: PackedStringArray = []
	for idx in ups:
		each += u.upgrade_cost(int(idx), int(ups[idx]), o)
		up_lines.append(str((u.upgrades[int(idx)] as Dictionary).get("text", "")) + (" x%d" % int(ups[idx]) if int(ups[idx]) > 1 else ""))
	if not up_lines.is_empty():
		tip += "\nUpgrades:\n- " + "\n- ".join(up_lines)
	var pts: String = "%d pts" % each
	if not ups.is_empty():
		pts += " (+upg)"
	tile.set_footer(pts + (" each" if count > 1 else ""), tip)
	tile.drag_payload = {"kind": "army", "unit_id": u.id, "option_index": oi, "upgrades": ups}
	tile.set_remove_count(int(_remove_counts.get(key, 0)))
	tile.clicked.connect(_on_tile_clicked.bind(key))
	tile.right_clicked.connect(_on_tile_right_clicked.bind(key))
	tile.activated.connect(_on_tile_activated.bind(key))
	_tiles[key] = tile
	return tile


func _update_header() -> void:
	_title.text = "%s  -  %s" % [_army.army_name, RulesDB.nation_label(_army.nation)]
	var total: int = _army.total_points()
	var support: int = _army.support_entries().size()
	var in_form: int = _army.entries.size() - support
	var text: String = "Total: %d pts   (%d units)" % [total, support]
	if _army.use_formations:
		var f: FormationData = _army.main_formation()
		text = "Total: %d pts   (formation %s: %d units; %d support units)" % [total, f.full_name() if f != null else "not chosen", in_form, support]
	var problems: PackedStringArray = _army.list_problems()
	_problems.text = "" if problems.is_empty() else "To fix: " + ";  ".join(problems)
	_problems.visible = not problems.is_empty()
	if _army.points_limit > 0:
		var left: int = _army.points_limit - total
		text += "   -   limit %d: %s" % [_army.points_limit, ("%d left" % left) if left >= 0 else ("%d OVER" % -left)]
	_totals.text = text
	_totals.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if _army.points_limit > 0 and total > _army.points_limit else Color.WHITE)


# ------------------------------------------------------------------ adding

func _on_catalog_dropped(payload: Dictionary) -> void:
	var u: UnitData = UnitDatabase.get_unit(StringName(payload.get("unit_id", "")))
	if u == null:
		return
	var problem: String = _army.support_problem(u, 1)
	if problem != "":
		_status.text = problem
		return
	_add(u, 0, 1)


func _add(u: UnitData, option_index: int, count: int, upgrades: Dictionary = {}) -> void:
	for i in count:
		_army.add_unit(u.id, option_index, "", upgrades)
	var extra: String = " with %d upgrade(s)" % upgrades.size() if not upgrades.is_empty() else ""
	_status.text = "Added %dx %s (%s)%s." % [count, u.display_name, u.options[option_index].label, extra]
	_refresh()
	changed.emit()


## Double-click on a card in the selector: the full card opens, ready to be added with the size / upgrades / copies chosen.
func _on_catalog_activated(u: UnitData) -> void:
	var problem: String = _army.support_problem(u, 1)
	if problem != "":
		_status.text = problem
		CardView.popup(u, self)                    # it cannot be bought here, but the card can still be read
		return
	_open_edit(u, 0, {}, 1, "")


## Opens the card window. `edit_key` = "" adds a new card; otherwise it changes the army card with that key.
func _open_edit(u: UnitData, option_index: int, upgrades: Dictionary, count: int, edit_key: String) -> void:
	var dlg: UnitEditDialog = UnitEditDialog.new().setup(u, option_index, upgrades, count, edit_key == "")
	if AppSettings.limit_units():
		dlg.set_max_copies(_army.room_for(u) + (count if edit_key != "" else 0))
	add_child(dlg)
	dlg.applied.connect(_on_unit_applied.bind(u, edit_key))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_unit_applied(option_index: int, upgrades: Dictionary, count: int, u: UnitData, edit_key: String) -> void:
	var old: Dictionary = {}
	if edit_key != "" and _groups_by_key.has(edit_key):
		old = _groups_by_key[edit_key]
		_army.remove_copies(StringName(old["unit_id"]), int(old["option_index"]), int(old["count"]), old["upgrades"])
	var problem: String = _army.support_problem(u, count)
	if problem != "":
		if not old.is_empty():                      # put the card back as it was
			for i in int(old["count"]):
				_army.add_unit(StringName(old["unit_id"]), int(old["option_index"]), "", old["upgrades"])
		_status.text = problem
		_refresh()
		return
	_add(u, option_index, count, upgrades)


# ------------------------------------------------------------------ taking cards out

## An army card was dragged back onto the card selector: one copy leaves the army.
func _on_army_card_returned(payload: Dictionary) -> void:
	var id: StringName = StringName(payload.get("unit_id", ""))
	if _army.remove_copies(id, int(payload.get("option_index", 0)), 1, payload.get("upgrades", {})) > 0:
		var u: UnitData = UnitDatabase.get_unit(id)
		_status.text = "Removed one %s." % (u.display_name if u != null else String(id))
		_refresh()
		changed.emit()


func _on_remove_toggled(on: bool) -> void:
	_removing = on
	_remove_counts.clear()
	_accept_btn.visible = on
	_mode_hint.visible = on
	_remove_btn.text = "Cancel removal" if on else "Remove selected"
	for t: CardTile in _tiles.values():
		t.set_remove_count(0)


func _leave_remove_mode() -> void:
	if _remove_btn.button_pressed:
		_remove_btn.button_pressed = false          # runs _on_remove_toggled(false)
	else:
		_on_remove_toggled(false)


func _on_tile_clicked(_unit: UnitData, key: String) -> void:
	if not _removing:
		return
	var have: int = int((_groups_by_key[key] as Dictionary)["count"])
	var now: int = int(_remove_counts.get(key, 0))
	_set_marked(key, now + 1 if now < have else 0)           # one more copy; past the last one it starts again at 0


func _on_tile_right_clicked(_unit: UnitData, key: String) -> void:
	if _removing:
		_set_marked(key, maxi(int(_remove_counts.get(key, 0)) - 1, 0))


func _set_marked(key: String, n: int) -> void:
	if n <= 0:
		_remove_counts.erase(key)
	else:
		_remove_counts[key] = n
	(_tiles[key] as CardTile).set_remove_count(n)


func _on_accept() -> void:
	var removed: int = 0
	for key in _remove_counts.keys():
		var g: Dictionary = _groups_by_key[key]
		removed += _army.remove_copies(StringName(g["unit_id"]), int(g["option_index"]), int(_remove_counts[key]), g["upgrades"])
	_leave_remove_mode()
	_status.text = "Removed %d card(s)." % removed if removed > 0 else "Nothing was marked."
	_refresh()
	if removed > 0:
		changed.emit()


func _on_clear() -> void:
	_leave_remove_mode()
	for e in _army.support_entries():                 # the formation is kept (it is edited on the formation screen)
		_army.entries.erase(e)
	_status.text = "Support units cleared." if _army.use_formations else "Army cleared."
	_refresh()
	changed.emit()


## Double-click on an army card: the full card opens with its current size, upgrades and number of copies.
func _on_tile_activated(u: UnitData, key: String) -> void:
	if _removing or not _groups_by_key.has(key):
		return
	var g: Dictionary = _groups_by_key[key]
	_open_edit(u, int(g["option_index"]), g["upgrades"], int(g["count"]), key)


# ------------------------------------------------------------------ header controls

func _on_name_changed(text: String) -> void:
	if _army != null:
		_army.army_name = text if text.strip_edges() != "" else "Player"
		_update_header()


func _on_limit_changed(v: float) -> void:
	if _army != null:
		_army.points_limit = int(v)
		_update_header()


func _on_back() -> void:
	_leave_remove_mode()
	back_requested.emit()
