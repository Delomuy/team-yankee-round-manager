extends Node
## Open scenes/smoke_test.tscn and press F6 ("Run Current Scene").
## It builds every unit, plays a few random rounds of battle through the rules engine and builds every
## screen. Read the Output panel: "0 problems" means everything ran; any red error shows the faulty line.

var _checks: int = 0
var _problems: int = 0


## The rolling functions are coroutines (dice can be typed in by the user), so every test that rolls is awaited.
## The test always rolls by itself: "Type in every dice result myself" is switched off for this run (not saved).
func _ready() -> void:
	var keep_manual: bool = AppSettings.manual_dice()
	AppSettings.set_manual_dice(false, false)
	var keep_formations: bool = AppSettings.use_formations()
	AppSettings.set_use_formations(false, false)       # the tests make armies without formations
	seed(20260101)
	print("=== Team Yankee smoke test ===")
	# a frame between the tests lets Godot run the deferred calls and free the screens; doing everything in one frame
	# overflowed the message queue and crashed Godot after the test had finished
	_test_all_units()
	await get_tree().process_frame
	_test_card_images()
	_test_rules()
	_test_army_screens()
	await get_tree().process_frame
	await _test_rulebook()
	await get_tree().process_frame
	seed(20260101)          # again: things running in the frames above use random numbers; keep the battle repeatable
	var state: BattleState = await _test_battle()
	_test_screens(state)
	await get_tree().process_frame
	_test_menu()
	await get_tree().process_frame
	_test_formations()
	await get_tree().process_frame
	_test_formation_editor()
	await get_tree().process_frame
	_test_unit_editor()
	await get_tree().process_frame
	_test_upgrade_costs()
	_test_saved_armies()
	await get_tree().process_frame
	_test_card_import()
	await get_tree().process_frame
	_test_formations_section()
	await get_tree().process_frame
	_test_formation_folding()
	await get_tree().process_frame
	_test_compulsory_preselect()
	await get_tree().process_frame
	AppSettings.set_use_formations(keep_formations, false)
	AppSettings.set_manual_dice(keep_manual, false)
	print("=== finished: %d checks, %d problem(s) ===" % [_checks, _problems])


## Unit limits, exclusive units, HQ / formation-only cards and formations (data/formations/ussr_formation_data.json).
func _test_formations() -> void:
	var keep_limit: bool = AppSettings.limit_units()
	AppSettings.set_limit_units(true, false)
	var f: FormationData = FormationDB.get_formation("ussr_btr60_motor_rifle_battalion")
	_check(f != null and f.hq == "TS124a" and f.slots.size() == 9, "formations: the example BTR-60 battalion is loaded")
	_check(FormationDB.for_nation("Soviet").has(f), "formations: listed for their nation")
	var hq: UnitData = UnitDatabase.get_unit(&"TS124a")
	var arty: UnitData = UnitDatabase.get_unit(&"TS108")
	var tank: UnitData = UnitDatabase.get_unit(&"TS138")
	var other_tank: UnitData = UnitDatabase.get_unit(&"TS102")
	if f == null or hq == null or arty == null or tank == null or other_tank == null:
		print("not tested: formations (example cards missing)")
		AppSettings.set_limit_units(keep_limit, false)
		return
	_check(arty.max_copies == 2 and tank.max_copies == 1, "unit json: artillery 2 copies, tanks 1")

	var army: Army = Army.new()
	army.nation = "Soviet"
	# without formations: HQ cards are ordinary support units
	_check(army.support_problem(hq) == "", "without formations an HQ card can be taken as a support unit")
	# limits
	for i in 2:
		_check(army.support_problem(arty) == "", "limits: artillery copy %d allowed" % (i + 1))
		army.add_unit(arty.id, 0)
	_check(army.support_problem(arty) != "" and army.room_for(arty) == 0, "limits: a third artillery battery is refused")
	army.add_unit(tank.id, 0)
	_check(army.support_problem(tank) != "", "limits: a second copy of a tank company is refused")
	AppSettings.set_limit_units(false, false)
	_check(army.support_problem(tank) == "" and army.room_for(tank) > 100, "limits off: any number of copies")
	AppSettings.set_limit_units(true, false)
	# exclusive units (set here, the example data has none)
	var keep_ex: PackedStringArray = tank.exclusive_with
	tank.exclusive_with = PackedStringArray([String(other_tank.id)])
	_check(army.support_problem(other_tank) != "", "exclusive: a unit exclusive with one in the army is refused")
	tank.exclusive_with = keep_ex
	_check(army.support_problem(other_tank) == "", "exclusive: allowed again without the exclusion")
	# formation-only cards
	other_tank.formation_only = true
	_check(army.support_problem(other_tank) != "", "formation-only cards cannot be support units")
	other_tank.formation_only = false

	# with formations
	_check(army.set_use_formations(true) == "" and army.use_formations, "formations switched on for one army")
	_check(army.support_problem(hq) != "", "with formations the HQ card is only taken with its formation")
	var key: String = army.add_formation(f.id)
	_check(key != "" and army.formation_problems(key).size() == 3, "a new formation misses its HQ and two compulsory companies")
	_check(army.set_slot(key, "hq", hq.id, 0) != null, "the HQ leads the formation")
	_check(army.set_slot(key, "tanks", &"TS125a", 0) == null, "a slot only takes its own cards")
	var c1: ArmyEntry = army.set_slot(key, "company_1", &"TS125a", 0)
	army.set_slot(key, "company_2", &"TS125a", maxi(UnitDatabase.get_unit(&"TS125a").options.size() - 1, 0))
	_check(c1 != null and army.formation_problems(key).is_empty(), "formation complete with HQ and compulsory units")
	_check(army.set_slot(key, "tanks", tank.id, 0) != null, "a tank company fills the optional tank slot")
	_check(army.support_problem(tank) != "" and army.support_copies(tank.id) == 1, "formation units do not count: still one support T-80 company")
	_check(army.groups().size() == 2, "the Units page shows only the support units")
	_check(army.set_use_formations(false) != "", "formations cannot be switched off while the army has some")
	# exclusive slots (a test formation)
	var tf: FormationData = FormationData.from_dict({"id": "smoke_exclusive", "name": "Test", "hq": "TS124a",
			"slots": [{"id": "a", "units": ["TS138"]}, {"id": "b", "units": ["TS102"]}], "exclusive": [["a", "b"]]}, "Soviet")
	FormationDB._ensure()
	FormationDB._by_id[tf.id] = tf
	var k2: String = army.add_formation(tf.id)
	army.set_slot(k2, "a", tank.id, 0)
	_check(army.slot_problem(k2, "b", other_tank.id) != "" and army.set_slot(k2, "b", other_tank.id, 0) == null, "exclusive slots: only one may be filled")
	army.remove_formation(k2)
	FormationDB._by_id.erase(tf.id)
	army.remove_formation(key)
	_check(army.formations.is_empty() and army.support_entries().size() == army.entries.size(), "removing a formation removes its units")

	# main formation chosen on the set-up page: HQ and single-card compulsory slots are filled at once
	var main_key: String = army.set_main_formation(f.id)
	_check(main_key != "" and army.formation_problems(main_key).is_empty(), "main formation: HQ and compulsory companies filled at once")
	_check(army.set_main_formation(f.id) == main_key, "main formation: choosing the same one keeps it")

	# the formation screen
	var keep_roster: Array[Army] = ArmyManager.roster.duplicate()
	var only: Array[Army] = [army]
	ArmyManager.roster = only
	var screen: FormationScreen = FormationScreen.new()
	add_child(screen)
	screen.open_player(0)
	_check(screen._top_flow.get_child_count() == 3 and screen._bottom_flow.get_child_count() == 7,
			"formation screen: HQ + 2 compulsory columns on top, 7 additional columns below (%d / %d)" % [
			screen._top_flow.get_child_count(), screen._bottom_flow.get_child_count()])
	screen._on_card_clicked(tank, main_key, "tanks", false)
	var tank_slot: ArmyEntry = army.slot_entry(main_key, "tanks")
	_check(tank_slot != null and tank_slot.unit_id == tank.id, "formation screen: clicking a card takes it")
	_check(screen._grey_reason(main_key, "tanks", other_tank, tank_slot) != "", "formation screen: the OR alternatives of a chosen card are greyed out")
	screen._on_card_clicked(other_tank, main_key, "tanks", false)
	_check(army.slot_entry(main_key, "tanks").unit_id == other_tank.id, "formation screen: clicking an OR alternative swaps the choice")
	other_tank.exclusive_with = PackedStringArray([String(arty.id)])
	_check(screen._grey_reason(main_key, "artillery", arty, null) != "", "formation screen: a card exclusive with a chosen unit is greyed out")
	other_tank.exclusive_with = PackedStringArray()
	screen.queue_free()
	ArmyManager.roster = keep_roster
	army.set_main_formation("")
	_check(army.formations.is_empty(), "main formation: unticking removes it")
	AppSettings.set_limit_units(keep_limit, false)


## The Formations section (FormationEditor): divisions, making a formation, saving and reading it back, deleting it.
## Saves go to user://smoke_formations so the real formation files are not touched.
func _test_formation_editor() -> void:
	var f: FormationData = FormationDB.get_formation("ussr_btr60_motor_rifle_battalion")
	_check(f != null and f.division == "228th Guards" and f.full_name() == "228th Guards - BTR-60 Motor Rifle Battalion",
			"formations: the BTR-60 battalion belongs to the 228th Guards")
	if f == null:
		return
	_check(FormationData.from_dict(f.to_dict(), f.nation).to_dict() == f.to_dict(), "formations: to_dict / from_dict round trip")
	_check(FormationDB.divisions("Soviet").has("228th Guards"), "formations: divisions listed per nation")
	# every HQ card leads a formation; the made ones are named after the card without "HQ"
	var hqs: Dictionary = {}
	for g: FormationData in FormationDB.for_nation(""):
		hqs[g.hq] = g
	var missing: PackedStringArray = []
	for u: UnitData in UnitDatabase.units.values():
		if u.is_hq() and not u.is_attachment and not hqs.has(String(u.id)):
			missing.append(String(u.id))
	_check(missing.is_empty(), "formations: every HQ card has a formation (missing: %s)" % ", ".join(missing))
	_check(FormationDB.name_from_hq("T-80 Shock Tank Company HQ") == "T-80 Shock Tank Company",
			"formations: a blank formation is named after its HQ card without 'HQ'")
	_check(FormationDB.name_from_hq("Challenger Armoured Squadron HQ (ROMOR)") == "Challenger Armoured Squadron (ROMOR)",
			"formations: HQ is taken out of the middle of a name too")
	var tab: FormationEditor = FormationEditor.new()
	add_child(tab)
	var keep_hide: bool = AppSettings.hide_hq()
	AppSettings.set_hide_hq(true, false)
	tab._browser.set_nation("Soviet")                  # the count is worked out without building the tiles
	var with_hq: String = tab._browser._count.text
	tab._browser.obey_hide_hq = true
	tab._browser.refresh()
	var without_hq: String = tab._browser._count.text
	_check(with_hq != without_hq, "formation editor: HQ cards are shown even with Hide HQ units on (%s, else %s)" % [with_hq, without_hq])
	AppSettings.set_hide_hq(keep_hide, false)
	remove_child(tab)
	tab.free()                  # at once: a queued free would still let its card grid build 250 tiles first

	var dir: String = "user://smoke_formations"
	FormationDB.save_dir_override = dir
	var before: int = FormationDB.for_nation("Soviet").size()
	var ed: FormationEditor = FormationEditor.new()
	add_child(ed)
	_check(ed.nation() == "Soviet" and ed.current() != null, "formation editor: opens on the Soviet formations")
	ed.open_formation(f.id)
	ed._on_new()
	var nf: FormationData = ed.current()
	_check(nf != null and nf.nation == "Soviet" and FormationDB.for_nation("Soviet").size() == before + 1,
			"formation editor: New makes a formation")
	_check(nf.division == "228th Guards", "formation editor: a new formation keeps the division of the one shown")
	ed._on_name_changed("Smoke Battalion")
	ed._on_division_changed("1st Smoke Division")
	ed.set_hq("TS124a")
	ed.add_to_slot(0, "TS125a")
	ed._on_add_slot()
	ed.add_to_slot(1, "TS138")
	ed.add_to_slot(1, "TS102")
	ed.add_to_slot(1, "TS102")
	_check(nf.slots.size() == 2 and (nf.slots[1]["units"] as PackedStringArray).size() == 2,
			"formation editor: cards dropped on a slot become OR choices (no doubles)")
	ed._on_add_slot()
	ed._on_add_exclusive()
	ed._on_exclusive_toggled(true, 0, str(nf.slots[1]["id"]))
	ed._on_exclusive_toggled(true, 0, str(nf.slots[2]["id"]))
	_check(nf.exclusive.size() == 1 and (nf.exclusive[0] as PackedStringArray).size() == 2, "formation editor: exclusive group of two slots")
	ed._on_delete_slot(2)
	_check(nf.slots.size() == 2 and nf.exclusive.is_empty(), "formation editor: deleting a slot removes it from the exclusive groups")
	ed._on_move_slot(1, -1)
	_check((nf.slots[0]["units"] as PackedStringArray).has("TS138"), "formation editor: slots can be moved")
	ed._save()
	var path: String = FormationDB.save_path("Soviet")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var found: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		for d in parsed.get("formations", []):
			if str(d.get("id", "")) == nf.id:
				found = d
	_check(path.begins_with(dir) and str(found.get("name", "")) == "Smoke Battalion" and str(found.get("division", "")) == "1st Smoke Division"
			and str(found.get("hq", "")) == "TS124a" and (found.get("slots", []) as Array).size() == 2,
			"formation editor: saved to the nation's file with name, division, HQ and slots")
	_check(typeof(parsed) == TYPE_DICTIONARY and parsed.has("_help"), "formation editor: the file keeps its _help notes")
	ed._delete_current()
	_check(FormationDB.get_formation(nf.id) == null and FormationDB.for_nation("Soviet").size() == before,
			"formation editor: Delete removes the formation")
	remove_child(ed)
	ed.free()
	FormationDB.save_dir_override = ""
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)
	FormationDB.reload()
	_check(FormationDB.get_formation("ussr_btr60_motor_rifle_battalion") != null, "formations: real files read again after the test")


