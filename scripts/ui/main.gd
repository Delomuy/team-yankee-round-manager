extends Control
## Root of the program "TY helper". Opens on the start menu (MainMenu); its buttons open the sections Cards (browse
## every card), Formations (make and change formations), Armies (army building with points), Battle (the round manager), Test range (two test units) and
## Settings. The sections live in a TabContainer with its tab bar hidden; the bar on top leads back to the menu
## and to the other sections.

const SECTIONS := ["Menu", "Cards", "Formations", "Armies", "Battle", "Test range", "Settings"]

var _tabs: TabContainer
var _nav: HBoxContainer
var _nav_frame: Control
var _nav_buttons: Dictionary = {}               # section name -> Button
var _menu: MainMenu
var _builder: ArmyBuilderScreen
var _battle: Control = null
var _formations_dirty: bool = false             # formations were edited since the Armies section was last shown
var _cards: CardBrowser
var _cards_formations: FormationEditor          # the Cards tab's "Formation editing" mode
var _formations: FormationsSection


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = AppTheme.build()                       # parchment look for the whole interface
	get_window().theme = theme                     # also popups added straight to the window (confirmations ...)
	get_window().title = AppSettings.PROGRAM_NAME
	var backdrop: Panel = Panel.new()
	backdrop.add_theme_stylebox_override("panel", Paper.style(Color(0.97, 0.96, 0.93)))
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var root: VBoxContainer = UIUtil.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# ---- navigation bar (hidden on the menu)
	_nav = UIUtil.hbox(6)
	for s: String in SECTIONS:
		var b: Button = UIUtil.button("< Menu" if s == "Menu" else s, open_section.bind(s))
		b.custom_minimum_size = Vector2(110, 34)
		b.toggle_mode = true
		_nav_buttons[s] = b
		_nav.add_child(b)
	_nav_frame = UIUtil.paper_frame(_nav, AppTheme.EDGE, 6, 8, 4, 1)
	root.add_child(_nav_frame)

	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_menu = MainMenu.new()
	_menu.name = "Menu"
	_menu.open_requested.connect(open_section)
	_tabs.add_child(_menu)

	# Cards: the card list, and its "Formation editing" mode (a formation editor next to the same kind of card grid)
	var cards_page: VBoxContainer = UIUtil.vbox(0)
	cards_page.name = "Cards"
	_cards = CardBrowser.new()
	_cards.name = "CardList"
	_cards.card_editing = true                        # New card, Import cards, New nation, Edit / Copy / Delete
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.formation_mode_requested.connect(_on_formation_mode)
	cards_page.add_child(_cards)
	_cards_formations = FormationEditor.new()
	_cards_formations.name = "CardFormationEditor"
	_cards_formations.visible = false
	_cards_formations.set_back_text("< Back to the cards")
	_cards_formations.back_requested.connect(func() -> void:
		_cards_formations.visible = false
		_cards.visible = true)
	_cards_formations.formations_changed.connect(func() -> void: _formations_dirty = true)
	cards_page.add_child(_cards_formations)
	_tabs.add_child(cards_page)

	_formations = FormationsSection.new()            # nations -> formations -> preview -> editor
	_formations.name = "Formations"
	_formations.formations_changed.connect(func() -> void: _formations_dirty = true)
	_tabs.add_child(_formations)

	_builder = ArmyBuilderScreen.new()
	_builder.name = "Armies"
	_builder.battle_requested.connect(_start_battle)
	_tabs.add_child(_builder)

	_set_battle_tab(_placeholder())

	var lab: TestLab = TestLab.new()                # two configurable test units to try every rule situation
	lab.name = "Test range"
	_tabs.add_child(lab)

	var settings: SettingsScreen = SettingsScreen.new()
	settings.name = "Settings"
	settings.title_changed.connect(_menu.refresh_title)
	_tabs.add_child(settings)

	open_section("Menu")


## Shows a section ("Menu", "Cards", "Formations", "Armies", "Battle", "Test range", "Settings").
func open_section(section: String) -> void:
	var idx: int = SECTIONS.find(section)
	if idx < 0:
		return
	if section == "Armies" and _formations_dirty:
		_formations_dirty = false
		_builder.formations_changed()
	if section == "Formations":
		_formations.refresh_page()                  # formations or nations may have changed in the Cards tab
	_tabs.current_tab = idx
	_nav_frame.visible = section != "Menu"
	for s in _nav_buttons:
		(_nav_buttons[s] as Button).set_pressed_no_signal(s == section)


## Cards > "Formation editing": the formation editor takes the place of the card list (Back returns to it).
func _on_formation_mode(nation: String) -> void:
	_cards.visible = false
	_cards_formations.visible = true
	_cards_formations.open_for(nation if nation != "" else _cards_formations.nation())


func _placeholder() -> Control:
	var l: Label = Label.new()
	l.text = "No battle yet. Build the armies in Armies and press 'Start battle'."
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _set_battle_tab(node: Control) -> void:
	if _battle != null:
		_tabs.remove_child(_battle)
		_battle.queue_free()
	_battle = node
	_battle.name = "Battle"
	_tabs.add_child(_battle)
	_tabs.move_child(_battle, SECTIONS.find("Battle"))   # keep the order of SECTIONS


func _start_battle() -> void:
	var state: BattleState = BattleState.new()
	var names: Array = []
	for i in ArmyManager.armies.size():
		names.append((ArmyManager.armies[i] as Army).army_name)
	state.setup(names, ArmyManager.battle_teams)
	var screen: BattleScreen = BattleScreen.new()
	_set_battle_tab(screen)
	screen.start(state)
	screen.back_requested.connect(open_section.bind("Armies"))
	open_section("Battle")
