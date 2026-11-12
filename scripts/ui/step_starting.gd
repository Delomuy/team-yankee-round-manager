class_name StartingPanel
extends StepPanel
## Starting Step: Remount bailed-out tanks, Rally pinned down units, roll for Strike Aircraft.


func build() -> void:
	add_child(UIUtil.heading(player_title("Starting Step")))
	add_child(UIUtil.note("Rules order: Formation Morale, Victory Conditions, Ambushes, Strike Aircraft, Reserves, Rally Pinned Down units, "
			+ "free Bogged Down tanks, Remount Bailed Out tanks, remove your Smoke. Here: roll for Strike Aircraft, Rally and Remount. "
			+ "Bogged Down models were freed automatically. Remove the Smoke you fired last turn. Morale, Ambushes and Reserves are not "
			+ "automated: roll them by hand if needed."))
	var any: bool = false
	for u: UnitInstance in state.friendly_living():
		var bailed: int = u.count_status(TeamState.Status.BAILED_OUT)
		var strike: bool = u.is_strike_aircraft()
		if bailed == 0 and not u.pinned and not strike:
			continue
		any = true
		var row: HBoxContainer = UIUtil.hbox(8)
		var name_btn: Button = Button.new()
		name_btn.text = unit_text(u)
		name_btn.flat = true
		UIUtil.ink_text(name_btn)
		name_btn.custom_minimum_size = Vector2(300, 0)
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.pressed.connect(show_card.bind(u))
		row.add_child(name_btn)
		var result: Label = UIUtil.label("")
		if bailed > 0:
			var need: int = u.data.remount if u.data.remount > 0 else u.data.courage
			row.add_child(UIUtil.button("Remount %d bailed-out team(s) (%s)" % [bailed, TYRules.needed_text(need)],
					_on_remount.bind(u, result)))
		if u.pinned:
			var need_r: int = u.data.rally if u.data.rally > 0 else u.data.courage
			row.add_child(UIUtil.button("Rally (%s)" % TYRules.needed_text(need_r), _on_rally.bind(u, result)))
		if strike:
			var arrive: int = 3 if TYRules.unit_has(u.data, "Jump Jet") else 4
			row.add_child(UIUtil.button("Roll for arrival (%s)" % TYRules.needed_text(arrive), _on_arrival.bind(u, arrive, result)))
		row.add_child(result)
		add_child(row)
	if not any:
		add_child(UIUtil.note("Nothing to remount, rally or roll for in this step."))


func _on_remount(u: UnitInstance, result: Label) -> void:
	var need: int = u.data.remount if u.data.remount > 0 else u.data.courage
	var lines: PackedStringArray = []
	var bailed: Array = []
	var codes: PackedStringArray = []
	for t in u.teams:
		if t.status == TeamState.Status.BAILED_OUT:
			bailed.append(t)
			codes.append(t.code)
	var rolls: Array = await TYRules.dice(bailed.size(), "Remount for %s, one die per bailed-out model in this order: %s" % [
			u.label, ", ".join(codes)], need)
	for i in bailed.size():
		var t: TeamState = bailed[i]
		var r: int = int(rolls[i])
		var ok: bool = need > 0 and r >= need
		if ok:
			t.status = TeamState.Status.OK
		lines.append("%d %s" % [r, "remounted" if ok else "stays bailed out"])
		state.log_line("%s Remount (%s): %s rolled %d -> %s" % [state.tag(u), TYRules.needed_text(need), TYRules.esc(t.team_name),
				r, "[color=#1f7a2a]remounted[/color]" if ok else "[color=#b02222]stays bailed out[/color]"])
	result.text = ", ".join(lines)
	state.touch()


func _on_rally(u: UnitInstance, result: Label) -> void:
	var need: int = u.data.rally if u.data.rally > 0 else u.data.courage
	var r: int = await TYRules.d6("Rally test for %s (Pinned Down)" % u.label, need)
	var ok: bool = need > 0 and r >= need
	if ok:
		u.pinned = false
	result.text = "rolled %d: %s" % [r, "Rallied" if ok else "still Pinned Down"]
	state.log_line("%s Rally (%s): rolled %d -> %s" % [state.tag(u), TYRules.needed_text(need), r,
			"[color=#1f7a2a]rallied[/color]" if ok else "[color=#b02222]still Pinned Down[/color]"])
	state.touch()


func _on_arrival(u: UnitInstance, needed: int, result: Label) -> void:
	var r: int = await TYRules.d6("Strike Aircraft arrival for %s" % u.label, needed)
	var ok: bool = r >= needed
	u.air_arrived = ok
	result.text = "rolled %d: %s" % [r, "ARRIVES this turn" if ok else "does not arrive"]
	state.log_line("%s Strike Aircraft (%s): rolled %d -> %s" % [state.tag(u), TYRules.needed_text(needed), r,
			"[color=#1f7a2a]arrives (shoots this turn, leaves after the Shooting Step)[/color]" if ok else "[color=#b02222]does not arrive[/color]"])
	state.touch()
