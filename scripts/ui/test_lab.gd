class_name TestLab
extends VBoxContainer
## The Test range: two test units (A = yours, B = the enemy) whose every number can be changed, to try out every
## situation of the rules (moving, mounting, shooting, saves, pinning, smoke, bombardments, assaults) without
## building armies. Fill in the two units (or start from a preset or from a real card), choose the step to start at
## and the situation each unit is in, and press "Start the test": the normal round manager opens on these two
## units, with its explanations and the event log showing every roll and every special rule that was applied.

enum Kind { INFANTRY, TANK, UNARMOURED, HELICOPTER, STRIKE }
const KIND_NAMES := ["Infantry / gun teams", "Armoured tank", "Unarmoured vehicle", "Helicopter", "Strike aircraft"]
const STEPS := ["Round 0 (transport set-up)", "Starting Step", "Movement Step", "Shooting Step", "Artillery Step", "Assault Step"]
const WEAPON_ROWS := 3
const WEAPON_KINDS := ["Direct fire", "Artillery bombardment", "Salvo bombardment"]

## Number fields of a unit: [key, label, min, max].
## [field, label, min, max]. Labels are short (three pairs per row); 0 = none / cannot is said once under the grid.
const NUMBERS := [
	["models", "Models", 1, 12], ["is_hit_on", "Is Hit On", 2, 6], ["save", "Save", 0, 6],
	["armour_front", "Front", 0, 25], ["armour_side", "Side", 0, 25], ["armour_top", "Top", 0, 5],
	["skill", "Skill", 2, 6], ["courage", "Courage", 2, 6], ["rally", "Rally/Remount", 2, 6],
	["assault", "Assault", 0, 6], ["counterattack", "Counterattack", 0, 6],
	["cross_skill", "Cross", 0, 6],
	["tactical", "Tactical", 0, 100], ["terrain_dash", "Terrain", 0, 200],
	["cross_dash", "Cross-country", 0, 200], ["road_dash", "Road", 0, 200],
]