## Making, changing, copying and deleting cards (UnitEditor, UnitDatabase custom cards) and linking transports.
## Saves go to user://smoke_custom so the real files are not touched.
func _test_unit_editor() -> void:
	# every card survives a trip through the file format unchanged
	var bad: PackedStringArray = []
	for u: UnitData in UnitDatabase.units.values():
		var d: Dictionary = UnitDatabase.unit_to_dict(u)
		var back: UnitData = UnitDatabase.build_unit(d)
		if back == null or UnitDatabase.unit_to_dict(back) != d:
			bad.append(String(u.id))
	_check(bad.is_empty(), "card editor: every card is saved and read back unchanged (%s)" % ", ".join(bad))

	var dir: String = "user://smoke_custom"
	UnitDatabase.custom_dir_override = dir
	var keep_custom: Dictionary = UnitDatabase.custom_ids.duplicate()
	var rifle: UnitData = UnitDatabase.get_unit(&"TS125a")
	var shock: UnitData = UnitDatabase.get_unit(&"TS201")
	if rifle == null or shock == null or UnitDatabase.get_unit(&"TS126") == null:
		print("not tested: card editor (example cards missing)")
		UnitDatabase.custom_dir_override = ""
		return

	# copy: a free id, the transport link kept
	var ed: UnitEditor = UnitEditor.new().setup(rifle, UnitEditor.Mode.COPY)
	_check(str(ed.card()["id"]) == "TS125ac" and ed.problem() == "", "card editor: a copy gets a free id (TS125a -> TS125ac)")
	ed.card()["id"] = "TS125a"
	_check(ed.problem() != "", "card editor: an id already used is refused")
	ed.card()["id"] = "TS125ac"
	_check(ed.save() == "", "card editor: the copy is saved")
	ed.free()
	var copy: GroundUnitData = UnitDatabase.get_unit(&"TS125ac") as GroundUnitData
	_check(copy != null and UnitDatabase.is_custom("TS125ac") and not UnitDatabase.has_original("TS125ac")
			and copy.options.size() == rifle.options.size() and copy.transport_ids == PackedStringArray(["TS126"]),
			"card editor: the copy has every size and still rides in BTR-60s (TS126)")

	# edit a card of the main files, then restore it
	ed = UnitEditor.new().setup(shock, UnitEditor.Mode.EDIT)
	ed.card()["name"] = "Changed Shock HQ"
	ed.card()["armour_front"] = 21
	_check(ed.save() == "", "card editor: a main card is changed")
	ed.free()
	var changed: ArmoredUnitData = UnitDatabase.get_unit(&"TS201") as ArmoredUnitData
	_check(changed.display_name == "Changed Shock HQ" and changed.armour_front == 21 and UnitDatabase.is_custom("TS201")
			and UnitDatabase.has_original("TS201"), "card editor: the changed card replaces the original")
	UnitDatabase.remove_custom("TS201")
	_check(UnitDatabase.get_unit(&"TS201").display_name == shock.display_name and not UnitDatabase.is_custom("TS201"),
			"card editor: Restore original brings the main card back")

	# a new infantry card linked to a transport, then a new transport card linked to it
	ed = UnitEditor.new().setup(null, UnitEditor.Mode.NEW, "Soviet")
	_check(ed.problem() != "", "card editor: a new card needs an id")
	ed.card()["id"] = "ZZ901"
	ed.card()["name"] = "Smoke Rifle Company"
	ed._on_kind_chosen(1)
	_check(str(ed.card()["category"]) == "ground" and str(ed.card()["unit_type"]) == "Infantry Unit",
			"card editor: changing the kind of unit changes the card type")
	ed.card()["options"][0]["composition"][0] = {"count": 6, "name": "AK-74 team"}
	ed._link_transport("TS126", 3)
	_check(ed.save() == "", "card editor: a new infantry card with a transport is saved")
	ed.free()
	var zz: GroundUnitData = UnitDatabase.get_unit(&"ZZ901") as GroundUnitData
	_check(zz != null and zz.options[0].models == 6 and zz.options[0].transport_models == 3
			and zz.transport_ids == PackedStringArray(["TS126"]) and zz.options[0].label == "6x AK-74 team + 3x BTR-60",
			"card editor: models, transport count, label and transport link are filled in")
	ed = UnitEditor.new().setup(null, UnitEditor.Mode.NEW, "Soviet")
	ed.card()["id"] = "ZZ902"
	ed.card()["name"] = "Smoke Truck Transport"
	ed._on_attachment_toggled(true)
	ed.card()["passengers"] = 3
	ed._link_units.append("ZZ901")
	_check(ed.save() == "", "card editor: a new transport card is saved")
	ed.free()
	var truck: UnitData = UnitDatabase.get_unit(&"ZZ902")
	_check(truck != null and truck.is_attachment and truck.options.is_empty() and truck.special_rules.has("Passengers 3"),
			"card editor: a transport card has no sizes and gets 'Passengers 3'")
	zz = UnitDatabase.get_unit(&"ZZ901") as GroundUnitData
	_check(zz.transport_ids.has("ZZ902") and UnitDatabase.users_of_transport("ZZ902") == PackedStringArray(["ZZ901"]),
			"card editor: linking a transport card to a unit adds it to that unit's sizes")
	_check(UnitDatabase.transport_cards().has(truck), "card editor: the new transport can be picked by other cards")

	# the files: read back from disk
	var path: String = dir.path_join("ussr_units.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ids: PackedStringArray = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for d in parsed.get("units", []):
			ids.append(str(d.get("id", "")))
	_check(ids.has("TS125ac") and ids.has("ZZ901") and ids.has("ZZ902") and not ids.has("TS201"),
			"card editor: the custom file holds the new and copied cards, not the restored one (%s)" % ", ".join(ids))

	# a card window with the edit buttons, and the grid follows the changes
	var browser: CardBrowser = CardBrowser.new()
	browser.card_editing = true
	add_child(browser)
	browser.open_card(UnitDatabase.get_unit(&"ZZ901"))
	_check(is_instance_valid(browser._card_dlg), "card editor: the card window opens with Edit / Copy / Delete")
	var uses: PackedStringArray = CardBrowser.card_uses("ZZ902")
	_check(uses.size() == 1, "card editor: deleting a transport warns that a card rides in it (%s)" % ", ".join(uses))

	# delete the test cards
	for id: String in ["ZZ901", "ZZ902", "TS125ac"]:
		UnitDatabase.remove_custom(id)
	_check(UnitDatabase.get_unit(&"ZZ901") == null and UnitDatabase.get_unit(&"TS125ac") == null
			and UnitDatabase.get_unit(&"TS125a") != null, "card editor: Delete card removes cards made in the program")
	remove_child(browser)
	browser.free()
	UnitDatabase.custom_dir_override = ""
	UnitDatabase.custom_ids = keep_custom
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## How the options (upgrades) are paid: once, for each one picked, or for every model they cover.
func _test_upgrade_costs() -> void:
	var cases: Array = [
		# [card, text starts with, size index, quantity picked, expected points, what]
		["TS201", "Add AT-11", 0, 1, 1, "once: HQ missile +1"],
		["TS138", "Add AT-11", 0, 1, 3, "per tank: 3x T-80 = 3 pts"],
		["TS138", "Add AT-11", 7, 1, 10, "per tank: 10x T-80 = 10 pts"],
		["TS138", "Fit up to three", 7, 1, 1, "once: mine clearing +1 for up to three tanks"],
		["TV133", "Replace all 240mm", 2, 1, 9, "per two aircraft: 6x Su-22 = 3x3 pts"],
		["TV133", "Replace all 240mm", 0, 1, 3, "per two aircraft: 2x Su-22 = 3 pts"],
		["TG137", "Replace the Milan", 1, 1, 2, "per Milan team: 2 Milan teams = 2 pts"],
		["TG137", "Replace the Milan", 0, 1, 1, "per Milan team: 1 Milan team = 1 pt"],
		["TB105", "Replace the Milan", 0, 1, 2, "per Milan team: the 2 teams of the other option = 2 pts"],
		["TS119a", "Add one Mi-8", 0, 1, 2, "every eight teams: 15 teams = 2 helicopters"],
		["TS119a", "Add one Mi-8", 2, 1, 1, "every eight teams: 7 teams = 1 helicopter"],
		["TU107a", "Arm all M109 with Laser", 0, 1, 6, "all M109 each: 6 pts for 6 guns"],
		["TU102a", "Replace any or all", 0, 2, 2, "any or all, per tank: 2 picked = 2 pts"],
	]
	for c in cases:
		var u: UnitData = UnitDatabase.get_unit(StringName(c[0]))
		var idx: int = -1
		if u != null:
			for i in u.upgrades.size():
				if str((u.upgrades[i] as Dictionary).get("text", "")).begins_with(str(c[1])):
					idx = i
		if idx < 0 or int(c[2]) >= u.options.size():
			_check(false, "upgrade costs: %s '%s' not found" % [c[0], c[1]])
			continue
		var got: int = u.upgrade_cost(idx, int(c[3]), u.options[int(c[2])])
		_check(got == int(c[4]), "upgrade costs: %s %s (got %d)" % [c[0], c[5], got])
	var tu: UnitData = UnitDatabase.get_unit(&"TU102a")
	var tb: UnitData = UnitDatabase.get_unit(&"TB104a")
	if tu != null and tb != null:
		_check(tu.upgrade_limit(0, 4) == 4, "upgrade costs: 'any or all' can be picked once per tank")
		_check(tb.upgrade_limit(0, 9) == 2, "upgrade costs: 'up to two' (in words) allows two")
		_check(tu.upgrade_price_text(0) == "+1 pt each", "upgrade costs: the card shows '+1 pt each'")
	var t80: UnitData = UnitDatabase.get_unit(&"TS138")
	if t80 != null:
		_check(t80.upgrade_price_text(0) == "+1 pt per model" and t80.upgrade_limit(0, 10) == 1,
				"upgrade costs: per-tank shows '+1 pt per model' and has no 'how many' box")
		var e: ArmyEntry = ArmyEntry.new()
		e.unit_id = t80.id
		e.option_index = 7
		e.upgrades = {0: 1}
		_check(e.get_points() == t80.options[7].cost(ArmyManager.use_dynamic_points) + 10 and e.upgrade_lines()[0].contains("x10"),
				"upgrade costs: an army card of 10x T-80 with missiles pays 10 more (%s)" % ", ".join(e.upgrade_lines()))


## Saved armies (ArmyFiles, SavedArmiesPage) and Settings > Use formations. Files go to user://smoke_saved.
func _test_saved_armies() -> void:
	var dir: String = "user://smoke_saved"
	ArmyFiles.dir_override = dir
	var keep_roster: Array[Army] = ArmyManager.roster.duplicate()
	var form: FormationData = FormationDB.get_formation("ussr_btr60_motor_rifle_battalion")
	var tank: UnitData = UnitDatabase.get_unit(&"TS138")
	if form == null or tank == null:
		print("not tested: saved armies (example data missing)")
		ArmyFiles.dir_override = ""
		return

	# an army with a formation and an upgraded support unit
	var a: Army = Army.new()
	a.army_name = "Smoke Red"
	a.nation = "Soviet"
	a.points_limit = 100
	a.use_formations = true
	a.set_main_formation(form.id)
	a.add_unit(tank.id, 2, "", {0: 1})
	_check(ArmyFiles.file_name(a) == "Smoke Red_Soviet_army.json", "saved armies: file named NAME_NATION_army.json")
	_check(not a.is_saved() and ArmyFiles.save(a) == "" and FileAccess.file_exists(dir.path_join("Smoke Red_Soviet_army.json")),
			"saved armies: an army is saved in the saved_army folder")
	_check(a.is_saved(), "saved armies: it counts as saved")
	ArmyManager.use_dynamic_points = not ArmyManager.use_dynamic_points
	_check(a.is_saved(), "saved armies: the points switch does not make it 'changed'")
	ArmyManager.use_dynamic_points = not ArmyManager.use_dynamic_points
	a.points_limit = 120
	_check(not a.is_saved(), "saved armies: a change makes it 'changed since saved'")
	ArmyFiles.save(a)

	var res: Dictionary = ArmyFiles.load_file(a.saved_path)
	var b: Army = res["army"]
	_check(b != null and b.state_key() == a.state_key() and b.is_saved() and b.has_formation()
			and b.main_formation().id == form.id and b.total_points() == a.total_points(),
			"saved armies: loading gives the same army, formation, upgrades and points")
	var list: Array = ArmyFiles.list()
	_check(list.size() == 1 and str(list[0]["formation"]).contains("BTR-60") and int(list[0]["units"]) == a.entries.size(),
			"saved armies: the list shows name, formation and units")

	# an army without a formation
	var c: Army = Army.new()
	c.army_name = "Smoke/Blue_Team"
	c.nation = "American"
	var us_tank: UnitData = UnitDatabase.query("American", UnitData.Category.ARMORED)[0]
	c.add_unit(us_tank.id, 0)
	_check(ArmyFiles.file_name(c) == "Smoke-Blue-Team_American_army.json", "saved armies: characters a file name cannot hold become '-'")
	ArmyFiles.save(c)
	var c_res: Dictionary = ArmyFiles.load_file(c.saved_path)
	_check(c_res["army"] != null and not (c_res["army"] as Army).has_formation(), "saved armies: an army without a formation loads too")

	# renaming: the old file goes, the new one is written
	var old_path: String = c.saved_path
	c.army_name = "Smoke Blue"
	ArmyFiles.save(c)
	_check(not FileAccess.file_exists(old_path) and FileAccess.file_exists(c.saved_path), "saved armies: a renamed army replaces its old file")

	# a card that is gone is left out with a warning
	var broken: Dictionary = JSON.parse_string(a.to_json())
	(broken["entries"] as Array).append({"unit_id": "NOPE1", "option_index": 0, "upgrades": {}, "formation": "", "slot": "", "card": "Ghost"})
	var br: Dictionary = Army.from_dict(broken)
	_check(br["army"] != null and (br["warnings"] as PackedStringArray).size() == 1, "saved armies: a missing card is left out with a warning")

	# import from another folder
	var other: String = "user://smoke_saved_other"
	DirAccess.make_dir_recursive_absolute(other)
	var src: String = other.path_join("friend.json")
	var f: FileAccess = FileAccess.open(src, FileAccess.WRITE)
	var friend: Dictionary = JSON.parse_string(a.to_json())
	friend["army_name"] = "Smoke Friend"
	f.store_string(JSON.stringify(friend))
	f.close()
	var imp: Dictionary = ArmyFiles.import_file(src)
	_check(str(imp["error"]) == "" and str(imp["path"]).get_file() == "Smoke Friend_Soviet_army.json", "saved armies: a file from elsewhere is imported")

	# the page: load as a new player
	var only: Array[Army] = [Army.new(), Army.new()]
	ArmyManager.roster = only
	var page: SavedArmiesPage = SavedArmiesPage.new()
	add_child(page)
	page.refresh()
	_check(page._list.get_child_count() == 3, "saved armies page: lists the 3 saved armies")
	page.load_into(a.saved_path, 2)
	_check(ArmyManager.roster.size() == 3 and ArmyManager.roster[2].army_name == "Smoke Red" and ArmyManager.roster[2].is_saved(),
			"saved armies page: an army is loaded as a new player")

	# Settings > Use formations
	var unsaved: Army = Army.new()
	unsaved.army_name = "Smoke Unsaved"
	unsaved.nation = "American"
	unsaved.add_unit(us_tank.id, 0)
	var nothing: Army = Army.new()
	nothing.nation = "Soviet"
	var r: Array[Army] = [ArmyManager.roster[2], unsaved, nothing]
	ArmyManager.roster = r
	_check(ArmyManager.armies_blocking_formations() == [unsaved], "use formations: an unsaved army without a formation blocks it")
	ArmyFiles.save(unsaved)
	_check(ArmyManager.armies_blocking_formations().is_empty(), "use formations: once saved it no longer blocks")
	AppSettings.set_use_formations(true, false)
	var closed: PackedStringArray = ArmyManager.apply_use_formations()
	_check(closed.size() == 2 and ArmyManager.roster.size() == 2 and ArmyManager.roster[0].army_name == "Smoke Red",
			"use formations: armies without a formation are closed (%s)" % ", ".join(closed))
	var all_have: bool = true
	for x: Army in ArmyManager.roster:
		all_have = all_have and x.has_formation()
	_check(all_have, "use formations: every army left (and the new one) has a formation")
	_check(ArmyFiles.load_file(c.saved_path)["army"] == null, "use formations: an army without a formation cannot be loaded")
	var bare: Army = Army.new()
	bare.nation = "Soviet"
	bare.add_unit(tank.id, 0)
	_check(bare.list_problems().size() > 0 and bare.list_problems()[0].contains("no formation"), "use formations: an army without one cannot fight")
	AppSettings.set_use_formations(false, false)

	remove_child(page)
	page.free()
	ArmyManager.roster = keep_roster
	ArmyFiles.dir_override = ""
	for d: String in [dir, other]:
		for fn in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(fn))
		DirAccess.remove_absolute(d)


