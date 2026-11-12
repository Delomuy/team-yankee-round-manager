class_name CardBrowser
extends HSplitContainer
## Every card drawn as a real card in a wrapping grid. A single click highlights a card; a double-click opens the
## full unit card in a window, which is also where a picture is attached to the card or removed from it.
## In the Cards tab (card_editing) there is also "New card..." and the window has Edit card / Copy card /
## Restore original or Delete card (UnitEditor, saved by UnitDatabase in data/custom).
## Other screens (the army editor) add their own pane next to the grid with add_child().

signal unit_selected(unit: UnitData)
signal unit_activated(unit: UnitData)    # double-click
signal army_card_returned(payload: Dictionary)   # an army-list card was dragged back onto the grid
## "Formation editing" was pressed (Cards tab): main shows the formation editor for that nation.
signal formation_mode_requested(nation: String)

const TILE_SIZE := Vector2(220, 310)

var selected: UnitData = null
## When true the cards can be dragged out of the grid (payload kind "catalog") and army cards dropped back on it.
var drag_cards: bool = false
## When true (the Cards tab) a double-click opens the full card with the picture buttons. The army editor turns it
## off and opens its own window on unit_activated.
var open_on_activate: bool = true
## When false, Settings > Hide HQ units is ignored (the Formations section needs the HQ cards).
var obey_hide_hq: bool = true
## When true (the Cards tab) there is a "New card" button and the card window has Edit / Copy / Delete (UnitEditor).
var card_editing: bool = false

var _tiles: Dictionary = {}              # card id -> CardTile
var _built: bool = false                 # the tiles are created the first time the screen is shown
var _unavailable: Dictionary = {}        # card id -> why it is greyed out (set_unavailable)
var _selected_tile: CardTile = null
var _nation_opt: OptionButton
var _cat_opt: OptionButton
var _search: LineEdit
var _attach: CheckBox
var _count: Label
var _scroll: ScrollContainer
var _grid: HFlowContainer
var _card_dlg: AcceptDialog             # the open card window (null/freed when closed)
var _card_unit: UnitData
var _card_box: VBoxContainer            # holds the UnitSheet inside that window
var _card_hint: Label
var _attach_btn: Button
var _remove_btn: Button
var _file_dialog: FileDialog
var _new_btn: Button
var _tools: HBoxContainer               # New card / Import cards / New nation / Formation editing (Cards tab only)
var _mine: CheckBox                     # "Only my cards": the cards made or changed in the program
var _hide_hq: CheckBox                  # Settings' "Hide HQ units", shown in the Cards tab


