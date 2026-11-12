class_name ArmyBuilderScreen
extends VBoxContainer
## The Armies tab. Four pages:
##   1. each player's name, main army (nation), points limit and whether the army uses a formation (with the formation
##      picked in a drop-down beside the tick box); the + and - buttons under the list add and remove players
##   2. the overview: one block per player (units, points, models, unit-type split); click a block to edit that army.
##      Under the block of an army with a formation: its formation section (name, points, what is missing, Edit)
##   3. the army editor (card selector on the left, the army as small cards on the right)
##   4. the formation screen (FormationScreen): HQ and compulsory units at the top, additional units below
##   5. the saved armies (SavedArmiesPage): save, load, import and delete armies in saved_army/ (ArmyFiles)
## With Settings > Use formations on, every army has a formation ("Uses a formation" is always ticked).
## "Start battle" hands two armies to the round manager (it asks which two when there are more than two players).

signal battle_requested

var _setup_page: VBoxContainer
var _overview_page: VBoxContainer
var _editor: ArmyEditor
var _formation: FormationScreen
var _saved: SavedArmiesPage
var _blocks: HFlowContainer
var _dyn: CheckBox
var _status: Label
var _setup_rows: Array = []       # per player: {"name": LineEdit, "nation": OptionButton, "limit": SpinBox}


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_page = UIUtil.vbox(10)
	_setup_page.size_flags_vertical = Control.SIZE_EXPAND_FILL       # without this the scroll area below collapses to nothing
	add_child(_setup_page)
	_overview_page = _build_overview_page()
	add_child(_overview_page)
	_editor = ArmyEditor.new()
	_editor.back_requested.connect(_show_overview)
	add_child(_editor)
	_formation = FormationScreen.new()
	_formation.back_requested.connect(_show_overview)
	add_child(_formation)
	_saved = SavedArmiesPage.new()
	_saved.back_requested.connect(_show_overview)
	_saved.roster_changed.connect(_on_roster_changed)
	_saved.army_saved.connect(func() -> void:
		if _overview_page.visible:
			_show_overview())
	add_child(_saved)
	ArmyManager.roster_changed.connect(_on_roster_changed)
	if ArmyManager.roster.is_empty():
		ArmyManager.set_player_count(2)               # two armies: American and Soviet (ArmyManager.DEFAULT_NATIONS)
		_build_setup_page()
		_show_page(_setup_page)
	else:
		_show_overview()


## Called by main when formations were made, changed or deleted in the Formations section: redraws the page that
## shows formations (the drop-downs of page 1, the formation sections of page 2; the formation screen goes back to
## the overview).
func formations_changed() -> void:
	if _setup_page.visible:
		_save_setup()
		_build_setup_page()
	elif _overview_page.visible or _formation.visible:
		_show_overview()


func _show_page(page: Control) -> void:
	for p: Control in [_setup_page, _overview_page, _editor, _formation, _saved]:
		p.visible = p == page


## Page 5: the saved armies (save, load, import, delete).
func show_saved() -> void:
	if _setup_page.visible:
		_save_setup()
	_saved.refresh()
	_show_page(_saved)


## Armies were loaded, or closed by Settings > Use formations: redraw the page that is shown (without copying the
## set-up rows back, they belong to the old roster).
func _on_roster_changed() -> void:
	if _setup_page.visible:
		_build_setup_page()
	elif _saved.visible:
		_saved.refresh()
	else:
		_show_overview()


# ------------------------------------------------------------------ page 1: players and main armies

