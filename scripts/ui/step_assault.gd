class_name AssaultPanel
extends StepPanel
## Assault Step, model against model.
##   1. press "Assaulting models"  -> click the models that charge (models of one unit)
##   2. press "Defending models"   -> click the enemy models they contact / that are within 20cm (models of one unit)
##   3. Charge into Contact
##   4. Defensive Fire: tick the defenders' weapons; every chosen defender that has the weapon fires it
##   5. Roll the assault: one die per assaulting model that is still OK; hits go on the defending models
##   6. Is it over? Otherwise the defenders test to Counterattack and the roles swap (back to 5).

enum Mode { IDLE, ATTACKERS, DEFENDERS, FIGHTING }

var _mode: int = Mode.IDLE
var _att: UnitInstance = null
var _def: UnitInstance = null
var _att_models: Array = []            # the models that assault (after a Counterattack: the former defenders)
var _def_models: Array = []            # the models in contact
var _over: bool = false
var _swapped: bool = false             # true while the enemy's models are the ones assaulting (a Counterattack)
var _countered: bool = false           # a Counterattack has happened: no more Defensive Fire in this assault
var _hits_on_att: int = 0
var _def_weapons: Dictionary = {}      # weapon index -> CheckBox (Defensive Fire)
var _atk_weapon_idx: Array = []        # entry 0 of the attack option is "Top armour"; the rest are weapons

var _hint: Label
var _att_btn: Button
var _def_btn: Button
var _own_box: VBoxContainer
var _enemy_box: VBoxContainer
var _chk_sneak: CheckBox
var _def_weapon_box: VBoxContainer
var _atk_weapon_opt: OptionButton
var _hit_spin: SpinBox
var _dice: DiceTray
var _status: RichTextLabel