const SAMPLE_CARDS := """Testland Rifle Company TL101
Infantry Unit
TACT. 	TERR. DASH 	CROSS C. DASH 	ROAD DASH 	CROSS
8"/20cm 	8"/20cm 	12"/30cm 	12"/30cm 	AUTO

    6x Rifle team
    3x Truck (TLV102) (4/dynamic: 3 points)
    9x Rifle team
    4x Truck (TLV102) (6 points)
Replace all rifles with assault rifles for +1 point per team
Add up to two mortar teams for +1 point each

weapon. 	Range 	h. ROF 	m. ROF 	AT 	FP 	Note
Rifle team 	16"/40cm 	2 	1 	2 	6 	Pinned ROF 1
Mortar 	8"/20cm - 40"/100cm 	ARTILLERY 	ARTILLERY 	2 	6 	Smoke Bombardment

COURAGE 4+
Morale 3+
Rally 4+
SKILL 4+
Assault 4+
Counterattack 4+
IS HIT ON 3+
Infantry 4+
Testland Truck TLV102
Tank Attachment, Passengers 3
TACT. 	TERR. DASH 	CROSS C. DASH 	ROAD DASH 	CROSS
10"/25cm 	12"/30cm 	16"/40cm 	36"/90cm 	4+
weapon. 	Range 	h. ROF 	m. ROF 	AT 	FP 	Note
COURAGE 4+
IS HIT ON 3+
FRONT 0
SIDE 0
TOP 0
"""