const PRESETS := {
	"Infantry platoon": {"name": "Rifle platoon", "kind": Kind.INFANTRY, "models": 5, "is_hit_on": 4, "save": 3, "skill": 4, "courage": 4,
		"rally": 4, "assault": 4, "counterattack": 4, "cross_skill": 0, "tactical": 20, "terrain_dash": 20, "cross_dash": 30, "road_dash": 30,
		"rules": "", "weapons": [
			["Rifle team", 20, 0, 2, 1, 1, 6, 0, "Pinned ROF 1"],
			["Dragon missile", 80, 20, 1, 0, 18, 3, 0, "Guided, HEAT"],
			["LAW anti-tank", 10, 0, 1, 1, 12, 5, 0, "HEAT, Slow Firing"]]},
	"Main battle tank": {"name": "Tank platoon", "kind": Kind.TANK, "models": 3, "is_hit_on": 4, "save": 0, "armour_front": 18, "armour_side": 8,
		"armour_top": 2, "skill": 4, "courage": 4, "rally": 3, "assault": 4, "counterattack": 4, "cross_skill": 2, "tactical": 35,
		"terrain_dash": 40, "cross_dash": 60, "road_dash": 70, "rules": "Thermal Imaging, Chobham Armour", "weapons": [
			["120mm gun", 100, 0, 2, 2, 22, 2, 0, "Advanced Stabiliser, Laser Rangefinder, Smoke"],
			["7.62mm MG", 40, 0, 3, 3, 2, 6, 0, ""],
			[".50 cal AA MG", 50, 0, 3, 2, 4, 5, 0, ""]]},
	"Infantry fighting vehicle (transport)": {"name": "IFV platoon", "kind": Kind.TANK, "models": 3, "is_hit_on": 4, "save": 0, "armour_front": 5,
		"armour_side": 3, "armour_top": 1, "skill": 4, "courage": 4, "rally": 3, "assault": 0, "counterattack": 0, "cross_skill": 3,
		"tactical": 25, "terrain_dash": 35, "cross_dash": 50, "road_dash": 60, "rules": "Passengers 2, Thermal Imaging", "weapons": [
			["25mm gun", 60, 0, 3, 2, 8, 5, 0, "Stabiliser, Anti-helicopter"],
			["Missile", 120, 20, 1, 0, 21, 3, 0, "Guided, HEAT, Tandem Warhead"],
			["7.62mm MG", 40, 0, 3, 3, 2, 6, 0, ""]]},
	"Artillery battery": {"name": "SP howitzer battery", "kind": Kind.TANK, "models": 3, "is_hit_on": 4, "save": 0, "armour_front": 2,
		"armour_side": 1, "armour_top": 1, "skill": 4, "courage": 4, "rally": 3, "assault": 0, "counterattack": 0, "cross_skill": 3,
		"tactical": 25, "terrain_dash": 35, "cross_dash": 45, "road_dash": 55, "rules": "", "weapons": [
			["155mm howitzer (bombardment)", 240, 0, 1, 1, 4, 2, 1, "Smoke Bombardment"],
			["155mm howitzer (direct)", 60, 0, 1, 1, 14, 1, 0, "Brutal, Slow Firing"],
			[".50 cal AA MG", 50, 0, 3, 2, 4, 5, 0, ""]]},
	"Anti-aircraft gun": {"name": "AA platoon", "kind": Kind.TANK, "models": 2, "is_hit_on": 4, "save": 0, "armour_front": 1, "armour_side": 1,
		"armour_top": 0, "skill": 4, "courage": 4, "rally": 3, "assault": 0, "counterattack": 0, "cross_skill": 3, "tactical": 25,
		"terrain_dash": 35, "cross_dash": 50, "road_dash": 60, "rules": "", "weapons": [
			["Quad 23mm AA gun", 60, 0, 4, 3, 7, 5, 0, "Dedicated AA, Radar"]]},
	"Truck (unarmoured)": {"name": "Truck section", "kind": Kind.UNARMOURED, "models": 2, "is_hit_on": 3, "save": 4, "skill": 5, "courage": 5,
		"rally": 5, "assault": 0, "counterattack": 0, "cross_skill": 4, "tactical": 20, "terrain_dash": 20, "cross_dash": 40, "road_dash": 80,
		"rules": "Passengers 2", "weapons": [[".50 cal AA MG", 50, 0, 3, 2, 4, 5, 0, ""]]},
	"Attack helicopter": {"name": "Attack helicopter flight", "kind": Kind.HELICOPTER, "models": 2, "is_hit_on": 4, "save": 4, "skill": 4,
		"courage": 4, "rally": 3, "assault": 0, "counterattack": 0, "cross_skill": 0, "tactical": 0, "terrain_dash": 0, "cross_dash": 0,
		"road_dash": 0, "rules": "Hunter-Killer", "weapons": [
			["Guided missile", 120, 20, 1, 1, 21, 3, 0, "Guided, HEAT"],
			["20mm gun", 20, 0, 3, 3, 5, 5, 0, "Anti-helicopter"]]},
	"Strike aircraft": {"name": "Strike aircraft flight", "kind": Kind.STRIKE, "models": 2, "is_hit_on": 4, "save": 5, "skill": 4, "courage": 4,
		"rally": 3, "assault": 0, "counterattack": 0, "cross_skill": 0, "tactical": 0, "terrain_dash": 0, "cross_dash": 0, "road_dash": 0,
		"rules": "", "weapons": [
			["30mm gun", 20, 0, 0, 3, 11, 5, 0, ""],
			["Bombs", 20, 0, 1, 1, 5, 2, 2, ""]]},
}

var state: BattleState
var _settings: Control
var _battle_holder: VBoxContainer
var _sides: Array = [{}, {}]                 # per side: field key -> control
var _step_opt: OptionButton
var _player_opt: OptionButton
var _status: Label


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_settings = _build_settings()
	add_child(_settings)
	_battle_holder = UIUtil.vbox(4)
	_battle_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_holder.visible = false
	add_child(_battle_holder)
	apply_preset(0, "Main battle tank")
	apply_preset(1, "Infantry platoon")


# ------------------------------------------------------------------ the settings page