func _init() -> void:
	# ---------------------------------------------------------------- filters + card grid
	var left: VBoxContainer = UIUtil.vbox(4)
	left.custom_minimum_size = Vector2(TILE_SIZE.x + 40.0, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	# one row: nation, type, search (takes the rest), New card
	var filters: HBoxContainer = UIUtil.hbox(4)
	_nation_opt = OptionButton.new()
	_nation_opt.custom_minimum_size = Vector2(150, 0)
	_cat_opt = UIUtil.option(["All types", "Armored", "Ground", "Air"])
	filters.add_child(_nation_opt)
	filters.add_child(_cat_opt)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name or id..."
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(120, 0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(_search)
	left.add_child(filters)
	# Cards tab only: making cards, importing them, nations and the formation editing mode
	_tools = UIUtil.hbox(6)
	_tools.visible = false
	_new_btn = UIUtil.button("New card...", _on_new_card)
	_new_btn.tooltip_text = "Make a new card from scratch (to make one from an existing card, open it and press Copy card)"
	_tools.add_child(_new_btn)
	var imp: Button = UIUtil.button("Import cards...", _on_import_cards)
	imp.tooltip_text = "Make cards from text copied from FowList (any nation, also a new one)"
	_tools.add_child(imp)
	var nat: Button = UIUtil.button("New nation...", func() -> void: NationDialog.open(self, _on_nation_added))
	nat.tooltip_text = "Add a nation that has no cards yet"
	_tools.add_child(nat)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tools.add_child(gap)
	var fm: Button = UIUtil.button("Formation editing", func() -> void: formation_mode_requested.emit(_current_nation()))
	fm.tooltip_text = "Edit formations next to the cards: drag cards onto the HQ box and the slots"
	_tools.add_child(fm)
	left.add_child(_tools)
	var ticks: HFlowContainer = HFlowContainer.new()      # wraps instead of widening a narrow card selector
	ticks.add_theme_constant_override("h_separation", 16)
	_attach = UIUtil.check("Show attachments (transports)")
	ticks.add_child(_attach)
	_mine = UIUtil.check("Only my cards (made or changed here)")
	_mine.visible = false
	ticks.add_child(_mine)
	_hide_hq = UIUtil.check("Hide HQ units", AppSettings.hide_hq())
	_hide_hq.tooltip_text = "Leave the HQ (commander) cards out of the card lists, here and in the army editor. HQ cards already in an army stay."
	_hide_hq.visible = false
	_hide_hq.toggled.connect(func(on: bool) -> void:
		AppSettings.set_hide_hq(on)              # remembered; the army editor's list filters again when it is shown
		refresh())
	ticks.add_child(_hide_hq)
	left.add_child(ticks)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS           # drops on the grid reach the drop zone behind it
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	var grid_bg: DropZone = DropZone.new()          # the parchment behind the card grid; army cards dropped here are taken out
	grid_bg.accepts = "army"
	grid_bg.dropped.connect(func(payload: Dictionary) -> void: army_card_returned.emit(payload))
	var grid_holder: MarginContainer = UIUtil.round_holder(grid_bg, 10, 6, 6, Color(0.92, 0.91, 0.88))
	grid_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_holder.add_child(_scroll)
	left.add_child(grid_bg)
	_count = UIUtil.label("")
	left.add_child(_count)
	add_child(left)

	_nation_opt.item_selected.connect(func(_i): refresh())
	_cat_opt.item_selected.connect(func(_i): refresh())
	_search.text_changed.connect(func(_t): refresh())
	_attach.toggled.connect(func(_b): refresh())
	_mine.toggled.connect(func(_b): refresh())


func _ready() -> void:
	_nation_opt.add_item("All nations")
	for n in UnitDatabase.get_nations():
		_nation_opt.add_item(n)
	_tools.visible = card_editing
	_mine.visible = card_editing
	_hide_hq.visible = card_editing and obey_hide_hq
	UnitDatabase.cards_changed.connect(update_card)
	visibility_changed.connect(_on_visibility_changed)
	get_window().files_dropped.connect(_on_files_dropped)
	refresh()
	_build_if_visible.call_deferred()


## A tab nobody opens costs nothing: its 250+ cards are only built when it is first shown.
func _build_if_visible() -> void:
	if _built or not is_visible_in_tree():
		return
	var n: Node = self
	while n != null:                         # a screen freed right after it was made never builds its 250+ cards
		if n.is_queued_for_deletion():
			return
		n = n.get_parent()
	_build_tiles()


func _build_tiles() -> void:
	_built = true
	var units: Array = UnitDatabase.units.values()
	units.sort_custom(_card_before)
	for u: UnitData in units:
		var tile: CardTile = _make_tile(u)
		_grid.add_child(tile)
		_tiles[u.id] = tile
	refresh()                                # hide the cards that do not match the filters
	if selected != null:
		_selected_tile = _tiles.get(selected.id)
		if _selected_tile != null:
			_selected_tile.set_selected(true)
	set_unavailable(_unavailable)


func _make_tile(u: UnitData) -> CardTile:
	var tile: CardTile = CardTile.new()
	tile.setup(u, TILE_SIZE)
	tile.clicked.connect(select_unit)
	tile.activated.connect(_on_tile_activated)
	if drag_cards:
		tile.drag_payload = {"kind": "catalog", "unit_id": u.id}
	return tile


## Redraws one card after it was made, changed, restored or deleted (UnitDatabase.cards_changed).
func update_card(id: String) -> void:
	var sid: StringName = StringName(id)
	var u: UnitData = UnitDatabase.get_unit(sid)
	if u != null and _nation_opt.item_count - 1 != UnitDatabase.get_nations().size():
		_refresh_nations()                       # the card brought a nation the filter does not list yet
	if _selected_tile != null and is_instance_valid(_selected_tile) and _selected_tile.unit.id == sid:
		_clear_selection()
	if _built:
		var old: CardTile = _tiles.get(sid)
		if old != null:
			_tiles.erase(sid)
			_grid.remove_child(old)
			old.queue_free()
		if u != null:
			var tile: CardTile = _make_tile(u)
			var at: int = 0
			for c in _grid.get_children():
				if _card_before((c as CardTile).unit, u):
					at += 1
			_grid.add_child(tile)
			_grid.move_child(tile, at)
			_tiles[sid] = tile
		set_unavailable(_unavailable)
	refresh()
	if is_instance_valid(_card_dlg) and _card_unit != null and _card_unit.id == sid:
		if u == null:
			_card_dlg.queue_free()
		else:
			open_card(u)                     # again: the buttons depend on whether the card is changed or new


## Greys out the cards that cannot be taken: card id -> reason (shown in the tooltip). Every other card is shown
## normally. The army editor passes the cards its army cannot take (exclusive units, limits ...).
func set_unavailable(reasons: Dictionary) -> void:
	_unavailable = reasons
	for id in _tiles:
		var why: String = str(reasons.get(id, ""))
		(_tiles[id] as CardTile).set_greyed(why != "", why)


## Grid order: nation, then Armored / Ground / Air, then name.
static func _card_before(a: UnitData, b: UnitData) -> bool:
	if a.nation != b.nation:
		return a.nation < b.nation
	if a.category != b.category:
		return a.category < b.category
	return a.display_name < b.display_name


# ------------------------------------------------------------------ filtering

## Shows only the cards that match the filters (the tiles are built once and just hidden).
func refresh() -> void:
	var nation: String = ""
	if _nation_opt.selected > 0:
		nation = _nation_opt.get_item_text(_nation_opt.selected)
	var cat: int = _cat_opt.selected - 1            # 0 = all types -> -1; then ARMORED, GROUND, AIR
	var q: String = _search.text.strip_edges().to_lower()
	var allowed: Dictionary = {}
	var hide_hq: bool = obey_hide_hq and AppSettings.hide_hq()
	for u in UnitDatabase.query(nation, cat, _attach.button_pressed):
		if hide_hq and u.is_hq():                  # Settings > Hide HQ units
			continue
		if q != "" and not (u.display_name.to_lower().contains(q) or String(u.id).to_lower().contains(q)):
			continue
		if _mine.button_pressed and not UnitDatabase.is_custom(String(u.id)):
			continue
		allowed[u.id] = true
	for id in _tiles.keys():
		var tile: CardTile = _tiles[id]
		tile.visible = allowed.has(id)
	_count.text = "%d card(s)" % allowed.size()
	if selected != null and not allowed.has(selected.id):
		_clear_selection()


## Picks a nation in the filter ("" = all nations).
func set_nation(nation: String) -> void:
	var idx: int = 0
	for i in _nation_opt.item_count:
		if _nation_opt.get_item_text(i) == nation:
			idx = i
	_nation_opt.select(idx)
	refresh()


## Updates the points text and pictures on every card (after the points switch or a new picture).
func refresh_tiles() -> void:
	for t: CardTile in _tiles.values():
		t.refresh_points()
		t.refresh_image()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	if not _built:
		_build_tiles()
	else:
		refresh_tiles()                      # pictures may have been attached in the other tab
		refresh()                            # Settings > Hide HQ units may have changed


# ------------------------------------------------------------------ selection

func select_unit(u: UnitData) -> void:
	if _selected_tile != null and is_instance_valid(_selected_tile):
		_selected_tile.set_selected(false)
	_selected_tile = _tiles.get(u.id)
	if _selected_tile != null:
		_selected_tile.set_selected(true)
	selected = u
	unit_selected.emit(u)


func _clear_selection() -> void:
	if _selected_tile != null and is_instance_valid(_selected_tile):
		_selected_tile.set_selected(false)
	_selected_tile = null
	selected = null


func _on_tile_activated(u: UnitData) -> void:
	select_unit(u)
	if open_on_activate:
		open_card(u)
	unit_activated.emit(u)


# ------------------------------------------------------------------ the card window

## Opens the full unit card in a window with the "Attach picture" / "Remove picture" buttons.
func open_card(u: UnitData) -> void:
	if is_instance_valid(_card_dlg):
		_card_dlg.queue_free()
	_card_unit = u
	var dlg: AcceptDialog = AcceptDialog.new()
	_card_dlg = dlg
	dlg.title = u.display_name
	dlg.ok_button_text = "Close"
	var room: Vector2 = get_viewport().get_visible_rect().size
	var v: VBoxContainer = UIUtil.vbox(6)
	var btns: HBoxContainer = UIUtil.hbox(6)
	_attach_btn = UIUtil.button("Attach picture...", _on_attach_pressed)
	_remove_btn = UIUtil.button("Remove picture", _on_remove_pressed)
	btns.add_child(_attach_btn)
	btns.add_child(_remove_btn)
	btns.add_child(UIUtil.button("Weapons per model...", _on_model_weapons_pressed))
	if card_editing:
		var gap: Control = Control.new()
		gap.custom_minimum_size = Vector2(24, 0)
		btns.add_child(gap)
		var edit: Button = UIUtil.button("Edit card...", _on_edit_card.bind(UnitEditor.Mode.EDIT))
		edit.tooltip_text = "Change this card. A card from the original files keeps its original: 'Restore original' brings it back."
		btns.add_child(edit)
		var copy: Button = UIUtil.button("Copy card...", _on_edit_card.bind(UnitEditor.Mode.COPY))
		copy.tooltip_text = "Make a new card from this one, with its own id (e.g. %sc)." % String(u.id)
		btns.add_child(copy)
		var id: String = String(u.id)
		if UnitDatabase.is_custom(id):
			var undo: Button = UIUtil.button("Restore original" if UnitDatabase.has_original(id) else "Delete card",
					_on_remove_card)
			undo.tooltip_text = "Throw away your changes and use the card from the original files again." \
					if UnitDatabase.has_original(id) else "Delete this card (it was made in the program)."
			btns.add_child(undo)
	v.add_child(btns)
	_card_hint = UIUtil.note("")
	_card_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_hint.custom_minimum_size = Vector2(400, 0)
	v.add_child(_card_hint)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(1060.0, room.x - 80.0), minf(640.0, room.y - 220.0))
	_card_box = UIUtil.vbox(0)
	_card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_card_box)
	v.add_child(scroll)
	dlg.add_child(v)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Choose a picture for this card"
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_image_chosen)
	dlg.add_child(_file_dialog)
	add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	_fill_card()
	dlg.popup_centered()
	UIUtil.fit_popup(dlg, scroll, _card_box, room.y - 220.0)


