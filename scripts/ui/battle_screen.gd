class_name BattleScreen
extends VBoxContainer
## The round manager for 2 to 4 players in teams.
##   - top: round, whose turn it is and the step, with the "Next step" button
##   - turn strip: every team in turn order, the one playing now highlighted
##   - left: one block per team with its players (in the colour of their army card), their points (and points lost)
##     and every unit as a grid of model tiles: icon, code ("IA3" = third model of infantry unit A) and name.
##     Click a unit's name to see which weapons each model fires, to change that ("Weapons per model...") and to
##     set the icon of its models ("Set icon...")
## Round 0 comes first: the set-up of who rides in or on which vehicle (DeployPanel).
##   - right: the panel of the current step and the event log
## A turn belongs to a team: all its players act in each step, and every other team is the enemy.

signal back_requested

const ACTIVE := Color(0.62, 0.42, 0.05)        # gold-brown: the team playing now

var state: BattleState
var back_text: String = "Edit armies"            # the Test range changes this to "Test settings"

var _header: RichTextLabel
var _next_btn: Button
var _strip: HBoxContainer
var _step_holder: VBoxContainer
var _teams_box: VBoxContainer
var _log: RichTextLabel


func start(s: BattleState) -> void:
	state = s
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	# ---- top bar
	var top: HBoxContainer = UIUtil.hbox(10)
	_header = RichTextLabel.new()
	_header.bbcode_enabled = true
	_header.fit_content = true
	_header.scroll_active = false
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_theme_color_override("default_color", UIUtil.INK)
	top.add_child(_header)
	top.add_child(UIUtil.button(back_text, func() -> void: back_requested.emit()))
	_next_btn = UIUtil.button("Next step", _on_next)
	_next_btn.custom_minimum_size = Vector2(260, 38)
	top.add_child(_next_btn)
	add_child(top)

	# ---- turn strip
	_strip = UIUtil.hbox(6)
	add_child(_strip)

	# ---- body
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(372, 0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_teams_box = UIUtil.vbox(10)
	_teams_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_teams_box)
	split.add_child(left_scroll)

	var right: VSplitContainer = VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.split_offset = 170                       # the step panel gets most of the height; drag the bar to change it
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	_step_holder = UIUtil.vbox(6)
	_step_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_step_holder)
	right.add_child(scroll)

	var log_box: VBoxContainer = UIUtil.vbox(2)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var log_top: HBoxContainer = UIUtil.hbox(8)
	log_top.add_child(UIUtil.label("Event log (every roll is shown here)"))
	log_top.add_child(UIUtil.button("Clear log", func() -> void: _log.clear()))
	log_box.add_child(log_top)
	_log = UIUtil.rich(120)
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_child(_log)
	right.add_child(log_box)
	split.add_child(right)
	add_child(split)

	for line in state.log_history:
		_log.append_text(str(line) + "\n")
	state.log_added.connect(_on_log)
	state.state_changed.connect(_update_teams)
	state.phase_changed.connect(_on_phase_changed)
	_on_phase_changed()
	_update_teams()


func _on_log(line: String) -> void:
	_log.append_text(line + "\n")


func _on_next() -> void:
	state.next_phase()


func _on_phase_changed() -> void:
	_update_header()
	_update_strip()
	_show_phase()


func _update_header() -> void:
	if state.in_setup():
		_header.text = "[font_size=22][b]Round 0[/b]  -  [color=#8a5a00]Set-up: transports[/color][/font_size]"
		_next_btn.text = "Start round 1 (%s plays first)" % state.team_label(state.active_team())
		return
	_header.text = "[font_size=22][b]Round %d[/b]  -  %s  -  [color=#8a5a00]%s[/color][/font_size]" % [
			state.round_number, state.team_tag(state.active_team()), state.phase_name()]
	if state.phase == BattleState.Phase.ASSAULT:
		_next_btn.text = "End turn (%s plays next)" % state.team_label(state.next_team())
	else:
		_next_btn.text = "Next step: %s" % BattleState.PHASE_NAMES[state.phase + 1]


