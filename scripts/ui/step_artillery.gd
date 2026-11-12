class_name ArtilleryPanel
extends StepPanel
## Artillery Step, model against model (same way of working as the Shooting step).
##   1. press "Bombard"            -> click the models that fire (same kind, same unit, with a bombardment weapon)
##   2. pick the weapon and Range In (up to three attempts on the spotter's Skill)
##   3. press "Choose targets"     -> click every enemy model under the Template (they may be from several units)
##   4. read the explanation and press FIRE: one die per model under the Template
## Also handles aircraft Salvo bombardments and Smoke Bombardments (no targets needed).

enum Mode { IDLE, SHOOTERS, TARGETS }

var _mode: int = Mode.IDLE
var _shooters: Array = []              # chosen TeamState of _shooter_unit (same kind)
var _shooter_unit: UnitInstance = null
var _targets: Array = []               # chosen enemy TeamState under the Template (any units)
var _weapon: int = -1
var _spotters: Array = []
var _attempts: Dictionary = {}         # "unit_weapon" -> 1..3 (Ranged In) or -1 (failed)

var _hint: Label
var _shoot_btn: Button
var _target_btn: Button
var _own_box: VBoxContainer
var _enemy_box: VBoxContainer
var _weapon_box: VBoxContainer
var _rules_label: RichTextLabel
var _spotter_opt: OptionButton
var _chk_night: CheckBox
var _chk_smoke: CheckBox
var _chk_cover: CheckBox
var _chk_repeat: CheckBox
var _chk_skip: CheckBox
var _chk_nospot: CheckBox
var _range_status: Label
var _preview: RichTextLabel
var _dice: DiceTray
var _result: Label
var _fire_btn: Button