## Cards read from FowList text (CardTextImport), new nations (NationDB) and importing them (CardImportDialog).
func _test_card_import() -> void:
	# the port gives the same cards as the Python converter for the Soviet text file
	var ussr: Dictionary = CardTextImport.parse(FileAccess.get_file_as_string("res://data/ussr_units.txt"), "Soviet")
	var same: int = 0
	var checked: int = 0
	for d: Dictionary in ussr["units"]:
		var u: UnitData = UnitDatabase.get_unit(StringName(str(d["id"])))
		if u == null or UnitDatabase.is_custom(String(u.id)):
			continue
		checked += 1
		var mine: Dictionary = UnitDatabase.unit_to_dict(UnitDatabase.build_unit(d))
		var theirs: Dictionary = UnitDatabase.unit_to_dict(u)
		var ok: bool = true
		for k in ["name", "category", "options", "weapons", "special_rules", "tactical", "courage", "skill", "is_hit_on"]:
			# through JSON on both sides: numbers read from a file are floats (3.0), the importer's are ints (3)
			var a: Variant = JSON.parse_string(JSON.stringify(mine.get(k)))
			var b: Variant = JSON.parse_string(JSON.stringify(theirs.get(k)))
			if JSON.stringify(a) != JSON.stringify(b):
				ok = false
		if ok:
			same += 1
	_check(checked > 40 and same >= checked - 2, "card import: the Soviet text gives the same cards as the converter (%d of %d)" % [same, checked])

	# three-letter card ids (Belgium TBE, Israel TIS, Sweden TSV): the infantry rides in its transport card
	for pair in [["TBE104", "TBE105"], ["TIS112", "TIS114"], ["TSV104", "TSV105"]]:
		var inf: GroundUnitData = UnitDatabase.get_unit(StringName(pair[0])) as GroundUnitData
		var linked: bool = false
		if inf != null and not inf.options.is_empty():
			for item in inf.options[0].composition:
				if str((item as Dictionary).get("unit_id", "")) == str(pair[1]):
					linked = true
		_check(inf != null and linked and inf.transport_ids.has(str(pair[1])) and inf.options[0].transport_models > 0,
				"unit data: %s rides in %s (three-letter card ids)" % [pair[0], pair[1]])

	# a sample of a new nation
	var res: Dictionary = CardTextImport.parse(SAMPLE_CARDS, "Testland")
	var cards: Array = res["units"]
	_check(cards.size() == 2, "card import: two cards read from the sample (%s)" % ", ".join(res["warnings"]))
	if cards.size() == 2:
		var rifle: Dictionary = cards[0]
		var truck: Dictionary = cards[1]
		var o0: Dictionary = rifle["options"][0]
		_check(str(rifle["id"]) == "TL101" and str(rifle["category"]) == "ground" and (rifle["options"] as Array).size() == 2
				and int(o0["models"]) == 6 and int(o0["transport_models"]) == 3 and int(o0["points"]) == 4 and int(o0["points_dynamic"]) == 3
				and str(o0["composition"][1]["unit_id"]) == "TLV102", "card import: sizes, dynamic points and the transport link")
		_check((rifle["transport_ids"] as Array) == ["TLV102"] and int(rifle["cross_skill"]) == -1 and int(rifle["save"]) == 4
				and int(rifle["rally"]) == 4, "card import: transport, Cross AUTO, Infantry save and Rally")
		var mortar: Dictionary = rifle["weapons"][1]
		_check(bool(mortar["artillery"]) and int(mortar["range_cm_min"]) == 20 and int(mortar["range_cm"]) == 100,
				"card import: artillery weapon with a minimum range")
		var ups: Array = rifle["upgrades"]
		_check(ups.size() == 2 and str(ups[0].get("per", "")) == "model" and bool(ups[1]["per_model"]),
				"card import: options paid per model / per each one picked")
		_check(bool(truck.get("is_attachment", false)) and int(truck.get("passengers", 0)) == 3, "card import: a transport card")

	# a new nation, its colour and label, then the cards imported into it
	var ndir: String = "user://smoke_nations"
	UnitDatabase.custom_dir_override = ndir          # also where NationDB keeps nations.json
	NationDB.reload()
	var keep_custom: Dictionary = UnitDatabase.custom_ids.duplicate()
	_check(NationDB.add_problem("Soviet", "x") != "", "nations: an existing nation cannot be added again")
	_check(NationDB.add("Testland", "Republic of Testland", "testland", Color.html("#123456")) == "", "nations: a new nation is added")
	_check(UnitDatabase.get_nations().has("Testland") and RulesDB.nation_label("Testland") == "Republic of Testland"
			and CardTile.nation_color_for("Testland").to_html(false) == "123456", "nations: listed, with its label and colour")
	NationDB.reload()
	_check(NationDB.is_added("Testland"), "nations: kept in nations.json")
	var dlg: CardImportDialog = CardImportDialog.new()
	add_child(dlg)
	dlg.set_nation("Testland")
	dlg.set_cards_text(SAMPLE_CARDS)
	dlg.read_cards()
	_check(dlg._found.size() == 2 and CardImportDialog.fate(dlg._found[0]) == "new", "card import window: reads the cards, both new")
	var n: int = dlg.import_ticked()
	_check(n == 2 and UnitDatabase.get_unit(&"TL101") != null and UnitDatabase.get_unit(&"TL101").nation == "Testland"
			and FileAccess.file_exists(ndir.path_join("testland_units.json")), "card import window: cards saved in testland_units.json")
	_check(NationDB.remove("Testland") != "", "nations: a nation with cards cannot be removed")
	UnitDatabase.remove_custom("TL101")
	UnitDatabase.remove_custom("TLV102")
	_check(NationDB.remove("Testland") == "" and not UnitDatabase.get_nations().has("Testland"), "nations: removed once its cards are gone")
	UnitDatabase.custom_ids = keep_custom
	UnitDatabase.custom_dir_override = ""
	NationDB.reload()
	UnitDatabase.nation_prefix.erase("Testland")
	for f in DirAccess.get_files_at(ndir):
		DirAccess.remove_absolute(ndir.path_join(f))
	DirAccess.remove_absolute(ndir)


## The Formations section: nation cards, formation cards, the preview with folded (compact) cards, the editor.
func _test_formations_section() -> void:
	var sec: FormationsSection = FormationsSection.new()
	add_child(sec)
	sec.show_nations()
	_check(sec.page() == "nations" and sec._nation_flow.get_child_count() == UnitDatabase.get_nations().size() + 1,
			"formations: one card per nation and + New nation")
	sec.show_nation("Soviet")
	_check(sec.page() == "nation" and sec._formation_flow.get_child_count() == FormationDB.for_nation("Soviet").size(),
			"formations: one card per Soviet formation")
	var f: FormationData = FormationDB.get_formation("ussr_btr60_motor_rifle_battalion")
	if f != null:
		sec.show_preview(f.id)
		_check(sec.page() == "preview" and sec._preview._army.main_formation().id == f.id and sec._preview._edit_btn.visible,
				"formations: a formation opens in the preview with Edit formation")
		var tanks: Dictionary = {}
		for s in f.slots:
			if (s["units"] as PackedStringArray).size() > 1:
				tanks = s
				break
		if not tanks.is_empty():
			var key: String = sec._preview._army.main_formation_key()
			var first: UnitData = UnitDatabase.get_unit(StringName((tanks["units"] as PackedStringArray)[0]))
			sec._preview._on_card_clicked(first, key, str(tanks["id"]), false)
			var strips: int = _count_type(sec._preview._bottom_flow, "CardStrip")
			_check(strips >= (tanks["units"] as PackedStringArray).size() - 1,
					"formations: after a choice the other cards of the slot are folded to one line (%d)" % strips)
			_check(sec._preview._army.slot_entry(key, str(tanks["id"])) != null and ArmyManager.roster.find(sec._preview._army) < 0,
					"formations: the preview army is a scratch army, not a player's")
		sec.open_editor("Soviet", f.id, false, true)
		_check(sec.page() == "editor" and sec._editor.current() != null and sec._editor.current().id == f.id,
				"formations: Edit formation opens the editor on it")
		sec._on_editor_back()
		_check(sec.page() == "preview", "formations: Back from the editor returns to the preview")
	remove_child(sec)
	sec.free()


## Folding in the formation screens: one card per choice in full, also before anything is chosen; the last pick wins.
func _test_formation_folding() -> void:
	var tf: FormationData = FormationData.from_dict({"id": "smoke_fold", "name": "Fold test", "hq": "TS124a",
			"slots": [{"id": "a", "units": ["TS138", "TS102"]}, {"id": "b", "units": ["TS111"]}, {"id": "c", "units": ["TS108"]}],
			"exclusive": [["b", "c"]]}, "Soviet")
	if UnitDatabase.get_unit(&"TS138") == null or UnitDatabase.get_unit(&"TS102") == null or UnitDatabase.get_unit(&"TS111") == null \
			or UnitDatabase.get_unit(&"TS108") == null or UnitDatabase.get_unit(&"TS124a") == null:
		print("not tested: formation folding (example cards missing)")
		return
	FormationDB._ensure()
	FormationDB._by_id[tf.id] = tf
	var a: Army = Army.new()
	a.nation = "Soviet"
	a.use_formations = true
	var key: String = a.add_formation(tf.id)
	var scr: FormationScreen = FormationScreen.new()
	add_child(scr)
	scr.open_army(a, true)
	var cols: Array = scr._bottom_flow.get_children()          # slots a, b, c (all optional)
	_check(cols.size() == 3 and _full_card(cols[0]) == "TS138" and _count_type(cols[0], "CardStrip") == 1,
			"folding: nothing chosen, the first card of an OR slot is full, the other folded")
	_check(_full_card(cols[1]) == "TS111" and _full_card(cols[2]) == "" and _count_type(cols[2], "CardStrip") == 1,
			"folding: of two exclusive slots only the first shows a full card")
	scr._on_card_clicked(UnitDatabase.get_unit(&"TS102"), key, "a", false)
	a.clear_slot(key, "a")
	scr._on_card_clicked(UnitDatabase.get_unit(&"TS108"), key, "c", false)
	a.clear_slot(key, "c")
	scr.refresh()
	cols = scr._bottom_flow.get_children()
	_check(_full_card(cols[0]) == "TS102", "folding: after removing a choice the last card picked stays full")
	_check(_full_card(cols[1]) == "" and _full_card(cols[2]) == "TS108",
			"folding: in an exclusive group the slot last picked from shows its card")
	remove_child(scr)
	scr.free()
	FormationDB._by_id.erase(tf.id)


## Compulsory slots with several cards (OR) get their first card when the formation is chosen or its screen opens.
func _test_compulsory_preselect() -> void:
	if UnitDatabase.get_unit(&"TS138") == null or UnitDatabase.get_unit(&"TS102") == null or UnitDatabase.get_unit(&"TS124a") == null:
		print("not tested: compulsory preselection (example cards missing)")
		return
	var tf: FormationData = FormationData.from_dict({"id": "smoke_presel", "name": "Preselect test", "hq": "TS124a",
			"slots": [{"id": "a", "compulsory": true, "units": ["TS138", "TS102"]},
					{"id": "b", "compulsory": true, "units": ["NOPE1", "TS102"]},
					{"id": "c", "compulsory": false, "units": ["TS138", "TS102"]}]}, "Soviet")
	FormationDB._ensure()
	FormationDB._by_id[tf.id] = tf
	var a: Army = Army.new()
	a.nation = "Soviet"
	a.use_formations = true
	var key: String = a.set_main_formation(tf.id)
	var sa: ArmyEntry = a.slot_entry(key, "a")
	var sb: ArmyEntry = a.slot_entry(key, "b")
	_check(sa != null and sa.unit_id == &"TS138", "compulsory OR slot: its first card is preselected")
	_check(sb != null and sb.unit_id == &"TS102", "compulsory OR slot: a card missing from the data is skipped")
	_check(a.slot_entry(key, "c") == null, "optional slots stay empty")
	# an army whose formation was added without filling (older armies): opening the screen fills it
	var old: Army = Army.new()
	old.nation = "Soviet"
	old.use_formations = true
	var k2: String = old.add_formation(tf.id)
	var scr: FormationScreen = FormationScreen.new()
	add_child(scr)
	scr.open_army(old, false)
	_check(old.slot_entry(k2, "hq") != null and old.slot_entry(k2, "a") != null and old.slot_entry(k2, "a").unit_id == &"TS138",
			"opening the formation screen fills empty compulsory slots")
	remove_child(scr)
	scr.free()
	FormationDB._by_id.erase(tf.id)


## The card id of the full CardTile in a formation column ("" = none).
func _full_card(n: Node) -> String:
	for ch in n.get_children():
		if ch is CardTile:
			return String((ch as CardTile).unit.id)
		var inner: String = _full_card(ch)
		if inner != "":
			return inner
	return ""


func _count_type(n: Node, cls: String) -> int:
	var c: int = 0
	for ch in n.get_children():
		if ch.get_script() != null and (ch.get_script() as Script).get_global_name() == cls:
			c += 1
		c += _count_type(ch, cls)
	return c


