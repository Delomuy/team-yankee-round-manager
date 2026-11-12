class_name FormationsSection
extends VBoxContainer
## The Formations section of the main menu. Four pages:
##   1. Nations:    one card per nation (its colour, how many formations, its divisions), and "+ New nation"
##   2. A nation:   one card per formation (division, name, HQ card, compulsory / optional slots, what is missing)
##                  and "+ New formation"
##   3. Preview:    the formation laid out like the army formation screen (FormationScreen.open_preview): click cards
##                  to try out choices and see the points; "Edit formation" opens the editor
##   4. Editor:     the formation editor (FormationEditor), only reached from "Edit formation" / "+ New formation"
## The Cards tab has its own "Formation editing" mode with another FormationEditor.

signal formations_changed

const NATION_CARD := Vector2(300, 190)
const FORMATION_CARD := Vector2(300, 170)

var _nations_page: VBoxContainer
var _nation_flow: HFlowContainer
var _nation_page: VBoxContainer
var _nation_title: Label
var _formation_flow: HFlowContainer
var _preview: FormationScreen
var _editor: FormationEditor
var _nation: String = ""                 # the nation shown on page 2
var _editor_from_preview: bool = false   # where the editor's Back button leads


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# ---- page 1: nations
	_nations_page = UIUtil.vbox(8)
	_nations_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var h1: HBoxContainer = UIUtil.hbox(10)
	h1.add_child(UIUtil.heading("Formations of every nation"))
	_nations_page.add_child(h1)
	_nations_page.add_child(UIUtil.note("Click a nation to see its formations. Formations are made and changed with 'Edit formation' "
			+ "(or in the Cards section: Formation editing)."))
	_nation_flow = _flow()
	_nations_page.add_child(_scrolled(_nation_flow))
	add_child(_nations_page)

	# ---- page 2: the formations of one nation
	_nation_page = UIUtil.vbox(8)
	_nation_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var h2: HBoxContainer = UIUtil.hbox(10)
	h2.add_child(UIUtil.button("< All nations", show_nations))
	_nation_title = UIUtil.heading("")
	_nation_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(_nation_title)
	h2.add_child(UIUtil.button("+ New formation", func() -> void: open_editor(_nation, "", true)))
	_nation_page.add_child(h2)
	_formation_flow = _flow()
	_nation_page.add_child(_scrolled(_formation_flow))
	add_child(_nation_page)

	# ---- page 3: preview
	_preview = FormationScreen.new()
	_preview.back_requested.connect(func() -> void: show_nation(_nation))
	_preview.edit_requested.connect(func(fid: String) -> void: open_editor(_nation, fid, false, true))
	add_child(_preview)

	# ---- page 4: editor
	_editor = FormationEditor.new()
	_editor.formations_changed.connect(func() -> void: formations_changed.emit())
	_editor.back_requested.connect(_on_editor_back)
	add_child(_editor)
	show_nations()


func _flow() -> HFlowContainer:
	var f: HFlowContainer = HFlowContainer.new()
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_theme_constant_override("h_separation", 14)
	f.add_theme_constant_override("v_separation", 14)
	return f


func _scrolled(c: Control) -> ScrollContainer:
	var s: ScrollContainer = ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.add_child(c)
	return s


func _show(page: Control) -> void:
	for p: Control in [_nations_page, _nation_page, _preview, _editor]:
		p.visible = p == page


## Redraws the page shown (when the section is opened again: formations or nations may have changed elsewhere).
func refresh_page() -> void:
	match page():
		"nations":
			show_nations()
		"nation":
			show_nation(_nation)
		"preview":
			var f: FormationData = _preview._army.main_formation() if _preview._army != null else null
			if f == null or FormationDB.get_formation(f.id) == null:
				show_nation(_nation)


## Which page is shown: "nations", "nation", "preview" or "editor".
func page() -> String:
	if _nation_page.visible:
		return "nation"
	if _preview.visible:
		return "preview"
	if _editor.visible:
		return "editor"
	return "nations"


# ------------------------------------------------------------------ page 1

func show_nations() -> void:
	UIUtil.clear_children(_nation_flow)
	for n: String in UnitDatabase.get_nations():
		_nation_flow.add_child(_nation_card(n))
	var add: Button = UIUtil.button("+ New nation", func() -> void: NationDialog.open(self, func(_n: String) -> void: show_nations()))
	add.custom_minimum_size = Vector2(200, 60)
	add.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_nation_flow.add_child(add)
	_show(_nations_page)