func build() -> void:
	add_child(UIUtil.heading(player_title("Artillery Step")))
	add_child(UIUtil.note("Press 'Bombard' and click the models that fire (same kind, same unit). Pick the weapon and Range In. Then press "
			+ "'Choose targets' and click every enemy model under the Template. Teams that Moved (except Aircraft) or are Pinned Down "
			+ "(except Armoured Tanks) cannot bombard. Danger Close: no Artillery Template within 10cm of friendly teams (15cm for Salvo). "
			+ "Tanks use Top armour; Infantry and Unarmoured units that are hit are Pinned Down."))

	var bar: HBoxContainer = UIUtil.hbox(8)
	_shoot_btn = UIUtil.button("1. Bombard", _on_shoot_pressed)
	_shoot_btn.custom_minimum_size = Vector2(150, 38)
	_target_btn = UIUtil.button("3. Choose targets", _on_targets_pressed)
	_target_btn.custom_minimum_size = Vector2(170, 38)
	bar.add_child(_shoot_btn)
	bar.add_child(_target_btn)
	bar.add_child(UIUtil.button("Start again", _on_reset))
	_hint = UIUtil.bold_label("", 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	add_child(bar)

	var grids: HBoxContainer = UIUtil.hbox(10)
	_own_box = UIUtil.vbox(4)
	_enemy_box = UIUtil.vbox(4)
	grids.add_child(grid_frame("YOUR MODELS", _own_box, AppTheme.BROWN))
	grids.add_child(grid_frame("ENEMY MODELS  (click the ones under the Template)", _enemy_box, AppTheme.RED))
	add_child(grids)

	var cols: HBoxContainer = UIUtil.hbox(14)
	var c1: VBoxContainer = UIUtil.vbox(4)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.add_child(UIUtil.bold_label("2. Weapon and ranging in", 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	_weapon_box = UIUtil.vbox(2)
	c1.add_child(_weapon_box)
	_rules_label = UIUtil.rich(50)
	_rules_label.add_theme_color_override("default_color", UIUtil.INK)
	RulePopup.connect_label(_rules_label)
	c1.add_child(_rules_label)
	cols.add_child(c1)

	var c2: VBoxContainer = UIUtil.vbox(4)
	c2.custom_minimum_size = Vector2(430, 0)
	var srow: HBoxContainer = UIUtil.hbox(6)
	srow.add_child(UIUtil.label("Spotting team from:"))
	_spotter_opt = OptionButton.new()
	_spotter_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spotter_opt.clip_text = true
	srow.add_child(_spotter_opt)
	c2.add_child(srow)
	_chk_repeat = ink_check(UIUtil.check("Repeat Bombardment on the Ranged In marker (Ranges In at once, no penalty)"))
	_chk_skip = ink_check(UIUtil.check("No ranging needed (Aircraft)"))
	_chk_nospot = ink_check(UIUtil.check("Targets not in Line of Sight of the Spotting Team (+1 to hit)"))
	_chk_smoke = ink_check(UIUtil.check("Bombarding through Smoke (+1 to hit)"))
	_chk_night = ink_check(UIUtil.check("Night (+1 to hit)"))
	_chk_cover = ink_check(UIUtil.check("Infantry targets in Bulletproof Cover (buildings and Foxholes count by themselves)"))
	for c: CheckBox in [_chk_repeat, _chk_skip, _chk_nospot, _chk_smoke, _chk_night, _chk_cover]:
		c.toggled.connect(_on_option_toggled)
		c2.add_child(c)
	var rrow: HBoxContainer = UIUtil.hbox(8)
	rrow.add_child(UIUtil.button("Roll to Range In", _on_range_in))
	_range_status = UIUtil.bold_label("Not Ranged In yet", 13, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	rrow.add_child(_range_status)
	c2.add_child(rrow)
	cols.add_child(c2)
	add_child(cols)

	_preview = UIUtil.rich(110)
	_preview.fit_content = true
	_preview.add_theme_color_override("default_color", UIUtil.INK)
	add_child(UIUtil.paper_frame(_preview, AppTheme.EDGE, 8, 10, 8, 2))
	var fire_row: HBoxContainer = UIUtil.hbox(10)
	_fire_btn = UIUtil.button("FIRE bombardment!", _on_fire)
	_fire_btn.custom_minimum_size = Vector2(200, 44)
	fire_row.add_child(_fire_btn)
	_result = UIUtil.bold_label("", 15, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	fire_row.add_child(_result)
	add_child(fire_row)
	_dice = DiceTray.new()
	add_child(_dice)

	_spotters = state.friendly_living()
	for u: UnitInstance in _spotters:
		_spotter_opt.add_item("%s (Skill %s)" % [u.label, TYRules.needed_text(u.data.skill)])
	_refresh()


# ------------------------------------------------------------------ helpers

## The bombardment weapons a model can fire (indexes into its unit's weapons).
static func bombard_weapons(u: UnitInstance, m: TeamState) -> Array:
	var out: Array = []
	for wi in m.weapons:
		if int(wi) < u.data.weapons.size() and TYRules.is_bombardment(u.data.weapons[int(wi)]):
			out.append(int(wi))
	return out


func _key() -> String:
	return "%d_%d" % [_shooter_unit.get_instance_id() if _shooter_unit != null else 0, _weapon]


func attempt() -> int:
	return int(_attempts.get(_key(), 0))


func _is_smoke() -> bool:
	return _shooter_unit != null and _weapon >= 0 and TYRules.weapon_has(_shooter_unit.data.weapons[_weapon], "Smoke Bombardment")


## The target models grouped by their unit: [[unit, [models]], ...].
func _groups() -> Array:
	var out: Array = []
	for u: UnitInstance in state.enemy_living():
		var mine: Array = []
		for m in _targets:
			if u.teams.has(m):
				mine.append(m)
		if not mine.is_empty():
			out.append([u, mine])
	return out


# ------------------------------------------------------------------ choosing

func _on_shoot_pressed() -> void:
	_mode = Mode.SHOOTERS
	_shooters.clear()
	_shooter_unit = null
	_targets.clear()
	_weapon = -1
	_result.text = ""
	_refresh()


func _on_targets_pressed() -> void:
	if _shooters.is_empty():
		_hint.text = "First press 'Bombard' and click the models that fire."
		return
	_mode = Mode.TARGETS
	_refresh()


func _on_reset() -> void:
	_mode = Mode.IDLE
	_shooters.clear()
	_shooter_unit = null
	_targets.clear()
	_weapon = -1
	_refresh()


## A model of the team playing was clicked. Returns "" or why it cannot be chosen.
func pick_shooter(u: UnitInstance, m: TeamState) -> String:
	if _mode != Mode.SHOOTERS:
		return "Press 'Bombard' first."
	if _shooters.has(m):
		_shooters.erase(m)
		if _shooters.is_empty():
			_shooter_unit = null
		return ""
	if not m.is_active():
		return "%s is %s and cannot bombard." % [m.code, m.status_text().to_lower()]
	if m.mounted():
		return "%s is being carried by %s and cannot bombard." % [m.code, m.carrier.code]
	if bombard_weapons(u, m).is_empty():
		return "%s has no Artillery or Salvo weapon." % m.code
	var problem: String = Combat.bombard_problem(u)
	if problem != "":
		return problem
	if not m.fired.is_empty():
		return "%s already fired this turn: a Bombardment is fired instead of its other weapons." % m.code
	if not _shooters.is_empty():
		var first: TeamState = _shooters[0]
		if u != _shooter_unit or m.kind != first.kind:
			return "Only models of the same kind from the same unit bombard together (%s are %s)." % [_shooter_unit.code, first.kind]
	_shooter_unit = u
	_shooters.append(m)
	if _shooters.size() == 1:
		_chk_skip.set_pressed_no_signal(u.is_air())
		for i in _spotters.size():
			if _spotters[i] == u:
				_spotter_opt.select(i)
	return ""


## An enemy model was clicked: it is (or is no longer) under the Template.
func pick_target(u: UnitInstance, m: TeamState) -> String:
	if _mode != Mode.TARGETS:
		return "Press 'Choose targets' first." if not _shooters.is_empty() else "Press 'Bombard' first."
	if _targets.has(m):
		_targets.erase(m)
		return ""
	if u.is_air():
		return "A Bombardment only hits Tank, Infantry and Landed Aircraft teams, not flying Aircraft."
	if not m.is_alive():
		return "%s is already destroyed." % m.code
	if m.mounted():
		return "%s is being carried by %s: choose the vehicle." % [m.code, m.carrier.code]
	_targets.append(m)
	return ""


func _on_own_clicked(m: TeamState, u: UnitInstance) -> void:
	var problem: String = pick_shooter(u, m)
	_refresh()
	if problem != "":
		_hint.text = problem


func _on_enemy_clicked(m: TeamState, u: UnitInstance) -> void:
	var problem: String = pick_target(u, m)
	_refresh()
	if problem != "":
		_hint.text = problem


func _on_option_toggled(_on: bool) -> void:
	_update_preview()


# ------------------------------------------------------------------ drawing

func _refresh() -> void:
	_fill_weapons()
	fill_models(_own_box, state.friendly_living(), _shooters, ModelTile.Mark.SHOOTER, _on_own_clicked)
	fill_models(_enemy_box, state.enemy_living(), _targets, ModelTile.Mark.TARGET, _on_enemy_clicked)
	_shoot_btn.text = "1. Bombard" if _shooters.is_empty() else "1. Bombard  (%d chosen)" % _shooters.size()
	_target_btn.text = "3. Choose targets" if _targets.is_empty() else "3. Targets  (%d under Template)" % _targets.size()
	match _mode:
		Mode.IDLE:
			_hint.text = "Press 'Bombard' to start."
		Mode.SHOOTERS:
			_hint.text = "Click the models that bombard (gold frame), pick the weapon and Range In. Then press 'Choose targets'."
		Mode.TARGETS:
			_hint.text = "Click every enemy model under the Template (red frame). Then FIRE."
	_update_status()
	_update_preview()


func _fill_weapons() -> void:
	UIUtil.clear_children(_weapon_box)
	if _shooters.is_empty():
		_weapon = -1
		_weapon_box.add_child(UIUtil.note("Choose the models that bombard: their Artillery / Salvo weapons appear here."))
		_rules_label.text = ""
		return
	var options: Array = bombard_weapons(_shooter_unit, _shooters[0])
	if not options.has(_weapon):
		_weapon = options[0] if not options.is_empty() else -1
	var group: ButtonGroup = ButtonGroup.new()
	for wi: int in options:
		var w: WeaponData = _shooter_unit.data.weapons[wi]
		var state_text: String = ""
		if _shooter_unit.used_once.has(wi):
			state_text = "   (USED)"
		else:
			for m: TeamState in _shooters:
				if m.fired.has(wi):
					state_text = "   (ALREADY FIRED)"
		var cb: CheckBox = ink_check(CheckBox.new())
		cb.button_group = group
		cb.text = "%s   %s, Anti-tank %d, Firepower %s%s%s" % [w.weapon_name, "Artillery" if w.artillery else "Salvo", w.anti_tank,
				TYRules.needed_text(w.firepower), ("   " + ", ".join(w.rules)) if not w.rules.is_empty() else "", state_text]
		cb.set_pressed_no_signal(wi == _weapon)
		cb.pressed.connect(_on_weapon_chosen.bind(wi))
		_weapon_box.add_child(cb)
	_rules_label.text = RulesDB.summary_bbcode(_shooter_unit.data, _shooter_unit.data.weapons[_weapon] if _weapon >= 0 else null)


func _on_weapon_chosen(wi: int) -> void:
	_weapon = wi
	_refresh()


func _update_status() -> void:
	UIUtil.set_color(_range_status, UIUtil.INK)
	if _shooter_unit == null or _weapon < 0:
		_range_status.text = "Choose models and a weapon"
		return
	var a: int = attempt()
	if a > 0:
		_range_status.text = "Ranged In on attempt %d (To Hit +%d)" % [a, a - 1]
		UIUtil.set_color(_range_status, UIUtil.GOOD)
	elif a < 0:
		_range_status.text = "Failed to Range In: no bombardment this turn"
		UIUtil.set_color(_range_status, UIUtil.BAD)
	else:
		_range_status.text = "Not Ranged In yet"


# ------------------------------------------------------------------ explanation

func weapons_firing() -> int:
	var n: int = _shooters.size()
	if _shooter_unit != null and TYRules.unit_has(_shooter_unit.data, "MLRS"):
		n *= 2
	return n


func _update_preview() -> void:
	if _preview == null:
		return
	_fire_btn.disabled = true
	if _shooters.is_empty() or _weapon < 0:
		_preview.text = "[color=#444444]The explanation of the bombardment appears here once the models and the weapon are chosen.[/color]"
		return
	var w: WeaponData = _shooter_unit.data.weapons[_weapon]
	var a: int = attempt()
	var firing: int = weapons_firing()
	var mod: int = TYRules.weapons_firing_modifier(firing)
	var text: String = "[b]1. Weapons firing:[/b] %d, which changes the score to hit by %+d  [color=#555555](1-2 weapons +1, 3-4 none, 5-6 -1, 7 or more -2%s)[/color]\n" % [
			firing, mod, "; special rule MLRS: each launcher counts as two" if firing != _shooters.size() else ""]
	if a <= 0:
		var sp: UnitInstance = _spotter()
		var ri: Dictionary = Combat.range_in_needed(sp, _shooter_unit)
		if int(ri["needed"]) > 0:
			text += "[b]2. Range In:[/b] [color=#a04000]not done yet.[/color] The Spotting Team gets up to three attempts needing [b]%s[/b] (%s). Ranging In on the 2nd attempt gives +1 to hit, on the 3rd +2.\n" % [
					TYRules.needed_text(int(ri["needed"])), TYRules.esc(", ".join(ri["parts"]))]
		else:
			text += "[b]2. Range In:[/b] [color=#a04000]%s Choose another Spotting Team.[/color]\n" % TYRules.esc(str(ri.get("error", "")))
	else:
		text += "[b]2. Ranged In[/b] on attempt %d%s.\n" % [a, "" if a == 1 else " (+%d to hit)" % (a - 1)]
	if _is_smoke():
		text += "[b]3. Smoke Bombardment[/b] (special rule): no targets and no Danger Close; a Smoke Screen %dcm long (10cm per weapon). Once per game. It blocks Line of Sight beyond 15cm and gives +1 to hit through it." % (firing * 10)
		_fire_btn.disabled = a <= 0
		_preview.text = text
		return
	if _targets.is_empty():
		text += "[b]3. Targets:[/b] [color=#a04000]press 'Choose targets' and click every enemy model under the Template.[/color]"
		_preview.text = text
		return
	text += "[b]3. To hit:[/b] one die for every model under the Template (%d dice):\n" % _targets.size()
	for g in _groups():
		var t: UnitInstance = g[0]
		var codes: PackedStringArray = []
		for m: TeamState in g[1]:
			codes.append(m.code)
		var th: Dictionary = TYRules.bombard_needed(_shooter_unit, w, t, firing, _ctx(maxi(a, 1), false))
		var line: String = "      %s (%s): hit on [b]%s[/b]  [color=#555555](%s)[/color]\n" % [TYRules.esc(t.label), ", ".join(codes),
				TYRules.needed_text(int(th["needed"])), TYRules.esc(", ".join(th["parts"]))]
		if t.uses_armour():
			var armour: int = TYRules.armour_value(t, "top", w)
			line += "            each hit: die + Top armour %d against Anti-tank %d (more = no effect, equal = Firepower %s bails out, less = Firepower %s destroys, else bailed out)" % [
					armour, w.anti_tank, TYRules.needed_text(w.firepower), TYRules.needed_text(w.firepower)]
		else:
			line += "            each hit: Save %s; in Bulletproof Cover (building, Foxholes) the shooter must also pass Firepower %s. Hit Infantry and Unarmoured units are Pinned Down." % [
					TYRules.needed_text(t.save_value()), TYRules.needed_text(w.firepower)]
		text += line + "\n"
	_fire_btn.disabled = a <= 0
	_preview.text = text.strip_edges()


func _spotter() -> UnitInstance:
	if _spotter_opt.selected >= 0 and _spotter_opt.selected < _spotters.size():
		return _spotters[_spotter_opt.selected]
	return _shooter_unit


func _ctx(a: int, later_unit: bool) -> Dictionary:
	return {"attempt": a, "no_los": _chk_nospot.button_pressed, "smoke": _chk_smoke.button_pressed,
			"night": _chk_night.button_pressed, "bulletproof": _chk_cover.button_pressed, "continue": later_unit}


# ------------------------------------------------------------------ range in and fire

func _warn(msg: String) -> void:
	_hint.text = msg
	state.log_line("[color=#b35a00](!) %s[/color]" % TYRules.esc(msg))


func _on_range_in() -> void:
	range_in()


## Coroutine (the dice may be typed in by the user): call it with await.
func range_in() -> void:
	if _shooter_unit == null or _weapon < 0:
		_warn("Choose the models that bombard and their weapon first.")
		return
	var u: UnitInstance = _shooter_unit
	var w: WeaponData = u.data.weapons[_weapon]
	for m: TeamState in _shooters:
		if m.fired.has(_weapon):
			_warn("%s already bombarded or fired ranging shots with that weapon this turn." % m.code)
			return
	var a: int = 0
	if _chk_repeat.button_pressed:
		a = 1
		state.log_line("%s Repeat Bombardment with %s: it is already Ranged In on its Aiming Point, so it Ranges In at once with no penalty." % [state.tag(u), TYRules.esc(w.weapon_name)])
	elif _chk_skip.button_pressed:
		a = 1
		state.log_line("%s bombards with %s without Ranging In (Aircraft)." % [state.tag(u), TYRules.esc(w.weapon_name)])
	else:
		var spotter: UnitInstance = _spotter()
		var ri: Dictionary = Combat.range_in_needed(spotter, u)
		if int(ri["needed"]) <= 0:
			_warn(str(ri.get("error", "This team cannot spot.")))
			return
		spotter.spotted_this_turn = true
		a = await Combat.range_in(state, spotter, int(ri["needed"]), "%s with %s; %s" % [u.label, w.weapon_name, ", ".join(ri["parts"])])
		if a == 0:                  # ranging shots only: these models may not Shoot this turn
			for m: TeamState in _shooters:
				m.fired[_weapon] = true
			u.fired_weapons[_weapon] = true
			u.bombarded_this_turn = true
			u.shot_this_turn = true
	_attempts[_key()] = a if a > 0 else -1
	state.touch()
	_refresh()


func _on_fire() -> void:
	fire()


## Resolves the bombardment on every chosen model, unit by unit. Returns the number of hits (-1 = not fired).
## Coroutine (the dice may be typed in by the user): call it with await.
func fire() -> int:
	if _shooter_unit == null or _weapon < 0:
		_warn("Choose the models that bombard and their weapon first.")
		return -1
	var a: int = attempt()
	if a <= 0:
		_warn("Range In first (the weapon must be Ranged In before it can bombard).")
		return -1
	if _is_smoke():
		Combat.smoke_bombard(state, _shooter_unit, _weapon, weapons_firing())
		for m: TeamState in _shooters:
			m.fired[_weapon] = true
		_result.text = "Smoke screen placed."
		_finish()
		return 0
	if _targets.is_empty():
		_warn("Press 'Choose targets' and click the models under the Template.")
		return -1
	Combat.begin_rolls()
	var all_results: Array = []
	var hits: int = 0
	var destroyed: int = 0
	var bailed: int = 0
	var first: bool = true
	for g in _groups():
		var ctx: Dictionary = _ctx(a, not first)
		var res: Dictionary = await Combat.bombard_models(state, _shooter_unit, _shooters, _weapon, g[0], g[1], ctx)
		if not res["ok"]:
			if first:
				_result.text = str(res.get("error", ""))
				return -1
			continue
		first = false
		all_results.append_array(res["results"])
		hits += int(res["hits"])
		destroyed += int(res["destroyed"])
		bailed += int(res["bailed"])
	_dice.play_groups(Combat.roll_groups(all_results))
	_result.text = "%d dice: %d hit(s)  ->  %d destroyed, %d bailed out   (details in the event log)" % [all_results.size(), hits, destroyed, bailed]
	_finish()
	return hits


func _finish() -> void:
	_mode = Mode.IDLE
	_shooters.clear()
	_shooter_unit = null
	_targets.clear()
	_weapon = -1
	state.touch()
	_refresh()
	_hint.text = "Done. Press 'Bombard' for the next bombardment."
