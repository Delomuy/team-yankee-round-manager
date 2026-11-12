class_name CardImportDialog
extends ConfirmationDialog
## Cards > "Import cards...": makes cards from text copied from FowList's list view (CardTextImport, the same rules
## as tools/convert_units.py) for any nation, also one added with "New nation...".
##   1. pick the nation (or add one), 2. paste the text or load a .txt file, 3. "Read the cards" shows every card
##   found with what will happen to it (new / replaces ...) and the converter's warnings, 4. untick cards you do not
##   want and press "Import". The cards are saved like cards made in the editor (data/custom/<prefix>_units.json).

signal imported(ids: PackedStringArray)

var _nations: Array = []
var _nation_opt: OptionButton
var _text: TextEdit
var _list: VBoxContainer
var _warn: Label
var _status: Label
var _found: Array = []          # unit dictionaries read from the text
var _ticks: Array = []          # CheckBox per found card
var _file_dialog: FileDialog


func _init() -> void:
	title = "Import cards from text"
	ok_button_text = "Import ticked cards"
	dialog_hide_on_ok = false
	var v: VBoxContainer = UIUtil.vbox(8)
	v.custom_minimum_size = Vector2(1100, 0)

	var top: HBoxContainer = UIUtil.hbox(8)
	top.add_child(UIUtil.label("Nation of the cards:"))
	_nation_opt = UIUtil.narrow(OptionButton.new(), 220)
	top.add_child(_nation_opt)
	top.add_child(UIUtil.button("New nation...", func() -> void: NationDialog.open(self, _on_nation_created)))
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	top.add_child(UIUtil.button("Load text file...", _on_load_file))
	top.add_child(UIUtil.button("Read the cards", read_cards))
	v.add_child(top)
	var how: Label = UIUtil.note("Paste the cards as copied from FowList's list view: each card starts with 'Name ID' (e.g. "
			+ "'T-80 Tank Company TS138'), then its type line, the TACT. line with the moves, the sizes with '(N points)', "
			+ "the options, the weapon lines and the ratings (COURAGE 4+, SKILL 5+, IS HIT ON 3+, FRONT 2 ...). "
			+ "A transport is written '(TS126)' after its size line. data/ussr_units.txt is a complete example.")
	how.custom_minimum_size = Vector2(1080, 0)        # a width before the first layout, or the window grows too tall
	v.add_child(how)

	var body: HBoxContainer = UIUtil.hbox(10)
	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(520, 380)
	_text.placeholder_text = "T-80 Tank Company TS138\nTank Unit, ERA, Infra-Red (IR)\nTACT. 	TERR. DASH 	CROSS C. DASH 	ROAD DASH 	CROSS\n14\"/35cm 	18\"/45cm 	28\"/70cm 	32\"/80cm 	2+\n    3x T-80 (22 points)\n..."
	_text.add_theme_color_override("font_color", UIUtil.INK)
	_text.add_theme_stylebox_override("normal", AppTheme.box(AppTheme.FIELD, AppTheme.EDGE, 1, 4, 6, 4))
	body.add_child(_text)
	var right: VBoxContainer = UIUtil.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(UIUtil.bold_label("CARDS FOUND", 15, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner: VBoxContainer = UIUtil.vbox(6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = UIUtil.vbox(2)
	inner.add_child(_list)
	_warn = UIUtil.label("", UIUtil.WARN)
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.custom_minimum_size = Vector2(400, 0)
	inner.add_child(_warn)
	scroll.add_child(inner)
	right.add_child(scroll)
	body.add_child(right)
	v.add_child(body)
	_status = UIUtil.label("", UIUtil.BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1080, 0)
	v.add_child(_status)
	add_child(v)
	get_ok_button().pressed.connect(import_ticked)
	canceled.connect(queue_free)
	_fill_nations("")
	_show_found()


func _fill_nations(select: String) -> void:
	_nation_opt.clear()
	_nations = NationDB.all()
	for n: String in _nations:
		_nation_opt.add_item(RulesDB.nation_label(n))
	var at: int = _nations.find(select)
	if at >= 0:
		_nation_opt.select(at)


## The nation picked ("" when there is none).
func nation() -> String:
	var i: int = _nation_opt.selected
	return str(_nations[i]) if i >= 0 and i < _nations.size() else ""


## Opens with `nation` picked.
func set_nation(n: String) -> void:
	_fill_nations(n)


## Puts `t` in the text box (AcceptDialog has its own set_text, hence the name).
func set_cards_text(t: String) -> void:
	_text.text = t


func _on_nation_created(n: String) -> void:
	_fill_nations(n)
	if not _found.is_empty():
		read_cards()


func _on_load_file() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.title = "Load cards copied from FowList"
		_file_dialog.filters = PackedStringArray(["*.txt ; Text"])
		_file_dialog.use_native_dialog = true
		_file_dialog.file_selected.connect(func(p: String) -> void:
			_text.text = FileAccess.get_file_as_string(p)
			read_cards())
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.7)


## Reads the text and lists the cards found.
func read_cards() -> void:
	if nation() == "":
		_status.text = "Pick the nation of the cards first (or add one with New nation...)."
		return
	var res: Dictionary = CardTextImport.parse(_text.text, nation())
	_found = res["units"]
	var w: PackedStringArray = res["warnings"]
	_warn.text = "" if w.is_empty() else "Check:\n- " + "\n- ".join(w)
	_status.text = ""
	_show_found()


## What importing card `d` would do: "new", "replaces your card" or "replaces the original card".
static func fate(d: Dictionary) -> String:
	var id: String = str(d.get("id", ""))
	if UnitDatabase.get_unit(StringName(id)) == null:
		return "new"
	if UnitDatabase.has_original(id):
		return "replaces the original card (Restore original brings it back)"
	return "replaces your card"


func _show_found() -> void:
	UIUtil.clear_children(_list)
	_ticks.clear()
	if _found.is_empty():
		_list.add_child(UIUtil.note("Nothing read yet. Paste the text and press 'Read the cards'."))
	for d: Dictionary in _found:
		var row: HBoxContainer = UIUtil.hbox(6)
		var cb: CheckBox = UIUtil.check("", true)
		row.add_child(cb)
		_ticks.append(cb)
		var sizes: int = (d.get("options", []) as Array).size()
		var text: String = "%s  %s   (%s, %d size%s, %d weapon%s%s)" % [str(d["id"]), str(d["name"]), str(d["category"]),
				sizes, "" if sizes == 1 else "s", (d["weapons"] as Array).size(), "" if (d["weapons"] as Array).size() == 1 else "s",
				", transport" if bool(d.get("is_attachment", false)) else ""]
		var l: Label = UIUtil.label(text)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.tooltip_text = text
		row.add_child(l)
		var f: String = fate(d)
		var short: String = "new" if f == "new" else ("replaces original" if f.begins_with("replaces the original") else "replaces yours")
		var fl: Label = UIUtil.label(short, UIUtil.GOOD if f == "new" else UIUtil.WARN)
		fl.tooltip_text = f
		fl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(fl)
		_list.add_child(row)
	get_ok_button().disabled = _found.is_empty()


## Saves the ticked cards. Returns how many were imported.
func import_ticked() -> int:
	var chosen: Array = []
	var ids: PackedStringArray = []
	for i in _found.size():
		if i < _ticks.size() and (_ticks[i] as CheckBox).button_pressed:
			chosen.append(_found[i])
			ids.append(str((_found[i] as Dictionary)["id"]))
	if chosen.is_empty():
		_status.text = "No card is ticked."
		return 0
	var err: String = UnitDatabase.save_custom_many(chosen)
	if err != "":
		_status.text = err
		return 0
	imported.emit(ids)
	hide()
	queue_free()
	return chosen.size()


## Opens the window over `host` with `nation_name` picked.
static func open(host: Node, nation_name: String = "") -> CardImportDialog:
	var d: CardImportDialog = CardImportDialog.new()
	host.add_child(d)
	d.set_nation(nation_name)
	d.popup_centered()
	return d
