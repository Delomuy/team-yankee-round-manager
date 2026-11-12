class_name DeployPanel
extends StepPanel
## Round 0: the set-up before the first turn. For every player there are two sets, the infantry and the carriers.
## Drag an infantry model onto a carrier: on its TOP half to ride on the outside (up to 3, ground vehicles only), on
## its BOTTOM half to ride inside (as many as "Passengers" on the vehicle's card). Drag it back onto the infantry
## set to put it on foot again. Nothing else happens in this round.

var _status: Label


func build() -> void:
	add_child(UIUtil.heading("Round 0 - set-up: who rides in or on which vehicle"))
	add_child(UIUtil.note("Drag an infantry model onto a carrier: drop it on the TOP box to ride on the outside (up to %d, not on aircraft), "
			% TeamState.RIDERS_ON_TOP + "on the BOTTOM box to ride inside (as many as 'Passengers' on the vehicle's card). "
			+ "Drag it back to the infantry box to leave it on foot. When everybody is placed press 'Start round 1'. "
			+ "Later, models mount and dismount in the Movement step."))
	_status = UIUtil.bold_label("", 13, UIUtil.BAD, HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_status)
	for p in state.player_count():
		add_child(_player_block(p))


func _kind(player: int) -> String:
	return "model_p%d" % player


func _tile(u: UnitInstance, m: TeamState, player: int, draggable: bool) -> ModelTile:
	var tile: ModelTile = ModelTile.new().setup(u, m, state.player_color(player))
	if draggable:
		tile.drag_payload = {"kind": _kind(player), "code": m.code}
	return tile


func _zone(player: int, title: String, min_size: Vector2, handler: Callable) -> Array:
	var zone: DropZone = DropZone.new()
	zone.accepts = _kind(player)
	zone.custom_minimum_size = min_size
	zone.add_theme_stylebox_override("panel", AppTheme.box(Color(0.93, 0.91, 0.85), AppTheme.EDGE, 1, 8, 6, 4))
	zone.dropped.connect(handler)
	var v: VBoxContainer = UIUtil.vbox(3)
	var head: Label = UIUtil.bold_label(title, 11, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(flow)
	zone.add_child(v)
	return [zone, flow]


func _player_block(player: int) -> Control:
	var color: Color = state.player_color(player)
	var v: VBoxContainer = UIUtil.vbox(6)
	v.add_child(UIUtil.title_bar(str(state.player_names[player]), BattleState.TEAM_NAMES[state.team_of(player)], color, 17))
	var infantry: Array = []        # [unit, model] on foot
	var carriers: Array = []        # [unit, model]
	for u: UnitInstance in state.living(player):
		for m in u.teams:
			if not m.is_alive():
				continue
			if m.is_vehicle:
				if m.capacity > 0 or (m.rides_on_top_ok and not m.is_aircraft):
					carriers.append([u, m])
			elif u.is_ground():
				infantry.append([u, m])
	if infantry.is_empty() or carriers.is_empty():
		v.add_child(UIUtil.note("No infantry to carry." if infantry.is_empty() else "No vehicles that can carry infantry."))
		return UIUtil.paper_frame(v, color, 10, 8, 6, 2)

	var cols: HBoxContainer = UIUtil.hbox(10)
	# ---- set 1: the infantry (on foot)
	var pool: Array = _zone(player, "INFANTRY ON FOOT  (drag onto a carrier)", Vector2(340, 120), _on_dropped.bind(player, "", false))
	(pool[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(pool[0] as Control).size_flags_stretch_ratio = 1.0
	for pair in infantry:
		var m: TeamState = pair[1]
		if not m.mounted():
			(pool[1] as Control).add_child(_tile(pair[0], m, player, true))
	cols.add_child(pool[0])
	# ---- set 2: the carriers
	var right: VBoxContainer = UIUtil.vbox(3)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.6
	right.add_child(UIUtil.bold_label("CARRIERS", 11, AppTheme.BROWN, HORIZONTAL_ALIGNMENT_LEFT))
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for pair in carriers:
		flow.add_child(_carrier_box(pair[0], pair[1], player))
	right.add_child(flow)
	cols.add_child(right)
	v.add_child(cols)
	return UIUtil.paper_frame(v, color, 10, 8, 6, 2)


## A carrier with its two drop boxes: on top (outside) above it, inside below it.
func _carrier_box(u: UnitInstance, c: TeamState, player: int) -> Control:
	var v: VBoxContainer = UIUtil.vbox(3)
	v.custom_minimum_size = Vector2(236, 0)
	if c.rides_on_top_ok and not c.is_aircraft:                # only Armoured Tank Teams carry infantry on top
		var riders: Array = state.passengers(c, true)
		var top: Array = _zone(player, "ON TOP  %d / %d" % [riders.size(), TeamState.RIDERS_ON_TOP], Vector2(236, 70),
				_on_dropped.bind(player, c.code, true))
		for m: TeamState in riders:
			(top[1] as Control).add_child(_tile(state.unit_of(m), m, player, true))
		v.add_child(top[0])
	var mid: CenterContainer = CenterContainer.new()
	mid.add_child(_tile(u, c, player, false))
	v.add_child(mid)
	if c.capacity > 0:
		var inside: Array = state.passengers(c, false)
		var bottom: Array = _zone(player, "INSIDE  %d / %d" % [inside.size(), c.capacity], Vector2(236, 70),
				_on_dropped.bind(player, c.code, false))
		for m: TeamState in inside:
			(bottom[1] as Control).add_child(_tile(state.unit_of(m), m, player, true))
		v.add_child(bottom[0])
	else:
		v.add_child(UIUtil.note("(no seats inside)"))
	return v


## An infantry model was dropped: on a carrier box (`carrier_code`) or back on the infantry set ("").
func _on_dropped(payload: Dictionary, _player: int, carrier_code: String, on_top: bool) -> void:
	var m: TeamState = state.find_model(String(payload.get("code", "")))
	if m == null:
		return
	place(m, carrier_code, on_top)


## Puts model `m` in / on the carrier with that code ("" = on foot). Returns false when there is no room.
func place(m: TeamState, carrier_code: String, on_top: bool) -> bool:
	var ok: bool = true
	if carrier_code == "":
		if m.carrier != null:
			state.mount(m, null)
	else:
		var c: TeamState = state.find_model(carrier_code)
		var why: String = state.mount_problem(m, c, on_top) if c != null else "No such carrier."
		ok = c != null and state.mount(m, c, on_top)
		if not ok:
			rebuild.call_deferred()
			_set_status.call_deferred(why)
			return false
	var message: String = ""
	rebuild.call_deferred()
	_set_status.call_deferred(message)
	return ok


func _set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text