func _build_settings() -> Control:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v: VBoxContainer = UIUtil.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIUtil.heading("Test range: try any situation with two test units"))
	var how: Label = UIUtil.note("1) Fill in unit A (yours) and unit B (the enemy): pick a preset or copy a real card, then change any number, "
			+ "weapon or special rule (special rules are typed as on the cards, separated by commas, e.g. 'Thermal Imaging, Passengers 2'). "
			+ "2) Set the situation each unit is in (how it moved, Pinned Down, Foxholes, in a building, Bailed Out models). "
			+ "3) Choose the step to start at and who plays, and press 'Start the test'. The normal round manager opens on the two units: "
			+ "every panel explains its numbers before you roll, and the event log shows each roll and each special rule that was applied. "
			+ "'Test settings' brings you back here to change something and start again.")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(how)

	var bar: HBoxContainer = UIUtil.hbox(8)
	bar.add_child(UIUtil.label("Start at:"))
	_step_opt = UIUtil.option(STEPS)
	_step_opt.select(3)
	bar.add_child(_step_opt)
	bar.add_child(UIUtil.label("Who plays:"))
	_player_opt = UIUtil.option(["Unit A plays, B is the enemy", "Unit B plays, A is the enemy"])
	bar.add_child(_player_opt)
	var go: Button = UIUtil.button("Start the test", _on_start)
	go.custom_minimum_size = Vector2(180, 40)
	bar.add_child(go)
	_status = UIUtil.bold_label("", 13, UIUtil.BAD, HORIZONTAL_ALIGNMENT_LEFT)
	bar.add_child(_status)
	v.add_child(bar)

	var cols: HBoxContainer = UIUtil.hbox(10)
	cols.add_child(_build_side(0, "UNIT A  (yours)", Color.html("#1f4f9a")))
	cols.add_child(_build_side(1, "UNIT B  (the enemy)", Color.html("#a82a1a")))
	v.add_child(cols)
	scroll.add_child(v)
	return scroll