## The teams in turn order; the one playing now is highlighted.
func _update_strip() -> void:
	UIUtil.clear_children(_strip)
	_strip.add_child(UIUtil.label("Turn order:"))
	for i in state.turn_order.size():
		var team: int = int(state.turn_order[i])
		var on: bool = team == state.active_team() and not state.in_setup()
		var pill: PanelContainer = PanelContainer.new()
		pill.add_theme_stylebox_override("panel", AppTheme.box(_team_color(team), ACTIVE if on else AppTheme.CLEAR, 3 if on else 0, 10, 12, 4))
		var text: String = state.team_label(team)
		pill.add_child(UIUtil.bold_label(("> %s <" % text) if on else text, 13, Color.WHITE))
		_strip.add_child(pill)
		if i < state.turn_order.size() - 1:
			_strip.add_child(UIUtil.label(">"))


func _show_phase() -> void:
	UIUtil.clear_children(_step_holder)
	var panel: StepPanel = null
	if state.in_setup():
		panel = DeployPanel.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_step_holder.add_child(panel)
		panel.setup(state)
		return
	match state.phase:
		BattleState.Phase.STARTING:
			panel = StartingPanel.new()
		BattleState.Phase.MOVEMENT:
			panel = MovementPanel.new()
		BattleState.Phase.SHOOTING:
			panel = ShootingPanel.new()
		BattleState.Phase.ARTILLERY:
			panel = ArtilleryPanel.new()
		BattleState.Phase.ASSAULT:
			panel = AssaultPanel.new()
	if panel == null:
		return
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_holder.add_child(panel)
	panel.setup(state)


## A team of one player has that player's colour; a bigger team is brown.
func _team_color(team: int) -> Color:
	var players: Array = state.team_players(team)
	if players.size() == 1:
		return state.player_color(int(players[0]))
	return AppTheme.BROWN


## One block per team: title bar (points, points lost), then every player with each unit as a grid of model tiles.
func _update_teams() -> void:
	UIUtil.clear_children(_teams_box)
	for t in state.turn_order:
		var team: int = int(t)
		var on: bool = team == state.active_team() and not state.in_setup()
		var players: Array = state.team_players(team)
		var v: VBoxContainer = UIUtil.vbox(4)
		var title: String = BattleState.TEAM_NAMES[team] if players.size() > 1 else str(state.player_names[players[0]])
		var caption: String = "%s%d pts  -  %d lost" % ["PLAYING NOW  -  " if on else "", state.team_points_total(team), state.team_points_lost(team)]
		v.add_child(UIUtil.title_bar(title, caption, _team_color(team), 17))
		for p in players:
			_add_player(v, int(p), players.size() > 1)
		_teams_box.add_child(UIUtil.paper_frame(v, ACTIVE if on else AppTheme.EDGE, 10, 6, 6, 4 if on else 2))


func _add_player(v: VBoxContainer, player: int, show_name: bool) -> void:
	var color: Color = state.player_color(player)
	if show_name:
		v.add_child(UIUtil.title_bar(str(state.player_names[player]),
				"%d pts  -  %d lost" % [state.points_total(player), state.points_lost(player)], color, 14))
	var prefix: String = str(state.player_names[player]) + ": "
	var list: Array = state.units[player]
	for i in list.size():
		var u: UnitInstance = list[i]
		var extra: String = ""
		if u.moved() and not u.is_destroyed():
			extra = "  -  %s %dcm" % [UnitInstance.MOVE_NAMES[u.move_mode], u.move_distance]
		var btn: Button = Button.new()                    # the unit's name: click for its models, weapons and icon
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.clip_text = true
		btn.text = "%s  -  %s%s" % [u.label.trim_prefix(prefix), u.status_text(), extra]
		btn.tooltip_text = "Click: the models of this unit, their weapons and their icon"
		btn.add_theme_font_override("font", UIUtil.bold_font())
		btn.add_theme_font_size_override("font_size", 12)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(key, Color(0.45, 0.45, 0.45) if u.is_destroyed() else UIUtil.INK)
		btn.pressed.connect(_open_unit.bind(u))
		v.add_child(btn)
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.add_theme_constant_override("v_separation", 5)
		for m in u.teams:
			flow.add_child(ModelTile.new().setup(u, m, color))
		v.add_child(flow)