# ------------------------------------------------------------------ making and changing cards (UnitEditor)

## The nation picked in the filter ("" = all nations).
func _current_nation() -> String:
	return _nation_opt.get_item_text(_nation_opt.selected) if _nation_opt.selected > 0 else ""


func _on_new_card() -> void:
	var nation: String = _current_nation()
	if nation == "" and not UnitDatabase.get_nations().is_empty():
		nation = UnitDatabase.get_nations()[0]
	open_editor(null, UnitEditor.Mode.NEW, nation)


func _on_import_cards() -> void:
	var d: CardImportDialog = CardImportDialog.open(self, _current_nation())
	d.imported.connect(func(ids: PackedStringArray) -> void:
		_refresh_nations()
		_count.text = "Imported %d card(s). " % ids.size() + _count.text)


## A nation was added: list it in the filter and pick it.
func _on_nation_added(nation: String) -> void:
	_refresh_nations()
	set_nation(nation)


## Fills the nation filter again (a nation may have been added or got its first cards).
func _refresh_nations() -> void:
	var keep: String = _current_nation()
	_nation_opt.clear()
	_nation_opt.add_item("All nations")
	for n in UnitDatabase.get_nations():
		_nation_opt.add_item(n)
	set_nation(keep)


func _on_edit_card(mode: int) -> void:
	if _card_unit != null:
		open_editor(_card_unit, mode)


