class_name ShootingPanel
extends StepPanel
## Shooting Step, model against model.
##   1. press "Shoot"                   -> click the models that shoot: models of the same kind, from any of your units
##   2. press "Choose targets"          -> click the enemy models that are shot at, from any enemy units; every click
##                                         aims one shot, the + / - buttons on a chosen model aim more or fewer at it.
##                                         The shots can never be more than the combined ROF of the shooters.
##   3. pick the weapon, set the range and the situation of each target unit, read the explanation, press FIRE
## The volley is split into parts (one shooting unit against one target unit) by Combat.split_volley; each part is
## rolled with its own to-hit number. The dice tumble in the dice tray; every roll is also written to the event log.

enum Mode { IDLE, SHOOTERS, TARGETS }

var _mode: int = Mode.IDLE
var _shooters: Array = []              # chosen TeamState (same kind, any of the player's units), in click order
var _shooter_unit: UnitInstance = null # unit of the first shooter: its card lists the weapons offered
var _targets: Array = []               # chosen enemy TeamState (any units), in click order
var _shots: Dictionary = {}            # target TeamState -> shots aimed at it
var _target_unit: UnitInstance = null  # the target unit whose situation is shown
var _situ: Dictionary = {}             # target UnitInstance -> {"range_cm", "facing", "concealed", "gone_to_ground", "bulletproof"}
var _weapon: int = -1                  # weapon index on _shooter_unit's card (other units: matched by name)

var _hint: Label
var _shoot_btn: Button
var _target_btn: Button
var _own_box: VBoxContainer
var _enemy_box: VBoxContainer
var _weapon_box: VBoxContainer
var _rules_label: RichTextLabel
var _situ_row: HBoxContainer
var _situ_opt: OptionButton             # which target unit the per-unit situation belongs to
var _situ_units: Array = []             # target units in the order of _situ_opt
var _range_spin: HSlider                # the range slider (0 .. the weapon's range)
var _range_lbl: Label
var _facing_opt: OptionButton
var _chk_concealed: CheckBox
var _chk_gone: CheckBox
var _chk_command: CheckBox
var _chk_smoke: CheckBox
var _chk_night: CheckBox
var _chk_cover: CheckBox
var _chk_fire_smoke: CheckBox
var _preview: RichTextLabel
var _dice: DiceTray
var _result: Label
var _fire_btn: Button