## The start menu, the settings screen and the settings themselves.
func _test_menu() -> void:
	var menu: MainMenu = MainMenu.new()
	add_child(menu)
	var opened: Array = []
	menu.open_requested.connect(func(s: String) -> void: opened.append(s))
	menu._on_pressed("Settings")
	_check(opened == ["Settings"], "menu: a button asks to open its section")
	menu.refresh_title()
	menu.queue_free()
	var settings: SettingsScreen = SettingsScreen.new()
	add_child(settings)
	settings.queue_free()
	AppSettings.set_manual_dice(true, false)
	_check(AppSettings.manual_dice(), "settings: dice input can be switched on")
	AppSettings.set_manual_dice(false, false)
	_check(not AppSettings.manual_dice(), "settings: and off again")

	# game options: Hide HQ units filters the card lists; No Morale and Formations are only remembered
	var hq: int = 0
	var plain: int = 0
	for u: UnitData in UnitDatabase.query("", -1, true):
		if u.is_hq():
			hq += 1
		else:
			plain += 1
	_check(hq > 0 and plain > 0, "settings: HQ cards are recognised (%d HQ, %d other)" % [hq, plain])
	var keep_hq: bool = AppSettings.hide_hq()
	var browser: CardBrowser = CardBrowser.new()
	add_child(browser)
	if not browser._built:
		browser._build_tiles()
	AppSettings.set_hide_hq(false, false)
	browser.refresh()
	var shown_all: String = browser._count.text
	AppSettings.set_hide_hq(true, false)
	browser.refresh()
	var shown_no_hq: String = browser._count.text
	_check(shown_all != shown_no_hq, "settings: Hide HQ units removes cards from the list (%s -> %s)" % [shown_all, shown_no_hq])
	AppSettings.set_hide_hq(keep_hq, false)
	browser.queue_free()
	var keep_morale: bool = AppSettings.no_morale()
	var keep_form: bool = AppSettings.use_formations()
	AppSettings.set_no_morale(true, false)
	AppSettings.set_use_formations(true, false)
	_check(AppSettings.no_morale() and AppSettings.use_formations(), "settings: No Morale and Use Formations are remembered")
	AppSettings.set_no_morale(keep_morale, false)
	AppSettings.set_use_formations(keep_form, false)

	# a new roster: two armies, American and Soviet
	var keep_roster: Array[Army] = ArmyManager.roster.duplicate()
	ArmyManager.roster.clear()
	ArmyManager.set_player_count(2)
	_check(ArmyManager.roster.size() == 2 and ArmyManager.roster[0].nation == "American" and ArmyManager.roster[1].nation == "Soviet",
			"armies: the default roster is American and Soviet")
	ArmyManager.roster = keep_roster


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_problems += 1
		push_error("CHECK FAILED: " + msg)
		print("  FAILED: ", msg)


## The rulebook rules, on the two configurable units of the Test range.
func _test_rulebook() -> void:
	var lab: TestLab = TestLab.new()
	add_child(lab)
	for preset in TestLab.PRESETS:
		lab.apply_preset(0, preset)
		var made: UnitData = lab.make_unit(0)
		_check(made != null and not made.weapons.is_empty() and made.options.size() == 1, "test preset '%s' builds a unit" % preset)
	lab.apply_preset(0, "Main battle tank")
	lab.apply_preset(1, "Infantry platoon")
	for step in TestLab.STEPS.size():
		var st0: BattleState = lab.start_test(step, step % 2)
		_check(st0 != null and st0.units.size() == 2 and (st0.in_setup() == (step == 0)), "test range starts at '%s'" % TestLab.STEPS[step])
		if step > 0:
			_check(st0.phase == step - 1 and st0.active_players() == [step % 2], "test range: right step and player for '%s'" % TestLab.STEPS[step])
	var st: BattleState = lab.start_test(3, 0)
	var tank: UnitInstance = st.units[0][0]
	var inf: UnitInstance = st.units[1][0]
	_check(BattleState.type_letter(tank) == "T" and BattleState.type_letter(inf) == "I", "test units get their type letters")

	# a 3+ is passed by a 3 or more
	_check(TYRules.hit_from_roll(3, 3)["hit"] and TYRules.hit_from_roll(6, 3)["hit"] and not TYRules.hit_from_roll(2, 3)["hit"],
			"3+: a 3 passes, a 2 fails")
	_check(not TYRules.hit_from_roll(5, 7)["hit"], "7+: anything but a 6 fails")
	# volley dice: the highest results go to the hardest to-hit number
	var fake_parts: Array = [{"shots": [3]}, {"shots": [2]}, {"shots": [3]}]
	var fake_plans: Array = [{"needed": 3}, {"needed": 5}, {"needed": 4}]
	var fake_target: UnitInstance = st.units[1][0]
	for fp in fake_parts:
		fp["target"] = fake_target
	var given: Array = await Combat.volley_dice(st, fake_parts, fake_plans)
	var lowest_hard: int = 7
	for r in given[1]:
		lowest_hard = mini(lowest_hard, int(r))
	var highest_mid: int = 0
	var lowest_mid: int = 7
	for r in given[2]:
		highest_mid = maxi(highest_mid, int(r))
		lowest_mid = mini(lowest_mid, int(r))
	var highest_easy: int = 0
	for r in given[0]:
		highest_easy = maxi(highest_easy, int(r))
	_check((given[0] as Array).size() == 3 and (given[1] as Array).size() == 2 and (given[2] as Array).size() == 3,
			"volley dice: every part gets its number of dice")
	_check(lowest_hard >= highest_mid and lowest_mid >= highest_easy, "volley dice: 5+ gets the best dice, then 4+, then 3+")

	# number of weapons firing (artillery)
	_check(TYRules.weapons_firing_modifier(1) == 1 and TYRules.weapons_firing_modifier(3) == 0
			and TYRules.weapons_firing_modifier(5) == -1 and TYRules.weapons_firing_modifier(7) == -2, "weapons firing: +1 / 0 / -1 / -2")
	var th: Dictionary = TYRules.bombard_needed(tank, tank.data.weapons[0], inf, 5, {"attempt": 3, "gone_to_ground": true})
	_check(int(th["needed"]) == inf.data.is_hit_on - 1 + 2 + 1, "bombardment to hit: Is Hit On, -1 five guns, +2 third attempt, +1 Gone to Ground")
	_check(int(TYRules.bombard_needed(tank, tank.data.weapons[0], inf, 7, {"gone_to_ground": false})["needed"]) >= 2, "a bombardment never hits on a 1")

	# which weapons can fire
	var ctx: Dictionary = {"range_cm": 20, "facing": "front"}
	var gun: TeamState = tank.teams[0]
	var first: Dictionary = await Combat.fire_models(st, tank, [gun], 0, inf, [inf.teams[0]], ctx)
	_check(first["ok"], "the tank fires its main gun")
	_check(Combat.fire_limit(tank, gun, 1) != "", "a tank that fired its gun cannot also fire an MG")
	var mg: TeamState = tank.teams[1]
	var mg_shot: Dictionary = await Combat.fire_models(st, tank, [mg], 1, inf, [inf.teams[1]], ctx)
	_check(mg_shot["ok"], "another tank fires an MG")
	_check(Combat.fire_limit(tank, mg, 2) == "" and Combat.fire_limit(tank, mg, 0) != "", "all MGs may fire, but not the gun as well")
	var rifle: TeamState = inf.teams[2]
	rifle.fired[0] = true
	_check(Combat.fire_limit(inf, rifle, 2) != "", "an infantry team fires only one of its weapons")
	rifle.fired.clear()

	# Pinned Down
	inf.pinned = true
	inf.move_mode = UnitInstance.MoveMode.TACTICAL
	_check(not Combat.plan_shot(inf, 0, 1, tank, {"range_cm": 10})["ok"], "Pinned Down infantry that moved cannot shoot")
	inf.move_mode = UnitInstance.MoveMode.HALTED
	var pinned_plan: Dictionary = Combat.plan_shot(inf, 0, 1, tank, {"range_cm": 10})
	_check(pinned_plan["ok"] and int(pinned_plan["rof"]) == 1 and not (pinned_plan["notes"] as Array).is_empty(), "Pinned Down infantry shoots with Moving ROF and the rule is named")
	_check(Combat.bombard_problem(inf) != "", "Pinned Down infantry cannot bombard")
	inf.pinned = false
	tank.move_mode = UnitInstance.MoveMode.TACTICAL
	_check(Combat.bombard_problem(tank) != "", "a unit that moved cannot bombard")
	tank.move_mode = UnitInstance.MoveMode.HALTED

	# Bogged Down
	gun.fired.clear()
	gun.cross_failed = true
	_check(not Combat.plan_models(tank, [gun], 0, inf, [inf.teams[0]], ctx)["ok"], "a Bogged Down model cannot shoot")
	tank.begin_turn()
	_check(not gun.bogged(), "Bogged Down models free themselves at the start of their turn")

	# special rules are named
	var far: Dictionary = Combat.plan_shot(tank, 0, 1, inf, {"range_cm": 60})
	_check(far["ok"] and ", ".join(far["parts"]).contains("Laser Rangefinder"), "Laser Rangefinder is named when it removes the long range penalty")
	var smoke: Dictionary = Combat.plan_shot(tank, 0, 1, inf, {"range_cm": 20, "smoke": true})
	_check(", ".join(smoke["parts"]).contains("Thermal Imaging") and int(smoke["needed"]) == inf.data.is_hit_on, "Thermal Imaging is named and ignores Smoke")
	var smoked: Dictionary = await Combat.fire_models(st, tank, [tank.teams[2]], 0, inf, [inf.teams[0]], {"range_cm": 20, "fire_smoke": true})
	_check(smoked["ok"] and int(smoked["destroyed"]) == 0, "firing Smoke does no damage")

	# foxholes and cross here
	inf.foxholes = true
	inf.teams[0].move_mode = UnitInstance.MoveMode.TACTICAL
	inf.sync_movement()
	_check(not inf.foxholes, "Foxholes are lost when the unit moves")
	tank.order = "cross_here"
	_check(TYRules.cross_number(tank) == maxi(tank.data.cross_skill - 1, 2), "Cross Here lowers the Cross number by 1")
	tank.order = ""

	# passengers: riders are hit with their tank; passengers of a destroyed transport save or die
	var c_data: UnitData = lab.make_unit(0)
	var i_data: UnitData = lab.make_unit(1)
	var carrier_unit: UnitInstance = UnitInstance.new(c_data, c_data.options[0], 0)
	var riders: UnitInstance = UnitInstance.new(i_data, i_data.options[0], 0)
	var enemy: UnitInstance = UnitInstance.new(lab.make_unit(0), c_data.options[0], 1)
	var st2: BattleState = BattleState.new()
	st2.setup_units(["A", "B"], [0, 1], [[carrier_unit, riders], [enemy]])
	var c: TeamState = carrier_unit.teams[0]
	_check(c.rides_on_top_ok and st2.free_places(c, true) == 3, "three infantry teams can ride on an armoured tank")
	for i in 4:
		st2.mount(riders.teams[i], c, true)
	_check(st2.passengers(c, true).size() == 3, "the fourth rider does not fit")
	_check(riders.teams[4].carrier == null and st2.mount_problem(riders.teams[4], c, false) != "", "no seats inside a tank without Passengers")
	await Combat._hit_passengers(st2, enemy.data.weapons[1], enemy, c, 2, {"facing": "front", "range_cm": 20})
	_check(riders.hits_taken == 2 * 3, "the three riders on top are each hit every time their tank is hit")
	c.capacity = 2
	riders.teams[4].carrier = c
	c.status = TeamState.Status.DESTROYED
	await Combat._hit_passengers(st2, enemy.data.weapons[0], enemy, c, 1, {"facing": "front", "range_cm": 20})
	_check(not riders.teams[4].mounted() and (not riders.teams[4].is_alive() or riders.pinned), "a passenger of a destroyed transport saves (and is Pinned Down) or is destroyed")
	lab.queue_free()


