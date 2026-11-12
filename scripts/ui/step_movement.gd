class_name MovementPanel
extends StepPanel
## Movement Step, model by model: how each model moves and how far (a slider that stops at the card's distance for
## that kind of move), Cross tests, where infantry is (on foot, in a building, in or on a vehicle). Movement Orders
## are given per unit.

const ORDERS := [
	["", "- no order -"],
	["blitz", "Blitz Move (Skill)"],
	["follow_me", "Follow Me! (Courage)"],
	["cross_here", "Cross Here"],
	["dig_in", "Dig In (Skill, instead of Moving)"],
]
const HEADERS := ["Model", "Movement", "Distance", "Difficult terrain", "Where"]


func build() -> void:
	add_child(UIUtil.heading(player_title("Movement Step")))
	add_child(UIUtil.note("Every model moves on its own: choose how it moves and drag the slider to how far (the slider stops at the "
			+ "distance on the card for that kind of move). Roll a Cross test when a model crosses Difficult Terrain: on a fail it stops there. "
			+ "Models that Dash cannot Shoot or Assault; models that moved shoot with Moving ROF. 'Where' puts infantry in a building, or in / "
			+ "on a vehicle: a model that gets out of a vehicle cannot get into one again this game."))
	for u: UnitInstance in state.friendly_living():
		_add_unit(u)


func _add_unit(u: UnitInstance) -> void:
	var v: VBoxContainer = UIUtil.vbox(4)
	# ---- the unit: name, movement order, "all models" shortcut
	var head: HBoxContainer = UIUtil.hbox(8)
	var name_btn: Button = Button.new()
	name_btn.text = unit_text(u)
	name_btn.flat = true
	UIUtil.ink_text(name_btn)
	name_btn.add_theme_font_override("font", UIUtil.bold_font())
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.tooltip_text = "Click for the card"
	name_btn.pressed.connect(show_card.bind(u))
	head.add_child(name_btn)
	head.add_child(UIUtil.label("All models:"))
	var all_opt: OptionButton = UIUtil.option(UnitInstance.MOVE_NAMES)
	all_opt.select(u.move_mode)
	all_opt.item_selected.connect(_on_all_mode.bind(u))
	head.add_child(all_opt)
	head.add_child(UIUtil.label("Order:"))
	var order_opt: OptionButton = OptionButton.new()
	var order_idx: int = 0
	for i in ORDERS.size():
		order_opt.add_item(str(ORDERS[i][1]))
		if ORDERS[i][0] == u.order:
			order_idx = i
	order_opt.select(order_idx)
	var order_result: Label = UIUtil.label("")
	var test_btn: Button = UIUtil.button("Test", _on_order_test.bind(u, order_result))
	test_btn.disabled = not (u.order in ["blitz", "follow_me", "dig_in"])
	order_opt.item_selected.connect(_on_order.bind(u, test_btn, order_result))
	head.add_child(order_opt)
	head.add_child(test_btn)
	head.add_child(order_result)
	v.add_child(head)

	# ---- its models
	var grid: GridContainer = GridContainer.new()
	grid.columns = HEADERS.size()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for h in HEADERS:
		grid.add_child(UIUtil.label(str(h), Color(0.30, 0.22, 0.12)))
	for m in u.teams:
		if m.is_alive():
			_add_model_row(grid, u, m)
	v.add_child(grid)
	add_child(UIUtil.paper_frame(v, state.player_color(u.owner_id), 8, 8, 6, 2))