## A unit's name was clicked: its models, what each one can fire, "Weapons per model..." and the icon buttons.
func _open_unit(u: UnitInstance) -> void:
	var dlg: AcceptDialog = AcceptDialog.new()
	dlg.title = u.label
	dlg.ok_button_text = "Close"
	dlg.add_button("Weapons per model...", false, "weapons")
	dlg.add_button("Set icon...", false, "icon")
	dlg.add_button("Remove icon", false, "no_icon")
	dlg.add_button("Show card", false, "card")
	var r: RichTextLabel = UIUtil.rich(260)
	r.custom_minimum_size = Vector2(660, 320)
	r.add_theme_color_override("default_color", UIUtil.INK)
	r.text = models_bbcode(u)
	dlg.add_child(UIUtil.paper_frame(r, AppTheme.EDGE, 6, 10, 8, 2))
	add_child(dlg)
	dlg.custom_action.connect(_on_unit_action.bind(u, r))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_unit_action(action: StringName, u: UnitInstance, r: RichTextLabel) -> void:
	if action == &"card":
		CardView.popup(u.data, self)
	elif action == &"weapons":
		var dlg: ModelWeaponsDialog = ModelWeaponsDialog.new().setup(u.data)
		add_child(dlg)
		dlg.saved.connect(_on_weapons_saved.bind(u, r))
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		dlg.popup_centered()
	elif action == &"icon":
		var fd: FileDialog = FileDialog.new()
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.title = "Choose the icon for the models of %s" % u.data.display_name
		fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		fd.use_native_dialog = true
		fd.file_selected.connect(_on_icon_chosen.bind(u))
		add_child(fd)
		fd.popup_centered_ratio(0.7)
	elif action == &"no_icon":
		ModelIcons.clear_icon(String(u.data.id))
		_refresh_icons()


func _on_icon_chosen(path: String, u: UnitInstance) -> void:
	var err: Error = ModelIcons.set_icon(String(u.data.id), path)
	if err != OK:
		state.log_line("[color=#b35a00](!) That file could not be read as a picture.[/color]")
	_refresh_icons()


## New icons: redraw the model tiles on the left and in the step panel.
func _refresh_icons() -> void:
	_update_teams()
	_show_phase()


func _on_weapons_saved(u: UnitInstance, r: RichTextLabel) -> void:
	state.refresh_model_weapons()
	if is_instance_valid(r):
		r.text = models_bbcode(u)


## Every model of a unit with its code, state and the weapons it can fire.
static func models_bbcode(u: UnitInstance) -> String:
	var t: String = "[font_size=20][b]%s[/b][/font_size]\n%s\n\n" % [TYRules.esc(u.label), u.status_text()]
	for m in u.teams:
		var names: PackedStringArray = []
		for wi in m.weapons:
			if int(wi) < u.data.weapons.size():
				names.append(u.data.weapons[int(wi)].weapon_name)
		var extra: String = ""
		if m.mounted():
			extra = "  [color=#1b5fa8]%s[/color]" % m.place_text()
		if m.is_vehicle and m.capacity > 0:
			extra += "  [color=#6b6b6b]carries %d[/color]" % m.capacity
		t += "[b]%s[/b]  %s  -  %s%s\n" % [m.code, TYRules.esc(m.kind), m.status_text(), extra]
		t += "      [color=#555555]fires: %s[/color]\n" % (TYRules.esc(", ".join(names)) if not names.is_empty() else "nothing")
	return t