func _test_all_units() -> void:
	var dummy_unit: UnitData = UnitDatabase.get_unit(&"TU102a")
	if dummy_unit == null:
		dummy_unit = UnitDatabase.query("", UnitData.Category.ARMORED)[0]
	var dummy: UnitInstance = UnitInstance.new(dummy_unit, dummy_unit.options[0], 1)
	var cards: int = 0
	for u: UnitData in UnitDatabase.units.values():
		cards += 1
		_check(CardView.build_bbcode(u).length() > 20, "card text for %s" % u.id)
		var tile: CardTile = CardTile.new()
		tile.setup(u, CardBrowser.TILE_SIZE)
		_check(tile.unit == u, "card tile for %s" % u.id)
		tile.free()
		var sheet: UnitSheet = UnitSheet.new().setup(u, u.id.hash() % 2 == 0)
		sheet.set_narrow(true)
		sheet.set_narrow(false)
		_check(sheet.find_children("*", "RichTextLabel", true, false).size() >= 1, "card sheet for %s has its rule labels" % u.id)
		var shows_assault: bool = false
		for l in sheet.find_children("*", "Label", true, false):
			if (l as Label).text.begins_with("ASSAULT"):
				shows_assault = true
		_check(shows_assault == (u.category != UnitData.Category.AIR), "%s: Assault / Counterattack shown only for ground units" % u.id)
		if u.category != UnitData.Category.AIR:
			_check(CardView.build_bbcode(u).contains("Counterattack"), "%s: legacy card text keeps Counterattack" % u.id)
		sheet.free()
		if not u.options.is_empty():
			var pick: UnitSheet = UnitSheet.new().setup(u, false, true, u.options.size() - 1)
			_check(pick.selected_option() == u.options.size() - 1, "sheet of %s starts on the given size" % u.id)
			pick.select_option(0)
			_check(pick.selected_option() == 0, "sheet of %s changes size" % u.id)
			pick.free()
		if u.is_attachment:
			continue
		_check(u.options.size() > 0, "%s has options" % u.id)
		for o: UnitOption in u.options:
			var inst: UnitInstance = UnitInstance.new(u, o, 0)
			_check(inst.total_teams() > 0, "%s / %s has teams" % [u.id, o.label])
			for wi in u.weapons.size():
				Combat.plan_shot(inst, wi, 1, dummy, {"range_cm": 20})
	print("units checked: %d cards, %d nations" % [cards, UnitDatabase.get_nations().size()])
	_check(cards > 0, "unit database is not empty")


func _test_card_images() -> void:
	var id: String = "SMOKE_TEST_CARD"
	CardImages.clear_image(id)
	_check(CardImages.get_texture(id) == null, "a card without a picture has no texture")
	var img: Image = Image.create_empty(900, 500, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.2))
	var src: String = "user://smoke_picture.png"
	_check(img.save_png(src) == OK, "test picture written")
	_check(CardImages.set_image(id, src) == OK, "picture attached to a card")
	var tex: Texture2D = CardImages.get_texture(id)
	_check(tex != null and tex.get_width() == 900, "attached picture loads at full size")
	var thumb: Texture2D = CardImages.get_thumbnail(id)
	_check(thumb != null and thumb.get_width() == CardImages.THUMB_WIDTH, "thumbnail is shrunk")
	CardImages.clear_image(id)
	_check(CardImages.get_texture(id) == null, "picture removed again")
	DirAccess.remove_absolute(src)
	print("card pictures saved in: ", CardImages.save_dir())


func _test_rules() -> void:
	_check(RulesDB.count() >= 100, "special rules loaded from the PDF data (%d)" % RulesDB.count())
	_check(RulesDB.has("Brutal"), "Brutal has a description")
	_check(RulesDB.has("Assault +1", "Soviet") and RulesDB.has("Assault 5+", "American"), "Assault +1 / 5+ find 'Assault #'")
	_check(RulesDB.has("Passengers 2", "Soviet"), "Passengers 2 finds 'Passengers #'")
	_check(RulesDB.has("ERA", "Soviet"), "ERA finds 'ERA Armour'")
	_check(RulesDB.has("Advanced Stabiliser"), "Advanced Stabiliser finds 'Advanced Stabilisers'")
	_check(RulesDB.has("Infra-Red (IR)") and RulesDB.has("Appliqué Armour", "American"), "brackets and accents are ignored")
	_check(not RulesDB.has("No Such Rule 123"), "an unknown rule is reported as unknown")
	_check(RulesDB.describe_bbcode("No Such Rule 123").contains("extra_rules.json"), "unknown rule text says how to add one")
	var unresolved: Dictionary = {}
	var seen: int = 0
	for u: UnitData in UnitDatabase.units.values():
		var names: Array = Array(u.special_rules)
		for w: WeaponData in u.weapons:
			names.append_array(Array(w.rules))
		for n in names:
			seen += 1
			var text: String = RulesDB.describe_bbcode(String(n), u.nation)
			_check(text.length() > 30, "rule text for %s on %s" % [n, u.id])
			if not RulesDB.has(String(n), u.nation):
				unresolved[String(n)] = true
		_check(RulesDB.summary_bbcode(u, u.weapons[0] if not u.weapons.is_empty() else null).length() > 5, "rule summary for %s" % u.id)
	var missing: Array = unresolved.keys()
	missing.sort()
	print("rule names on cards: %d uses, %d without a description: %s" % [seen, missing.size(), ", ".join(PackedStringArray(missing))])
	# the pop-up itself (opened on this node, then closed again)
	_check(RulePopup.handle_meta("rule|Brutal|", self), "rule link opens the pop-up")
	_check(not RulePopup.handle_meta("https://example.com", self), "other links are ignored")
	for c in get_children():
		if c is AcceptDialog:
			c.queue_free()


func _test_army_screens() -> void:
	_check(AppTheme.build() != null, "theme builds")
	ArmyManager.set_player_count(3)
	_check(ArmyManager.roster.size() == 3, "three players in the roster")
	ArmyManager.set_player_count(2)
	_check(ArmyManager.roster.size() == 2, "roster shrinks to two players")
	ArmyManager.set_player_count(3)
	var nations: Array = UnitDatabase.get_nations()
	var army: Army = ArmyManager.roster[0]
	army.nation = String(nations[0])
	army.army_name = "Test army"
	army.points_limit = 500
	var pool: Array = UnitDatabase.query(army.nation, -1, false)
	var u: UnitData = pool[0]
	army.add_unit(u.id, 0)
	army.add_unit(u.id, 0)
	army.add_unit(u.id, 0)
	var other: UnitData = pool[pool.size() - 1]
	army.add_unit(other.id, 0)
	_check(army.entries.size() == 4, "army has four entries")
	_check(army.groups().size() == (1 if other.id == u.id else 2), "repeated units are one group")
	_check(army.count_of(u.id, 0) == (4 if other.id == u.id else 3), "count of a repeated unit")
	var counts: Array = army.category_counts()
	_check(int(counts[0]) + int(counts[1]) + int(counts[2]) == 4, "unit types add up to the number of units")
	_check(army.total_models() > 0, "army has models")
	var block: PlayerBlock = PlayerBlock.new().setup(0, army)
	_check(block.get_child_count() > 0, "player block is built")
	block.free()

	var builder: ArmyBuilderScreen = ArmyBuilderScreen.new()
	add_child(builder)
	var players: int = ArmyManager.roster.size()
	builder._on_add_player()
	_check(ArmyManager.roster.size() == players + 1, "plus button adds a player")
	builder._on_remove_player()
	_check(ArmyManager.roster.size() == players, "minus button removes a player")
	var editor: ArmyEditor = ArmyEditor.new()
	add_child(editor)
	army.entries.clear()
	editor.open_player(0)
	var multi: UnitData = null
	for c: UnitData in pool:
		if c.options.size() >= 1 and not c.is_attachment:
			multi = c
			break
	editor._add(multi, 0, 3)
	_check(army.count_of(multi.id, 0) == 3, "editor adds three copies")
	var key: String = "%s|%d" % [multi.id, 0]
	editor._on_remove_toggled(true)
	editor._on_tile_clicked(multi, key)
	editor._on_tile_clicked(multi, key)
	editor._on_tile_right_clicked(multi, key)
	editor._on_tile_clicked(multi, key)
	editor._on_accept()
	_check(army.count_of(multi.id, 0) == 1, "remove mode removed the two marked copies")
	editor._on_army_card_returned({"kind": "army", "unit_id": multi.id, "option_index": 0})
	_check(army.entries.is_empty(), "dragging a card back removes a copy")
	editor._add(multi, 0, 2)
	editor._on_clear()
	_check(army.entries.is_empty(), "clear army empties the list")
	_test_upgrades(army, editor)
	editor.queue_free()
	builder.queue_free()
	for c in get_children():
		if c is AcceptDialog:
			c.queue_free()
	ArmyManager.roster.clear()


## Upgrades are ticked with check boxes, cost points, and make a different card from the plain unit.
func _test_upgrades(army: Army, editor: ArmyEditor) -> void:
	var paid: UnitData = null
	var idx: int = -1
	for c: UnitData in UnitDatabase.units.values():
		if c.options.is_empty():
			continue
		for i in c.upgrades.size():
			if int((c.upgrades[i] as Dictionary).get("cost", 0)) > 0:
				paid = c
				idx = i
				break
		if paid != null:
			break
	if paid == null:
		_check(false, "some unit has a paid upgrade")
		return
	var base: int = paid.options[0].cost(ArmyManager.use_dynamic_points)
	var cost: int = paid.upgrade_cost(idx, 1, paid.options[0])
	var dlg: UnitEditDialog = UnitEditDialog.new().setup(paid, 0)
	add_child(dlg)
	_check(dlg.price_each() == base, "card window: price without upgrades is the size price")
	dlg._sheet._up_checks[idx].button_pressed = true
	var ticked: Dictionary = dlg.chosen_upgrades()
	_check(ticked.has(idx), "card window: ticked upgrade is returned")
	_check(dlg.price_each() == base + paid.upgrade_cost(idx, int(ticked[idx]), paid.options[0]), "card window: ticked upgrade adds its points")
	dlg.queue_free()
	var keep_limit: bool = AppSettings.limit_units()
	AppSettings.set_limit_units(false, false)          # copies and upgrades are tested here, not the limits
	army.entries.clear()
	editor._add(paid, 0, 1)
	editor._add(paid, 0, 2, {idx: 1})
	_check(army.groups().size() == 2, "same unit with and without upgrade are two cards")
	_check(army.count_of(paid.id, 0, {idx: 1}) == 2 and army.count_of(paid.id, 0) == 1, "count by upgrade choice")
	_check(army.total_points() == base + 2 * (base + cost), "army total includes upgrade points (%d)" % army.total_points())
	editor._on_unit_applied(0, {}, 3, paid, ArmyEntry.make_key(paid.id, 0, {idx: 1}))
	_check(army.count_of(paid.id, 0) == 4 and army.count_of(paid.id, 0, {idx: 1}) == 0, "editing a card replaces it (3 copies, no upgrade)")
	# with limits on, an edit past max_copies is refused and the card stays as it was
	army.entries.clear()
	AppSettings.set_limit_units(true, false)
	editor._add(paid, 0, 1, {idx: 1})
	editor._on_unit_applied(0, {}, paid.max_copies + 1, paid, ArmyEntry.make_key(paid.id, 0, {idx: 1}))
	_check(army.count_of(paid.id, 0, {idx: 1}) == 1 and army.count_of(paid.id, 0) == 0, "limits: an edit past max_copies is refused, the card is kept")
	AppSettings.set_limit_units(keep_limit, false)
	army.entries.clear()
	editor._add(paid, 0, 1, {idx: 1})
	_check(army.remove_copies(paid.id, 0, 5, {idx: 1}) == 1 and army.entries.is_empty(), "remove only the upgraded copies")
	army.entries.clear()
	editor._refresh()
	for c in get_children():
		if c is AcceptDialog:
			c.queue_free()


## Cards of the original unit files only: the cards and nations the user makes in the program (data/custom) must not
## change the random battle (a different army once sent it down a path that flooded the log and crashed Godot).
func _base_pool(nation: String) -> Array:
	var out: Array = []
	for u: UnitData in UnitDatabase.query(nation, -1, false):
		if UnitDatabase.has_original(String(u.id)) and not UnitDatabase.is_custom(String(u.id)):
			out.append(u)
	return out


