class_name StepPanel
extends VBoxContainer
## Base class for the panels of the round manager (one per step of the turn).

var state: BattleState


func setup(s: BattleState) -> void:
	state = s
	build()


## Subclasses create their controls here.
func build() -> void:
	pass


func show_card(u: UnitInstance) -> void:
	CardView.popup(u.data, self)


func unit_text(u: UnitInstance) -> String:
	return "%s  [%d/%d]" % [u.label, u.active_teams().size(), u.total_teams()]


func player_title(step: String) -> String:
	return "%s - %s" % [step, state.active_name()]


# ------------------------------------------------------------------ where a model is (used by the Movement step)

## Vehicle models of the same player that are still alive.
func carriers_of(owner_id: int) -> Array:
	var out: Array = []
	for u: UnitInstance in state.living(owner_id):
		for t in u.teams:
			if t.is_vehicle and t.is_alive():
				out.append(t)
	return out


## The drop-down of one infantry model: On foot / In a building / Inside X / On top of X.
## A model that got out of a vehicle during the game cannot get into a vehicle again (buildings are still allowed).
func place_option(u: UnitInstance, t: TeamState) -> OptionButton:
	var opt: OptionButton = OptionButton.new()
	opt.custom_minimum_size = Vector2(230, 0)
	var choices: Array = [["foot", null, false], ["building", null, false]]
	opt.add_item("On foot")
	opt.add_item("In a building")
	var current: int = 1 if t.in_building and not t.mounted() else 0
	for c: TeamState in carriers_of(u.owner_id):
		for top in [false, true]:
			var on_top: bool = top
			var here: bool = t.mounted() and t.carrier == c and t.on_top == on_top
			var free: int = state.free_places(c, on_top)
			if not here and (free <= 0 or (on_top and not c.rides_on_top_ok)):
				continue
			if here:
				current = choices.size()
			choices.append(["carrier", c, on_top])
			opt.add_item("%s %s  (%d free)" % ["On top of" if on_top else "Inside", c.team_name, free])
	opt.select(current)
	opt.tooltip_text = "Where this model is. A Team cannot Mount and Dismount in the same turn, and dismounts before its Transport moves."
	opt.item_selected.connect(_on_place_chosen.bind(t, choices))
	return opt


func _on_place_chosen(index: int, t: TeamState, choices: Array) -> void:
	var choice: Array = choices[index]
	match String(choice[0]):
		"foot":
			state.set_in_building(t, false)
			state.mount(t, null)
		"building":
			state.set_in_building(t, true)
		_:
			state.mount(t, choice[1], bool(choice[2]))
	rebuild.call_deferred()


func rebuild() -> void:
	UIUtil.clear_children(self)
	build()


# ------------------------------------------------------------------ model grids (Artillery and Assault steps)

## A titled parchment box for a grid of model tiles; add the content to `box`. It grows with its tiles (the step
## panel scrolls as a whole: a scroll area of its own here gave the step two or three scrollbars). `height` is kept
## as the smallest height so an empty grid still shows where the models go.
func grid_frame(title: String, box: VBoxContainer, color: Color, height: float = 120.0) -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	v.add_child(UIUtil.title_bar(title, "", color, 14))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(0, minf(height, 120.0))
	v.add_child(box)
	var frame: PanelContainer = UIUtil.paper_frame(v, color, 10, 6, 6, 2)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return frame


## Fills `box` with every unit as a heading and its models as tiles. `chosen` = the models that get the frame `mark`
## (ModelTile.Mark); `on_click` is called with (model, unit).
func fill_models(box: VBoxContainer, units: Array, chosen: Array, mark: int, on_click: Callable) -> void:
	UIUtil.clear_children(box)
	for u: UnitInstance in units:
		var info: String = u.label
		if u.moved():
			info += "   (%s %dcm)" % [UnitInstance.MOVE_NAMES[u.move_mode], u.move_distance]
		if u.pinned:
			info += "   PINNED"
		box.add_child(UIUtil.bold_label(info, 12, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.add_theme_constant_override("v_separation", 5)
		for m in u.teams:
			var tile: ModelTile = ModelTile.new().setup(u, m, state.player_color(u.owner_id))
			tile.set_mark(mark if chosen.has(m) else ModelTile.Mark.NONE)
			tile.clicked.connect(on_click.bind(u))
			flow.add_child(tile)
		box.add_child(flow)
	if units.is_empty():
		box.add_child(UIUtil.note("Nobody here."))


## Dark text for a check box / radio button on the parchment.
func ink_check(cb: CheckBox) -> CheckBox:
	for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		cb.add_theme_color_override(key, UIUtil.INK)
	return cb