func build() -> void:
	add_child(UIUtil.heading(player_title("Assault Step")))
	add_child(UIUtil.note("Only Infantry and Armoured Tanks may Assault (not after Dashing, not Unarmoured Tanks). Choose the assaulting "
			+ "models and the defending models, then work through the numbered buttons. After a successful Counterattack the roles "
			+ "swap and you repeat steps 5-6."))

	var bar: HBoxContainer = UIUtil.hbox(8)
	_att_btn = UIUtil.button("1. Assaulting models", _on_attackers_pressed)
	_att_btn.custom_minimum_size = Vector2(200, 38)
	_def_btn = UIUtil.button("2. Defending models", _on_defenders_pressed)
	_def_btn.custom_minimum_size = Vector2(200, 38)
	bar.add_child(_att_btn)
	bar.add_child(_def_btn)
	bar.add_child(UIUtil.button("Finish / start again", _on_reset))
	_hint = UIUtil.bold_label("", 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	add_child(bar)

	var grids: HBoxContainer = UIUtil.hbox(10)
	_own_box = UIUtil.vbox(4)
	_enemy_box = UIUtil.vbox(4)
	grids.add_child(grid_frame("YOUR MODELS", _own_box, AppTheme.BROWN))
	grids.add_child(grid_frame("ENEMY MODELS", _enemy_box, AppTheme.RED))
	add_child(grids)

	var cols: HBoxContainer = UIUtil.hbox(14)
	var c1: VBoxContainer = UIUtil.vbox(4)
	c1.custom_minimum_size = Vector2(320, 0)
	_chk_sneak = ink_check(UIUtil.check("Infantry sneaked up on Tanks: no Defensive Fire"))
	_chk_sneak.tooltip_text = "The infantry was Concealed and did not Move or Shoot"
	c1.add_child(_chk_sneak)
	c1.add_child(UIUtil.button("3. Charge into Contact", _on_charge))
	c1.add_child(UIUtil.button("Roll Cross to charge across Difficult Terrain", _on_charge_cross))
	var scoot: Button = UIUtil.button("Shoot and Scoot (instead of assaulting)", _on_scoot)
	scoot.tooltip_text = "Movement Order for the unit of the chosen assaulting models: Skill test; on a pass the teams that did not Move in the Movement Step may Move up to 10cm."
	c1.add_child(scoot)
	cols.add_child(c1)

	var c2: VBoxContainer = UIUtil.vbox(4)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.add_child(UIUtil.bold_label("4. Defensive Fire: the defenders' weapons", 13, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	_def_weapon_box = UIUtil.vbox(2)
	c2.add_child(_def_weapon_box)
	c2.add_child(UIUtil.button("4. Fire Defensive Fire", _on_defensive))
	cols.add_child(c2)

	var c3: VBoxContainer = UIUtil.vbox(4)
	c3.custom_minimum_size = Vector2(340, 0)
	var hr: HBoxContainer = UIUtil.hbox(6)
	hr.add_child(UIUtil.label("Assault to hit on:"))
	_hit_spin = UIUtil.spin(2, 8, 4)
	hr.add_child(_hit_spin)
	c3.add_child(hr)
	c3.add_child(UIUtil.label("Hits on tanks use:"))
	_atk_weapon_opt = OptionButton.new()
	_atk_weapon_opt.clip_text = true
	c3.add_child(_atk_weapon_opt)
	c3.add_child(UIUtil.button("5. Roll to hit and saves", _on_roll_hits))
	c3.add_child(UIUtil.button("6. Is the Assault over? / Counterattack test", _on_check))
	cols.add_child(c3)
	add_child(cols)

	_dice = DiceTray.new()
	add_child(_dice)
	_status = UIUtil.rich(70)
	_status.fit_content = true
	_status.add_theme_color_override("default_color", UIUtil.INK)
	add_child(UIUtil.paper_frame(_status, AppTheme.EDGE, 8, 10, 8, 2))
	_refresh()


# ------------------------------------------------------------------ choosing the models

func _on_attackers_pressed() -> void:
	if _mode == Mode.FIGHTING:
		_hint.text = "An assault is in progress: press 'Finish / start again' first."
		return
	_mode = Mode.ATTACKERS
	_refresh()


func _on_defenders_pressed() -> void:
	if _mode == Mode.FIGHTING:
		_hint.text = "An assault is in progress: press 'Finish / start again' first."
		return
	if _att_models.is_empty():
		_hint.text = "First press 'Assaulting models' and click the models that charge."
		return
	_mode = Mode.DEFENDERS
	_refresh()


func _on_reset() -> void:
	_mode = Mode.IDLE
	_att = null
	_def = null
	_att_models = []
	_def_models = []
	_over = false
	_swapped = false
	_countered = false
	_hits_on_att = 0
	_refresh()


func _can_assault(u: UnitInstance, m: TeamState) -> String:
	if u.is_air():
		return "Aircraft cannot Assault."
	if u.is_unarmoured():
		return "An Unarmoured Tank cannot Charge into Contact."
	if not m.is_active():
		return "%s is %s and cannot assault." % [m.code, m.status_text().to_lower()]
	if m.mounted():
		return "%s is being carried by %s and cannot assault (Passengers cannot Shoot or Assault)." % [m.code, m.carrier.code]
	if m.bogged():
		return "%s is Bogged Down and cannot Assault until its next turn." % m.code
	if u.order == "cross_here":
		return "%s used a Cross Here order: its teams cannot Shoot or Assault this turn." % u.label
	if m.move_mode >= UnitInstance.MoveMode.TERRAIN_DASH:
		return "%s Dashed this turn and cannot Assault." % m.code
	if u.is_armored() and m.move_distance > TYRules.STAB_LIMIT_CM:
		for w in u.data.weapons:
			if TYRules.weapon_has(w, "Stabiliser") or TYRules.weapon_has(w, "Advanced Stabiliser"):
				return "%s moved more than %dcm with Stabilisers and cannot Assault." % [m.code, TYRules.STAB_LIMIT_CM]
	return ""


## A model of the team playing was clicked. Returns "" or why it cannot be chosen.
func pick_attacker(u: UnitInstance, m: TeamState) -> String:
	if _mode != Mode.ATTACKERS:
		return "An assault is in progress." if _mode == Mode.FIGHTING else "Press 'Assaulting models' first."
	if _att_models.has(m):
		_att_models.erase(m)
		if _att_models.is_empty():
			_att = null
		return ""
	var why: String = _can_assault(u, m)
	if why != "":
		return why
	if not _att_models.is_empty() and u != _att:
		return "The models of one unit assault together (%s). Finish this assault, then start another." % _att.code
	_att = u
	_att_models.append(m)
	if _att_models.size() == 1:
		_hit_spin.value = maxi(u.data.assault, 2)
	return ""


## An enemy model was clicked. Returns "" or why it cannot be chosen.
func pick_defender(u: UnitInstance, m: TeamState) -> String:
	if _mode != Mode.DEFENDERS:
		return "An assault is in progress." if _mode == Mode.FIGHTING else "Press 'Defending models' first."
	if _def_models.has(m):
		_def_models.erase(m)
		if _def_models.is_empty():
			_def = null
		return ""
	if u.is_air():
		return "Flying Aircraft play no part in Assaults."
	if not m.is_alive():
		return "%s is already destroyed." % m.code
	if m.mounted():
		return "%s is being carried by %s: assault the vehicle." % [m.code, m.carrier.code]
	if not _def_models.is_empty() and u != _def:
		return "One assault is fought against the models of one unit (%s)." % _def.code
	_def = u
	_def_models.append(m)
	return ""


func _on_own_clicked(m: TeamState, u: UnitInstance) -> void:
	var problem: String = pick_attacker(u, m)
	_refresh()
	if problem != "":
		_hint.text = problem


func _on_enemy_clicked(m: TeamState, u: UnitInstance) -> void:
	var problem: String = pick_defender(u, m)
	_refresh()
	if problem != "":
		_hint.text = problem


# ------------------------------------------------------------------ drawing

## Models of the team playing that are in this fight (they are the defenders after a Counterattack).
func _own_models() -> Array:
	return _def_models if _swapped else _att_models


func _enemy_models() -> Array:
	return _att_models if _swapped else _def_models


func _refresh() -> void:
	fill_models(_own_box, state.friendly_living(), _own_models(),
			ModelTile.Mark.TARGET if _swapped else ModelTile.Mark.SHOOTER, _on_own_clicked)
	fill_models(_enemy_box, state.enemy_living(), _enemy_models(),
			ModelTile.Mark.SHOOTER if _swapped else ModelTile.Mark.TARGET, _on_enemy_clicked)
	_att_btn.text = "1. Assaulting models" if _own_models().is_empty() else "1. Assaulting  (%d chosen)" % _own_models().size()
	_def_btn.text = "2. Defending models" if _enemy_models().is_empty() else "2. Defending  (%d chosen)" % _enemy_models().size()
	_fill_defensive_weapons()
	_fill_attack_options()
	match _mode:
		Mode.IDLE:
			_hint.text = "Press 'Assaulting models' to start."
		Mode.ATTACKERS:
			_hint.text = "Click the models that charge (gold frame). Then press 'Defending models'."
		Mode.DEFENDERS:
			_hint.text = "Click the enemy models that are contacted or within 20cm (red frame). Then 'Charge into Contact'."
		Mode.FIGHTING:
			_hint.text = "The assault is over: press 'Finish / start again'." if _over else "Assault in progress: Defensive Fire (4), roll (5), check (6)."
	_update_status()


## Defensive Fire weapons: one check box per direct-fire weapon the chosen defenders have.
func _fill_defensive_weapons() -> void:
	var ticked: Dictionary = {}
	for wi in _def_weapons:
		if is_instance_valid(_def_weapons[wi]) and (_def_weapons[wi] as CheckBox).button_pressed:
			ticked[wi] = true
	UIUtil.clear_children(_def_weapon_box)
	_def_weapons = {}
	if _def == null or _def_models.is_empty() or _countered:
		_def_weapon_box.add_child(UIUtil.note("A Counterattack has no Defensive Fire." if _countered else "Choose the defending models: their weapons appear here."))
		return
	for i in _def.data.weapons.size():
		var w: WeaponData = _def.data.weapons[i]
		if TYRules.is_bombardment(w):
			continue
		var n: int = defenders_with(i).size()
		if n == 0:
			continue
		var cb: CheckBox = ink_check(CheckBox.new())
		cb.text = "%s   %d model(s) x ROF %d, Anti-tank %d, Firepower %s" % [w.weapon_name, n, TYRules.effective_rof(_def, w, true),
				w.anti_tank, TYRules.needed_text(w.firepower)]
		cb.button_pressed = ticked.has(i)
		_def_weapon_box.add_child(cb)
		_def_weapons[i] = cb


## The chosen defending models that are OK and have weapon `widx`.
func defenders_with(widx: int) -> Array:
	var out: Array = []
	for m: TeamState in _def_models:
		if m.is_active() and not m.mounted() and m.weapons.has(widx):
			out.append(m)
	return out


func _active(models: Array) -> Array:
	var out: Array = []
	for m: TeamState in models:
		if m.is_active() and not m.mounted():
			out.append(m)
	return out


func _alive(models: Array) -> Array:
	var out: Array = []
	for m: TeamState in models:
		if m.is_alive():
			out.append(m)
	return out


## "Hit Side with Anti-tank rating, or Top with Anti-tank 2 and Firepower 1+." Only weapons the assaulting models have.
func _fill_attack_options() -> void:
	var keep: int = _atk_weapon_opt.selected
	_atk_weapon_opt.clear()
	_atk_weapon_idx.clear()
	_atk_weapon_opt.add_item("Top armour: Anti-tank 2, Firepower 1+")
	if _att != null:
		for i in _att.data.weapons.size():
			var w: WeaponData = _att.data.weapons[i]
			if TYRules.is_bombardment(w) or TYRules.weapon_has(w, "Guided") or TYRules.weapon_has(w, "Guided AA") or w.anti_tank <= 0:
				continue
			var has: bool = false
			for m: TeamState in _att_models:
				if m.weapons.has(i):
					has = true
			if not has:
				continue
			_atk_weapon_idx.append(i)
			_atk_weapon_opt.add_item("Side armour: %s (AT %d, FP %s)" % [w.weapon_name, w.anti_tank, TYRules.needed_text(w.firepower)])
	_atk_weapon_opt.select(keep if keep >= 0 and keep < _atk_weapon_opt.item_count else 0)


func _codes(models: Array) -> String:
	var out: PackedStringArray = []
	for m: TeamState in models:
		out.append(m.code)
	return ", ".join(out)


func _update_status() -> void:
	if _att == null:
		_status.text = "[color=#444444]No assault yet. One die is rolled for every assaulting model that is still OK; each hit goes on a defending model in contact (infantry and unarmoured vehicles get no save; tanks are hit on Side or Top armour).[/color]"
		return
	var t: String = "[b]%s[/b]: %s (%d OK)" % [TYRules.esc(_att.label), _codes(_att_models), _active(_att_models).size()]
	if _def != null:
		t += "\n%s [b]%s[/b]: %s (%d still OK)" % ["COUNTERATTACKS" if _swapped else "assaults", TYRules.esc(_def.label),
				_codes(_def_models), Combat.contact_remaining(_def_models)]
	if _mode == Mode.FIGHTING:
		t += "\n[b]Dice:[/b] %d (one per assaulting model that is OK), each hits on %s. Defensive Fire has scored %d hit(s); %d make the assault Fall Back." % [
				_active(_att_models).size(), TYRules.needed_text(int(_hit_spin.value)), _hits_on_att, 8 if _att.total_teams() >= 12 else 5]
	if _over:
		t += "\n[color=#8a5a00][b]This assault is over.[/b][/color]"
	_status.text = t


# ------------------------------------------------------------------ steps

func _warn(msg: String) -> void:
	_hint.text = msg
	state.log_line("[color=#b35a00](!) %s[/color]" % TYRules.esc(msg))


func _on_charge() -> void:
	charge()


func charge() -> bool:
	if _mode == Mode.FIGHTING:
		_warn("This assault has already charged.")
		return false
	if _att_models.is_empty() or _def_models.is_empty():
		_warn("Choose the assaulting models and the defending models first.")
		return false
	_mode = Mode.FIGHTING
	_over = false
	_swapped = false
	_countered = false
	_hits_on_att = 0
	_att.assaulted_this_turn = true
	state.log_line("")
	state.log_line("[b]%s[/b] (%s) charges into contact with %s (%s)." % [state.tag(_att), _codes(_att_models), state.tag(_def), _codes(_def_models)])
	state.touch()
	_refresh()
	return true


func _on_charge_cross() -> void:
	if _att == null:
		_warn("Choose the assaulting models first.")
		return
	var r: Dictionary = await TYRules.roll_test(TYRules.cross_number(_att), "Cross Check for %s charging through Difficult Terrain" % _att.label)
	if r["auto"]:
		state.log_line("%s crosses Difficult Terrain to charge: Auto." % state.tag(_att))
	elif r["ok"]:
		state.log_line("%s crosses Difficult Terrain to charge: rolled %d vs %s -> [color=#1f7a2a]crosses[/color]" % [
				state.tag(_att), r["roll"], TYRules.needed_text(r["needed"])])
	else:
		state.log_line("%s crosses Difficult Terrain to charge: rolled %d vs %s -> [color=#b02222]FAILS: falls back 5cm and the charge is stopped[/color]" % [
				state.tag(_att), r["roll"], TYRules.needed_text(r["needed"])])


func _on_scoot() -> void:
	if _att == null or _mode == Mode.FIGHTING:
		_warn("Choose a model of the unit first (press 'Assaulting models' and click it). A unit that assaults cannot Shoot and Scoot.")
		return
	shoot_and_scoot(_att)


## Shoot and Scoot (rules p.35): in the Assault Step instead of assaulting, the Unit Leader takes a Skill test; on a
## pass the teams that did not Move in the Movement Step may Move up to 10cm.
func shoot_and_scoot(u: UnitInstance) -> bool:
	if u.order != "":
		_warn("%s already issued a Movement Order this turn (one per turn)." % u.label)
		return false
	if u.assaulted_this_turn:
		_warn("%s assaulted: Shoot and Scoot is used instead of assaulting." % u.label)
		return false
	u.order = "shoot_and_scoot"
	var r: Dictionary = await TYRules.roll_test(u.data.skill, "Skill test for the Shoot and Scoot order of %s" % u.label)
	u.order_failed = not r["ok"]
	state.log_line("%s Shoot and Scoot order (Skill): rolled %d vs %s -> %s" % [state.tag(u), r["roll"], TYRules.needed_text(u.data.skill),
			"[color=#1f7a2a]passed[/color]: teams that did not Move in the Movement Step may now Move up to 10cm" if r["ok"]
			else "[color=#b02222]failed[/color]: the unit stays where it is"])
	_on_reset()
	state.touch()
	return bool(r["ok"])


func _on_defensive() -> void:
	var picked: Array = []
	for wi in _def_weapons:
		if (_def_weapons[wi] as CheckBox).button_pressed:
			picked.append(int(wi))
	defensive_fire(picked)


## Defensive Fire with the given weapon indexes of the defending unit. Returns the hits scored.
func defensive_fire(weapon_indexes: Array) -> int:
	if _mode != Mode.FIGHTING or _over:
		_warn("Charge into Contact first (step 3), or this assault is already over.")
		return 0
	if _countered:
		_warn("A Counterattack has no Defensive Fire.")
		return 0
	if _chk_sneak.button_pressed and _def.uses_armour():
		state.log_line("%s cannot fire Defensive Fire: the Infantry sneaked up on it." % state.tag(_def))
		return 0
	if weapon_indexes.is_empty():
		_warn("Tick at least one defending weapon (or skip Defensive Fire).")
		return 0
	Combat.begin_rolls()
	var hits_now: int = 0
	var dice: Array = []
	for wi in weapon_indexes:
		var shooters: Array = defenders_with(int(wi))
		var targets: Array = _alive(_att_models)
		if shooters.is_empty() or targets.is_empty():
			continue
		var ctx: Dictionary = {"defensive": true, "range_cm": 10, "facing": "side", "concealed": false,
				"gone_to_ground": false, "target_stationary": false}
		var res: Dictionary = await Combat.fire_models(state, _def, shooters, int(wi), _att, targets, ctx)
		if res["ok"]:
			hits_now += int(res["hits"])
			dice.append_array(res["results"])
	_dice.play_groups(Combat.roll_groups(dice, "Defensive Fire to hit  (green = hit)"))
	_hits_on_att += hits_now
	var threshold: int = 8 if _att.total_teams() >= 12 else 5
	if _hits_on_att >= threshold:
		var falls: bool = true
		if _att.uses_armour() and _att.armour("top") <= 2:
			# Tanks with Top armour 1 or 2 only Fall Back if two or more are Bailed Out or Destroyed.
			falls = (_att.count_status(TeamState.Status.BAILED_OUT) + _att.count_status(TeamState.Status.DESTROYED)) >= 2
		if falls:
			if _att.can_be_pinned():
				_att.pinned = true
			_over = true
			state.log_line("[b]%s took %d hits from Defensive Fire: it Falls Back 5cm%s and the assault ends.[/b]" % [
					state.tag(_att), _hits_on_att, " and is Pinned Down" if _att.pinned else ""])
	state.touch()
	_refresh()
	return hits_now


func _on_roll_hits() -> void:
	roll_hits()


## The assaulting models roll to hit. Returns the result of Combat.assault_attack.
func roll_hits() -> Dictionary:
	if _mode != Mode.FIGHTING or _over:
		_warn("Charge into Contact first (step 3), or this assault is already over.")
		return {"ok": false}
	var attackers: int = _active(_att_models).size()
	if attackers == 0:
		_warn("No assaulting model is still OK: check whether the assault is over (step 6).")
		return {"ok": false}
	var w: WeaponData = null
	var facing: String = "top"
	var sel: int = _atk_weapon_opt.selected
	if sel > 0 and sel - 1 < _atk_weapon_idx.size():
		w = _att.data.weapons[_atk_weapon_idx[sel - 1]]
		facing = "side"
	else:
		w = Combat.assault_top_weapon()
	Combat.begin_rolls()
	var res: Dictionary = await Combat.assault_attack(state, _att, attackers, _def, _def_models, int(_hit_spin.value), w, facing)
	if res["ok"] and res.has("results"):
		_dice.play_groups(Combat.roll_groups(res["results"], "Assault to hit  (green = hit)"))
	_refresh()
	return res


func _on_check() -> void:
	check_over()


## Step 6. Returns "won", "broke_off", "counterattack" or "" (nothing to check).
func check_over() -> String:
	if _mode != Mode.FIGHTING or _over:
		_warn("There is no assault to check (charge first, or it is already over).")
		return ""
	if Combat.contact_remaining(_def_models) == 0:
		_over = true
		state.log_line("[b]The assault is over:[/b] every defender in contact is Destroyed or Bailed Out. %s wins; surviving defenders Break Off. The victor may move up to 10cm." % state.tag(_att))
		_refresh()
		return "won"
	var need: int = _def.data.counterattack
	if need <= 0:
		_over = true
		state.log_line("%s has no Counterattack rating: it Breaks Off (retires 15cm or is Destroyed). %s may move up to 10cm." % [state.tag(_def), state.tag(_att)])
		_refresh()
		return "broke_off"
	var r: Dictionary = await TYRules.roll_test(need, "Counterattack test for %s" % _def.label)
	if not r["ok"]:
		_over = true
		state.log_line("%s tests to Counterattack: rolled %d vs %s -> [color=#b02222]fails: Breaks Off[/color] (retires 15cm or is Destroyed). %s may move up to 10cm." % [
				state.tag(_def), r["roll"], TYRules.needed_text(need), state.tag(_att)])
		_refresh()
		return "broke_off"
	state.log_line("%s tests to Counterattack: rolled %d vs %s -> [color=#1f7a2a][b]COUNTERATTACK![/b][/color] The defenders become the assaulters (no Defensive Fire)." % [
			state.tag(_def), r["roll"], TYRules.needed_text(need)])
	var old_att: UnitInstance = _att
	var old_att_models: Array = _att_models
	_att = _def
	_att_models = _def_models
	_def = old_att
	_def_models = _alive(old_att_models)
	_swapped = not _swapped
	_countered = true
	_hit_spin.value = maxi(_att.data.assault, 2)
	state.touch()
	_refresh()
	return "counterattack"
