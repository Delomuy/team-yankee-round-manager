class_name NationDialog
extends ConfirmationDialog
## "New nation...": adds a nation to the program (NationDB): its name as written on the cards, the name shown, the
## file prefix of its files (made from the name) and the colour of its cards. Opened from the Cards tab, the card
## import window, the card editor and the Formations overview. Emits `created(name)`.

signal created(nation: String)

var _name: LineEdit
var _label: LineEdit
var _prefix: LineEdit
var _color: ColorPickerButton
var _status: Label
var _prefix_typed: bool = false


func _init() -> void:
	title = "New nation"
	ok_button_text = "Add nation"
	dialog_hide_on_ok = false
	var g: GridContainer = GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 8)
	g.add_child(UIUtil.label("Name on the cards:"))
	_name = LineEdit.new()
	_name.placeholder_text = "French"
	_name.custom_minimum_size = Vector2(260, 0)
	_name.text_changed.connect(_on_name_changed)
	g.add_child(_name)
	g.add_child(UIUtil.label("Shown as:"))
	_label = LineEdit.new()
	_label.placeholder_text = "France (empty = the name)"
	g.add_child(_label)
	g.add_child(UIUtil.label("File prefix:"))
	_prefix = LineEdit.new()
	_prefix.placeholder_text = "france"
	_prefix.text_changed.connect(func(_t: String) -> void:
		_prefix_typed = true
		_check())
	g.add_child(_prefix)
	g.add_child(UIUtil.label("Card colour:"))
	_color = ColorPickerButton.new()
	_color.color = Color.html("#4a5a8a")
	_color.custom_minimum_size = Vector2(120, 32)
	_color.edit_alpha = false
	g.add_child(_color)
	var v: VBoxContainer = UIUtil.vbox(8)
	v.add_child(g)
	var note: Label = UIUtil.note("The name is what the cards say in their 'nation' field (no spaces needed, e.g. WestGerman). "
			+ "Its cards are saved in data/custom/<prefix>_units.json and its formations in data/formations/<prefix>_formation_data.json.")
	note.custom_minimum_size = Vector2(420, 0)
	v.add_child(note)
	_status = UIUtil.label("", UIUtil.BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 0)
	v.add_child(_status)
	add_child(v)
	get_ok_button().pressed.connect(_on_ok)
	canceled.connect(queue_free)
	_check()


func _on_name_changed(text: String) -> void:
	if not _prefix_typed:
		_prefix.set_block_signals(true)
		_prefix.text = NationDB.prefix_for_name(text) if text.strip_edges() != "" else ""
		_prefix.set_block_signals(false)
	_check()


func _check() -> void:
	var p: String = NationDB.add_problem(_name.text, _prefix.text.strip_edges())
	_status.text = p
	get_ok_button().disabled = p != ""


func _on_ok() -> void:
	var err: String = NationDB.add(_name.text, _label.text, _prefix.text.strip_edges(), _color.color)
	if err != "":
		_status.text = err
		return
	var nm: String = _name.text.strip_edges()
	hide()
	created.emit(nm)
	queue_free()


## Opens the window over `host`; `on_created` is called with the new nation's name.
static func open(host: Node, on_created: Callable = Callable()) -> NationDialog:
	var d: NationDialog = NationDialog.new()
	if on_created.is_valid():
		d.created.connect(on_created)
	host.add_child(d)
	d.popup_centered()
	return d