## Opens the card editor. The saved card is shown in the grid (and its window opened for a new or copied card).
func open_editor(u: UnitData, mode: int, nation: String = "") -> UnitEditor:
	var ed: UnitEditor = UnitEditor.new().setup(u, mode, nation)
	add_child(ed)
	ed.canceled.connect(ed.queue_free)
	ed.saved.connect(_on_card_saved.bind(mode))
	ed.popup_centered()
	return ed


func _on_card_saved(id: String, mode: int) -> void:
	var u: UnitData = UnitDatabase.get_unit(StringName(id))
	if u == null:
		return
	if u.is_attachment and not _attach.button_pressed:
		_attach.button_pressed = true          # a new transport card would otherwise be hidden
	if mode != UnitEditor.Mode.EDIT:
		select_unit(u)
		open_card(u)


## "Restore original" (a changed card from the main files) or "Delete card" (a card made in the program).
func _on_remove_card() -> void:
	if _card_unit == null:
		return
	var id: String = String(_card_unit.id)
	var restore: bool = UnitDatabase.has_original(id)
	var dlg: ConfirmationDialog = ConfirmationDialog.new()
	dlg.title = "Restore original" if restore else "Delete card"
	var text: String = ("Throw away your changes to %s (%s) and use the original card again?" if restore
			else "Delete the card %s (%s)? This cannot be undone.") % [_card_unit.display_name, id]
	if not restore:
		var uses: PackedStringArray = card_uses(id)
		if not uses.is_empty():
			text += "\n\nIt is still used by:\n- " + "\n- ".join(uses)
	dlg.dialog_text = text
	dlg.ok_button_text = "Restore" if restore else "Delete"
	dlg.confirmed.connect(func() -> void: UnitDatabase.remove_custom(id))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