func build() -> void:
	add_child(UIUtil.heading(player_title("Shooting Step")))
	add_child(UIUtil.note("Shooting is model against model. Press 'Shoot' and click the models that fire (models of the same kind, "
			+ "from any of your units), then press 'Choose targets' and click the enemy models they shoot at (any enemy units). "
			+ "Pick the weapon, set the range and situation of each target unit and press FIRE. Bombardments (Artillery / Salvo) "
			+ "are handled in the next step."))

	var bar: HBoxContainer = UIUtil.hbox(8)
	_shoot_btn = UIUtil.button("1. Shoot", _on_shoot_pressed)
	_shoot_btn.custom_minimum_size = Vector2(150, 38)
	_target_btn = UIUtil.button("2. Choose targets", _on_targets_pressed)
	_target_btn.custom_minimum_size = Vector2(170, 38)
	bar.add_child(_shoot_btn)
	bar.add_child(_target_btn)
	bar.add_child(UIUtil.button("Start again", _on_reset))
	_hint = UIUtil.bold_label("", 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	add_child(bar)

	# ---- the two model grids
	var grids: HBoxContainer = UIUtil.hbox(10)
	_own_box = UIUtil.vbox(4)
	_enemy_box = UIUtil.vbox(4)
	grids.add_child(_grid_frame("YOUR MODELS", _own_box, AppTheme.BROWN))
	grids.add_child(_grid_frame("ENEMY MODELS", _enemy_box, AppTheme.RED))
	add_child(grids)

	# ---- weapon and situation
	var cols: HBoxContainer = UIUtil.hbox(14)
	var c1: VBoxContainer = UIUtil.vbox(4)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.add_child(UIUtil.bold_label("3. Weapon", 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	_weapon_box = UIUtil.vbox(2)
	c1.add_child(_weapon_box)
	_rules_label = UIUtil.rich(56)
	_rules_label.add_theme_color_override("default_color", UIUtil.INK)
	RulePopup.connect_label(_rules_label)
	c1.add_child(_rules_label)
	cols.add_child(c1)

	var c2: VBoxContainer = UIUtil.vbox(4)
	c2.custom_minimum_size = Vector2(380, 0)
	c2.add_child(UIUtil.bold_label("4. Situation", 14, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	_situ_row = UIUtil.hbox(6)
	_situ_row.add_child(UIUtil.label("Target unit:"))
	_situ_opt = OptionButton.new()
	_situ_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_situ_opt.item_selected.connect(_on_situ_unit_chosen)
	_situ_row.add_child(_situ_opt)
	_situ_row.visible = false
	c2.add_child(_situ_row)
	var rr: HBoxContainer = UIUtil.hbox(6)
	rr.add_child(UIUtil.label("Range (cm):"))
	_range_spin = HSlider.new()
	_range_spin.min_value = 0
	_range_spin.max_value = 100
	_range_spin.step = 1
	_range_spin.value = 30
	_range_spin.custom_minimum_size = Vector2(150, 24)
	rr.add_child(_range_spin)
	_range_lbl = UIUtil.bold_label("30 cm", 13, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_range_lbl.custom_minimum_size = Vector2(96, 0)
	rr.add_child(_range_lbl)
	c2.add_child(rr)
	rr = UIUtil.hbox(6)
	rr.add_child(UIUtil.label("Armour hit:"))
	_facing_opt = UIUtil.option(["Front", "Side", "Top"])
	rr.add_child(_facing_opt)
	c2.add_child(rr)
	_chk_concealed = UIUtil.check("Target is Concealed (+1)")
	_chk_gone = UIUtil.check("Target is Gone to Ground (+2 total if Concealed)")
	_chk_cover = UIUtil.check("Infantry target in Bulletproof Cover (needs Firepower)")
	_chk_command = UIUtil.check("Shooter moved Out of Command (+1)")
	_chk_smoke = UIUtil.check("Shooting through Smoke (+1)")
	_chk_night = UIUtil.check("Night (+1)")
	_chk_fire_smoke = UIUtil.check("Fire Smoke instead (special rule Smoke: hits place Smoke, no damage)")
	_chk_fire_smoke.visible = false
	for c: CheckBox in [_chk_concealed, _chk_gone, _chk_cover, _chk_command, _chk_smoke, _chk_night, _chk_fire_smoke]:
		c.add_theme_color_override("font_color", UIUtil.INK)
		c.add_theme_color_override("font_pressed_color", UIUtil.INK)
		c.add_theme_color_override("font_hover_color", UIUtil.INK)
		c.add_theme_color_override("font_hover_pressed_color", UIUtil.INK)
		c.toggled.connect(_on_situation_toggled)
		c2.add_child(c)
	cols.add_child(c2)
	add_child(cols)

	# ---- explanation, dice, fire
	_preview = UIUtil.rich(120)
	_preview.fit_content = true
	_preview.add_theme_color_override("default_color", UIUtil.INK)
	add_child(UIUtil.paper_frame(_preview, AppTheme.EDGE, 8, 10, 8, 2))
	var fire_row: HBoxContainer = UIUtil.hbox(10)
	_fire_btn = UIUtil.button("FIRE!", _on_fire)
	_fire_btn.custom_minimum_size = Vector2(160, 44)
	fire_row.add_child(_fire_btn)
	_result = UIUtil.bold_label("", 15, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT)
	fire_row.add_child(_result)
	add_child(fire_row)
	_dice = DiceTray.new()
	add_child(_dice)
	_range_spin.value_changed.connect(_on_number_changed)
	_facing_opt.item_selected.connect(_on_number_changed)
	_refresh()


func _grid_frame(title: String, box: VBoxContainer, color: Color) -> Control:
	var v: VBoxContainer = UIUtil.vbox(4)
	v.add_child(UIUtil.title_bar(title, "", color, 14))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL       # grows with its tiles; the step panel scrolls as a whole
	box.custom_minimum_size = Vector2(0, 120)
	v.add_child(box)
	var frame: PanelContainer = UIUtil.paper_frame(v, color, 10, 6, 6, 2)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return frame


# ------------------------------------------------------------------ the three steps

func _clear_choice() -> void:
	_shooters.clear()
	_shooter_unit = null
	_targets.clear()
	_shots.clear()
	_target_unit = null
	_situ.clear()
	_weapon = -1


func _on_shoot_pressed() -> void:
	_mode = Mode.SHOOTERS
	_clear_choice()
	_result.text = ""
	_refresh()


func _on_targets_pressed() -> void:
	if _shooters.is_empty():
		_hint.text = "First press 'Shoot' and click the models that fire."
		return
	_mode = Mode.TARGETS
	_refresh()


func _on_reset() -> void:
	_mode = Mode.IDLE
	_clear_choice()
	_refresh()


## A model of the team playing was clicked. Returns "" or why it cannot be chosen.
func pick_shooter(u: UnitInstance, m: TeamState) -> String:
	if _mode != Mode.SHOOTERS:
		return "Press 'Shoot' first."
	if _shooters.has(m):
		_shooters.erase(m)
		_shooter_unit = state.unit_of(_shooters[0]) if not _shooters.is_empty() else null
		return ""
	if not m.is_active():
		return "%s is %s and cannot shoot." % [m.code, m.status_text().to_lower()]
	if m.mounted():
		return "%s is being carried by %s and cannot shoot." % [m.code, m.carrier.code]
	if not _shooters.is_empty():
		var first: TeamState = _shooters[0]
		if m.kind != first.kind:
			return "Only models of the same kind shoot together (the chosen ones are %s). Fire, then shoot again with the others." % first.kind
		if _weapon >= 0 and Combat.weapon_index(u, m, _weapon_name()) < 0:
			return "%s cannot fire %s." % [m.code, _weapon_name()]
	if _shooters.is_empty():
		_shooter_unit = u
	_shooters.append(m)
	return ""


## An enemy model was clicked. Returns "" or why it cannot be chosen.
func pick_target(u: UnitInstance, m: TeamState) -> String:
	if _mode != Mode.TARGETS:
		return "Press 'Choose targets' first." if not _shooters.is_empty() else "Press 'Shoot' first."
	if _targets.has(m):
		_targets.erase(m)
		_shots.erase(m)
		_prune_situ()
		return ""
	if not m.is_alive():
		return "%s is already destroyed." % m.code
	if m.mounted():
		return "%s is being carried by %s: shoot at the vehicle." % [m.code, m.carrier.code]
	var limit: int = max_shots()
	if _weapon >= 0 and limit <= 0:
		return "The chosen weapon cannot fire now (it has no ROF for how these models moved)."
	if limit > 0 and shots_total() >= limit:
		return "All %d shots are already aimed (%d model(s) x ROF). Use - on a target to free one." % [limit, _shooters.size()]
	_targets.append(m)
	_shots[m] = 1
	if not _situ.has(u):                              # sensible defaults for a new target unit
		_store_situ()
		_situ[u] = {
			"range_cm": int(_range_spin.value),
			"facing": 0,
			"concealed": u.is_ground() and u.move_mode == UnitInstance.MoveMode.HALTED,
			"gone_to_ground": u.is_gone_to_ground(),
			"bulletproof": false,                    # buildings and Foxholes count as Bulletproof Cover by themselves
		}
		_target_unit = u
		_load_situ()
	return ""


## The units the chosen targets belong to, in the order they were first clicked.
func target_units() -> Array:
	var out: Array = []
	for m: TeamState in _targets:
		var u: UnitInstance = state.unit_of(m)
		if u != null and not out.has(u):
			out.append(u)
	return out


## Forgets the situation of target units that no longer have a chosen model.
func _prune_situ() -> void:
	var units: Array = target_units()
	for u in _situ.keys():
		if not units.has(u):
			_situ.erase(u)
	if not units.has(_target_unit):
		_target_unit = units[0] if not units.is_empty() else null
		_load_situ()


func _weapon_name() -> String:
	if _shooter_unit == null or _weapon < 0 or _weapon >= _shooter_unit.data.weapons.size():
		return ""
	return (_shooter_unit.data.weapons[_weapon] as WeaponData).weapon_name


## The most shots the chosen models have with the chosen weapon (models x ROF, every shooting unit added up).
func max_shots() -> int:
	if _shooters.is_empty() or _weapon < 0:
		return 0
	var total: int = 0
	for g in Combat.volley_groups(state, _shooters, _weapon_name()):
		total += int(g["capacity"])
	return total


func shots_total() -> int:
	var total: int = 0
	for m in _shots:
		total += int(_shots[m])
	return total


## + / - on a chosen target. Returns "" or why it was refused.
func change_shots(m: TeamState, delta: int) -> String:
	if not _targets.has(m):
		return ""
	if delta > 0:
		var limit: int = max_shots()
		if shots_total() >= limit:
			return "No shots left: %d model(s) x ROF = %d shots, all aimed." % [_shooters.size(), limit]
		_shots[m] = int(_shots[m]) + 1
	else:
		_shots[m] = int(_shots[m]) - 1
		if int(_shots[m]) <= 0:
			_shots.erase(m)
			_targets.erase(m)
			_prune_situ()
	return ""


## Fewer shots available (another weapon, the shooters moved ...): take the extra ones away, last target first.
func _trim_shots() -> void:
	var limit: int = max_shots()
	var i: int = _targets.size() - 1
	while shots_total() > limit and i >= 0:
		var m: TeamState = _targets[i]
		var over: int = shots_total() - limit
		var take: int = mini(over, int(_shots[m]))
		_shots[m] = int(_shots[m]) - take
		if int(_shots[m]) <= 0:
			_shots.erase(m)
			_targets.remove_at(i)
		i -= 1
	_prune_situ()


func _on_shots_changed(m: TeamState, delta: int) -> void:
	var problem: String = change_shots(m, delta)
	_refresh()
	if problem != "":
		_hint.text = problem


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


# ------------------------------------------------------------------ situation of each target unit

## Writes the per-unit controls into the situation of the target unit shown.
func _store_situ() -> void:
	if _target_unit == null or not _situ.has(_target_unit):
		return
	_situ[_target_unit] = {
		"range_cm": int(_range_spin.value),
		"facing": _facing_opt.selected,
		"concealed": _chk_concealed.button_pressed,
		"gone_to_ground": _chk_gone.button_pressed,
		"bulletproof": _chk_cover.button_pressed,
	}


## Shows the situation of _target_unit in the per-unit controls.
func _load_situ() -> void:
	if _target_unit == null or not _situ.has(_target_unit):
		return
	var s: Dictionary = _situ[_target_unit]
	_fit_range()
	_range_spin.set_value_no_signal(mini(int(s["range_cm"]), int(_range_spin.max_value)))
	_facing_opt.select(int(s["facing"]))
	_chk_concealed.set_pressed_no_signal(bool(s["concealed"]))
	_chk_gone.set_pressed_no_signal(bool(s["gone_to_ground"]))
	_chk_cover.set_pressed_no_signal(bool(s["bulletproof"]))
	_range_lbl.text = "%d cm (max %d)" % [int(_range_spin.value), int(_range_spin.max_value)]


func _fill_situ_units() -> void:
	_situ_units = target_units()
	_situ_opt.clear()
	for u: UnitInstance in _situ_units:
		_situ_opt.add_item("%s  %s" % [u.code, u.label])
	var at: int = _situ_units.find(_target_unit)
	if at >= 0:
		_situ_opt.select(at)
	_situ_row.visible = _situ_units.size() > 1


func _on_situ_unit_chosen(idx: int) -> void:
	if idx < 0 or idx >= _situ_units.size():
		return
	_store_situ()
	_target_unit = _situ_units[idx]
	_load_situ()
	_update_preview()


# ------------------------------------------------------------------ drawing

func _refresh() -> void:
	_fill_weapons()
	_trim_shots()
	_fit_range()
	_fill_situ_units()
	_fill_grid(_own_box, state.friendly_living(), true)
	_fill_grid(_enemy_box, state.enemy_living(), false)
	_shoot_btn.text = "1. Shoot" if _shooters.is_empty() else "1. Shoot  (%d chosen)" % _shooters.size()
	_target_btn.text = "2. Choose targets" if _targets.is_empty() else "2. Targets  (%d of %d shots)" % [shots_total(), max_shots()]
	match _mode:
		Mode.IDLE:
			_hint.text = "Press 'Shoot' to start."
		Mode.SHOOTERS:
			_hint.text = "Click the models that shoot (gold frame), from any of your units, all of one kind. Then press 'Choose targets'."
		Mode.TARGETS:
			_hint.text = "Click the enemy models that are shot at (red frame), from any enemy units: one shot per click, + and - on the model for more or fewer. %d of %d shots aimed. Then FIRE." % [shots_total(), max_shots()]
	_update_preview()


## Every unit as a heading with its models as a grid of tiles under it.
func _fill_grid(box: VBoxContainer, units: Array, own: bool) -> void:
	UIUtil.clear_children(box)
	for u: UnitInstance in units:
		var info: String = u.label
		if own and u.moved():
			info += "   (%s %dcm)" % [UnitInstance.MOVE_NAMES[u.move_mode], u.move_distance]
		if u.pinned:
			info += "   PINNED"
		box.add_child(UIUtil.bold_label(info, 12, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.add_theme_constant_override("v_separation", 5)
		for m in u.teams:
			var tile: ModelTile = ModelTile.new().setup(u, m, state.player_color(u.owner_id))
			if own:
				tile.set_mark(ModelTile.Mark.SHOOTER if _shooters.has(m) else ModelTile.Mark.NONE)
				tile.clicked.connect(_on_own_clicked.bind(u))
			else:
				tile.set_mark(ModelTile.Mark.TARGET if _targets.has(m) else ModelTile.Mark.NONE)
				tile.set_shots(int(_shots.get(m, 0)))
				tile.shots_changed.connect(_on_shots_changed)
				tile.clicked.connect(_on_enemy_clicked.bind(u))
			flow.add_child(tile)
		box.add_child(flow)
	if units.is_empty():
		box.add_child(UIUtil.note("Nobody left."))


## The weapons the chosen models have (radio buttons): the first model's direct-fire weapons that every chosen
## model can fire (matched by name across units).
func _fill_weapons() -> void:
	UIUtil.clear_children(_weapon_box)
	if _shooters.is_empty():
		_weapon = -1
		_weapon_box.add_child(UIUtil.note("Choose the models that shoot: their weapons appear here."))
		_rules_label.text = ""
		return
	var first: TeamState = _shooters[0]
	var options: Array = []
	for wi in first.weapons:
		if int(wi) >= _shooter_unit.data.weapons.size():
			continue
		var w0: WeaponData = _shooter_unit.data.weapons[int(wi)]
		if TYRules.is_bombardment(w0):
			continue
		var everyone: bool = true
		for m: TeamState in _shooters:
			if Combat.weapon_index(state.unit_of(m), m, w0.weapon_name) < 0:
				everyone = false
		if everyone:
			options.append(int(wi))
	if not options.has(_weapon):
		_weapon = options[0] if not options.is_empty() else -1
	if options.is_empty():
		_weapon_box.add_child(UIUtil.note("These models have no direct-fire weapon in common (set it with 'Weapons per model...' on the unit)."))
	var group: ButtonGroup = ButtonGroup.new()
	for wi: int in options:
		var w: WeaponData = _shooter_unit.data.weapons[wi]
		var rng: String = "%dcm" % w.range_cm
		if w.range_cm_min > 0:
			rng = "%d-%dcm" % [w.range_cm_min, w.range_cm]
		var fired: int = 0
		for m: TeamState in _shooters:
			if m.fired.has(Combat.weapon_index(state.unit_of(m), m, w.weapon_name)):
				fired += 1
		var cb: CheckBox = CheckBox.new()
		cb.button_group = group
		cb.text = "%s   range %s, ROF %s halted / %s moving, Anti-tank %d, Firepower %s%s" % [w.weapon_name, rng,
				str(w.rof_static) if w.rof_static > 0 else "-", str(w.rof_moving) if w.rof_moving > 0 else "-",
				w.anti_tank, TYRules.needed_text(w.firepower), "   (ALREADY FIRED)" if fired > 0 else ""]
		for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
			cb.add_theme_color_override(key, UIUtil.INK)
		cb.set_pressed_no_signal(wi == _weapon)
		cb.pressed.connect(_on_weapon_chosen.bind(wi))
		_weapon_box.add_child(cb)
	_rules_label.text = RulesDB.summary_bbcode(_shooter_unit.data, _shooter_unit.data.weapons[_weapon] if _weapon >= 0 else null)


func _on_weapon_chosen(wi: int) -> void:
	_weapon = wi
	_refresh()


## The range slider goes from 0 to the range of the chosen weapon (against the target unit shown).
func _fit_range() -> void:
	var can_smoke: bool = _weapon >= 0 and _shooter_unit != null and TYRules.weapon_has(_shooter_unit.data.weapons[_weapon], "Smoke")
	_chk_fire_smoke.visible = can_smoke
	if not can_smoke:
		_chk_fire_smoke.set_pressed_no_signal(false)
	var top: int = 100
	if _weapon >= 0 and _shooter_unit != null:
		var w: WeaponData = _shooter_unit.data.weapons[_weapon]
		top = TYRules.max_range(w, _target_unit) if _target_unit != null else w.range_cm
	_range_spin.max_value = maxi(top, 1)
	if _range_spin.value > _range_spin.max_value:
		_range_spin.set_value_no_signal(_range_spin.max_value)
	_range_lbl.text = "%d cm (max %d)" % [int(_range_spin.value), int(_range_spin.max_value)]


func _on_situation_toggled(_on: bool) -> void:
	_store_situ()
	_update_preview()


func _on_number_changed(_v: Variant) -> void:
	_range_lbl.text = "%d cm (max %d)" % [int(_range_spin.value), int(_range_spin.max_value)]
	_store_situ()
	_update_preview()


## The shooting ctx against target unit `u` (its own range, facing and cover; the shooter ticks are shared).
func _ctx(u: UnitInstance = null) -> Dictionary:
	if u == null:
		u = _target_unit
	_store_situ()
	var facings: Array = ["front", "side", "top"]
	var s: Dictionary = _situ.get(u, {"range_cm": int(_range_spin.value), "facing": _facing_opt.selected,
			"concealed": _chk_concealed.button_pressed, "gone_to_ground": _chk_gone.button_pressed,
			"bulletproof": _chk_cover.button_pressed})
	return {
		"range_cm": int(s["range_cm"]),
		"facing": str(facings[int(s["facing"])]),
		"concealed": bool(s["concealed"]),
		"gone_to_ground": bool(s["gone_to_ground"]),
		"out_of_command": _chk_command.button_pressed,
		"smoke": _chk_smoke.button_pressed,
		"night": _chk_night.button_pressed,
		"bulletproof": bool(s["bulletproof"]),
		"target_stationary": u != null and u.move_mode == UnitInstance.MoveMode.HALTED,
		"fire_smoke": _chk_fire_smoke.visible and _chk_fire_smoke.button_pressed,
	}


## target UnitInstance -> ctx, for Combat.plan_volley / fire_volley.
func _ctx_for() -> Dictionary:
	var out: Dictionary = {}
	for u: UnitInstance in target_units():
		out[u] = _ctx(u)
	return out


## Shots aimed at each chosen target, in the order of _targets.
func _shot_list() -> Array:
	var out: Array = []
	for m in _targets:
		out.append(int(_shots.get(m, 1)))
	return out


func _split() -> Dictionary:
	return Combat.split_volley(state, _shooters, _weapon_name(), _targets, _shot_list())


## Plans the whole volley without rolling: {"ok", "error", "plans"} plus "split".
func plan() -> Dictionary:
	var split: Dictionary = _split()
	var p: Dictionary = Combat.plan_volley(split, _ctx_for())
	p["split"] = split
	return p


# ------------------------------------------------------------------ explanation

func _update_preview() -> void:
	if _preview == null:
		return
	if _shooters.is_empty() or _targets.is_empty() or _weapon < 0:
		_preview.text = "[color=#444444]The explanation of the shot appears here once the shooters, the targets and the weapon are chosen.[/color]"
		_fire_btn.disabled = true
		return
	var p: Dictionary = plan()
	_fire_btn.disabled = not p["ok"]
	_preview.text = explain(p)


## What the numbers mean, step by step. `p` is the result of plan().
func explain(p: Dictionary) -> String:
	if not p["ok"]:
		return "[color=#a04000][b]Cannot fire:[/b] %s[/color]" % TYRules.esc(str(p["error"]))
	var plans: Array = p["plans"]
	var parts: Array = p["split"]["parts"]
	var groups: Array = p["split"]["groups"]
	var first: Dictionary = plans[0]
	var w: WeaponData = first["w"]
	var top: int = max_shots()

	# 1. dice
	var per_unit: PackedStringArray = []
	for g in groups:
		per_unit.append("%s: %d model(s), %d shot(s)" % [(g["unit"] as UnitInstance).code, (g["models"] as Array).size(), int(g["capacity"])])
	var text: String = "[b]1. How many dice:[/b] models x ROF = at most [b]%d shots[/b] (%s); you aimed [b]%d[/b], so %d dice are rolled   [color=#555555](ROF = shots per model. Halted ROF if the model did not move, Moving ROF if it moved, is Pinned Down, tried to Dig In or is an aircraft.)[/color]\n" % [
			top, ", ".join(per_unit), shots_total(), shots_total()]

	# 2. to hit, one line per part
	text += "[b]2. To hit:[/b]\n"
	for i in plans.size():
		var pl: Dictionary = plans[i]
		var part: Dictionary = parts[i]
		var aimed: int = 0
		for n in part["shots"]:
			aimed += int(n)
		text += "      %s -> %s: %d dice need [b]%s[/b]   [color=#555555](%s)[/color]\n" % [
				TYRules.esc((part["shooter"] as UnitInstance).code), TYRules.esc((part["target"] as UnitInstance).label), aimed,
				TYRules.needed_text(pl["needed"]), TYRules.esc(", ".join(pl["parts"]))]
		if int(pl["needed"]) > 6:
			text += "      [color=#555555]More than 6: roll a 6, then roll again and get %d+.[/color]\n" % (int(pl["needed"]) - 2)

	# 3. effect of a hit, per target unit
	if bool(_ctx()["fire_smoke"]):
		text += "[b]3. Every hit[/b] places a Smoke ball on the target instead of doing damage (special rule Smoke). Shots into, through or out of Smoke get +1 to hit.\n"
	else:
		for t: UnitInstance in target_units():
			text += _explain_hit(t, w)

	# 4. who takes the hits
	var codes: PackedStringArray = []
	for m: TeamState in _targets:
		codes.append("%s x%d" % [m.code, int(_shots.get(m, 1))])
	text += "[b]4. Who takes the hits:[/b] each model takes the hits of the shots aimed at it: %s. " % ", ".join(codes)
	var spare: int = top - shots_total()
	if spare > 0:
		text += "[color=#a04000]%d shot(s) not aimed yet: press + on a target or click another model.[/color] " % spare
	text += "5 hits on a unit in one turn Pin Down infantry and guns."
	text += "\n[b]5. Which weapons can fire:[/b] an Infantry model fires one of its weapons per turn; a Tank or Aircraft fires all its MGs or one other weapon."

	var notes: Array = []
	var warnings: Array = []
	for pl in plans:
		for n in pl.get("notes", []):
			if not notes.has(n):
				notes.append(n)
		for wm in pl["warnings"]:
			if not warnings.has(wm):
				warnings.append(wm)
	if not notes.is_empty():
		text += "\n[color=#1b5fa8][b]Special rules applied:[/b] %s[/color]" % TYRules.esc("; ".join(notes))
	var riders: int = 0
	for tm: TeamState in _targets:
		riders += state.passengers(tm, true).size()
	if riders > 0:
		text += "\n[color=#1b5fa8]%d infantry model(s) ride on top of the targets: they are hit every time their tank is hit (Infantry Save, no cover).[/color]" % riders
	for wmsg in warnings:
		text += "\n[color=#a04000](!) %s[/color]" % TYRules.esc(str(wmsg))
	return text


## Step 3 of the explanation for one target unit: what a hit on it does.
func _explain_hit(t: UnitInstance, w: WeaponData) -> String:
	var c: Dictionary = _ctx(t)
	var head: String = "[b]3. Every hit on %s:[/b]" % TYRules.esc(t.label) if target_units().size() > 1 else "[b]3. Every hit:[/b]"
	if t.uses_armour():
		var facing: String = str(c["facing"])
		var armour: int = TYRules.armour_value(t, facing, w)
		var text: String = "%s the target rolls a die and adds its %s armour %d. Compared with the weapon's Anti-tank %d:\n" % [head, facing, armour, w.anti_tank]
		text += "      higher = no effect   |   equal = Firepower %s bails it out   |   lower = Firepower %s destroys it, otherwise bailed out\n" % [
				TYRules.needed_text(w.firepower), TYRules.needed_text(w.firepower)]
		text += "      [color=#555555]So it shrugs the hit off on a roll of %d or more (+1 armour beyond %dcm, not against HEAT).[/color]\n" % [
				maxi(w.anti_tank - armour + 1, 1), TYRules.LONG_RANGE_CM]
		return text
	var extra: String = ""
	var in_cover: bool = bool(c["bulletproof"]) or t.foxholes
	for tm: TeamState in _targets:
		if t.teams.has(tm):
			in_cover = in_cover or tm.in_building
	if t.is_air() or (in_cover and t.is_ground()):
		extra = " %s: after a failed save the shooter must still pass Firepower %s to destroy it." % [
				"Aircraft" if t.is_air() else "Bulletproof Cover (building, Foxholes or ticked)", TYRules.needed_text(w.firepower)]
	if TYRules.weapon_has(w, "Brutal") and (t.is_ground() or t.is_unarmoured()):
		extra += " Special rule Brutal: successful saves are rolled again."
	return "%s the target model rolls its Save %s. A failed save destroys the model.%s\n" % [head, TYRules.needed_text(t.save_value()), extra]


# ------------------------------------------------------------------ fire

func _on_fire() -> void:
	fire()


## Rolls the volley. Returns the result of Combat.fire_volley plus "plan" (the plan of its first part).
## Coroutine (the dice may be typed in by the user): call it with await.
func fire() -> Dictionary:
	if _shooters.is_empty() or _targets.is_empty() or _weapon < 0:
		_hint.text = "Choose the shooters, the targets and the weapon first."
		return {"ok": false}
	Combat.begin_rolls()
	_fire_btn.disabled = true                                    # no second press while dice are being typed in
	var res: Dictionary = await Combat.fire_volley(state, _split(), _ctx_for())
	if not res["ok"]:
		_result.text = str(res.get("error", ""))
		_update_preview()
		return res
	res["plan"] = res["plans"][0]
	_dice.play_groups(Combat.roll_groups(res["results"]))        # to hit, then saves / armour, then Firepower
	var needs: PackedStringArray = []
	for pl in res["plans"]:
		var nt: String = TYRules.needed_text(pl["needed"])
		if not needs.has(nt):
			needs.append(nt)
	_result.text = "%d dice needing %s: %d hit(s)  ->  %d destroyed, %d bailed out   (details in the event log)" % [
			(res["results"] as Array).size(), " / ".join(needs), res["hits"], res["destroyed"], res["bailed"]]
	_mode = Mode.IDLE
	_clear_choice()
	_refresh()
	_hint.text = "Done. Press 'Shoot' for the next shot."
	return res