## The nations of the original unit files (see _base_pool).
func _base_nations() -> Array[String]:
	var out: Array[String] = []
	for n in UnitDatabase.get_nations():
		if not _base_pool(n).is_empty():
			out.append(n)
	return out


func _make_army(p: int, nation: String, n: int) -> void:
	var army: Army = Army.new()
	army.army_name = "%s army" % nation
	var pool: Array = _base_pool(nation)
	for i in n:
		var u: UnitData = pool[randi() % pool.size()]
		army.add_unit(u.id, randi() % u.options.size())
	ArmyManager.register_army(p, army)


func _test_battle() -> BattleState:
	var nations: Array[String] = _base_nations()
	# team bookkeeping for every layout: 2v2, 3v1, 2v1, 1v1v1, 2v1v1, free-for-all
	for layout in [[0, 1], [0, 0, 1, 1], [0, 0, 0, 1], [0, 0, 1], [0, 1, 2], [0, 0, 1, 2], [0, 1, 2, 3], [1, 3, 1]]:
		var teams: Array = layout
		ArmyManager.clear()
		var names: Array = []
		for p in teams.size():
			_make_army(p, nations[randi() % nations.size()], 3)
			names.append("P%d" % (p + 1))
		var st: BattleState = BattleState.new()
		st.setup(names, teams)
		var distinct: Dictionary = {}
		for t in teams:
			distinct[t] = true
		_check(st.turn_order.size() == distinct.size(), "layout %s: one turn per team" % str(teams))
		var all_units: int = 0
		for list in st.units:
			all_units += (list as Array).size()
		_check(all_units >= 3 * teams.size() and st.friendly_living().size() + st.enemy_living().size() == all_units, "layout %s: every unit is friend or enemy" % str(teams))
		for u: UnitInstance in st.enemy_living():
			_check(st.are_enemies(u.owner_id, int(st.active_players()[0])), "layout %s: enemies are in another team" % str(teams))
		_check(st.in_setup(), "layout %s: the battle starts with round 0" % str(teams))
		st.next_phase()
		_check(st.round_number == 1 and st.phase == BattleState.Phase.STARTING, "layout %s: round 1 follows round 0" % str(teams))
		var first: int = st.active_team()
		for i in 5 * st.turn_order.size():
			st.next_phase()
		_check(st.active_team() == first and st.round_number == 2, "layout %s: round 2 starts with the first team again" % str(teams))
	_check(ArmyBuilderScreen.battle_problem([0], [0]) != "", "one player cannot fight")

	# a full 2v2 battle with random actions
	ArmyManager.clear()
	for p in 4:
		_make_army(p, nations[randi() % nations.size()], 6)
	ArmyManager.battle_teams = [0, 1, 0, 1]
	var state: BattleState = BattleState.new()
	state.setup(["Alpha", "Bravo", "Charlie", "Delta"], ArmyManager.battle_teams)
	_check(state.units.size() == 4 and state.units[3].size() >= 6, "four armies were created")
	_test_models(state)
	await _test_setup_round(state)
	state.next_phase()                             # round 0 -> round 1
	_test_model_movement(state)
	await _test_model_shooting(state)
	await _test_model_artillery(state)
	await _test_model_assault(state)
	var shots: int = 0
	for turn in 6:                                 # three full rounds
		for phase in 5:
			for u: UnitInstance in state.friendly_living():
				match state.phase:
					BattleState.Phase.MOVEMENT:
						u.move_mode = randi() % 5
						u.move_distance = randi() % 40
						await TYRules.cross_test(u)
					BattleState.Phase.SHOOTING:
						shots += await _random_shot(state, u)
					BattleState.Phase.ARTILLERY:
						await _random_bombardment(state, u)
					BattleState.Phase.ASSAULT:
						await _random_assault(state, u)
			state.next_phase()
	print("random shots that were legal: %d, log lines: %d" % [shots, state.log_history.size()])
	for p in state.player_count():
		for u: UnitInstance in state.units[p]:
			_check(u.alive_teams().size() <= u.total_teams(), "team counts of %s" % u.label)
	return state


## Models: unique codes, weapons per model, riding in and on vehicles.
func _test_models(state: BattleState) -> void:
	_check(BattleState.unit_letters(0) == "A" and BattleState.unit_letters(25) == "Z" and BattleState.unit_letters(26) == "AA", "unit letters A..Z, AA")
	var codes: Dictionary = {}
	var models: int = 0
	for list in state.units:
		for u: UnitInstance in list:
			_check(u.code != "" and u.label.contains(u.code), "%s has a unit code" % u.label)
			_check("ITACHP".contains(BattleState.type_letter(u)), "%s has a type letter" % u.label)
			_check(u.is_air() == (BattleState.type_letter(u) in ["H", "P"]), "%s: H and P are the aircraft" % u.label)
			for i in u.teams.size():
				var m: TeamState = u.teams[i]
				models += 1
				codes[m.code] = true
				_check(m.code == "%s%d" % [u.code, i + 1], "model code %s" % m.code)
				for wi in m.weapons:
					_check(int(wi) >= 0 and int(wi) < u.data.weapons.size(), "weapons of %s exist" % m.code)
			for wi in u.data.weapons.size():
				_check(TYRules.default_teams_for_weapon(u, u.data.weapons[wi]) <= u.teams.size(), "models firing weapon %d of %s" % [wi, u.label])
	_check(codes.size() == models, "every model has its own code (%d models)" % models)
	_check(state.find_model(String(codes.keys()[0])) != null, "a model is found by its code")
	# every card: each kind of model gets weapons, and what is specified by hand is used
	for c: UnitData in UnitDatabase.units.values():
		for kind in ModelWeapons.kinds(c):
			var w: Array = ModelWeapons.weapons_for(c, kind)
			_check(c.weapons.is_empty() or not w.is_empty(), "%s / %s fires something" % [c.id, kind])
	var card: UnitData = null
	for c: UnitData in UnitDatabase.units.values():
		if c.weapons.size() >= 2:
			card = c
			break
	var kind0: String = ModelWeapons.kinds(card)[0]
	ModelWeapons.set_override(card, kind0, [1])
	_check(ModelWeapons.weapons_for(card, kind0) == [1], "weapons specified by hand are used")
	var wd: ModelWeaponsDialog = ModelWeaponsDialog.new().setup(card)
	_check(wd.chosen(kind0) == [1], "weapons window shows what was specified")
	wd.free()
	ModelWeapons.clear_override(card)
	_check(not ModelWeapons.has_override(card, kind0), "back to the automatic guess")
	# riding: inside up to the card's Passengers, on top up to 3
	var foot: Array = []
	var carrier: TeamState = null
	for u: UnitInstance in state.units[0]:
		foot.append_array(u.foot_teams())
		for m in u.teams:
			if m.is_vehicle and not m.is_aircraft and carrier == null:
				carrier = m
	if carrier != null and foot.size() >= 1:
		var inside: int = 0
		var on_top: int = 0
		for m: TeamState in foot:
			if state.mount(m, carrier, false):
				inside += 1
			elif state.mount(m, carrier, true):
				on_top += 1
		_check(inside <= carrier.capacity and on_top <= TeamState.RIDERS_ON_TOP, "vehicle carries %d inside, %d on top" % [inside, on_top])
		_check(inside == mini(carrier.capacity, foot.size()), "inside places are filled first")
		for m: TeamState in foot:
			state.mount(m, null)
		_check(state.passengers(carrier, false).is_empty() and state.passengers(carrier, true).is_empty(), "everybody got out")
	else:
		print("  (no ground vehicle + infantry in the random army: riding not tested)")


## Round 0: the screen shows the set-up panel; dropping infantry on a carrier mounts it.
func _test_setup_round(state: BattleState) -> void:
	var screen: BattleScreen = BattleScreen.new()
	add_child(screen)
	screen.start(state)
	var panel: DeployPanel = null
	for c in screen._step_holder.get_children():
		if c is DeployPanel:
			panel = c
	_check(panel != null, "round 0 shows the set-up panel")
	if panel != null:
		for p in state.player_count():
			var foot: TeamState = null
			var carrier: TeamState = null
			for u: UnitInstance in state.units[p]:
				for m in u.teams:
					if m.is_vehicle and not m.is_aircraft and carrier == null:
						carrier = m
					elif not m.is_vehicle and u.is_ground() and foot == null:
						foot = m
			if foot != null and carrier != null:
				_check(panel.place(foot, carrier.code, true) and foot.mounted() and foot.on_top, "%s rides on top of %s" % [foot.code, carrier.code])
				_check(panel.place(foot, "", false) and not foot.mounted(), "%s is back on foot" % foot.code)
	_check(ModelTile.new().setup(state.units[0][0], state.units[0][0].teams[0], state.player_color(0)).model != null, "model tile builds")
	var tray: DiceTray = DiceTray.new()
	var five: Dictionary = await TYRules.roll_to_hit(5, 4)
	tray.play(five["results"])
	tray.finish()
	_check(tray.die_count() == 5, "dice tray shows one die per roll")
	Combat.begin_rolls()
	Combat._note("save", 3, true, "IA1")
	Combat._note("armour", 2, false, "TA1")
	Combat._note("firepower", 5, true, "gun")
	var four: Dictionary = await TYRules.roll_to_hit(4, 4)
	var groups: Array = Combat.roll_groups(four["results"])
	tray.play_groups(groups)
	tray.finish()
	_check(groups.size() == 4 and tray.die_count() == 7, "dice tray also shows the save, armour and Firepower dice")
	tray.free()
	screen.queue_free()


## Movement is per model; the unit counts as its fastest model. No remounting, buildings.
func _test_model_movement(state: BattleState) -> void:
	while state.phase != BattleState.Phase.MOVEMENT:
		state.next_phase()
	var panel: MovementPanel = MovementPanel.new()
	add_child(panel)
	panel.setup(state)
	_check(panel.find_children("*", "HSlider", true, false).size() >= 1, "movement panel has a distance slider per model")
	var u: UnitInstance = state.friendly_living()[0]
	var m: TeamState = u.teams[0]
	var slider: HSlider = HSlider.new()
	var lbl: Label = Label.new()
	panel._on_mode(UnitInstance.MoveMode.TACTICAL, u, m, slider, lbl)
	_check(int(slider.max_value) == u.slider_limit(UnitInstance.MoveMode.TACTICAL), "slider stops at the Tactical distance")
	slider.value = slider.max_value
	panel._on_dist(slider.value, u, m, lbl)
	_check(m.move_distance == int(slider.max_value) and u.move_mode == UnitInstance.MoveMode.TACTICAL, "the unit counts as its fastest model")
	if u.teams.size() > 1:
		_check(u.teams[1].move_mode == UnitInstance.MoveMode.HALTED, "the other models did not move")
	slider.free()
	lbl.free()
	# a Team cannot Mount and Dismount in the same turn; buildings stay possible
	for list in state.units:
		for unit: UnitInstance in list:
			for foot in unit.foot_teams():
				var carrier: TeamState = null
				for c in panel.carriers_of(unit.owner_id):
					if state.free_places(c, true) > 0 and c.move_mode == UnitInstance.MoveMode.HALTED:
						carrier = c
				if carrier == null or not unit.is_ground():
					continue
				_check(state.mount(foot, carrier, true), "%s mounts %s" % [foot.code, carrier.code])
				_check(not state.mount(foot, null) and foot.mounted(), "%s cannot dismount in the turn it mounted" % foot.code)
				foot.mounted_this_turn = false             # as if a turn went by
				carrier.move_mode = UnitInstance.MoveMode.TACTICAL
				_check(state.mount_problem(foot, null) != "", "%s cannot dismount after its transport moved" % foot.code)
				carrier.move_mode = UnitInstance.MoveMode.HALTED
				_check(state.mount(foot, null) and not foot.mounted(), "%s dismounts before its transport moves" % foot.code)
				_check(not state.mount(foot, carrier, true), "%s cannot mount again in the turn it dismounted" % foot.code)
				foot.dismounted_this_turn = false
				_check(state.set_in_building(foot, true) and foot.in_building, "%s can still enter a building" % foot.code)
				state.set_in_building(foot, false)
				panel.queue_free()
				return
	panel.queue_free()