func _build_side(side: int, title: String, color: Color) -> Control:
	var f: Dictionary = {}
	_sides[side] = f
	var v: VBoxContainer = UIUtil.vbox(6)
	v.add_child(UIUtil.title_bar(title, "", color, 16))

	var top: HBoxContainer = UIUtil.hbox(6)
	top.add_child(UIUtil.label("Preset:"))
	var preset: OptionButton = UIUtil.narrow(UIUtil.option(PRESETS.keys()), 190)
	preset.item_selected.connect(_on_preset_chosen.bind(side, preset))
	top.add_child(preset)
	top.add_child(UIUtil.label("or card id:"))
	var card: LineEdit = LineEdit.new()
	card.placeholder_text = "e.g. TU102"
	card.custom_minimum_size = Vector2(100, 0)
	top.add_child(card)
	top.add_child(UIUtil.button("Copy card", _on_copy_card.bind(side, card)))
	v.add_child(top)

	var head: HBoxContainer = UIUtil.hbox(6)
	head.add_child(UIUtil.label("Name"))
	var name_edit: LineEdit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_edit)
	f["name"] = name_edit
	head.add_child(UIUtil.label("Type"))
	var kind: OptionButton = UIUtil.narrow(UIUtil.option(KIND_NAMES), 170)
	head.add_child(kind)
	f["kind"] = kind
	v.add_child(head)
	var grid: GridContainer = GridContainer.new()          # three "label [number]" pairs per row
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for row in NUMBERS:
		grid.add_child(UIUtil.label(str(row[1])))
		var spin: SpinBox = UIUtil.small_spin(float(row[2]), float(row[3]), float(row[2]))
		grid.add_child(spin)
		f[str(row[0])] = spin
	v.add_child(grid)
	v.add_child(UIUtil.note("Front / Side / Top = armour. Save, Assault, Counterattack 0 = none; Cross 0 = no check. "
			+ "Tactical, Terrain, Cross-country and Road are the move and dash distances in cm."))

	v.add_child(UIUtil.label("Special rules of the unit (comma separated):"))
	var rules: LineEdit = LineEdit.new()
	rules.placeholder_text = "Thermal Imaging, Passengers 2, Scout, Observer, ERA ..."
	v.add_child(rules)
	f["rules"] = rules

	v.add_child(UIUtil.bold_label("Weapons  (ROF 0 = cannot fire in that state; minimum range for missiles)", 12, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var wgrid: GridContainer = GridContainer.new()
	wgrid.columns = 9
	wgrid.add_theme_constant_override("h_separation", 3)
	wgrid.add_theme_constant_override("v_separation", 4)
	for h in ["Name", "Range", "Min", "ROF H", "ROF M", "AT", "FP", "Fire", "Weapon rules"]:
		var hl: Label = UIUtil.label(str(h), Color(0.30, 0.22, 0.12))
		hl.add_theme_font_size_override("font_size", 13)
		wgrid.add_child(hl)
	var weapons: Array = []
	for i in WEAPON_ROWS:
		var w: Dictionary = {}
		var wn: LineEdit = LineEdit.new()
		wn.custom_minimum_size = Vector2(96, 0)
		wn.placeholder_text = "(no weapon)"
		wgrid.add_child(wn)
		w["name"] = wn
		for spec in [["range", 0, 400], ["min", 0, 100], ["rof_h", 0, 8], ["rof_m", 0, 8], ["at", 0, 30], ["fp", 1, 6]]:
			var sp: SpinBox = UIUtil.small_spin(float(spec[1]), float(spec[2]), float(spec[1]))
			wgrid.add_child(sp)
			w[str(spec[0])] = sp
		var wk: OptionButton = UIUtil.narrow(UIUtil.option(WEAPON_KINDS), 86)
		wgrid.add_child(wk)
		w["kind"] = wk
		var wr: LineEdit = LineEdit.new()
		wr.custom_minimum_size = Vector2(70, 0)
		wr.tooltip_text = "Weapon rules, comma separated"
		wr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wr.placeholder_text = "HEAT, Guided, Brutal ..."
		wgrid.add_child(wr)
		w["rules"] = wr
		weapons.append(w)
	f["weapons"] = weapons
	v.add_child(wgrid)

	v.add_child(UIUtil.bold_label("Situation when the test starts", 12, UIUtil.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var sit: GridContainer = GridContainer.new()
	sit.columns = 4
	sit.add_theme_constant_override("h_separation", 10)
	sit.add_theme_constant_override("v_separation", 4)
	sit.add_child(UIUtil.label("It moved:"))
	var mv: OptionButton = UIUtil.option(UnitInstance.MOVE_NAMES)
	sit.add_child(mv)
	f["s_move"] = mv
	sit.add_child(UIUtil.label("Distance cm:"))
	var dist: SpinBox = UIUtil.spin(0, 200, 0)
	sit.add_child(dist)
	f["s_dist"] = dist
	sit.add_child(UIUtil.label("Bailed Out models:"))
	var bailed: SpinBox = UIUtil.spin(0, 12, 0)
	sit.add_child(bailed)
	f["s_bailed"] = bailed
	sit.add_child(UIUtil.label("Bogged Down models:"))
	var bogged: SpinBox = UIUtil.spin(0, 12, 0)
	sit.add_child(bogged)
	f["s_bogged"] = bogged
	v.add_child(sit)
	var checks: HFlowContainer = HFlowContainer.new()
	checks.add_theme_constant_override("h_separation", 12)
	for spec in [["s_pinned", "Pinned Down"], ["s_foxholes", "In Foxholes"], ["s_building", "In a building"], ["s_shot", "Already shot (not Gone to Ground)"]]:
		var cb: CheckBox = UIUtil.check(str(spec[1]))
		checks.add_child(cb)
		f[str(spec[0])] = cb
	v.add_child(checks)

	var frame: PanelContainer = UIUtil.paper_frame(v, color, 10, 8, 6, 2)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0                    # A and B share the width equally
	return frame


# ------------------------------------------------------------------ filling the form

func _on_preset_chosen(index: int, side: int, opt: OptionButton) -> void:
	apply_preset(side, opt.get_item_text(index))


## Puts a preset into the form of a side (0 = A, 1 = B).
func apply_preset(side: int, preset_name: String) -> void:
	if PRESETS.has(preset_name):
		set_config(side, PRESETS[preset_name])


func _on_copy_card(side: int, edit: LineEdit) -> void:
	var u: UnitData = UnitDatabase.get_unit(StringName(edit.text.strip_edges()))
	if u == null:
		_status.text = "There is no card with the id '%s' (the id is shown on every card, e.g. TU102)." % edit.text.strip_edges()
		return
	_status.text = ""
	set_config(side, config_from_card(u))


## A real card as a test configuration.
static func config_from_card(u: UnitData) -> Dictionary:
	var kind: int = Kind.INFANTRY
	if u.category == UnitData.Category.ARMORED:
		kind = Kind.UNARMOURED if u.unit_type.to_lower().contains("unarmoured") else Kind.TANK
	elif u.category == UnitData.Category.AIR:
		kind = Kind.HELICOPTER if str(u.get("aircraft_type")) == "helicopter" else Kind.STRIKE
	var cfg: Dictionary = {"name": u.display_name, "kind": kind, "models": u.options[0].models if not u.options.is_empty() else 1,
		"is_hit_on": u.is_hit_on, "save": u.save, "skill": u.skill, "courage": u.courage,
		"rally": u.remount if u.remount > 0 else u.rally, "assault": u.assault, "counterattack": u.counterattack,
		"cross_skill": maxi(u.cross_skill, 0), "tactical": maxi(u.tactical, 0), "terrain_dash": maxi(u.terrain_dash, 0),
		"cross_dash": maxi(u.cross_dash, 0), "road_dash": maxi(u.road_dash, 0), "rules": ", ".join(u.special_rules),
		"armour_front": int(u.get("armour_front")) if u.get("armour_front") != null else 0,
		"armour_side": int(u.get("armour_side")) if u.get("armour_side") != null else 0,
		"armour_top": int(u.get("armour_top")) if u.get("armour_top") != null else 0}
	var ws: Array = []
	for w in u.weapons:
		if ws.size() < WEAPON_ROWS:
			ws.append([w.weapon_name, w.range_cm, w.range_cm_min, w.rof_static, w.rof_moving, w.anti_tank, maxi(w.firepower, 1),
					1 if w.artillery else (2 if w.salvo else 0), ", ".join(w.rules)])
	cfg["weapons"] = ws
	return cfg


## Writes a configuration ({"name", "kind", numbers ..., "rules", "weapons": [[name, range, min, rof halted,
## rof moving, AT, FP, 0 direct / 1 artillery / 2 salvo, rules], ...]}) into the form.
func set_config(side: int, cfg: Dictionary) -> void:
	var f: Dictionary = _sides[side]
	(f["name"] as LineEdit).text = str(cfg.get("name", "Test unit"))
	(f["kind"] as OptionButton).select(int(cfg.get("kind", 0)))
	for row in NUMBERS:
		(f[str(row[0])] as SpinBox).value = float(cfg.get(str(row[0]), row[2]))
	(f["rules"] as LineEdit).text = str(cfg.get("rules", ""))
	var ws: Array = cfg.get("weapons", [])
	var rows: Array = f["weapons"]
	for i in rows.size():
		var w: Dictionary = rows[i]
		var src: Array = ws[i] if i < ws.size() else ["", 0, 0, 0, 0, 0, 1, 0, ""]
		(w["name"] as LineEdit).text = str(src[0])
		(w["range"] as SpinBox).value = float(src[1])
		(w["min"] as SpinBox).value = float(src[2])
		(w["rof_h"] as SpinBox).value = float(src[3])
		(w["rof_m"] as SpinBox).value = float(src[4])
		(w["at"] as SpinBox).value = float(src[5])
		(w["fp"] as SpinBox).value = float(src[6])
		(w["kind"] as OptionButton).select(int(src[7]))
		(w["rules"] as LineEdit).text = str(src[8])


static func _split(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for part in text.split(","):
		if part.strip_edges() != "":
			out.append(part.strip_edges())
	return out


## Builds the UnitData the form of a side describes.
func make_unit(side: int) -> UnitData:
	var f: Dictionary = _sides[side]
	var kind: int = (f["kind"] as OptionButton).selected
	var u: UnitData
	match kind:
		Kind.TANK, Kind.UNARMOURED:
			var a: ArmoredUnitData = ArmoredUnitData.new()
			a.armour_front = int((f["armour_front"] as SpinBox).value)
			a.armour_side = int((f["armour_side"] as SpinBox).value)
			a.armour_top = int((f["armour_top"] as SpinBox).value)
			a.unit_type = "Unarmoured Tank Unit" if kind == Kind.UNARMOURED else "Tank Unit"
			u = a
		Kind.HELICOPTER, Kind.STRIKE:
			var air: AirUnitData = AirUnitData.new()
			air.aircraft_type = "helicopter" if kind == Kind.HELICOPTER else "jet"
			air.unit_type = "Helicopter Unit" if kind == Kind.HELICOPTER else "Strike Aircraft Unit"
			u = air
		_:
			u = GroundUnitData.new()
			u.unit_type = "Infantry Unit"
	u.id = StringName("TEST_A" if side == 0 else "TEST_B")
	u.display_name = (f["name"] as LineEdit).text.strip_edges() if (f["name"] as LineEdit).text.strip_edges() != "" else "Test unit"
	u.nation = "Test"
	for key in ["is_hit_on", "save", "skill", "courage", "assault", "counterattack", "cross_skill", "tactical", "terrain_dash", "cross_dash", "road_dash"]:
		u.set(key, int((f[key] as SpinBox).value))
	u.rally = int((f["rally"] as SpinBox).value)
	u.remount = u.rally
	u.morale = u.courage
	if kind == Kind.HELICOPTER or kind == Kind.STRIKE:      # aircraft move anywhere
		u.tactical = UnitData.AUTO
		u.terrain_dash = UnitData.AUTO
		u.cross_dash = UnitData.AUTO
		u.road_dash = UnitData.AUTO
	if u.cross_skill <= 0:
		u.cross_skill = UnitData.AUTO
	u.special_rules = _split((f["rules"] as LineEdit).text)
	var weapons: Array[WeaponData] = []
	for item in (f["weapons"] as Array):
		var wd: Dictionary = item
		var wname: String = (wd["name"] as LineEdit).text.strip_edges()
		if wname == "":
			continue
		var w: WeaponData = WeaponData.new()
		w.weapon_name = wname
		w.range_cm = int((wd["range"] as SpinBox).value)
		w.range_cm_min = int((wd["min"] as SpinBox).value)
		w.rof_static = int((wd["rof_h"] as SpinBox).value)
		w.rof_moving = int((wd["rof_m"] as SpinBox).value)
		w.anti_tank = int((wd["at"] as SpinBox).value)
		w.firepower = int((wd["fp"] as SpinBox).value)
		w.artillery = (wd["kind"] as OptionButton).selected == 1
		w.salvo = (wd["kind"] as OptionButton).selected == 2
		w.rules = _split((wd["rules"] as LineEdit).text)
		weapons.append(w)
	u.weapons = weapons
	var o: UnitOption = UnitOption.new()
	o.models = int((f["models"] as SpinBox).value)
	o.label = "%dx %s" % [o.models, u.display_name]
	o.composition = [{"count": o.models, "name": u.display_name}]
	var options: Array[UnitOption] = [o]
	u.options = options
	return u


# ------------------------------------------------------------------ starting the test

func _on_start() -> void:
	start_test(_step_opt.selected, _player_opt.selected)


## Builds the two units, opens the round manager at `step` (index into STEPS) with player `active` (0 = A) playing,
## and puts both units in the situation chosen on the form.
func start_test(step: int, active: int) -> BattleState:
	_status.text = ""
	var units: Array = []
	for side in 2:
		var data: UnitData = make_unit(side)
		ModelWeapons.clear_override(data)
		units.append(UnitInstance.new(data, data.options[0], side))
	state = BattleState.new()
	state.setup_units(["A: " + units[0].data.display_name, "B: " + units[1].data.display_name], [0, 1], [[units[0]], [units[1]]], ["#1f4f9a", "#a82a1a"])
	state.log_line("[color=#1b5fa8][b]Test range.[/b] Start: %s, %s plays. Every roll and every special rule that is applied is written here.[/color]" % [
			STEPS[step], "A" if active == 0 else "B"])
	if step > 0:
		state.next_phase()                           # round 0 -> round 1, A's Starting Step
		if active == 1:
			for i in 5:
				state.next_phase()                   # A's turn passes: B's Starting Step
		for i in step - 1:
			state.next_phase()
	for side in 2:
		_apply_situation(units[side], _sides[side])
	state.touch()
	UIUtil.clear_children(_battle_holder)
	var screen: BattleScreen = BattleScreen.new()
	screen.back_text = "Test settings"
	_battle_holder.add_child(screen)
	screen.start(state)
	screen.back_requested.connect(_show_settings)
	_settings.visible = false
	_battle_holder.visible = true
	return state


func _show_settings() -> void:
	_battle_holder.visible = false
	_settings.visible = true


func _apply_situation(u: UnitInstance, f: Dictionary) -> void:
	var mode: int = (f["s_move"] as OptionButton).selected
	var dist: int = int((f["s_dist"] as SpinBox).value)
	for i in u.teams.size():
		var m: TeamState = u.teams[i]
		m.move_mode = mode
		m.move_distance = 0 if mode == UnitInstance.MoveMode.HALTED else mini(dist, u.slider_limit(mode))
		if i < int((f["s_bailed"] as SpinBox).value) and u.uses_armour():
			m.status = TeamState.Status.BAILED_OUT
		elif i < int((f["s_bailed"] as SpinBox).value) + int((f["s_bogged"] as SpinBox).value):
			m.cross_failed = true
		if (f["s_building"] as CheckBox).button_pressed and not m.is_vehicle:
			m.in_building = true
	u.sync_movement()
	u.pinned = (f["s_pinned"] as CheckBox).button_pressed and u.can_be_pinned()
	u.foxholes = (f["s_foxholes"] as CheckBox).button_pressed and u.is_ground()
	u.shot_this_turn = (f["s_shot"] as CheckBox).button_pressed