func _add_model_row(grid: GridContainer, u: UnitInstance, m: TeamState) -> void:
	var can_move: bool = m.is_active() and not m.mounted() and not m.bogged()
	var name_lbl: Label = UIUtil.bold_label(m.team_name, 13, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.custom_minimum_size = Vector2(230, 0)
	name_lbl.clip_text = true
	grid.add_child(name_lbl)

	if m.mounted():
		grid.add_child(UIUtil.label("carried: moves with %s" % m.carrier.code, Color(0.10, 0.37, 0.66)))
		grid.add_child(UIUtil.label(""))
		grid.add_child(UIUtil.label(""))
	else:
		var mode: OptionButton = UIUtil.option(UnitInstance.MOVE_NAMES)
		mode.select(m.move_mode)
		mode.disabled = not can_move
		grid.add_child(mode)

		var dist_box: HBoxContainer = UIUtil.hbox(6)
		var slider: HSlider = HSlider.new()
		slider.min_value = 0
		slider.step = 1
		slider.max_value = u.slider_limit(m.move_mode)
		slider.value = m.move_distance
		slider.editable = can_move and m.move_mode != UnitInstance.MoveMode.HALTED
		slider.custom_minimum_size = Vector2(190, 24)
		var dist_lbl: Label = UIUtil.label("")
		dist_lbl.custom_minimum_size = Vector2(96, 0)
		dist_box.add_child(slider)
		dist_box.add_child(dist_lbl)
		grid.add_child(dist_box)
		_show_distance(u, m, dist_lbl)

		var cross_box: HBoxContainer = UIUtil.hbox(6)
		var cross_btn: Button = Button.new()
		cross_btn.text = "Cross (%s)" % TYRules.needed_text(TYRules.cross_number(u))
		cross_btn.tooltip_text = "Cross Check when the model enters or starts in Difficult Going. A fail = Bogged Down until its next turn."
		cross_btn.disabled = not can_move
		var cross_result: Label = UIUtil.label("")
		if m.cross_failed:
			cross_result.text = "BOGGED DOWN"
			UIUtil.set_color(cross_result, UIUtil.BAD)
		cross_btn.pressed.connect(_on_cross.bind(u, m, cross_result))
		cross_box.add_child(cross_btn)
		cross_box.add_child(cross_result)
		grid.add_child(cross_box)

		mode.item_selected.connect(_on_mode.bind(u, m, slider, dist_lbl))
		slider.value_changed.connect(_on_dist.bind(u, m, dist_lbl))

	if not m.is_vehicle and u.is_ground():
		grid.add_child(place_option(u, m))
	else:
		grid.add_child(UIUtil.label(""))


func _show_distance(u: UnitInstance, m: TeamState, lbl: Label) -> void:
	if m.move_mode == UnitInstance.MoveMode.HALTED:
		lbl.text = "-"
		return
	var limit: int = u.movement_limit(m.move_mode)
	lbl.text = ("%d cm (no limit)" % m.move_distance) if limit < 0 else ("%d / %d cm" % [m.move_distance, limit])


func _on_mode(idx: int, u: UnitInstance, m: TeamState, slider: HSlider, dist_lbl: Label) -> void:
	m.move_mode = idx
	slider.max_value = u.slider_limit(idx)                # the slider stops at what this kind of move allows
	slider.editable = idx != UnitInstance.MoveMode.HALTED
	if idx == UnitInstance.MoveMode.HALTED:
		slider.set_value_no_signal(0)
	m.move_distance = mini(int(slider.value), int(slider.max_value))
	slider.set_value_no_signal(m.move_distance)
	u.sync_movement()
	_show_distance(u, m, dist_lbl)
	var note: String = " (Dash: cannot Shoot or Assault)" if idx >= UnitInstance.MoveMode.TERRAIN_DASH else ""
	state.log_line("%s %s moves: %s%s" % [state.tag(u), TYRules.esc(m.code), UnitInstance.MOVE_NAMES[idx], note])
	state.touch()


func _on_dist(value: float, u: UnitInstance, m: TeamState, dist_lbl: Label) -> void:
	m.move_distance = int(value)
	u.sync_movement()
	_show_distance(u, m, dist_lbl)


## The same kind of move for every model of the unit (distances are then set per model).
func _on_all_mode(idx: int, u: UnitInstance) -> void:
	for m in u.teams:
		if m.is_active() and not m.mounted():
			m.move_mode = idx
			m.move_distance = mini(m.move_distance, u.slider_limit(idx)) if idx != UnitInstance.MoveMode.HALTED else 0
	u.sync_movement()
	state.log_line("%s moves: %s (all models)" % [state.tag(u), UnitInstance.MOVE_NAMES[idx]])
	state.touch()
	rebuild.call_deferred()


func _on_cross(u: UnitInstance, m: TeamState, result: Label) -> void:
	var r: Dictionary = await TYRules.roll_test(TYRules.cross_number(u), "Cross Check for %s (%s)" % [m.code, u.label])
	var who: String = "%s %s" % [state.tag(u), TYRules.esc(m.code)]
	if u.order == "cross_here" and u.data.cross_skill > 0:
		who += " (Cross Here order: Cross number reduced by 1)"
	if r["auto"]:
		result.text = "Auto: no roll"
		UIUtil.set_color(result, UIUtil.GOOD)
		state.log_line("%s Cross test: Auto (no roll needed)" % who)
		return
	if r["ok"]:
		result.text = "%d vs %s: crossed" % [r["roll"], TYRules.needed_text(r["needed"])]
		UIUtil.set_color(result, UIUtil.GOOD)
		state.log_line("%s Cross test: rolled %d vs %s -> [color=#1f7a2a][b]crosses[/b][/color]" % [
				who, r["roll"], TYRules.needed_text(r["needed"])])
	else:
		m.cross_failed = true
		u.sync_movement()
		result.text = "%d vs %s: BOGGED DOWN" % [r["roll"], TYRules.needed_text(r["needed"])]
		UIUtil.set_color(result, UIUtil.BAD)
		state.log_line("%s Cross Check: rolled %d vs %s -> [color=#b02222][b]BOGGED DOWN[/b][/color]: it stops and cannot Move, Shoot or Assault until the start of its next turn, when it frees itself." % [
				who, r["roll"], TYRules.needed_text(r["needed"])])
		rebuild.call_deferred()
	state.touch()


func _on_order(idx: int, u: UnitInstance, test_btn: Button, order_result: Label) -> void:
	u.order = str(ORDERS[idx][0])
	u.order_failed = false
	order_result.text = ""
	test_btn.disabled = not (u.order in ["blitz", "follow_me", "dig_in"])
	if u.order == "cross_here":
		state.log_line("%s issues Cross Here: teams within 15cm of the Leader reduce their Cross rating by 1 (they cannot Shoot this turn)." % state.tag(u))
	elif u.order != "":
		state.log_line("%s issues a Movement Order: %s" % [state.tag(u), str(ORDERS[idx][1])])
	state.touch()


func _on_order_test(u: UnitInstance, result: Label) -> void:
	var needed: int = u.data.courage if u.order == "follow_me" else u.data.skill
	var stat: String = "Courage" if u.order == "follow_me" else "Skill"
	var r: Dictionary = await TYRules.roll_test(needed, "%s test for the Movement Order of %s" % [stat, u.label])
	u.order_failed = not r["ok"]
	var effect: String = ""
	match u.order:
		"blitz":
			effect = "teams may Move up to 10cm at Tactical (if they stay put they Shoot at Halted ROF)" if r["ok"] \
					else "teams cannot Dash and suffer +1 to hit when Shooting"
		"follow_me":
			effect = "Leader moves 10cm, then teams may follow 10cm; they cannot Shoot this turn" if r["ok"] \
					else "no extra move; teams that are In Command still cannot Shoot"
		"dig_in":
			effect = "Foxholes dug: Bulletproof Cover until the teams Move" if r["ok"] else "failed to dig in"
			effect += "; either way the teams Shoot with Moving ROF and cannot fire a Bombardment"
			if r["ok"] and u.is_ground():
				u.foxholes = true
	result.text = "%d vs %s: %s" % [r["roll"], TYRules.needed_text(needed), "OK" if r["ok"] else "FAILED"]
	UIUtil.set_color(result, UIUtil.GOOD if r["ok"] else UIUtil.BAD)
	state.log_line("%s %s test (%s): rolled %d vs %s -> %s - %s" % [
			state.tag(u), stat, str(u.order), r["roll"], TYRules.needed_text(needed),
			"[color=#1f7a2a]passed[/color]" if r["ok"] else "[color=#b02222]failed[/color]", effect])
	state.touch()