func _build_setup_page() -> void:
	UIUtil.clear_children(_setup_page)
	_setup_rows.clear()
	_setup_page.add_child(UIUtil.bold_label("MAIN ARMY OF EACH PLAYER", 26, AppTheme.BROWN))
	_setup_page.add_child(UIUtil.note("Choose a name and the nation each player is leading. The card selector starts on that nation; "
			+ "you can still pick cards from any other nation (allies) while building the list. Use + and - to add or remove players "
			+ "(a battle is fought between two armies; with more players you choose which two fight when you press Start battle)."))
	var nations: Array = UnitDatabase.get_nations()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	for h in ["Player", "Name", "Main army", "Points limit (0 = none)", "Formation"]:
		grid.add_child(UIUtil.bold_label(String(h).to_upper(), 12, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	for i in ArmyManager.roster.size():
		var army: Army = ArmyManager.roster[i]
		grid.add_child(UIUtil.bold_label("Player %d" % (i + 1), 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var name_edit: LineEdit = LineEdit.new()
		name_edit.text = army.army_name
		name_edit.custom_minimum_size = Vector2(220, 0)
		grid.add_child(name_edit)
		var nation_opt: OptionButton = OptionButton.new()
		nation_opt.custom_minimum_size = Vector2(190, 0)
		for n in nations:
			nation_opt.add_item(RulesDB.nation_label(String(n)))
		var at: int = nations.find(army.nation)
		nation_opt.select(at if at >= 0 else i % maxi(nations.size(), 1))
		grid.add_child(nation_opt)
		var limit: SpinBox = UIUtil.spin(0, 5000, army.points_limit)
		grid.add_child(limit)
		# ---- formation: tick box, and beside it the formations of the row's main army
		var frow: HBoxContainer = UIUtil.hbox(6)
		var use: CheckBox = UIUtil.check("Uses a formation", army.use_formations)
		for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			use.add_theme_color_override(key, UIUtil.INK)
		frow.add_child(use)
		var form_opt: OptionButton = UIUtil.narrow(OptionButton.new(), 400)
		frow.add_child(form_opt)
		grid.add_child(frow)
		var row: Dictionary = {"name": name_edit, "nation": nation_opt, "limit": limit, "use": use, "formation": form_opt, "fids": []}
		_setup_rows.append(row)
		_fill_formations(row, army)
		use.toggled.connect(_on_use_formation_toggled.bind(row))
		nation_opt.item_selected.connect(_on_setup_nation_changed.bind(row))
	# the rows, then right under them the + / - and the page buttons (they used to sit at the bottom of the screen)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body: VBoxContainer = UIUtil.vbox(12)
	body.add_child(grid)
	scroll.add_child(body)
	_setup_page.add_child(scroll)
	var count_row: HBoxContainer = UIUtil.hbox(8)
	var minus: Button = UIUtil.button("-", _on_remove_player)
	minus.custom_minimum_size = Vector2(46, 38)
	minus.disabled = ArmyManager.roster.size() <= 2
	minus.tooltip_text = "Remove the last player"
	var plus: Button = UIUtil.button("+", _on_add_player)
	plus.custom_minimum_size = Vector2(46, 38)
	plus.disabled = ArmyManager.roster.size() >= ArmyManager.MAX_PLAYERS
	plus.tooltip_text = "Add a player"
	count_row.add_child(minus)
	count_row.add_child(plus)
	count_row.add_child(UIUtil.bold_label("%d players" % ArmyManager.roster.size(), 16, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	body.add_child(count_row)
	var btns: HBoxContainer = UIUtil.hbox(8)
	btns.add_child(UIUtil.button("Create armies >", _on_setup_done))
	btns.add_child(UIUtil.button("Saved armies...", show_saved))
	body.add_child(btns)
	if AppSettings.use_formations():
		body.add_child(UIUtil.note("Settings > Use formations is on: every army has a formation (pick it beside the "
				+ "nation). Armies without one cannot be made or loaded."))


## Fills a row's formation drop-down with the formations of the nation picked in that row. The drop-down is shown
## only while "Uses a formation" is ticked; a nation without formations disables the tick box.
func _fill_formations(row: Dictionary, army: Army = null) -> void:
	var nations: Array = UnitDatabase.get_nations()
	var nation_opt: OptionButton = row["nation"]
	var nation: String = String(nations[nation_opt.selected]) if nation_opt.selected >= 0 and nation_opt.selected < nations.size() else ""
	var opt: OptionButton = row["formation"]
	var use: CheckBox = row["use"]
	var keep: String = ""
	if opt.selected >= 0 and opt.selected < (row["fids"] as Array).size():
		keep = str(row["fids"][opt.selected])
	elif army != null and army.main_formation() != null:
		keep = army.main_formation().id
	opt.clear()
	var fids: Array = []
	for f: FormationData in FormationDB.for_nation(nation):
		opt.add_item(f.full_name())
		fids.append(f.id)
	row["fids"] = fids
	var at: int = fids.find(keep)
	if not fids.is_empty():
		opt.select(at if at >= 0 else 0)
	use.disabled = fids.is_empty()
	use.tooltip_text = "No formations for %s yet (data/formations)." % RulesDB.nation_label(nation) if fids.is_empty() else ""
	if fids.is_empty():
		use.set_pressed_no_signal(false)
	if AppSettings.use_formations():                 # every army must have a formation: always ticked
		use.set_pressed_no_signal(not fids.is_empty())
		use.disabled = true
		use.tooltip_text = "Settings > Use formations is on: every army has a formation." if not fids.is_empty() \
				else "%s has no formations, and Settings > Use formations is on: pick another nation." % RulesDB.nation_label(nation)
	opt.visible = use.button_pressed and not fids.is_empty()


func _on_use_formation_toggled(_on: bool, row: Dictionary) -> void:
	_fill_formations(row)


func _on_setup_nation_changed(_idx: int, row: Dictionary) -> void:
	_fill_formations(row)


## Copies what is typed in the rows into the armies (also the formation: a new choice replaces the old formation
## and its units; unticking removes the formation).
func _save_setup() -> void:
	var nations: Array = UnitDatabase.get_nations()
	for i in mini(ArmyManager.roster.size(), _setup_rows.size()):
		var army: Army = ArmyManager.roster[i]
		var row: Dictionary = _setup_rows[i]
		var nm: String = (row["name"] as LineEdit).text.strip_edges()
		army.army_name = nm if nm != "" else "Player %d" % (i + 1)
		army.nation = String(nations[(row["nation"] as OptionButton).selected])
		army.points_limit = int((row["limit"] as SpinBox).value)
		var fids: Array = row["fids"]
		var opt: OptionButton = row["formation"]
		if (row["use"] as CheckBox).button_pressed and opt.selected >= 0 and opt.selected < fids.size():
			army.use_formations = true
			army.set_main_formation(str(fids[opt.selected]))
		else:
			army.set_main_formation("")
			army.use_formations = false


func _on_add_player() -> void:
	_save_setup()
	ArmyManager.set_player_count(ArmyManager.roster.size() + 1)
	_build_setup_page()


func _on_remove_player() -> void:
	_save_setup()
	ArmyManager.set_player_count(ArmyManager.roster.size() - 1)
	_build_setup_page()


func _on_setup_done() -> void:
	_save_setup()
	_show_overview()


# ------------------------------------------------------------------ page 2: overview

func _build_overview_page() -> VBoxContainer:
	var v: VBoxContainer = UIUtil.vbox(8)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top: HBoxContainer = UIUtil.hbox(12)
	top.add_child(UIUtil.heading("Armies"))
	_dyn = UIUtil.check("Use dynamic points", ArmyManager.use_dynamic_points)
	_dyn.toggled.connect(_on_dynamic_toggled)
	top.add_child(_dyn)
	_status = UIUtil.label("")
	UIUtil.expand(_status)
	top.add_child(_status)
	top.add_child(UIUtil.button("Players / main armies", _show_setup))
	top.add_child(UIUtil.button("Saved armies...", show_saved))
	var start: Button = UIUtil.button("Start battle", _on_start)
	start.custom_minimum_size = Vector2(170, 38)
	top.add_child(start)
	v.add_child(top)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_blocks = HFlowContainer.new()
	_blocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blocks.add_theme_constant_override("h_separation", 16)
	_blocks.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_blocks)
	v.add_child(scroll)
	return v


func _show_setup() -> void:
	_build_setup_page()
	_show_page(_setup_page)


func _show_overview() -> void:
	UIUtil.clear_children(_blocks)
	for i in ArmyManager.roster.size():
		var col: VBoxContainer = UIUtil.vbox(6)
		var block: PlayerBlock = PlayerBlock.new().setup(i, ArmyManager.roster[i])
		block.opened.connect(_open_editor)
		col.add_child(block)
		var army: Army = ArmyManager.roster[i]
		if army.use_formations:
			col.add_child(_formation_section(i, army))
		col.add_child(_save_row(i, army))
		_blocks.add_child(col)
	_dyn.set_pressed_no_signal(ArmyManager.use_dynamic_points)
	_show_page(_overview_page)


## The formation section under an army's block: formation name, points, what is still missing, and the button that
## opens the formation screen.
func _formation_section(index: int, army: Army) -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	v.custom_minimum_size = Vector2(330, 0)
	v.add_child(UIUtil.bold_label("FORMATION", 12, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	var f: FormationData = army.main_formation()
	var key: String = army.main_formation_key()
	if f == null:
		v.add_child(UIUtil.label("No formation chosen (Players / main armies page).", UIUtil.BAD))
	else:
		if f.division != "":
			v.add_child(UIUtil.label(f.division, AppTheme.BROWN))
		v.add_child(UIUtil.bold_label("%s   %d pts" % [f.name, army.formation_points(key)], 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var problems: PackedStringArray = army.formation_problems(key)
		var state: Label = UIUtil.label("Ready to field." if problems.is_empty() else "Missing: " + "; ".join(problems),
				UIUtil.GOOD if problems.is_empty() else UIUtil.BAD)
		state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(state)
	var b: Button = UIUtil.button("Edit formation", _open_formation.bind(index))
	b.disabled = FormationDB.for_nation(army.nation).is_empty()
	v.add_child(b)
	var color: Color = UnitSheet.color_for(army.nation) if army.nation != "" else AppTheme.BROWN
	return UIUtil.paper_frame(v, color, 10, 10, 8, 2)


## Under each army: whether it is saved, and Save army (to saved_army/NAME_NATION_army.json).
func _save_row(index: int, army: Army) -> Control:
	var row: HBoxContainer = UIUtil.hbox(8)
	var b: Button = UIUtil.button("Save army", _saved.save_player.bind(index))
	b.tooltip_text = "Save to %s" % ArmyFiles.file_name(army)
	row.add_child(b)
	var l: Label = UIUtil.label(SavedArmiesPage.saved_text(army), UIUtil.GOOD if army.is_saved() else Color(0.35, 0.35, 0.35))
	l.custom_minimum_size = Vector2(220, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	return row


func _open_editor(index: int) -> void:
	_editor.open_player(index)
	_show_page(_editor)


func _open_formation(index: int) -> void:
	_formation.open_player(index)
	_show_page(_formation)


func _on_dynamic_toggled(on: bool) -> void:
	ArmyManager.use_dynamic_points = on
	_show_overview()


# ------------------------------------------------------------------ battle

func _on_start() -> void:
	if ArmyManager.roster.size() == 2:
		_launch([0, 1], [0, 1])
	else:
		_ask_teams()


## More than two players: who plays (2 to 4 of them) and in which team. Players with the same team fight together,
## so 2v2, 3v1, 2v1, 1v1v1, 2v1v1 or everyone against everyone are all possible.
func _ask_teams() -> void:
	var dlg: AcceptDialog = AcceptDialog.new()
	dlg.title = "Teams for this battle"
	dlg.ok_button_text = "Start battle"
	dlg.add_cancel_button("Cancel")
	var v: VBoxContainer = UIUtil.vbox(8)
	v.add_child(UIUtil.heading("Who fights, and in which team?"))
	var note: Label = UIUtil.note("Give every player a team. Players with the same team fight together and play their turn together; "
			+ "every other team is their enemy. 2 to %d players can fight, in at least two teams. Team A plays first, then B, C, D." % BattleState.MAX_PLAYERS)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(460, 0)
	v.add_child(note)
	var picks: Array = []
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for i in ArmyManager.roster.size():
		var a: Army = ArmyManager.roster[i]
		grid.add_child(UIUtil.bold_label("%s  (%s, %d pts)" % [a.army_name, RulesDB.nation_label(a.nation), a.total_points()], 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var opt: OptionButton = OptionButton.new()
		opt.add_item("Not playing")
		for t in BattleState.TEAM_NAMES:
			opt.add_item(String(t))
		opt.select(1 + i % 2 if i < BattleState.MAX_PLAYERS else 0)        # A, B, A, B; the rest sit out
		opt.custom_minimum_size = Vector2(150, 0)
		grid.add_child(opt)
		picks.append(opt)
	v.add_child(grid)
	dlg.add_child(UIUtil.paper_frame(v, AppTheme.EDGE, 6, 14, 12, 2))
	add_child(dlg)
	dlg.confirmed.connect(_on_teams_chosen.bind(dlg, picks))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_teams_chosen(dlg: AcceptDialog, picks: Array) -> void:
	var players: Array = []
	var teams: Array = []
	for i in picks.size():
		var sel: int = (picks[i] as OptionButton).selected
		if sel > 0:
			players.append(i)
			teams.append(sel - 1)
	dlg.queue_free()
	_launch(players, teams)


## `players` = roster indexes that fight, `teams` = the team id (0-3) of each of them.
func _launch(players: Array, teams: Array) -> void:
	var problem: String = battle_problem(players, teams)
	if problem != "":
		_status.text = problem
		return
	_status.text = ""
	ArmyManager.clear()
	for i in players.size():
		ArmyManager.register_army(i, ArmyManager.roster[int(players[i])])
	ArmyManager.battle_teams = teams.duplicate()
	battle_requested.emit()


## "" when the battle can start, otherwise what is wrong.
static func battle_problem(players: Array, teams: Array) -> String:
	if players.size() < 2:
		return "At least two players must fight."
	if players.size() > BattleState.MAX_PLAYERS:
		return "A battle has at most %d players (set the others to 'Not playing')." % BattleState.MAX_PLAYERS
	var distinct: Dictionary = {}
	for t in teams:
		distinct[int(t)] = true
	if distinct.size() < 2:
		return "Everybody is in the same team: put the players in at least two teams."
	for i in players:
		var army: Army = ArmyManager.roster[int(i)]
		if army.entries.is_empty():
			return "%s has no units yet." % army.army_name
		var wrong: PackedStringArray = army.list_problems()
		if not wrong.is_empty():
			return "%s's army list is not legal yet: %s. Fix it in the army editor (or untick Settings > Limit unit quantities)." % [
					army.army_name, ";  ".join(wrong)]
	return ""