## Model against model: choose shooters, choose targets, fire.
func _test_model_shooting(state: BattleState) -> void:
	while state.phase != BattleState.Phase.SHOOTING:
		state.next_phase()
	var panel: ShootingPanel = ShootingPanel.new()
	add_child(panel)
	panel.setup(state)
	var fired: int = 0
	for u: UnitInstance in state.friendly_living():
		if u.is_air():
			continue
		var m: TeamState = u.teams[0]
		panel._on_reset()
		_check(panel.pick_shooter(u, m) != "", "cannot pick a shooter before pressing Shoot")
		panel._on_shoot_pressed()
		if panel.pick_shooter(u, m) != "":
			continue
		if u.teams.size() > 1 and u.teams[1].kind != m.kind:
			_check(panel.pick_shooter(u, u.teams[1]) != "", "models of another kind cannot join the shot")
		panel._on_targets_pressed()
		var enemy: UnitInstance = state.enemy_living()[0]
		_check(panel.pick_target(enemy, enemy.alive_teams()[0]) == "", "an enemy model can be chosen as target")
		panel._refresh()
		panel._range_spin.value = 10
		var top: int = panel.max_shots()
		var tm: TeamState = panel._targets[0]
		for i in top + 3:
			panel.change_shots(tm, 1)
		_check(panel.shots_total() == maxi(top, 1) or top == 0, "shots stop at the combined ROF (%d)" % top)
		_check(top == 0 or panel.change_shots(tm, 1) != "", "one shot too many is refused")
		_check(panel._range_spin.max_value >= 1, "range slider has the weapon's range")
		var plan: Dictionary = panel.plan() if panel._weapon >= 0 else {"ok": false, "error": "no weapon"}
		_check(panel.explain(plan).length() > 10, "the shot is explained")
		if plan["ok"]:
			var res: Dictionary = await panel.fire()
			_check(res["ok"] and m.fired.has(u.data.weapons.find(res["plan"]["w"])), "%s fired and is marked as fired" % m.code)
			fired += 1
		if fired >= 3:
			break
	print("model-to-model shots fired: %d" % fired)
	await _test_volley_two_units(state, panel)
	panel.queue_free()


## One volley at models of two different enemy units (and, when the army has them, shooters of one kind from two units).
func _test_volley_two_units(state: BattleState, panel: ShootingPanel) -> void:
	var enemies: Array = []
	for e: UnitInstance in state.enemy_living():
		if not e.is_air() and e.alive_teams().size() > 0:
			enemies.append(e)
	if enemies.size() < 2:
		print("not tested: volley at two enemy units (fewer than two enemy ground units left)")
		return
	for u: UnitInstance in state.friendly_living():
		if u.is_air():
			continue
		for m: TeamState in u.teams:
			if not m.is_active() or m.mounted() or not m.fired.is_empty():
				continue
			panel._on_reset()
			panel._on_shoot_pressed()
			if panel.pick_shooter(u, m) != "":
				continue
			# another model of the same kind from a different unit joins, if there is one
			var other_unit: bool = false
			for u2: UnitInstance in state.friendly_living():
				if u2 == u or other_unit:
					continue
				for m2: TeamState in u2.teams:
					if m2.kind == m.kind and m2.is_active() and not m2.mounted() and m2.fired.is_empty():
						other_unit = panel.pick_shooter(u2, m2) == ""
						break
			panel._on_targets_pressed()
			panel._refresh()
			if panel._weapon < 0 or panel.max_shots() < 2:
				continue
			var e1: UnitInstance = enemies[0]
			var e2: UnitInstance = enemies[1]
			panel._range_spin.value = 10                       # new target units start at this range
			_check(panel.pick_target(e1, e1.alive_teams()[0]) == "", "volley: a model of %s is a target" % e1.code)
			_check(panel.pick_target(e2, e2.alive_teams()[0]) == "", "volley: a model of another unit (%s) joins the targets" % e2.code)
			_check(panel.target_units().size() == 2, "volley: two target units")
			var p: Dictionary = panel.plan()
			_check(panel.explain(p).length() > 10, "volley: explained")
			if not p["ok"]:
				print("volley not fired: %s" % str(p["error"]))
				return
			_check((p["split"]["parts"] as Array).size() >= 2, "volley: split into one part per target unit")
			var res: Dictionary = await panel.fire()
			_check(res["ok"] and m.fired.size() > 0, "volley: fired at two units%s" % (" with shooters of two units" if other_unit else ""))
			return
	print("not tested: volley at two enemy units (no shooter with 2+ shots)")


## Artillery with models: choose the battery's models, range in, choose the models under the Template, fire.
func _test_model_artillery(state: BattleState) -> void:
	while state.phase != BattleState.Phase.ARTILLERY:
		state.next_phase()
	var panel: ArtilleryPanel = ArtilleryPanel.new()
	add_child(panel)
	panel.setup(state)
	var enemy: UnitInstance = state.enemy_living()[0]
	_check(panel.pick_target(enemy, enemy.teams[0]) != "", "artillery: targets cannot be picked before the battery")
	var done: bool = false
	for u: UnitInstance in state.friendly_living():
		for m in u.teams:
			if done or u.is_strike_aircraft() or not m.is_active() or m.mounted() or ArtilleryPanel.bombard_weapons(u, m).is_empty() \
					or Combat.bombard_problem(u) != "" or not m.fired.is_empty():
				continue
			panel._on_shoot_pressed()
			_check(panel.pick_shooter(u, m) == "", "artillery: %s is chosen to bombard" % m.code)
			panel._refresh()
			var early: int = 0
			if panel._weapon >= 0:
				early = await panel.fire()
			_check(panel._weapon >= 0 and early == -1, "artillery: cannot fire before ranging in")
			panel._chk_skip.button_pressed = true          # no ranging needed, so the test always gets to fire
			await panel.range_in()
			_check(panel.attempt() == 1, "artillery: ranged in")
			panel._on_targets_pressed()
			var under: int = 0
			for t: UnitInstance in state.enemy_living():
				if under < 2 and panel.pick_target(t, t.alive_teams()[0]) == "":
					under += 1
			panel._refresh()
			if not panel._is_smoke():
				var fired_hits: int = await panel.fire()
				_check(fired_hits >= 0 and m.fired.has(ArtilleryPanel.bombard_weapons(u, m)[0]), "artillery: %s bombarded %d unit(s)" % [m.code, under])
			done = true
	if not done:
		print("  (no bombardment weapon in the random army: model artillery not tested)")
	# the rules function itself, on any unit
	var any: UnitInstance = state.friendly_living()[0]
	var target: UnitInstance = state.enemy_living()[0]
	var res: Dictionary = {"ok": true, "results": []}
	if not any.data.weapons.is_empty():
		res = await Combat.bombard_under(state, any, 0, 3, target, target.alive_teams().slice(0, 2), {"attempt": 1})
	_check(not res["ok"] or (res["results"] as Array).size() <= 2, "one die per model under the Template")
	panel.queue_free()


## Assault with models: choose attackers and defenders, charge, defensive fire, roll, check.
func _test_model_assault(state: BattleState) -> void:
	while state.phase != BattleState.Phase.ASSAULT:
		state.next_phase()
	var panel: AssaultPanel = AssaultPanel.new()
	add_child(panel)
	panel.setup(state)
	_check(not panel.charge(), "assault: cannot charge before choosing models")
	var fought: bool = false
	for u: UnitInstance in state.friendly_living():
		if fought:
			break
		panel._on_reset()
		panel._on_attackers_pressed()
		var picked: int = 0
		for m in u.teams:
			if panel.pick_attacker(u, m) == "":
				picked += 1
		if picked == 0:
			continue
		panel._on_defenders_pressed()
		var d: UnitInstance = null
		for e: UnitInstance in state.enemy_living():
			if d == null and not e.is_air() and panel.pick_defender(e, e.alive_teams()[0]) == "":
				d = e
		if d == null:
			continue
		var other: UnitInstance = state.friendly_living()[-1]
		_check(other == u or panel.pick_attacker(other, other.teams[0]) != "", "assault: attackers cannot be changed while choosing defenders")
		_check(panel.charge(), "assault: %s charges %s" % [u.code, d.code])
		panel._refresh()
		await panel.defensive_fire(panel._def_weapons.keys())
		if not panel._over:
			var res: Dictionary = await panel.roll_hits()
			_check(res["ok"], "assault: the assaulting models roll")
			var outcome: String = await panel.check_over()
			_check(outcome in ["won", "broke_off", "counterattack"], "assault: outcome %s" % outcome)
			if outcome == "counterattack":
				var counter_hits: int = await panel.defensive_fire([0])
				_check(panel._att == d and counter_hits == 0, "assault: roles swap, no Defensive Fire in a Counterattack")
				await panel.roll_hits()
		fought = true
	if not fought:
		print("  (nobody could assault in the random army: model assault not tested)")
	panel.queue_free()


func _random_shot(state: BattleState, u: UnitInstance) -> int:
	var targets: Array = state.enemy_living()
	if targets.is_empty() or u.data.weapons.is_empty():
		return 0
	var t: UnitInstance = targets[randi() % targets.size()]
	var wi: int = randi() % u.data.weapons.size()
	var ctx: Dictionary = {"range_cm": 5 + randi() % 80, "facing": ["front", "side", "top"][randi() % 3],
			"concealed": randi() % 2 == 0, "gone_to_ground": randi() % 2 == 0}
	var res: Dictionary = await Combat.fire_weapon(state, u, wi, 1 + randi() % 4, t, 0, ctx)
	return 1 if res["ok"] else 0


func _random_bombardment(state: BattleState, u: UnitInstance) -> void:
	var targets: Array = state.enemy_living()
	if targets.is_empty():
		return
	for wi in u.data.weapons.size():
		if not TYRules.is_bombardment(u.data.weapons[wi]):
			continue
		var attempt: int = await Combat.range_in(state, u, maxi(u.data.skill, 2), "smoke test")
		if attempt > 0:
			var t: UnitInstance = targets[randi() % targets.size()]
			await Combat.bombard_group(state, u, wi, 1 + randi() % 6, t, 1 + randi() % 4, {"attempt": attempt})
		return


func _random_assault(state: BattleState, u: UnitInstance) -> void:
	var targets: Array = state.enemy_living()
	if targets.is_empty() or u.is_air() or u.active_teams().is_empty():
		return
	var d: UnitInstance = targets[randi() % targets.size()]
	var contact: Array = d.alive_teams().slice(0, 2)
	await Combat.assault_attack(state, u, 2, d, contact, 4, Combat.assault_top_weapon(), "top")
	if not d.data.weapons.is_empty():
		await Combat.defensive_fire(state, d, 0, 1, u)


func _test_screens(state: BattleState) -> void:
	var screen: BattleScreen = BattleScreen.new()
	add_child(screen)
	screen.start(state)
	for i in 12:                                   # walks through every step panel
		state.next_phase()
	_check(true, "battle screen built every step panel")
	screen.queue_free()
	var browser: CardBrowser = CardBrowser.new()
	add_child(browser)
	var first: UnitData = UnitDatabase.query("", -1, false)[0]
	browser.select_unit(first)
	browser.refresh_tiles()
	_check(browser.selected == first, "card browser selects a card")
	browser.open_card(first)
	_check(is_instance_valid(browser._card_dlg) and browser._card_box.get_child_count() == 1, "double-click opens the full card window")
	_check(browser._attach_btn != null and browser._remove_btn != null, "card window has the picture buttons")
	browser.queue_free()