## Where a card is used: formations, the armies being built and cards that ride in it (for the delete warning).
static func card_uses(id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f: FormationData in FormationDB.for_nation(""):
		var named: bool = f.hq == id
		for s in f.slots:
			if (s["units"] as PackedStringArray).has(id):
				named = true
		if named:
			out.append("formation %s" % f.full_name())
	for a: Army in ArmyManager.roster:
		for e: ArmyEntry in a.entries:
			if String(e.unit_id) == id:
				out.append("army %s" % a.army_name)
				break
	for uid in UnitDatabase.users_of_transport(id):
		out.append("card %s (its transport)" % uid)
	return out


## Which weapons each kind of model of this card can fire (used by the round manager).
func _on_model_weapons_pressed() -> void:
	if _card_unit == null:
		return
	var dlg: ModelWeaponsDialog = ModelWeaponsDialog.new().setup(_card_unit)
	add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


## (Re)draws the sheet and the picture buttons inside the card window.
func _fill_card() -> void:
	if not is_instance_valid(_card_dlg) or _card_unit == null:
		return
	UIUtil.clear_children(_card_box)
	var id: String = String(_card_unit.id)
	var sheet: UnitSheet = UnitSheet.new().setup(_card_unit, ArmyManager.use_dynamic_points)
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_box.add_child(sheet)
	var has_pic: bool = CardImages.get_texture(id) != null
	_card_hint.text = "" if has_pic else "No picture yet. Press 'Attach picture...' or drop an image file onto the window (saved as %s/%s.png)." % [CardImages.save_dir(), id]
	_remove_btn.disabled = not has_pic


# ------------------------------------------------------------------ pictures

func _on_attach_pressed() -> void:
	if _card_unit != null and is_instance_valid(_file_dialog):
		_file_dialog.popup_centered_ratio(0.7)


func _on_image_chosen(path: String) -> void:
	_set_picture(path)


func _on_files_dropped(files: PackedStringArray) -> void:
	if not is_instance_valid(_card_dlg) or _card_unit == null or not _card_dlg.visible:
		return
	for f in files:
		if CardImages.EXTENSIONS.has(f.get_extension().to_lower()):
			_set_picture(f)
			return


func _set_picture(path: String) -> void:
	if _card_unit == null:
		return
	var err: Error = CardImages.set_image(String(_card_unit.id), path)
	_after_picture_change()
	if err != OK:
		_card_hint.text = "Could not use that file as a picture (error %d). Try a PNG, JPG or WEBP image." % err


func _on_remove_pressed() -> void:
	if _card_unit == null:
		return
	CardImages.clear_image(String(_card_unit.id))
	_after_picture_change()


func _after_picture_change() -> void:
	var tile: CardTile = _tiles.get(_card_unit.id)
	if tile != null:
		tile.refresh_image()
	_fill_card()