func _nation_card(n: String) -> Control:
	var forms: Array = FormationDB.for_nation(n)
	var filled: int = 0
	for f: FormationData in forms:
		if not f.slots.is_empty():
			filled += 1
	var v: VBoxContainer = UIUtil.vbox(4)
	v.custom_minimum_size = NATION_CARD - Vector2(20, 20)
	v.add_child(UIUtil.title_bar(RulesDB.nation_label(n).to_upper(), "", CardTile.nation_color_for(n), 20))
	v.add_child(UIUtil.bold_label("%d formation%s" % [forms.size(), "" if forms.size() == 1 else "s"], 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	v.add_child(UIUtil.label("%d with slots, %d still blank" % [filled, forms.size() - filled], Color(0.35, 0.35, 0.35)))
	var divs: PackedStringArray = FormationDB.divisions(n)
	var dl: Label = UIUtil.label("Divisions: " + (", ".join(divs) if not divs.is_empty() else "none yet"), AppTheme.BROWN)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(NATION_CARD.x - 30.0, 0)
	v.add_child(dl)
	var cards: int = 0
	for u: UnitData in UnitDatabase.units.values():
		if u.nation == n:
			cards += 1
	v.add_child(UIUtil.label("%d cards%s" % [cards, "  (added nation)" if NationDB.is_added(n) else ""], Color(0.35, 0.35, 0.35)))
	return _clickable(v, CardTile.nation_color_for(n), show_nation.bind(n), "Open the formations of %s" % RulesDB.nation_label(n))


## A framed card that does `action` when clicked.
func _clickable(content: Control, color: Color, action: Callable, tip: String) -> Control:
	var frame: PanelContainer = UIUtil.paper_frame(content, color, 10, 10, 8, 2)
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.tooltip_text = tip
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_ignore_mouse(content)
	frame.gui_input.connect(func(ev: InputEvent) -> void:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			action.call())
	return frame


func _ignore_mouse(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)


# ------------------------------------------------------------------ page 2

func show_nation(n: String) -> void:
	_nation = n
	_nation_title.text = "%s  -  formations" % RulesDB.nation_label(n)
	UIUtil.clear_children(_formation_flow)
	var list: Array = FormationDB.for_nation(n)
	list.sort_custom(func(a: FormationData, b: FormationData) -> bool: return a.full_name().naturalnocasecmp_to(b.full_name()) < 0)
	for f: FormationData in list:
		_formation_flow.add_child(_formation_card(f))
	if list.is_empty():
		_formation_flow.add_child(UIUtil.note("%s has no formations yet. Press + New formation." % RulesDB.nation_label(n)))
	_show(_nation_page)


func _formation_card(f: FormationData) -> Control:
	var v: VBoxContainer = UIUtil.vbox(3)
	v.custom_minimum_size = FORMATION_CARD - Vector2(20, 20)
	v.add_child(UIUtil.label(f.division if f.division != "" else "(no division)", AppTheme.BROWN))
	var nm: Label = UIUtil.bold_label(f.name, 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(FORMATION_CARD.x - 30.0, 0)
	v.add_child(nm)
	var hq: UnitData = f.hq_unit()
	v.add_child(UIUtil.label("HQ: %s" % (hq.display_name if hq != null else f.hq), Color(0.25, 0.25, 0.25)))
	var comp: int = 0
	for s in f.slots:
		if bool(s["compulsory"]):
			comp += 1
	v.add_child(UIUtil.label("%d compulsory, %d optional slots" % [comp, f.slots.size() - comp], Color(0.35, 0.35, 0.35)))
	var p: PackedStringArray = f.problems()
	var state: Label = UIUtil.label("Ready" if p.is_empty() else "To check: " + p[0] + ("" if p.size() == 1 else " (+%d)" % (p.size() - 1)),
			UIUtil.GOOD if p.is_empty() else UIUtil.WARN)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.custom_minimum_size = Vector2(FORMATION_CARD.x - 30.0, 0)
	v.add_child(state)
	return _clickable(v, CardTile.nation_color_for(f.nation), show_preview.bind(f.id), "Open %s" % f.full_name())


# ------------------------------------------------------------------ pages 3 and 4

func show_preview(formation_id: String) -> void:
	var f: FormationData = FormationDB.get_formation(formation_id)
	if f == null:
		show_nation(_nation)
		return
	_nation = f.nation
	_preview.open_preview(formation_id)
	_show(_preview)


## Opens the editor on `nation` / `formation_id`; `new` makes a new formation. `from_preview`: Back returns to the
## preview of that formation, otherwise to the nation page.
func open_editor(n: String, formation_id: String, new: bool, from_preview: bool = false) -> void:
	_nation = n
	_editor_from_preview = from_preview
	_editor.set_back_text("< Back to the formation" if from_preview else "< Back to %s" % RulesDB.nation_label(n))
	_show(_editor)
	if new:
		_editor.start_new(n)
	else:
		_editor.open_for(n, formation_id)


func _on_editor_back() -> void:
	var f: FormationData = _editor.current()
	if _editor_from_preview and f != null:
		show_preview(f.id)
	else:
		show_nation(f.nation if f != null else _nation)
